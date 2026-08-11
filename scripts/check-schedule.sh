#!/usr/bin/env bash
# Determine push mode from the MLB schedule for a team.
# Outputs: fast | once | skip
#   fast  - live game or pregame window; push.sh loops every 90s
#   once  - render once (final score, upcoming game, hourly refresh)
#   skip  - no game activity; skip this workflow run
set -euo pipefail

TEAM_ID="${TEAM_ID:-141}"
TIMEZONE="${TIMEZONE:-America/Vancouver}"
WINDOW_BEFORE_MIN="${WINDOW_BEFORE_MIN:-30}"
WINDOW_AFTER_MIN="${WINDOW_AFTER_MIN:-300}"
SKIP_HOURS="${SKIP_HOURS:-6}"

now_epoch="$(TZ="${TIMEZONE}" date +%s)"
today="$(TZ="${TIMEZONE}" date +%Y-%m-%d)"
yesterday="$(TZ="${TIMEZONE}" date -d "${today} -1 day" +%Y-%m-%d)"
tomorrow="$(TZ="${TIMEZONE}" date -d "${today} +2 days" +%Y-%m-%d)"

schedule_url="https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId=${TEAM_ID}&startDate=${yesterday}&endDate=${tomorrow}&hydrate=team"

result="$(curl -fsSL "${schedule_url}" | python3 -c "
import json, sys
from datetime import datetime, timezone

now_epoch = int(sys.argv[1])
window_before = int(sys.argv[2]) * 60
window_after = int(sys.argv[3]) * 60
skip_hours = int(sys.argv[4])
payload = json.load(sys.stdin)

now = datetime.fromtimestamp(now_epoch, tz=timezone.utc)
games = []
for day in payload.get('dates', []):
    games.extend(day.get('games', []))

if not games:
    print('skip')
    raise SystemExit(0)

def parse_game_time(game):
    raw = game.get('gameDate')
    if not raw:
        return None
    return datetime.fromisoformat(raw.replace('Z', '+00:00'))

live = False
in_window = False
upcoming_soon = False
recent_final = False

for game in games:
    status = game.get('status', {}).get('abstractGameState', '')
    start = parse_game_time(game)

    if status == 'Live':
        live = True
        break

    if status == 'Final' and start:
        end_estimate = start.timestamp() + (3.5 * 3600)
        if now.timestamp() - end_estimate < skip_hours * 3600:
            recent_final = True

    if start:
        start_epoch = start.timestamp()
        if now_epoch >= start_epoch - window_before and now_epoch <= start_epoch + window_after:
            in_window = True
        if 0 <= start_epoch - now_epoch <= window_before:
            upcoming_soon = True

if live or in_window or upcoming_soon:
    print('fast')
elif recent_final:
    print('once')
else:
    minute = datetime.fromtimestamp(now_epoch).minute
    print('once' if minute < 5 else 'skip')
" "${now_epoch}" "${WINDOW_BEFORE_MIN}" "${WINDOW_AFTER_MIN}" "${SKIP_HOURS}")"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "push_mode=${result}" >> "${GITHUB_OUTPUT}"
else
  echo "${result}"
fi
