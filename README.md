# Ash SQL projection benchmark

A reproducible example for [jechol/ash_sql#3](https://github.com/jechol/ash_sql/pull/3).
The goal is to inspect how many unused columns appear in generated SQL for a
`from_many?` relationship. PostgreSQL already optimizes away many unused values;
this benchmark does not assume that shorter SQL makes execution faster.

An example run is checked in under [`examples/`](examples/), including full
before/after SQL and runtime/dependency metadata. The fixture has 500 Invoices,
10 Products and 1,350 Payment attempts. Each Payment has 20 ordinary billing
fields; the query needs only its `status` and `paid_at` outside the subquery.

| Query | Before SQL bytes | After SQL bytes |
|---|---:|---:|
| Latest Payment (20 → 2 columns) | 1,544 | 918 |

See [`examples/summary.md`](examples/summary.md) and the complete SQL for this run.

## Run

Requires Docker. Elixir, dependencies and PostgreSQL run inside containers.

```sh
git clone https://github.com/jechol/ash-sql-projection-benchmark.git
cd ash-sql-projection-benchmark
./run.sh
```

The script builds the pinned application image, starts a dedicated PostgreSQL
container, runs both variants, writes `results/`, and removes its database
container and network. It does not expose a database port or use an existing DB.

Optional inputs:

```sh
BENCH_ROWS=1000 BENCH_ITERATIONS=500 ./run.sh
```

To use an existing local PostgreSQL with Elixir 1.18+ instead:

```sh
DATABASE_URL=postgres://user:password@localhost/benchmark ./scripts/benchmark.sh
```

All fixture tables are temporary and scoped to one transaction/connection.

## What is being queried?

Each Invoice belongs to a Product and has three Payment attempts, except every
tenth Invoice has none. The first two attempts fail; the latest succeeds except
for every seventh Invoice, whose latest attempt also fails with `paid_at = NULL`.
The `latest_payment` relationship uses `from_many?: true`, ordered by
`created_at DESC, id DESC` so failed attempts are still considered.

This is a deliberately small billing model with one Product per Invoice. It is
synthetic and requires no private application code or production data.

The exact Ash query is in
[`ProjectionBenchmark.query/1`](lib/projection_benchmark/projection_benchmark.ex):

```elixir
Invoice
|> Ash.Query.select([:id, :number])
|> Ash.Query.calculate(:product_name, :string, expr(product.name))
|> Ash.Query.calculate(:latest_payment_status, :string, expr(latest_payment.status))
|> Ash.Query.calculate(:latest_payment_paid_at, :utc_datetime_usec, expr(latest_payment.paid_at))
|> Ash.Query.sort(id: :asc)
```

The Product join provides the product name. The Payment subquery has 20 columns:
IDs, amount, currency, status, method, provider references, timestamps, refund
amount, fees, failure details, transaction ID, receipt URL and memo. Only
`status` and `paid_at` are needed outside that subquery. Internal filtering and
ordering still use `invoice_id`, `created_at` and `id`.

## Before and after

[`pins.exs`](pins.exs) fixes all three Ash dependencies to public commits.

- **Before:** upstream ash_sql at `1961731174355284814e97c4d0627779f945b173`.
- **After:** the proposed change at `7c76ce808e1d11dcb399927174f289a8c590bfc4`.
- Ash and AshPostgres are identical in both variants.

Each variant has its own lockfile, dependency directory, build directory and VM.
The benchmark verifies the installed Git SHAs. It uses unchanged upstream
AshPostgres to construct the Ecto query, then explicitly calls the proposed
optimizer in the after variant. It does not require an unreleased AshPostgres
dependency or the companion integration patch.

## Output and timing boundaries

`results/summary.md` reports the SQL byte counts for these exact queries.
`before-invoice_latest_payment.sql` and `after-invoice_latest_payment.sql`
contain the complete SQL. Each byte count is `byte_size(sql)` before adding a
trailing newline to the saved file.

`before.json` and `after.json` include:

- Fixture width, Invoice/Product/Payment counts, iterations, dependency SHAs and runtime versions.
- SQL generation time **including the optimizer on every after iteration**.
  Ash query construction is done beforehand and is not included in this timing.
- Warmed `Repo.all` time with named prepared statements, and separately with
  unnamed statements. These include client work and a DB round trip.
- PostgreSQL planning/execution medians from 9 `EXPLAIN ANALYZE` runs with
  `plan_cache_mode=force_custom_plan`. Full verbose plans are saved separately.
- Result and bind-parameter hashes. Each query is also checked against an
  independent expected-value fixture, including missing Payments and NULL payment timestamps.

Client timings use 20 warmup calls followed by the requested number of samples.
Schema creation, seeding, dependency compilation and file writing are excluded.
Both variants run sequentially; timing differences can include order, cache and
machine effects. There is no pass threshold for timing improvements.

The run fails if results/bind parameters differ, the fixture oracle fails, or
generated SQL does not shrink. SQL bytes are deterministic for the pinned
dependencies; timings are not. Bytes of generated SQL are not a measurement of
wire traffic: prepared statements may reuse already-parsed SQL.

The comparator also checks that the unoptimized SQL is identical in both
variants and that the lockfiles differ only in ash_sql.

## CI

The [Reproduce workflow](.github/workflows/benchmark.yml) runs the same command
and uploads SQL, plans, JSON metadata and the summary as an artifact.

If a local Docker build cannot reach DNS through its bridge network, the optional
`DOCKER_BUILD_NETWORK=host` setting passes Docker's host build-network option.
This is not needed for the benchmark's runtime database network.
