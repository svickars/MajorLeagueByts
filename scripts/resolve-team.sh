#!/usr/bin/env bash
# Resolve MLB team abbreviation to team ID via the public Stats API.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <TEAM_ABBR>" >&2
  echo "Example: $0 TOR" >&2
  exit 1
fi

ABBR="$(echo "$1" | tr '[:lower:]' '[:upper:]')"

team_id="$(curl -fsSL "https://statsapi.mlb.com/api/v1/teams?sportId=1" | python3 -c "
import json, sys
abbr = sys.argv[1].upper()
data = json.load(sys.stdin)
for team in data.get('teams', []):
    if team.get('abbreviation', '').upper() == abbr:
        print(team['id'])
        break
" "${ABBR}")"

if [[ -z "${team_id:-}" ]]; then
  echo "Team not found for abbreviation: ${ABBR}" >&2
  exit 1
fi

cat <<EOF
Found ${ABBR} → team ID ${team_id}

GitHub repository variables:
  TEAM_ID=${team_id}
  TEAM_ABBR=${ABBR}

Local .env:
  TEAM_ID=${team_id}
  TEAM_ABBR=${ABBR}
EOF
