defmodule ProjectionBenchmark.MixProject do
  use Mix.Project

  def project do
    variant = System.get_env("PROJECTION_VARIANT", "before")
    unless variant in ["before", "after"], do: raise("PROJECTION_VARIANT must be before or after")
    pins = Code.eval_file("pins.exs") |> elem(0)

    [
      app: :projection_benchmark,
      version: "0.1.0",
      elixir: "~> 1.18",
      build_path: "_build/#{variant}",
      deps_path: "deps/#{variant}",
      lockfile: "locks/#{variant}.lock",
      deps: [
        {:ash, git: pins.ash.url, ref: pins.ash.ref, override: true},
        {:ash_postgres, git: pins.ash_postgres.url, ref: pins.ash_postgres.ref},
        {:ash_sql, git: pins[variant].url, ref: pins[variant].ref, override: true},
        {:ecto_sql, "~> 3.14.0"},
        {:postgrex, "~> 0.22.0"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
