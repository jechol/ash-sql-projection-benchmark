# Ash SQL projection example

Reproduction for [jechol/ash_sql#3](https://github.com/jechol/ash_sql/pull/3).

Read an Invoice's number, Product name, and latest Payment's `status` and
`paid_at`. The Payment resource has 20 fields, but only those two are needed
outside the `from_many?` subquery. The patch reduces its selection accordingly.

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
lockfiles, dependencies, builds and VMs. Ash and AshPostgres stay the same.
The after version calls `AshSql.Query.Projection.prune/1` before executing the
query; it does not need the companion AshPostgres patch.

## Result

```text
before: 1532 SQL bytes, 500 rows
after: 906 SQL bytes, 500 rows
```

The script checks that rows and bind parameters match. Generated SQL is saved to
`results/before.sql` and `results/after.sql`; an example is in [`examples/`](examples/).
Fixtures include missing payments and failed payments with `paid_at = NULL`.

PostgreSQL already prunes unused values. This example shows shorter SQL for
debugging, not a runtime speedup.

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
      ssp0."status" AS "status",
      ssp0."paid_at" AS "paid_at"
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
