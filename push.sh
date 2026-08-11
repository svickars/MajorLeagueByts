#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -z "${TIDBYT_API_TOKEN:-}" ]]; then
  echo "Set TIDBYT_API_TOKEN before running push.sh" >&2
  exit 1
fi

if [[ -z "${TIDBYT_DEVICE_ID:-}" ]]; then
  echo "Set TIDBYT_DEVICE_ID before running push.sh" >&2
  exit 1
fi

: "${TIDBYT_INSTALLATION_ID:=MajorLeagueByts}"
: "${TIMEZONE:=America/Vancouver}"
: "${TEAM_ID:=141}"
: "${PUSH_INTERVAL_SEC:=90}"
: "${MAX_FAST_MINUTES:=360}"

render_args=(
  "team_id=${TEAM_ID}"
  "timezone=${TIMEZONE}"
)

render_and_push() {
  pixlet render major_league_byts.star "${render_args[@]}" -o major_league_byts.webp
  pixlet push \
    --api-token="${TIDBYT_API_TOKEN}" \
    --installation-id="${TIDBYT_INSTALLATION_ID}" \
    --background \
    "${TIDBYT_DEVICE_ID}" \
    major_league_byts.webp
}

is_live_game() {
  local status
  status="$(
    curl -fsSL \
      "https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId=${TEAM_ID}&date=$(TZ="${TIMEZONE}" date +%Y-%m-%d)&hydrate=team" \
      | python3 -c "
import json, sys
data = json.load(sys.stdin)
for day in data.get('dates', []):
    for game in day.get('games', []):
        if game.get('status', {}).get('abstractGameState') == 'Live':
            print('live')
            raise SystemExit(0)
print('not_live')
"
  )"
  [[ "${status}" == "live" ]]
}

should_fast_loop() {
  if [[ "${FORCE_FAST_LOOP:-false}" == "true" ]]; then
    return 0
  fi

  local mode
  mode="$(TEAM_ID="${TEAM_ID}" TIMEZONE="${TIMEZONE}" ./scripts/check-schedule.sh)"
  [[ "${mode}" == "fast" ]]
}

render_and_push

if ! should_fast_loop; then
  echo "Pushed Major League Byts to ${TIDBYT_DEVICE_ID} (single update)"
  exit 0
fi

echo "Live game window detected — updating every ${PUSH_INTERVAL_SEC}s until game ends"
iterations=$(( (MAX_FAST_MINUTES * 60) / PUSH_INTERVAL_SEC ))
for ((i = 1; i <= iterations; i++)); do
  sleep "${PUSH_INTERVAL_SEC}"
  if ! is_live_game; then
    render_and_push
    echo "Game no longer live — final push sent"
    exit 0
  fi
  render_and_push
  echo "Fast update ${i}/${iterations}"
done

echo "Reached fast-loop time limit; next scheduled workflow run will continue updates"
