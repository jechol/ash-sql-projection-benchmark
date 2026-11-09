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
