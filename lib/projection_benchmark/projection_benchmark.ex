defmodule ProjectionBenchmark do
  require Ash.Query
  import Ash.Expr
  alias ProjectionBenchmark.{Invoice, Repo}

  def run do
    {:ok, _} = Repo.start_link()
    variant = Application.fetch_env!(:projection_benchmark, :variant)
    File.mkdir_p!("results")

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
