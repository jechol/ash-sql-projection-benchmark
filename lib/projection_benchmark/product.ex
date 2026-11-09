defmodule ProjectionBenchmark.Product do
  use Ash.Resource, domain: ProjectionBenchmark.Domain, data_layer: AshPostgres.DataLayer

  postgres do
    repo(ProjectionBenchmark.Repo)
    table("products")
  end

  attributes do
    attribute(:id, :integer, primary_key?: true, allow_nil?: false)
    attribute(:sku, :string)
    attribute(:name, :string)
    attribute(:currency, :string)
    attribute(:unit_price, :decimal)
    attribute(:tax_rate, :decimal)
    attribute(:is_active, :boolean)
    attribute(:created_at, :utc_datetime_usec)
    attribute(:updated_at, :utc_datetime_usec)
  end

  actions do
    defaults([:read])
  end
end
