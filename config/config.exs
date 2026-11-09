import Config

config :projection_benchmark, :variant, System.get_env("PROJECTION_VARIANT", "before")
config :ash, :validate_domain_config_inclusion?, false
config :ash, :default_string_length_count, :codepoints
config :logger, level: :warning
