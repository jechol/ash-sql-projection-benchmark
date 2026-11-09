import Config

config :projection_benchmark, ProjectionBenchmark.Repo,
  url: System.get_env("DATABASE_URL", "postgres://postgres:postgres@localhost:5432/postgres"),
  pool_size: 1,
  log: false

config :projection_benchmark, :variant, System.get_env("PROJECTION_VARIANT", "before")
