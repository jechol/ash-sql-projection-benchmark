%{
  :ash => %{
    url: "https://github.com/ash-project/ash.git",
    ref: "a901146fbbd57afabe09a42a8ab9e0463d2eade8"
  },
  :ash_postgres => %{
    url: "https://github.com/ash-project/ash_postgres.git",
    ref: "c21b875d97aa0fa2d3409ac6d2e36013324ccfb4"
  },
  "before" => %{
    url: "https://github.com/ash-project/ash_sql.git",
    ref: "1961731174355284814e97c4d0627779f945b173"
  },
  "after" => %{
    url: "https://github.com/jechol/ash_sql.git",
    ref: "7c76ce808e1d11dcb399927174f289a8c590bfc4"
  }
}
