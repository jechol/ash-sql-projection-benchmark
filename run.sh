#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

for variant in before after; do
  export PROJECTION_VARIANT="$variant"
  mix deps.get
  if [[ "$variant" == before ]]; then
    mix ash.setup
    mix run priv/repo/seeds.exs
  fi
  mix run -e 'ProjectionBenchmark.run()'
done

cmp results/before.term results/after.term
echo 'Results and bind parameters match. SQL is in results/before.sql and results/after.sql.'
