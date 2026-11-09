alias ProjectionBenchmark.{Invoice, Payment, Product, Repo}

{:ok, _} = Repo.start_link()

Repo.transaction(fn ->
  for id <- 1..10 do
    Ash.Seed.upsert!(Product, %{
      id: id,
      sku: "SKU-#{id}",
      name: "Product #{id}",
      currency: "USD",
      unit_price: 100,
      tax_rate: "0.1",
      is_active: true
    })
  end

  for id <- 1..500 do
    Ash.Seed.upsert!(Invoice, %{
      id: id,
      product_id: rem(id - 1, 10) + 1,
      number: "INV-#{id}",
      customer_id: id,
      customer_name: "Customer #{id}",
      customer_email: "customer#{id}@example.com",
      status: "issued",
      currency: "USD",
      quantity: 1,
      unit_price: 100,
      subtotal_amount: 100,
      tax_amount: 10,
      total_amount: 110,
      paid_amount: 0,
      due_date: ~D[2026-01-31],
      issued_on: ~D[2026-01-01]
    })

    for attempt <- 1..3, rem(id, 10) != 0 do
      paid? = attempt == 3 and rem(id, 7) != 0
      created_at = DateTime.add(~U[2026-01-01 00:00:00Z], attempt * 86_400, :second)

      Ash.Seed.upsert!(Payment, %{
        id: id * 10 + attempt,
        invoice_id: id,
        amount: 110,
        currency: "USD",
        status: if(paid?, do: "paid", else: "failed"),
        method: "card",
        provider: "example",
        provider_reference: "payment-#{id}-#{attempt}",
        paid_at: if(paid?, do: created_at),
        created_at: created_at,
        updated_at: created_at,
        refund_amount: 0,
        fee_amount: if(paid?, do: 3, else: 0),
        net_amount: if(paid?, do: 107, else: 0),
        failure_code: if(paid?, do: nil, else: "declined"),
        transaction_id: "tx-#{id}-#{attempt}"
      })
    end
  end
end)
