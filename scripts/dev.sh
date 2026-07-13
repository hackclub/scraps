#!/usr/bin/env bash
# Starts the full local dev stack: postgres, redis, the Rails backend, Sidekiq, and the SvelteKit frontend.
# Ctrl+C stops everything.
set -e
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker start scraps-postgres scraps-redis >/dev/null

pids=()
cleanup() {
	echo "Stopping dev stack..."
	kill "${pids[@]}" 2>/dev/null
}
trap cleanup EXIT INT TERM

(cd "$root/backend" && bundle exec rails server) &
pids+=($!)

(cd "$root/backend" && bundle exec sidekiq) &
pids+=($!)

(cd "$root/frontend" && npm run dev) &
pids+=($!)

wait
