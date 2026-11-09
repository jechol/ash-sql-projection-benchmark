#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
read -r -a docker_cmd <<< "${DOCKER:-docker}"
run_id="projection-bench-$$"
results_dir="${RESULTS_DIR:-$PWD/results}"
mkdir -p "$results_dir"
results_dir="$(cd "$results_dir" && pwd)"

cleanup() {
  "${docker_cmd[@]}" rm -f "$run_id-db" >/dev/null 2>&1 || true
  "${docker_cmd[@]}" network rm "$run_id" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"${docker_cmd[@]}" build --network="${DOCKER_BUILD_NETWORK:-default}" -t ash-sql-projection-benchmark .
"${docker_cmd[@]}" network create "$run_id" >/dev/null
"${docker_cmd[@]}" run -d --name "$run_id-db" --network "$run_id" --network-alias db \
  -e POSTGRES_USER=benchmark -e POSTGRES_PASSWORD=benchmark -e POSTGRES_DB=projection_benchmark \
  --health-cmd='pg_isready -h 127.0.0.1 -U benchmark -d projection_benchmark' --health-interval=1s --health-retries=60 \
  postgres:17@sha256:ff87138949ad9a46f32ff23bd6852b52ce024a13dffe9b4087be98292cdd3b4f >/dev/null

ready=0
for _ in {1..60}; do
  if [[ "$("${docker_cmd[@]}" inspect --format '{{.State.Health.Status}}' "$run_id-db")" == healthy ]]; then
    ready=1
    break
  fi
  sleep 1
done
[[ "$ready" == 1 ]] || { echo 'PostgreSQL did not become ready' >&2; exit 1; }

"${docker_cmd[@]}" run --rm --network "$run_id" --user "$(id -u):$(id -g)" \
  -e DATABASE_URL=postgres://benchmark:benchmark@db:5432/projection_benchmark \
  -e BENCH_ROWS="${BENCH_ROWS:-500}" -e BENCH_ITERATIONS="${BENCH_ITERATIONS:-200}" \
  -v "$results_dir:/app/results" ash-sql-projection-benchmark
