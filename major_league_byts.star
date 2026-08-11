"""Major League Byts - live MLB scorebug for Tidbyt."""

load("http.star", "http")
load("render.star", "render")
load("time.star", "time")

DEFAULT_TIMEZONE = "America/Vancouver"
DEFAULT_TEAM_ID = "141"
MLB_BASE = "https://statsapi.mlb.com/api/v1"
MLB_LIVE = "https://statsapi.mlb.com/api/v1.1"

# Primary color, background accent, logo letter
TEAM_STYLES = {
    "ARI": ("#A71930", "#000000", "A"),
    "ATL": ("#CE1141", "#13274F", "A"),
    "BAL": ("#DF4601", "#000000", "O"),
    "BOS": ("#BD3039", "#0C2340", "B"),
    "CHC": ("#0E3386", "#CC3433", "C"),
    "CWS": ("#27251F", "#C4CED4", "C"),
    "CIN": ("#C6011F", "#000000", "C"),
    "CLE": ("#00385D", "#E50022", "C"),
    "COL": ("#33006F", "#C4CED4", "C"),
    "DET": ("#0C2340", "#FA4616", "D"),
    "HOU": ("#002D62", "#EB6E1F", "H"),
    "KC": ("#004687", "#BD9B60", "K"),
    "LAA": ("#BA0021", "#003263", "A"),
    "LAD": ("#005A9C", "#EF3E42", "L"),
    "MIA": ("#00A3E0", "#EF3340", "M"),
    "MIL": ("#12284B", "#FFC52F", "M"),
    "MIN": ("#002B5C", "#D31145", "M"),
    "NYM": ("#002D72", "#FF5910", "N"),
    "NYY": ("#003087", "#E4002C", "N"),
    "ATH": ("#003831", "#EFB21E", "A"),
    "OAK": ("#003831", "#EFB21E", "A"),
    "PHI": ("#E81828", "#002D72", "P"),
    "PIT": ("#FDB827", "#27251F", "P"),
    "SD": ("#2F241D", "#FFC425", "S"),
    "SF": ("#FD5A1E", "#27251F", "S"),
    "SEA": ("#0C2C56", "#005C5C", "S"),
    "STL": ("#C41E3A", "#0C2340", "S"),
    "TB": ("#092C5C", "#8FBCE6", "T"),
    "TEX": ("#003278", "#C0111F", "T"),
    "TOR": ("#134A8E", "#1D2D5C", "T"),
    "WSH": ("#AB0003", "#14225A", "W"),
}

def main(config):
    timezone = config.get("timezone") or DEFAULT_TIMEZONE
    team_id = str(config.get("team_id") or DEFAULT_TEAM_ID)

    if not team_id:
        return _render_setup("Set team_id")

    games = _fetch_schedule(team_id, timezone)
    if len(games) == 0:
        return _render_idle("No games")

    game = _select_game(games, timezone)
    if not game:
        return _render_idle("No games")

    status = game.get("status", {}).get("abstractGameState", "")
    away = game.get("teams", {}).get("away", {})
    home = game.get("teams", {}).get("home", {})
    away_abbr = _team_abbr(away)
    home_abbr = _team_abbr(home)

    if status == "Live" or status == "Final":
        live = _fetch_live(game.get("gamePk"))
        if live:
            return _render_scorebug(live, status == "Final")

        away_score = away.get("score", 0) or 0
        home_score = home.get("score", 0) or 0
        return _render_simple_score(
            away_abbr,
            home_abbr,
            away_score,
            home_score,
            "FINAL" if status == "Final" else "LIVE",
        )

    return _render_upcoming(
        away_abbr,
        home_abbr,
        game.get("gameDate", ""),
        timezone,
    )

def _team_abbr(team_block):
    team = team_block.get("team", {})
    abbr = team.get("abbreviation")
    if abbr:
        return abbr
    return "???"

def _fetch_schedule(team_id, timezone):
    now = time.now().in_location(timezone)
    today = now.format("2006-01-02")
    yesterday = (now + time.parse_duration("-24h")).format("2006-01-02")
    tomorrow = (now + time.parse_duration("48h")).format("2006-01-02")

    url = (
        MLB_BASE + "/schedule?sportId=1&teamId=" + team_id +
        "&startDate=" + yesterday + "&endDate=" + tomorrow +
        "&hydrate=linescore,team"
    )
    response = http.get(url, ttl_seconds = 60)
    if response.status_code != 200:
        fail("Schedule request failed: " + str(response.status_code))

    body = response.json()
    games = []
    for day in body.get("dates", []):
        for game in day.get("games", []):
            games.append(game)

    return games

def _select_game(games, timezone):
    live = None
    final = None
    upcoming = None

    for game in games:
        status = game.get("status", {}).get("abstractGameState", "")
        if status == "Live":
            live = game
        elif status == "Final":
            if not final or game.get("gameDate", "") > final.get("gameDate", ""):
                final = game
        elif status in ["Preview", "Pre-Game", "Scheduled"]:
            if not upcoming or game.get("gameDate", "") < upcoming.get("gameDate", ""):
                upcoming = game

    if live:
        return live
    if final:
        return final
    return upcoming

def _fetch_live(game_pk):
    if not game_pk:
        return None

    url = MLB_LIVE + "/game/" + str(game_pk) + "/feed/live"
    response = http.get(url, ttl_seconds = 30)
    if response.status_code != 200:
        return None

    data = response.json()
    game_data = data.get("gameData", {})
    live_data = data.get("liveData", {})
    linescore = live_data.get("linescore", {})
    if not linescore:
        return None

    away = game_data.get("teams", {}).get("away", {}).get("abbreviation", "???")
    home = game_data.get("teams", {}).get("home", {}).get("abbreviation", "???")
    teams = linescore.get("teams", {})
    offense = linescore.get("offense", {})

    return {
        "away": away,
        "home": home,
        "away_score": teams.get("away", {}).get("runs", 0) or 0,
        "home_score": teams.get("home", {}).get("runs", 0) or 0,
        "inning": linescore.get("currentInning", 0) or 0,
        "half": linescore.get("inningHalf", ""),
        "balls": linescore.get("balls", 0) or 0,
        "strikes": linescore.get("strikes", 0) or 0,
        "outs": linescore.get("outs", 0) or 0,
        "first": offense.get("first") != None,
        "second": offense.get("second") != None,
        "third": offense.get("third") != None,
    }

def _team_style(abbr):
    style = TEAM_STYLES.get(abbr)
    if style:
        return style
    return ("#334155", "#111827", abbr[:1] if abbr else "?")

def _render_scorebug(data, is_final):
    away_style = _team_style(data["away"])
    home_style = _team_style(data["home"])

    state_label = "FINAL" if is_final else _format_count(data["balls"], data["strikes"])
    inning_label = "F" if is_final else str(data["inning"])
    half_symbol = "" if is_final else _half_symbol(data["half"])
    outs = 0 if is_final else data["outs"]

    return render.Root(
        child = render.Row(
            expanded = True,
            children = [
                _render_logo_column(away_style, home_style),
                _render_score_column(data["away"], data["home"], data["away_score"], data["home_score"]),
                _render_state_column(
                    data["first"],
                    data["second"],
                    data["third"],
                    half_symbol,
                    inning_label,
                    state_label,
                    outs,
                    is_final,
                ),
            ],
        ),
    )

def _render_simple_score(away, home, away_score, home_score, label):
    away_style = _team_style(away)
    home_style = _team_style(home)

    return render.Root(
        child = render.Row(
            expanded = True,
            children = [
                _render_logo_column(away_style, home_style),
                _render_score_column(away, home, away_score, home_score),
                render.Box(
                    width = 26,
                    height = 32,
                    color = "#000000",
                    child = render.Column(
                        expanded = True,
                        main_align = "center",
                        cross_align = "center",
                        children = [
                            render.Text(label, color = "#FFFFFF", font = "5x8"),
                        ],
                    ),
                ),
            ],
        ),
    )

def _render_upcoming(away, home, game_date, timezone):
    away_style = _team_style(away)
    home_style = _team_style(home)
    when = _format_game_time(game_date, timezone)

    return render.Root(
        child = render.Row(
            expanded = True,
            children = [
                _render_logo_column(away_style, home_style),
                render.Box(
                    width = 38,
                    height = 32,
                    color = "#000000",
                    child = render.Column(
                        expanded = True,
                        main_align = "center",
                        cross_align = "center",
                        children = [
                            render.Text(away + " @ " + home, color = "#FFFFFF", font = "5x8"),
                            render.Text("NEXT", color = "#94A3B8", font = "tom-thumb"),
                            render.Text(when, color = "#E2E8F0", font = "tom-thumb"),
                        ],
                    ),
                ),
            ],
        ),
    )

def _render_logo_column(away_style, home_style):
    return render.Box(
        width = 16,
        height = 32,
        child = render.Column(
            children = [
                _render_logo_cell(away_style),
                _render_logo_cell(home_style),
            ],
        ),
    )

def _render_logo_cell(style):
    primary, accent, letter = style
    return render.Box(
        width = 16,
        height = 16,
        color = accent,
        child = render.Box(
            color = primary,
            width = 14,
            height = 14,
            child = render.Text(
                letter,
                color = "#FFFFFF",
                font = "6x13",
            ),
        ),
    )

def _render_score_column(away, home, away_score, home_score):
    return render.Box(
        width = 22,
        height = 32,
        color = "#000000",
        child = render.Column(
            children = [
                _render_score_row(away, away_score),
                _render_score_row(home, home_score),
            ],
        ),
    )

def _render_score_row(abbr, score):
    return render.Box(
        width = 22,
        height = 16,
        color = "#000000",
        child = render.Column(
            main_align = "center",
            cross_align = "center",
            children = [
                render.Text(abbr, color = "#FFFFFF", font = "tom-thumb"),
                render.Text(str(score), color = "#FFFFFF", font = "6x13"),
            ],
        ),
    )

def _render_state_column(first, second, third, half_symbol, inning, count_label, outs, is_final):
    base_color_on = "#FFFFFF"
    base_color_off = "#333333"

    return render.Box(
        width = 26,
        height = 32,
        color = "#000000",
        child = render.Column(
            expanded = True,
            main_align = "space_evenly",
            cross_align = "center",
            children = [
                render.Box(
                    height = 14,
                    child = _render_bases(first, second, third, base_color_on, base_color_off, is_final),
                ),
                render.Row(
                    main_align = "space_evenly",
                    cross_align = "center",
                    children = [
                        render.Row(
                            children = [
                                render.Text(half_symbol, color = "#FFFFFF", font = "tom-thumb"),
                                render.Text(inning, color = "#FFFFFF", font = "5x8"),
                            ],
                        ),
                        render.Column(
                            cross_align = "center",
                            children = [
                                render.Text(count_label, color = "#FFFFFF", font = "5x8"),
                                _render_outs(outs, is_final),
                            ],
                        ),
                    ],
                ),
            ],
        ),
    )

def _render_bases(first, second, third, on_color, off_color, is_final):
    if is_final:
        return render.Text("FINAL", color = "#64748B", font = "tom-thumb")

    return render.Column(
        main_align = "center",
        cross_align = "center",
        children = [
            render.Box(
                width = 5,
                height = 5,
                color = on_color if second else off_color,
            ),
            render.Row(
                children = [
                    render.Box(width = 2),
                    render.Box(
                        width = 5,
                        height = 5,
                        color = on_color if third else off_color,
                    ),
                    render.Box(width = 2),
                    render.Box(
                        width = 5,
                        height = 5,
                        color = on_color if first else off_color,
                    ),
                ],
            ),
        ],
    )

def _render_outs(outs, is_final):
    if is_final:
        return render.Box(height = 4)

    out_on = "#FFFFFF"
    out_off = "#333333"
    return render.Row(
        children = [
            render.Box(width = 4, height = 4, color = out_on if outs >= 1 else out_off),
            render.Box(width = 2),
            render.Box(width = 4, height = 4, color = out_on if outs >= 2 else out_off),
        ],
    )

def _half_symbol(half):
    if half == "Top":
        return "^"
    if half == "Bottom":
        return "v"
    return ""

def _format_count(balls, strikes):
    return str(balls) + "-" + str(strikes)

def _format_game_time(game_date, timezone):
    if not game_date:
        return "TBD"

    parsed = time.parse_time(game_date)
    if not parsed:
        return "TBD"

    local = parsed.in_location(timezone)
    return local.format("Jan 2") + " " + local.format("3:04 PM")

def _render_setup(message):
    return render.Root(
        child = render.Box(
            color = "#000000",
            child = render.Column(
                expanded = True,
                main_align = "center",
                cross_align = "center",
                children = [
                    render.Text("MLB BYTS", color = "#FFFFFF", font = "5x8"),
                    render.Text(message, color = "#94A3B8", font = "tom-thumb"),
                ],
            ),
        ),
    )

def _render_idle(message):
    return render.Root(
        child = render.Box(
            color = "#000000",
            child = render.Column(
                expanded = True,
                main_align = "center",
                cross_align = "center",
                children = [
                    render.Text("MLB BYTS", color = "#334155", font = "5x8"),
                    render.Text(message, color = "#475569", font = "tom-thumb"),
                ],
            ),
        ),
    )
