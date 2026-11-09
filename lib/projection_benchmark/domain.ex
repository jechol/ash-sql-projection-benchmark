defmodule ProjectionBenchmark.Domain do
  use Ash.Domain

  resources do
    resource(ProjectionBenchmark.Product)
    resource(ProjectionBenchmark.Invoice)
    resource(ProjectionBenchmark.Payment)
  end
end
