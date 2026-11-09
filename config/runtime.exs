import Config

config :projection_benchmark, ProjectionBenchmark.Repo,
  url:
    System.get_env(
      "DATABASE_URL",
      "postgres://benchmark:benchmark@localhost:5432/projection_benchmark"
    ),
  pool_size: 1,
  log: false

config :projection_benchmark,
  rows: String.to_integer(System.get_env("BENCH_ROWS", "500")),
  iterations: String.to_integer(System.get_env("BENCH_ITERATIONS", "200")),
  results_dir: System.get_env("RESULTS_DIR", "results")
