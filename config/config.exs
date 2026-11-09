import Config

config :ash, :default_string_length_count, :codepoints
config :logger, level: :warning

config :projection_benchmark,
  ash_domains: [ProjectionBenchmark.Domain],
  ecto_repos: [ProjectionBenchmark.Repo]
