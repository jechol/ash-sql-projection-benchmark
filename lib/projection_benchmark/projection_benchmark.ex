defmodule ProjectionBenchmark do
  require Ash.Query
  import Ash.Expr
  alias ProjectionBenchmark.{Invoice, Repo}

  def run do
    {:ok, _} = Repo.start_link()
    variant = Application.fetch_env!(:projection_benchmark, :variant)
    File.mkdir_p!("results")

    {:ok, _} =
      Repo.transaction(fn ->
        seed()
        query = query() |> Ash.data_layer_query!() |> Map.fetch!(:query)

        query =
          if variant == "after",
            do: apply(AshSql.Query.Projection, :prune, [query]),
            else: query

        {sql, params} = Repo.to_sql(:all, query)
        rows = Repo.all(query) |> AshSql.Query.remap_mapped_fields(query)
        500 = length(rows)
        values = Enum.map(rows, &{&1.id, &1.number, &1.calculations})

        File.write!("results/#{variant}.sql", sql <> "\n")
        File.write!("results/#{variant}.term", :erlang.term_to_binary({params, values}))
        IO.puts("#{variant}: #{byte_size(sql)} SQL bytes, #{length(rows)} rows")
      end)
  end

  def query do
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

  defp seed do
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
      [500]
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
end
