#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

for variant in upstream ast_scan tracked; do
  export PROJECTION_VARIANT="$variant"
  mix deps.get
  if [[ "$variant" == upstream ]]; then
    mix ash.setup
    mix run priv/repo/seeds.exs
  fi
  mix compile
done

for variant in upstream ast_scan tracked; do
  export PROJECTION_VARIANT="$variant"
  mix run -e 'ProjectionBenchmark.run()'
  mix run bench.exs
done

cmp results/upstream.term results/ast_scan.term
cmp results/upstream.term results/tracked.term
echo 'Results and bind parameters match across all three variants. See results/ for SQL and timings.'
