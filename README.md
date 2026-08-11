# Major League Byts

Live MLB scorebug for Tidbyt — scores, inning, count, bases, and outs for your favourite team.

Fork this repo, add your Tidbyt credentials and team as GitHub variables, and a scheduled workflow keeps your device updated. No Tidbyt app store required.

## What it shows

| When | Display |
|------|---------|
| **Live game** | Scorebug: team logos, scores, inning, count, bases, outs |
| **Just finished** | Final score with team colours |
| **Upcoming game** | Matchup and start time |
| **Off day** | Next scheduled game or idle screen |

Default team is the **Toronto Blue Jays** (`TEAM_ID=141`) in **America/Vancouver** timezone.

---

## How updates work

This app uses the MLB schedule to decide how often to ping the API — not guesswork about game times.

1. **GitHub Actions runs every 5 minutes** (the minimum interval GitHub allows).
2. **`scripts/check-schedule.sh`** queries the MLB schedule and picks a mode:
   - **`fast`** — a game is live, or first pitch is within 30 minutes, or we're inside the game window (30 min before → 5 hours after scheduled start). `push.sh` enters a **90-second push loop** until the game ends.
   - **`once`** — show a final score, upcoming game, or hourly refresh. Renders once and exits.
   - **`skip`** — no game activity soon. The workflow exits without calling Tidbyt (saves runner minutes).
3. During a live game, updates land on your Tidbyt roughly **every 90 seconds** without waiting for the next cron tick.

You do **not** need to ping the API constantly on off days. The schedule tells us when to wake up.

---

## Setup guide

### Step 1: Fork this repository

1. Click **Fork** at the top of this GitHub page.
2. Go to the **Actions** tab in your fork.
3. If GitHub asks, click **I understand my workflows, go ahead and enable them**.

### Step 2: Get your Tidbyt device ID and API key

1. Open the **Tidbyt** app on your phone.
2. Tap your device → **Settings** (gear icon) → **Get API key**.
3. Save:
   - **API key** → `TIDBYT_API_TOKEN` (secret)
   - **Device ID** → `TIDBYT_DEVICE_ID` (variable)

Never commit your API key to the repo.

### Step 3: Pick your team

Look up any team's ID:

```bash
chmod +x scripts/resolve-team.sh
./scripts/resolve-team.sh TOR
```

Or use these common IDs:

| Team | Abbr | ID |
|------|------|----|
| Blue Jays | TOR | 141 |
| Red Sox | BOS | 111 |
| Yankees | NYY | 147 |
| Dodgers | LAD | 119 |
| Pirates | PIT | 134 |

Full list: `curl -s "https://statsapi.mlb.com/api/v1/teams?sportId=1" | jq '.teams[] | {id, abbreviation}'`

### Step 4: Add GitHub secrets and variables

In **your fork**: **Settings → Secrets and variables → Actions**

#### Secret (required)

| Name | Value |
|------|-------|
| `TIDBYT_API_TOKEN` | Your API key from Step 2 |

#### Variables

| Name | Required | Default | Notes |
|------|----------|---------|-------|
| `TIDBYT_DEVICE_ID` | Yes | — | From Tidbyt app settings |
| `TEAM_ID` | No | `141` | Blue Jays |
| `TIMEZONE` | No | `America/Vancouver` | [IANA timezone](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) |
| `TIDBYT_INSTALLATION_ID` | No | `MajorLeagueByts` | Name in Tidbyt rotation |
| `PUSH_INTERVAL_SEC` | No | `90` | Seconds between live-game updates |
| `MAX_FAST_MINUTES` | No | `360` | Max duration of a live push loop |

### Step 5: Run the workflow

1. **Actions → Push Major League Byts to Tidbyt → Run workflow**
2. Check your Tidbyt — **MajorLeagueByts** should appear in rotation.

The workflow also runs automatically every 5 minutes and self-throttles on off days.

---

## Local setup (optional)

```bash
cp .env.example .env
# Edit .env with your Tidbyt credentials
chmod +x push.sh scripts/*.sh
./push.sh
```

Preview in a browser without pushing:

```bash
pixlet serve major_league_byts.star team_id=141 timezone=America/Vancouver
```

Open http://localhost:8080

Requires [Pixlet](https://tidbyt.dev/docs/build/installing-pixlet) v0.34.0+.

---

## Troubleshooting

**Workflow skips every run**  
Normal on off days between hourly refreshes. Force a push with **Run workflow**, or wait for the top-of-hour `once` refresh.

**Live game not updating fast enough**  
GitHub cron fires every 5 minutes; once a live game is detected, the 90-second loop kicks in within that run. First fast update may take up to 5 minutes after first pitch.

**Wrong team showing**  
Check `TEAM_ID` matches your team. Run `scripts/resolve-team.sh ABBR` to confirm.

**"Set team_id" on Tidbyt**  
`TEAM_ID` variable is missing or misnamed.

---

## Files

| File | Purpose |
|------|---------|
| `major_league_byts.star` | Pixlet scorebug app |
| `push.sh` | Render, push, and live-game loop |
| `scripts/check-schedule.sh` | Schedule-aware push mode |
| `scripts/resolve-team.sh` | Look up team ID from abbreviation |
| `.env.example` | Local config template |
| `.github/workflows/push.yml` | Scheduled auto-push |

## License

MIT — fork it, tweak it, share it.
