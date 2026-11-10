# Ash SQL projection example

Example for [ash-project/ash_sql#281](https://github.com/ash-project/ash_sql/pull/281).
Query-execution integration: [ash-project/ash_postgres#919](https://github.com/ash-project/ash_postgres/pull/919).

Read an Invoice's number, Product name, and latest Payment's `status` and
`paid_at`. The Payment resource has 20 fields, but only those two are needed
outside the `from_many?` subquery. The patch narrows the selection, conservatively retaining extra columns when
named bindings overlap.

## Run

Requires Elixir 1.18+ and PostgreSQL on localhost:5432.

```sh
./run.sh
```

The default connection is `postgres://postgres:postgres@localhost:5432/postgres`.
Use `DATABASE_URL` to change it. The script creates `products`, `invoices` and
`payments` tables and leaves the fixture data in the database.

Migration and seed data run once, then both variants read the same tables.
The migration was generated from the Resources with `mix ash.codegen`;
`priv/repo/seeds.exs` inserts data with `Ash.Seed.upsert!`.

The script runs the same query with two pinned ash_sql commits, using separate
lockfiles, dependencies and builds. Ash and AshPostgres stay the same.
The after version calls `AshSql.Query.Projection.prune/1` before executing the
query; it does not need the companion AshPostgres patch.

## Result

```text
before: 1532 SQL bytes, 500 rows
after: 960 SQL bytes, 500 rows
```

The script checks that rows and bind parameters match. Generated SQL is saved to
`results/before.sql` and `results/after.sql`; an example is in [`examples/`](examples/).
Fixtures include missing payments and failed payments with `paid_at = NULL`.

PostgreSQL already prunes unused values. This example shows shorter SQL for
debugging, not a runtime speedup.

## Pruning overhead

After `./run.sh`, run:

```sh
PROJECTION_VARIANT=after mix run bench.exs
```

This compares the same query with and without the final pruning pass.
It includes a query without joins to measure the candidate check, and the latest
Payment query above. Rows and bind parameters must match before timing starts.

`SQL generation` calls `Repo.to_sql/2` to produce the SQL string and bind
parameters without executing a database query. It and `prune` use an already-built
Ecto query. `build` includes `Ash.data_layer_query!/1`; `execute` includes
PostgreSQL execution and result mapping instead of a separate `to_sql` call.
The script invokes pruning directly, as `run.sh` does; it does not benchmark the
companion AshPostgres integration or the complete `Ash.read!` lifecycle.

Times are microseconds per call: the median of 15 batch averages, after a short
warmup. Phase order rotates between rounds. Compilation and fixture setup are
excluded. The phases are measured independently, so their times are not additive.

An [example run](examples/bench.txt) on an AMD Ryzen 5 7430U,
Elixir 1.19.5 / OTP 28, PostgreSQL 17.10:

| Query | Build + SQL generation | Build + prune + SQL generation |
|---|---:|---:|
| No join | 55.38 µs | 56.42 µs |
| Latest Payment | 519.51 µs | 545.40 µs |

Across two runs, the latest Payment query added about 15–26 µs during query
construction and SQL generation. Its database-inclusive path took about 29–30 ms
in either case. These measurements show the cost of pruning, not a runtime speedup.

## Generated SQL

Formatted for readability; the byte counts above refer to the original output.
JOINs and subquery nesting are unchanged.

### Before

```sql
SELECT
  s0."id",
  s0."number",
  s0."__calculations__product_name",
  s0."__calculations__latest_payment_status",
  s0."__calculations__latest_payment_paid_at",
  s0."__order__"
FROM (
  SELECT DISTINCT ON (si0."id", si0."id")
    si0."id" AS "id",
    si0."number" AS "number",
    sp1."name"::text AS "__calculations__product_name",
    ss2."status"::text AS "__calculations__latest_payment_status",
    ss2."paid_at"::timestamp AS "__calculations__latest_payment_paid_at",
    row_number() OVER "order" AS "__order__"
  FROM "invoices" AS si0
  LEFT OUTER JOIN "public"."products" AS sp1
    ON si0."product_id" = sp1."id"
  LEFT OUTER JOIN LATERAL (
    SELECT
      ssp0."id" AS "id",
      ssp0."invoice_id" AS "invoice_id",
      ssp0."amount" AS "amount",
      ssp0."currency" AS "currency",
      ssp0."status" AS "status",
      ssp0."method" AS "method",
      ssp0."provider" AS "provider",
      ssp0."provider_reference" AS "provider_reference",
      ssp0."paid_at" AS "paid_at",
      ssp0."created_at" AS "created_at",
      ssp0."updated_at" AS "updated_at",
      ssp0."refunded_at" AS "refunded_at",
      ssp0."refund_amount" AS "refund_amount",
      ssp0."fee_amount" AS "fee_amount",
      ssp0."net_amount" AS "net_amount",
      ssp0."failure_code" AS "failure_code",
      ssp0."failure_message" AS "failure_message",
      ssp0."transaction_id" AS "transaction_id",
      ssp0."receipt_url" AS "receipt_url",
      ssp0."memo" AS "memo"
    FROM "public"."payments" AS ssp0
    WHERE (si0."id" = ssp0."invoice_id")
    ORDER BY ssp0."created_at" DESC, ssp0."id" DESC
    LIMIT 1
  ) AS ss2 ON TRUE
  WINDOW "order" AS (ORDER BY si0."id")
  ORDER BY si0."id", si0."id"
) AS s0
ORDER BY s0."__order__";
```

### After

```sql
SELECT
  s0."id",
  s0."number",
  s0."__calculations__product_name",
  s0."__calculations__latest_payment_status",
  s0."__calculations__latest_payment_paid_at",
  s0."__order__"
FROM (
  SELECT DISTINCT ON (si0."id", si0."id")
    si0."id" AS "id",
    si0."number" AS "number",
    sp1."name"::text AS "__calculations__product_name",
    ss2."status"::text AS "__calculations__latest_payment_status",
    ss2."paid_at"::timestamp AS "__calculations__latest_payment_paid_at",
    row_number() OVER "order" AS "__order__"
  FROM "invoices" AS si0
  LEFT OUTER JOIN "public"."products" AS sp1
    ON si0."product_id" = sp1."id"
  LEFT OUTER JOIN LATERAL (
    SELECT
      ssp0."id" AS "id",
      ssp0."status" AS "status",
      ssp0."paid_at" AS "paid_at",
      ssp0."created_at" AS "created_at"
    FROM "public"."payments" AS ssp0
    WHERE (si0."id" = ssp0."invoice_id")
    ORDER BY ssp0."created_at" DESC, ssp0."id" DESC
    LIMIT 1
  ) AS ss2 ON TRUE
  WINDOW "order" AS (ORDER BY si0."id")
  ORDER BY si0."id", si0."id"
) AS s0
ORDER BY s0."__order__";
```
