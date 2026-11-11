alias ProjectionBenchmark, as: Bench
alias ProjectionBenchmark.Repo

variant = Application.fetch_env!(:projection_benchmark, :variant)
{:ok, _} = Repo.start_link()

defmodule ProjectionTiming do
  def measure(fun, count) do
    :erlang.garbage_collect()
    {:reductions, before} = Process.info(self(), :reductions)
    {elapsed, _} = :timer.tc(fn -> Enum.reduce(1..count, nil, fn _, _ -> fun.() end) end)
    {:reductions, after_count} = Process.info(self(), :reductions)
    {elapsed / count, (after_count - before) / count}
  end

  def median(values), do: values |> Enum.sort() |> Enum.at(div(length(values), 2))

  def run(name, query, variant) do
    ecto = Bench.build(query)
    prepare = fn -> query |> Bench.build() |> Bench.prune(variant) end

    phases = [
      {"prune", 1000, fn -> Bench.prune(ecto, variant) end},
      {"build + prune + SQL generation", 150, fn -> Repo.to_sql(:all, prepare.()) end},
      {"build + prune + execute", 10, fn -> prepare.() |> Bench.execute() end}
    ]

    samples =
      for round <- 0..14,
          {label, count, fun} <-
            Enum.drop(phases, rem(round, length(phases))) ++
              Enum.take(phases, rem(round, length(phases))) do
        {label, measure(fun, count)}
      end

    for {label, _, _} <- phases do
      times = for {^label, {us, _}} <- samples, do: us
      reductions = for {^label, {_, reductions}} <- samples, do: reductions

      "#{variant}\t#{name}\t#{label}\t#{Float.round(median(times), 3)}\t#{Float.round(median(reductions), 1)}\n"
    end
  end
end

pins = Code.eval_file("pins.exs") |> elem(0)

IO.puts("Elixir #{System.version()} / OTP #{:erlang.system_info(:otp_release)}")
IO.puts("PostgreSQL #{Repo.query!("SHOW server_version").rows |> hd() |> hd()}")
IO.puts("AshSql #{pins[variant].ref}")

output = [
  "variant\tquery\tphase\tus/call\tprocess reductions/call\n",
  for({name, query} <- Bench.queries(), do: ProjectionTiming.run(name, query, variant))
]

File.mkdir_p!("results")
File.write!("results/#{variant}-bench.tsv", output)
IO.write(output)
