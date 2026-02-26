#!/usr/bin/env bash
# session-reviewer.sh — SessionStart hook
# Reads session metrics and emits a compact summary to stderr (terminal only).
# Matcher: "startup|resume|clear|compact"
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "${PLUGIN_ROOT}/lib/term.sh"

IFS= read -r -t 3 INPUT 2>/dev/null || INPUT="{}"
CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

METRICS_FILE="${CWD}/.claude/session-metrics.jsonl"

# No metrics → output nothing (first-ever session)
if [ ! -f "$METRICS_FILE" ] || [ ! -s "$METRICS_FILE" ]; then
    exit 0
fi

TOTAL_SESSIONS=$(wc -l < "$METRICS_FILE" | tr -d ' ')
if [ "$TOTAL_SESSIONS" -eq 0 ]; then
    exit 0
fi

# --- Extract last entry (pure grep/sed — no jq) ---
LAST_ENTRY=$(tail -1 "$METRICS_FILE")
extract_field() { echo "$1" | grep -oE "\"$2\":[^,}]+" | grep -oE '[^:]+$' | tr -d '"' | tr -d ' '; }

LAST_BRANCH=$(extract_field "$LAST_ENTRY" "branch")
LAST_DURATION=$(extract_field "$LAST_ENTRY" "duration")
LAST_TOOL_USE=$(extract_field "$LAST_ENTRY" "toolUseCount")
LAST_COMMITS=$(extract_field "$LAST_ENTRY" "commitsCreated")
LAST_FILES=$(extract_field "$LAST_ENTRY" "filesChanged")
LAST_WAVES_DONE=$(extract_field "$LAST_ENTRY" "wavesCompleted")
LAST_TOTAL_WAVES=$(extract_field "$LAST_ENTRY" "totalWaves")
LAST_PRS_MERGED=$(extract_field "$LAST_ENTRY" "prsMerged" || true)
LAST_PRS_MERGED="${LAST_PRS_MERGED:-0}"
LAST_REVIEW_ROUNDS=$(extract_field "$LAST_ENTRY" "reviewRounds" || true)
LAST_REVIEW_ROUNDS="${LAST_REVIEW_ROUNDS:-0}"

# Wave progress from task-state.md (current session context)
TASK_STATE="${CWD}/.claude/task-state.md"
WAVE_DISPLAY=""
if [ -f "$TASK_STATE" ]; then
    WAVE=$(grep "^Wave: " "$TASK_STATE" 2>/dev/null | head -1 | sed 's/^Wave: //' || echo "")
    STATUS_NOW=$(grep "^Status: " "$TASK_STATE" 2>/dev/null | head -1 | sed 's/^Status: //' || echo "")
    if [ "$STATUS_NOW" = "awaiting-review" ]; then
        WAVE_DISPLAY=" | waves $WAVE 🔄"
    elif [ -n "$WAVE" ]; then
        WAVE_DISPLAY=" | waves $WAVE"
    fi
elif [ -n "$LAST_WAVES_DONE" ] && [ -n "$LAST_TOTAL_WAVES" ] && [ "${LAST_TOTAL_WAVES:-0}" -gt 0 ] 2>/dev/null; then
    WAVE_DISPLAY=" | waves ${LAST_WAVES_DONE}/${LAST_TOTAL_WAVES}"
fi

# Default numeric values
LAST_DURATION="${LAST_DURATION:-0}"
LAST_TOOL_USE="${LAST_TOOL_USE:-0}"
LAST_COMMITS="${LAST_COMMITS:-0}"
LAST_FILES="${LAST_FILES:-0}"

# Format duration
if [ "$LAST_DURATION" -ge 3600 ] 2>/dev/null; then
    DURATION_STR="$(( LAST_DURATION / 3600 ))h $(( (LAST_DURATION % 3600) / 60 ))m"
elif [ "$LAST_DURATION" -ge 60 ] 2>/dev/null; then
    DURATION_STR="$(( LAST_DURATION / 60 )) min"
else
    DURATION_STR="${LAST_DURATION}s"
fi

# --- Trend analysis (last vs avg of up to 4 prior sessions) ---
compute_trend() {
    local last_val="$1" avg_val="$2" has_prev="$3"
    if [ "$has_prev" -eq 0 ]; then echo "—"; return; fi
    if [ "${avg_val:-0}" = "0" ]; then
        [ "${last_val:-0}" -gt 0 ] 2>/dev/null && echo "↑" || echo "→"; return
    fi
    local diff=$(( (last_val - avg_val) * 100 / avg_val ))
    if   [ "$diff" -ge  10 ] 2>/dev/null; then echo "↑"
    elif [ "$diff" -le -10 ] 2>/dev/null; then echo "↓"
    else echo "→"; fi
}

HAS_PREV=0
AVG_TOOL_USE=0; AVG_COMMITS=0; AVG_FILES=0

if [ "$TOTAL_SESSIONS" -ge 2 ] 2>/dev/null; then
    HAS_PREV=1
    PREV_COUNT=$(( TOTAL_SESSIONS - 1 ))
    [ "$PREV_COUNT" -gt 4 ] && PREV_COUNT=4
    PREV_LINES=$(head -n $(( TOTAL_SESSIONS - 1 )) "$METRICS_FILE" | tail -n "$PREV_COUNT")
    avg_field() {
        echo "$PREV_LINES" | grep -oE "\"$1\": *[0-9]+" | grep -oE '[0-9]+$' \
            | awk '{s+=$1; n++} END {if(n>0) printf "%d", s/n; else print 0}' || true
    }
    AVG_TOOL_USE=$(avg_field "toolUseCount")
    AVG_COMMITS=$(avg_field "commitsCreated")
    AVG_FILES=$(avg_field "filesChanged")
fi

TREND_TOOL_USE=$(compute_trend "$LAST_TOOL_USE" "$AVG_TOOL_USE" "$HAS_PREV")
TREND_COMMITS=$(compute_trend  "$LAST_COMMITS"  "$AVG_COMMITS"  "$HAS_PREV")
TREND_FILES=$(compute_trend    "$LAST_FILES"    "$AVG_FILES"    "$HAS_PREV")

# --- Scoring (value-based: ships code > activity) ---
TREND_UP=0; TREND_DOWN=0
for t in "$TREND_TOOL_USE" "$TREND_COMMITS" "$TREND_FILES"; do
    [ "$t" = "↑" ] && TREND_UP=$(( TREND_UP + 1 ))
    [ "$t" = "↓" ] && TREND_DOWN=$(( TREND_DOWN + 1 ))
done

SHIPPED=0
if [ "${LAST_COMMITS:-0}" -ge 1 ] && [ "${LAST_FILES:-0}" -ge 1 ] 2>/dev/null; then
    SHIPPED=1
fi

if [ "${LAST_PRS_MERGED:-0}" -ge 1 ] 2>/dev/null; then
    RATING="❤️ Awesome"
elif [ "$SHIPPED" -eq 1 ] && [ "$TREND_DOWN" -eq 0 ] 2>/dev/null; then
    RATING="❤️ Awesome"
elif [ "$SHIPPED" -eq 1 ] || [ "${LAST_TOOL_USE:-0}" -ge 10 ] 2>/dev/null; then
    RATING="😊 Good"
else
    RATING="😞 Do better"
fi

# --- Branch compliance ---
APIM_ENTRIES=$(grep -c '"branch":"apim-' "$METRICS_FILE" 2>/dev/null || true)
APIM_ENTRIES="${APIM_ENTRIES:-0}"
COMPLIANCE_STR=""
if [ "$TOTAL_SESSIONS" -gt 0 ] 2>/dev/null; then
    COMPLIANCE=$(( APIM_ENTRIES * 100 / TOTAL_SESSIONS ))
    COMPLIANCE_STR="${COMPLIANCE}% branch compliance"
fi

# --- Output (stderr — terminal only, not injected into Claude context) ---
printf '[Session Reviewer] Last: %s | %s%s | tools %s %s | commits %s %s | files %s %s → %s\n' \
    "${LAST_BRANCH:-—}" "$DURATION_STR" "$WAVE_DISPLAY" \
    "$LAST_TOOL_USE" "$TREND_TOOL_USE" \
    "$LAST_COMMITS" "$TREND_COMMITS" \
    "$LAST_FILES" "$TREND_FILES" \
    "$RATING" >&2

[ -n "$COMPLIANCE_STR" ] && printf '%s\n' "$COMPLIANCE_STR" >&2
[ "${LAST_PRS_MERGED:-0}" -ge 1 ] 2>/dev/null \
    && printf '🚀 %d PR(s) merged last session\n' "$LAST_PRS_MERGED" >&2
if [ "${LAST_PRS_MERGED:-0}" -ge 1 ] && [ "${LAST_REVIEW_ROUNDS:-0}" -ge 2 ] 2>/dev/null; then
    printf '💡 %d review round(s) on last PR — consider more upfront tests or smaller waves.\n' \
        "$LAST_REVIEW_ROUNDS" >&2
fi

# --- Actionable tip ---
if [[ "$RATING" == "😞 Do better" ]]; then
    if [ "${LAST_DURATION:-0}" -lt 300 ] 2>/dev/null; then
        printf '💡 Longer focused sessions help Claude build deeper context.\n' >&2
    else
        printf '💡 Reusing context across sessions is more productive than short free-chat sessions.\n' >&2
    fi
fi

# --- Wave-stall tip ---
if [[ "$RATING" != "❤️ Awesome" ]] && [ -f "$TASK_STATE" ] 2>/dev/null; then
    CURRENT_WAVE_NUM=$(extract_field "$LAST_ENTRY" "currentWave")
    SESSIONS_ON_WAVE=0
    if [ -n "$CURRENT_WAVE_NUM" ] && [ "$CURRENT_WAVE_NUM" != "0" ] && [ "$CURRENT_WAVE_NUM" != "1" ] 2>/dev/null; then
        SESSIONS_ON_WAVE=$(grep -c "\"currentWave\":${CURRENT_WAVE_NUM}[,}]" "$METRICS_FILE" 2>/dev/null || true)
        SESSIONS_ON_WAVE="${SESSIONS_ON_WAVE:-0}"
    fi
    if [ "${SESSIONS_ON_WAVE:-0}" -ge 3 ] 2>/dev/null; then
        printf '💡 %d sessions on the same wave — consider splitting it into smaller steps.\n' \
            "$SESSIONS_ON_WAVE" >&2
    fi
fi

exit 0
