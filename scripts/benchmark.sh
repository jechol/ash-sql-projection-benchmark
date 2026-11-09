#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

for variant in before after; do
  export PROJECTION_VARIANT="$variant"
  if [[ "${BENCH_PRECOMPILED:-0}" != 1 ]]; then
    mix deps.get
    mix compile --warnings-as-errors
  fi
  mix run --no-compile --no-deps-check -e 'ProjectionBenchmark.run()'
done
mix run --no-compile --no-deps-check -e 'ProjectionBenchmark.compare()'
