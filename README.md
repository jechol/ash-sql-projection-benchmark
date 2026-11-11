# AshSql relationship projection benchmark

Compare three AshSql implementations using the same Invoice, Product and Payment resources:

| Variant | Implementation | Commit |
|---|---|---|
| `upstream` | Shared upstream base, no pruning | `1961731` |
| `ast_scan` | Final AST scan: [ash-project/ash_sql#281](https://github.com/ash-project/ash_sql/pull/281) | `7f7baef` |
| `tracked` | Collect fields during query construction: [jechol/ash_sql#4](https://github.com/jechol/ash_sql/pull/4) | `c434539` |

All dependencies except AshSql are identical; full commit pins are in [`pins.exs`](pins.exs).
Each variant has its own lockfile, dependencies and build directory.

## Run

Requires Elixir 1.18+ and PostgreSQL 17+ on localhost:5432.

```sh
./run.sh
```

The default connection is `postgres://postgres:postgres@localhost:5432/postgres`.
Use `DATABASE_URL` to choose another database:

```sh
DATABASE_URL=postgres://postgres:postgres@localhost:5432/projection_benchmark ./run.sh
```

The script creates the database and tables with `mix ash.setup`, then inserts
10 Products, 500 Invoices and 1,350 Payments with `Ash.Seed.upsert!`. Tables and
fixture data are left in place. The migration was generated with `mix ash.codegen`.
All variants use the same database; setup and compilation finish before measurement.

The three queries are:

- Invoice number, without joins.
- Invoice number, Product name, and latest Payment's `status` and `paid_at`.
- The same latest Payment query, filtered by `latest_payment.amount > 1`.

Payment has 20 fields. Fixtures include missing payments and failed payments with
`paid_at = NULL`. The queries return 500, 500 and 450 rows respectively. The script
checks rows and bind parameters before/after pruning, then compares all three
variants. SQL and timing output are written to `results/`.

Pruning is invoked directly before `Repo.to_sql/2` or `Repo.all/1`. This isolates
AshSql and does not require the execution hooks in
[ash-project/ash_postgres#919](https://github.com/ash-project/ash_postgres/pull/919).
It does not measure the complete `Ash.read!` lifecycle.

## Measurements

[`bench.exs`](bench.exs) measures three phases:

- `prune`: the final pass on an already-built Ecto query; a no-op in `upstream`.
- `build + prune + SQL generation`: `Ash.data_layer_query!/1`, pruning, and
  `Repo.to_sql/2`. SQL generation produces a string and bind parameters without
  querying PostgreSQL. This includes field collection in the `tracked` variant.
- `build + prune + execute`: query construction, pruning, PostgreSQL execution
  and result mapping.

The final pass alone excludes field collection, so it cannot establish the total
cost of the new implementation. Use the build-inclusive measurements for that.

Each result is the median of 15 batch averages: 1,000 calls for pruning, 150 for
build + SQL generation, and 10 for build + execution. Phase order rotates between
rounds. There is no separate warmup loop; validation reads run before timing.
Compilation and fixture setup are excluded.

Reductions count only the calling Erlang process, not the whole VM or PostgreSQL.
Variants run in separate processes, in `upstream`, `ast_scan`, `tracked` order. Small
time differences can reflect run order or system load; repeat runs before drawing
conclusions. The phases are independent and their times are not additive.

To repeat just the measurements after setup:

```sh
for variant in tracked ast_scan upstream; do
  PROJECTION_VARIANT="$variant" mix run bench.exs
done
```

PostgreSQL already prunes unused values. This benchmark primarily evaluates SQL
readability and the Elixir cost of producing shorter SQL, not a database speedup.

An [example run](examples/bench.txt) on an AMD Ryzen 5 7430U, Elixir 1.19.5 /
OTP 28.3.1 and PostgreSQL 17.10, for the latest Payment query:

| Variant | SQL bytes | Build + prune + SQL, run 1 | Build + prune + SQL, run 2 | Reductions, run 1 / run 2 |
|---|---:|---:|---:|---:|
| `upstream` | 1,532 | 610.5 µs | 2,189.3 µs | 35,691 / 35,710 |
| `ast_scan` | 960 | 652.4 µs | 756.6 µs | 38,034 / 38,059 |
| `tracked` | 906 | 634.5 µs | 766.7 µs | 36,259 / 36,296 |

For this query, `tracked` used about 1.6% more caller reductions than the upstream
base, and about 4.6% fewer than the AST scan. Wall times varied substantially
between runs, so they do not establish a runtime speedup.

## Generated SQL

Formatted for readability; byte counts refer to the original output. JOINs and
subquery nesting are unchanged. See [`examples/`](examples/) for saved output.

### Upstream base

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

### Collected fields (#4)

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
