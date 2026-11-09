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

defmodule ProjectionBenchmark.Payment do
  use Ash.Resource, domain: ProjectionBenchmark.Domain, data_layer: AshPostgres.DataLayer

  postgres do
    repo(ProjectionBenchmark.Repo)
    table("payments")
  end

  attributes do
    attribute(:id, :integer, primary_key?: true, allow_nil?: false)
    attribute(:invoice_id, :integer)
    attribute(:amount, :decimal)
    attribute(:currency, :string)
    attribute(:status, :string)
    attribute(:method, :string)
    attribute(:provider, :string)
    attribute(:provider_reference, :string)
    attribute(:paid_at, :utc_datetime_usec)
    attribute(:created_at, :utc_datetime_usec)
    attribute(:updated_at, :utc_datetime_usec)
    attribute(:refunded_at, :utc_datetime_usec)
    attribute(:refund_amount, :decimal)
    attribute(:fee_amount, :decimal)
    attribute(:net_amount, :decimal)
    attribute(:failure_code, :string)
    attribute(:failure_message, :string)
    attribute(:transaction_id, :string)
    attribute(:receipt_url, :string)
    attribute(:memo, :string)
  end

  actions do
    defaults([:read])
  end
end

defmodule ProjectionBenchmark.Invoice do
  use Ash.Resource, domain: ProjectionBenchmark.Domain, data_layer: AshPostgres.DataLayer

  postgres do
    repo(ProjectionBenchmark.Repo)
    table("invoices")
  end

  attributes do
    attribute(:id, :integer, primary_key?: true, allow_nil?: false)
    attribute(:product_id, :integer)
    attribute(:number, :string)
    attribute(:customer_id, :integer)
    attribute(:customer_name, :string)
    attribute(:customer_email, :string)
    attribute(:status, :string)
    attribute(:currency, :string)
    attribute(:quantity, :integer)
    attribute(:unit_price, :decimal)
    attribute(:subtotal_amount, :decimal)
    attribute(:tax_amount, :decimal)
    attribute(:total_amount, :decimal)
    attribute(:paid_amount, :decimal)
    attribute(:due_date, :date)
    attribute(:issued_on, :date)
    attribute(:memo, :string)
    attribute(:external_reference, :string)
    attribute(:created_at, :utc_datetime_usec)
    attribute(:updated_at, :utc_datetime_usec)
  end

  relationships do
    belongs_to :product, ProjectionBenchmark.Product do
      define_attribute?(false)
      attribute_type(:integer)
    end

    has_one :latest_payment, ProjectionBenchmark.Payment do
      destination_attribute(:invoice_id)
      from_many?(true)
      sort(created_at: :desc, id: :desc)
    end
  end

  actions do
    defaults([:read])
  end
end
