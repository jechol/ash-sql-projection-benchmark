require Ash.Query
alias ProjectionBenchmark.{Invoice, Repo}

"after" = Application.fetch_env!(:projection_benchmark, :variant)
{:ok, _} = Repo.start_link()

defmodule ProjectionTiming do
  def prune(query), do: AshSql.Query.Projection.prune(query)
  def build(query), do: Ash.data_layer_query!(query).query
  def sql(query), do: Repo.to_sql(:all, query)
  def execute(query), do: Repo.all(query) |> AshSql.Query.remap_mapped_fields(query)

  def measure(fun, count) do
    :erlang.garbage_collect()
    {elapsed, _} = :timer.tc(fn -> Enum.reduce(1..count, nil, fn _, _ -> fun.() end) end)
    elapsed / count
  end

  def run(name, query) do
    ecto = build(query)
    pruned = prune(ecto)
    {before_sql, params} = sql(ecto)
    {after_sql, ^params} = sql(pruned)
    rows = execute(ecto)
    ^rows = execute(pruned)

    phases = [
      {"SQL generation", 1000, fn -> sql(ecto) end},
      {"prune", 1000, fn -> prune(ecto) end},
      {"prune + SQL generation", 1000, fn -> ecto |> prune() |> sql() end},
      {"build + SQL generation", 100, fn -> query |> build() |> sql() end},
      {"build + prune + SQL generation", 100, fn -> query |> build() |> prune() |> sql() end},
      {"build + execute", 10, fn -> query |> build() |> execute() end},
      {"build + prune + execute", 10, fn -> query |> build() |> prune() |> execute() end}
    ]

    for {_, _, fun} <- phases, _ <- 1..5, do: fun.()

    samples =
      for round <- 0..14,
          {label, count, fun} <-
            Enum.drop(phases, rem(round, length(phases))) ++
              Enum.take(phases, rem(round, length(phases))) do
        {label, measure(fun, count)}
      end

    IO.puts(
      "\n#{name}: #{length(rows)} rows, #{byte_size(before_sql)} -> #{byte_size(after_sql)} SQL bytes"
    )

    for {label, _, _} <- phases do
      values = for {^label, value} <- samples, do: value
      median = values |> Enum.sort() |> Enum.at(7)
      IO.puts("#{String.pad_trailing(label, 34)} #{Float.round(median, 2)} us")
    end
  end
end

IO.puts("Elixir #{System.version()} / OTP #{:erlang.system_info(:otp_release)}")

for app <- [:ash, :ash_sql, :ash_postgres, :ecto] do
  IO.puts("#{app}: #{Application.spec(app, :vsn)}")
end

IO.puts("PostgreSQL: #{Repo.query!("SHOW server_version").rows |> hd() |> hd()}")

ProjectionTiming.run(
  "no join",
  Invoice |> Ash.Query.select([:id, :number]) |> Ash.Query.sort(id: :asc)
)

ProjectionTiming.run("latest payment", ProjectionBenchmark.query())
