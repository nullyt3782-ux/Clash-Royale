#!/usr/bin/env bash
set -e

# ================== CONFIG ==================

CLAN_TAG="QQVULYR2"
API="https://api.clashroyale.com/v1"
HDR=(-H "Authorization: Bearer $CR_TOKEN")
HTML="index.html"
TMP=$(mktemp)

cleanup() {
  rm -f "$TMP"
}
trap cleanup EXIT

# ================== helpers ==================

fmt_time() {
  local T=$1
  [ "$T" -le 0 ] && echo "0s" && return
  local D=$((T/86400))
  local H=$(((T%86400)/3600))
  local M=$(((T%3600)/60))

  if [ "$D" -gt 0 ]; then
    echo "${D}d ${H}h"
  elif [ "$H" -gt 0 ]; then
    echo "${H}h ${M}m"
  else
    echo "${M}m"
  fi
}

# ================== API ==================

MEMBERS=$(curl -s "${HDR[@]}" "$API/clans/%23$CLAN_TAG/members")
WAR=$(curl -s "${HDR[@]}" "$API/clans/%23$CLAN_TAG/currentriverrace")

# ================== procesar players ==================

process_player() {
  TAG="$1"
  NAME="$2"
  ROLE="$3"
  LASTSEEN_RAW="$4"
  TAG_CLEAN="${TAG#\#}"

  case "$ROLE" in
    leader) ROLE_TXT="💮 Líder" ;;
    coLeader) ROLE_TXT="🔱 Co-líder" ;;
    elder) ROLE_TXT="⭐ Veterano" ;;
    member) ROLE_TXT="🔰 Miembro" ;;
    *) ROLE_TXT="$ROLE" ;;
  esac

  # ---- última conexión ----
  CONN="—"
  if [ -n "$LASTSEEN_RAW" ]; then
    TS_CONN=$(date -u -d \
      "${LASTSEEN_RAW:0:4}-${LASTSEEN_RAW:4:2}-${LASTSEEN_RAW:6:2} \
${LASTSEEN_RAW:9:2}:${LASTSEEN_RAW:11:2}:${LASTSEEN_RAW:13:2}" +%s 2>/dev/null)

    if [ -n "$TS_CONN" ]; then
      NOW=$(date -u +%s)
      DIFF_CONN=$((NOW-TS_CONN))
      [ "$DIFF_CONN" -lt 0 ] && DIFF_CONN=0
      CONN=$(fmt_time "$DIFF_CONN")
    fi
  fi

  # ---- guerra ----
  PLAYER=$(echo "$WAR" | jq -c --arg TAG "$TAG" '.clans[].participants[]? | select(.tag==$TAG)')
  FAME=$(echo "$PLAYER" | jq -r '.fame // 0')
  DECKS=$(echo "$PLAYER" | jq -r '.decksUsed // 0')
  TODAY=$(echo "$PLAYER" | jq -r '.decksUsedToday // 0')
  BOATS=$(echo "$PLAYER" | jq -r '.boatAttacks // 0')

  FAME=${FAME:-0}
  DECKS=${DECKS:-0}
  TODAY=${TODAY:-0}
  BOATS=${BOATS:-0}

  # ---- última batalla ----
  MODE="—"
  LAST="—"

  BATTLE=$(curl -s "${HDR[@]}" "$API/players/%23$TAG_CLEAN/battlelog" \
    | jq 'if type=="array" and length>0 then .[0] else empty end')

  if [ -n "$BATTLE" ]; then
    MODE=$(echo "$BATTLE" | jq -r '.gameMode.name // .type // "—"')
    BTIME=$(echo "$BATTLE" | jq -r '.battleTime // empty')

    if [ -n "$BTIME" ]; then
      TS=$(date -u -d \
        "${BTIME:0:4}-${BTIME:4:2}-${BTIME:6:2} \
${BTIME:9:2}:${BTIME:11:2}:${BTIME:13:2}" +%s 2>/dev/null)

      if [ -n "$TS" ]; then
        NOW=$(date -u +%s)
        DIFF=$((NOW-TS))
        [ "$DIFF" -lt 0 ] && DIFF=0
        LAST=$(fmt_time "$DIFF")
      fi
    fi
  fi

  echo "$FAME|$NAME|$ROLE_TXT|$DECKS|$TODAY|$BOATS|$CONN|$MODE|$LAST" >> "$TMP"
}

export -f process_player
export WAR API HDR TMP

echo "$MEMBERS" | jq -c '.items[]' | while read -r row; do
  process_player \
    "$(echo "$row" | jq -r '.tag')" \
    "$(echo "$row" | jq -r '.name')" \
    "$(echo "$row" | jq -r '.role')" \
    "$(echo "$row" | jq -r '.lastSeen // empty')"
done

# ================== HTML ==================

cat > "$HTML" <<'HTML'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Clan Clash Royale</title>
<style>
body {
  margin:0;
  font-family: system-ui, sans-serif;
  background: #050b18;
  color:#fff;
}
h1 {
  text-align:center;
  padding:16px;
}
.card {
  background:#0b1226;
  margin:12px;
  padding:14px;
  border-radius:14px;
}
.rank {
  font-size:18px;
  font-weight:bold;
}
.role {
  opacity:.8;
}
.grid {
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:8px;
  margin-top:10px;
}
.box {
  background:#121a33;
  padding:8px;
  border-radius:10px;
  text-align:center;
}
.meta {
  margin-top:10px;
  font-size:14px;
  opacity:.9;
}
</style>
</head>
<body>
<h1>🏆 CLAN – CLASH ROYALE</h1>
HTML

i=0
sort -t"|" -k1,1nr "$TMP" | while IFS="|" read -r FAME NAME ROLE DECKS TODAY BOATS CONN MODE LAST; do
  i=$((i+1))
  cat >> "$HTML" <<HTML
<div class="card">
  <div class="rank">$i) $NAME</div>
  <div class="role">$ROLE</div>

  <div class="grid">
    <div class="box">🏅 $FAME</div>
    <div class="box">🃏 Total: $DECKS</div>
    <div class="box">Hoy: $TODAY/4</div>
    <div class="box">⚓ $BOATS</div>
  </div>

  <div class="meta">🕙 Última conexión: $CONN</div>
  <div class="meta">⚔ Última batalla: $MODE $LAST</div>
</div>
HTML
done

echo "</body></html>" >> "$HTML"
