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
Use `DATABASE_URL` to change it. All fixture tables are temporary.

The script runs the same query with two pinned ash_sql commits, using separate
lockfiles, dependencies, builds and VMs. Ash and AshPostgres stay the same.
The after version calls `AshSql.Query.Projection.prune/1` before executing the
query; it does not need the companion AshPostgres patch.

## Result

```text
before: 1544 SQL bytes, 500 rows
after: 918 SQL bytes, 500 rows
```

The script checks that rows and bind parameters match. Generated SQL is saved to
`results/before.sql` and `results/after.sql`; an example is in [`examples/`](examples/).
Fixtures include missing payments and failed payments with `paid_at = NULL`.

PostgreSQL already prunes unused values. This example shows shorter SQL for
debugging, not a runtime speedup.
