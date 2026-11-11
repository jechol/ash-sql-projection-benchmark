defmodule ProjectionBenchmark do
  require Ash.Query
  import Ash.Expr
  alias ProjectionBenchmark.{Invoice, Repo}

  def run do
    {:ok, _} = Repo.start_link()
    variant = Application.fetch_env!(:projection_benchmark, :variant)
    File.mkdir_p!("results")

    results =
      for {name, query} <- queries() do
        ecto = build(query)
        pruned = prune(ecto, variant)
        {_, params} = Repo.to_sql(:all, ecto)
        {sql, ^params} = Repo.to_sql(:all, pruned)
        rows = execute(ecto)
        ^rows = execute(pruned)
        expected_count = if name == "filtered", do: 450, else: 500
        ^expected_count = length(rows)

        File.write!("results/#{variant}-#{name}.sql", sql <> "\n")
        IO.puts("#{variant} / #{name}: #{byte_size(sql)} SQL bytes, #{length(rows)} rows")
        {name, params, Enum.map(rows, &Map.take(&1, [:id, :number, :calculations]))}
      end

    File.write!("results/#{variant}.term", :erlang.term_to_binary(results))
  end

  def build(query), do: Ash.data_layer_query!(query).query
  def prune(query, "upstream"), do: query
  def prune(query, _variant), do: apply(AshSql.Query.Projection, :prune, [query])
  def execute(query), do: Repo.all(query) |> AshSql.Query.remap_mapped_fields(query)

  def queries do
    [
      {"plain", Invoice |> Ash.Query.select([:id, :number]) |> Ash.Query.sort(id: :asc)},
      {"latest", query()},
      {"filtered", query() |> Ash.Query.filter(latest_payment.amount > 1)}
    ]
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
end
