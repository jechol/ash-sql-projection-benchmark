defmodule ProjectionBenchmark do
  alias ProjectionBenchmark.{Invoice, Payment, Repo}
  require Ash.Query
  import Ash.Expr

  def run do
    {:ok, _} = Repo.start_link()
    rows = Application.fetch_env!(:projection_benchmark, :rows)
    iterations = Application.fetch_env!(:projection_benchmark, :iterations)
    unless rows > 0 and iterations > 0, do: raise("Rows and iterations must be positive")
    variant = Application.fetch_env!(:projection_benchmark, :variant)

    {:ok, cases} =
      Repo.transaction(
        fn ->
          seed(rows)
          [benchmark(:invoice_latest_payment, rows, iterations, variant)]
        end,
        timeout: :infinity
      )

    pins = Code.eval_file("pins.exs") |> elem(0)

    installed =
      for {app, pin} <- [ash: pins.ash, ash_postgres: pins.ash_postgres, ash_sql: pins[variant]],
          into: %{} do
        path = Mix.Project.deps_paths()[app]

        {sha, 0} =
          System.cmd("git", [
            "-c",
            "safe.directory=#{Path.expand(path)}",
            "-C",
            path,
            "rev-parse",
            "HEAD"
          ])

        unless String.trim(sha) == pin.ref, do: raise("Unexpected #{app} dependency commit")
        {app, String.trim(sha)}
      end

    report = %{
      variant: variant,
      cases: cases,
      pins: pins,
      installed: installed,
      environment: %{
        elixir: System.version(),
        otp: to_string(:erlang.system_info(:otp_release)),
        architecture: to_string(:erlang.system_info(:system_architecture)),
        schedulers: :erlang.system_info(:schedulers_online),
        postgres: Repo.query!("SHOW server_version").rows |> hd() |> hd(),
        ash: version(:ash),
        ash_sql: version(:ash_sql),
        ash_postgres: version(:ash_postgres),
        ecto: version(:ecto)
      }
    }

    write("#{variant}.json", Jason.encode!(report, pretty: true))
  end

  def query(:invoice_latest_payment) do
    Invoice
    |> Ash.Query.select([:id, :number])
    |> Ash.Query.calculate(:product_name, :string, expr(product.name))
    |> Ash.Query.calculate(:latest_payment_status, :string, expr(latest_payment.status))
    |> Ash.Query.calculate(
      :latest_payment_paid_at,
      :utc_datetime_usec,
      expr(latest_payment.paid_at)
    )
    |> Ash.Query.sort(id: :asc)
  end

  defp benchmark(name, rows, iterations, variant) do
    original = name |> query() |> Ash.data_layer_query!() |> Map.fetch!(:query)

    prepare = fn ->
      if variant == "after",
        do: apply(AshSql.Query.Projection, :prune, [original]),
        else: original
    end

    selected = prepare.()
    {sql, params} = Repo.to_sql(:all, selected)
    {original_sql, original_params} = Repo.to_sql(:all, original)
    unless params == original_params, do: raise("Optimizer changed bind parameters")
    actual = read(selected) |> canonical_rows()

    unless actual == expected_rows(rows),
      do: raise("Latest payment results differ from the fixture oracle")

    unless canonical_rows(read(original)) == actual,
      do: raise("Optimizer changed the query results")

    write("#{variant}-#{name}.sql", sql <> "\n")

    # This includes the optimizer on every iteration, not only the smaller SQL.
    Repo.query!("SET LOCAL plan_cache_mode = auto")
    generation = measure(fn -> Repo.to_sql(:all, prepare.()) end, iterations)
    named = measure(fn -> read(prepare.(), prepare: :named) end, iterations)
    unnamed = measure(fn -> read(prepare.(), prepare: :unnamed) end, iterations)
    Repo.query!("SET LOCAL plan_cache_mode = force_custom_plan")

    plans =
      for _ <- 1..9 do
        %{rows: [[[plan]]]} =
          Repo.query!("EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT JSON) " <> sql, params)

        plan
      end

    write("#{variant}-#{name}-plan.json", Jason.encode!(List.last(plans), pretty: true))
    IO.puts("#{variant}/#{name}: #{byte_size(sql)} SQL bytes, #{length(actual)} verified rows")

    %{
      name: name,
      source_columns: length(Payment.__schema__(:fields)),
      referenced_columns: 2,
      rows: length(actual),
      products: 10,
      payments: (rows - div(rows, 10)) * 3,
      iterations: iterations,
      sql_bytes: byte_size(sql),
      unoptimized_sql_bytes: byte_size(original_sql),
      unoptimized_sql_sha256: :crypto.hash(:sha256, original_sql) |> Base.encode16(case: :lower),
      result_sha256:
        :crypto.hash(:sha256, :erlang.term_to_binary(actual)) |> Base.encode16(case: :lower),
      params_sha256:
        :crypto.hash(:sha256, :erlang.term_to_binary(params)) |> Base.encode16(case: :lower),
      generation_including_optimizer: generation,
      prepared_named_read: named,
      unnamed_read: unnamed,
      planning_ms: median(Enum.map(plans, & &1["Planning Time"])),
      execution_ms: median(Enum.map(plans, & &1["Execution Time"]))
    }
  end

  defp measure(fun, count) do
    Enum.each(1..20, fn _ -> fun.() end)

    samples =
      for _ <- 1..count do
        {:reductions, before} = Process.info(self(), :reductions)
        {micros, _} = :timer.tc(fun)
        {:reductions, after_count} = Process.info(self(), :reductions)
        {micros, after_count - before}
      end

    %{
      median_us: median(Enum.map(samples, &elem(&1, 0))),
      median_reductions: median(Enum.map(samples, &elem(&1, 1)))
    }
  end

  defp seed(rows) do
    Repo.query!("""
    CREATE TEMP TABLE products (
      id bigint PRIMARY KEY, sku text, name text, currency text, unit_price numeric,
      tax_rate numeric, is_active boolean, created_at timestamp(6), updated_at timestamp(6)
    ) ON COMMIT DROP
    """)

    Repo.query!("""
    CREATE TEMP TABLE invoices (
      id bigint PRIMARY KEY, product_id bigint, number text, customer_id bigint,
      customer_name text, customer_email text, status text, currency text,
      quantity bigint, unit_price numeric, subtotal_amount numeric, tax_amount numeric,
      total_amount numeric, paid_amount numeric, due_date date, issued_on date,
      memo text, external_reference text, created_at timestamp(6), updated_at timestamp(6)
    ) ON COMMIT DROP
    """)

    Repo.query!("""
    CREATE TEMP TABLE payments (
      id bigint PRIMARY KEY, invoice_id bigint, amount numeric, currency text,
      status text, method text, provider text, provider_reference text,
      paid_at timestamp(6), created_at timestamp(6), updated_at timestamp(6),
      refunded_at timestamp(6), refund_amount numeric, fee_amount numeric,
      net_amount numeric, failure_code text, failure_message text,
      transaction_id text, receipt_url text, memo text
    ) ON COMMIT DROP
    """)

    Repo.query!("""
    INSERT INTO products
    SELECT id, 'SKU-' || id, 'Product ' || id, 'USD', 100, 0.1, true,
      timestamp '2026-01-01', timestamp '2026-01-01'
    FROM generate_series(1, 10) AS p(id)
    """)

    Repo.query!(
      """
      INSERT INTO invoices
      SELECT id, (id - 1) % 10 + 1, 'INV-' || id, id,
        'Customer ' || id, 'customer' || id || '@example.com', 'issued', 'USD',
        1, 100, 100, 10, 110, 0, date '2026-01-31', date '2026-01-01',
        NULL, NULL, timestamp '2026-01-01', timestamp '2026-01-01'
      FROM generate_series(1, $1) AS i(id)
      """,
      [rows]
    )

    Repo.query!("""
    INSERT INTO payments
    SELECT i.id * 10 + p.n, i.id, 110, 'USD',
      CASE WHEN p.n < 3 OR i.id % 7 = 0 THEN 'failed' ELSE 'paid' END,
      'card', 'example', 'payment-' || i.id || '-' || p.n,
      CASE WHEN p.n < 3 OR i.id % 7 = 0 THEN NULL
           ELSE timestamp '2026-01-01' + p.n * interval '1 day' END,
      timestamp '2026-01-01' + p.n * interval '1 day',
      timestamp '2026-01-01' + p.n * interval '1 day',
      NULL, 0,
      CASE WHEN p.n = 3 AND i.id % 7 <> 0 THEN 3 ELSE 0 END,
      CASE WHEN p.n = 3 AND i.id % 7 <> 0 THEN 107 ELSE 0 END,
      CASE WHEN p.n < 3 OR i.id % 7 = 0 THEN 'declined' ELSE NULL END,
      NULL, 'tx-' || i.id || '-' || p.n, NULL, NULL
    FROM invoices i CROSS JOIN generate_series(1, 3) AS p(n) WHERE i.id % 10 <> 0
    """)

    Repo.query!("CREATE INDEX ON payments (invoice_id, created_at DESC, id DESC)")
    for table <- ["products", "invoices", "payments"], do: Repo.query!("ANALYZE #{table}")
  end

  defp read(query, opts \\ []) do
    Repo.all(query, opts) |> AshSql.Query.remap_mapped_fields(query)
  end

  defp canonical_rows(rows) do
    Enum.map(rows, fn row ->
      {row.id, row.number, row.calculations.product_name, row.calculations.latest_payment_status,
       row.calculations.latest_payment_paid_at}
    end)
  end

  defp expected_rows(count) do
    for id <- 1..count do
      {status, paid_at} =
        cond do
          rem(id, 10) == 0 -> {nil, nil}
          rem(id, 7) == 0 -> {"failed", nil}
          true -> {"paid", ~U[2026-01-04 00:00:00.000000Z]}
        end

      {id, "INV-#{id}", "Product #{rem(id - 1, 10) + 1}", status, paid_at}
    end
  end

  def compare do
    root = Application.fetch_env!(:projection_benchmark, :results_dir)
    before = root |> Path.join("before.json") |> File.read!() |> Jason.decode!()
    after_data = root |> Path.join("after.json") |> File.read!() |> Jason.decode!()
    before_lock = Mix.Dep.Lock.read("locks/before.lock") |> Map.delete(:ash_sql)
    after_lock = Mix.Dep.Lock.read("locks/after.lock") |> Map.delete(:ash_sql)

    unless before_lock == after_lock,
      do: raise("Other dependency versions differ between variants")

    unless Enum.map(before["cases"], & &1["name"]) == ["invoice_latest_payment"] and
             Enum.map(after_data["cases"], & &1["name"]) == ["invoice_latest_payment"],
           do: raise("Expected the invoice fixture in both variants")

    lines =
      for {a, b} <- Enum.zip(before["cases"], after_data["cases"]) do
        for key <- [
              "name",
              "rows",
              "products",
              "payments",
              "iterations",
              "result_sha256",
              "params_sha256",
              "unoptimized_sql_sha256"
            ] do
          unless a[key] == b[key], do: raise("Variants differ in #{key}")
        end

        unless b["sql_bytes"] < a["sql_bytes"], do: raise("Expected smaller generated SQL")

        "| #{a["name"]} (#{a["source_columns"]} → #{a["referenced_columns"]} columns) | #{a["sql_bytes"]} | #{b["sql_bytes"]} |"
      end

    summary =
      Enum.join(
        [
          "| Query | Before SQL bytes | After SQL bytes |",
          "|---|---:|---:|" | lines
        ],
        "\n"
      ) <> "\n"

    write("summary.md", summary)
    IO.puts(summary)

    IO.puts(
      "Rows and bind parameters match. Full SQL, plans and environment metadata are in #{root}."
    )
  end

  defp median(values) do
    sorted = Enum.sort(values)
    n = length(sorted)
    (Enum.at(sorted, div(n - 1, 2)) + Enum.at(sorted, div(n, 2))) / 2
  end

  defp version(app), do: app |> Application.spec(:vsn) |> to_string()

  defp write(name, value) do
    root = Application.fetch_env!(:projection_benchmark, :results_dir)
    File.mkdir_p!(root)
    File.write!(Path.join(root, name), value)
  end
end
