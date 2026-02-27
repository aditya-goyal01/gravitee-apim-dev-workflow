#!/usr/bin/env bash
# session-terminator.sh — SessionEnd hook
# Reads wave progress from task-state.md, appends metrics, cleans markers.
# Matcher: ""
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "${PLUGIN_ROOT}/lib/git.sh"

IFS= read -r -t 3 INPUT 2>/dev/null || INPUT="{}"
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || echo "")
TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null || echo "")
CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Only save state if on an apim-* branch
if ! echo "$BRANCH" | grep -qE '^apim-'; then
    exit 0
fi

TICKET_NUMBER=$(echo "$BRANCH" | sed 's/^apim-//')
TASK_STATE="$CWD/.claude/task-state.md"
METRICS_FILE="$CWD/.claude/session-metrics.jsonl"
MARKERS_DIR="$CWD/.claude/session-markers"

# --- Read wave progress from task-state.md ---
WAVES_DONE=0
TOTAL_WAVES=0
CURRENT_WAVE=1
if [ -f "$TASK_STATE" ]; then
    WAVES_DONE=$(grep -c "^### Wave.*✓" "$TASK_STATE" 2>/dev/null || true)
    WAVES_DONE="${WAVES_DONE:-0}"
    TOTAL_WAVES=$(grep -c "^### Wave " "$TASK_STATE" 2>/dev/null || true)
    TOTAL_WAVES="${TOTAL_WAVES:-0}"
    CURRENT_WAVE=$(grep "^Wave: " "$TASK_STATE" 2>/dev/null | head -1 | grep -oE "[0-9]+" | head -1 || echo "1")
fi

# --- Compute session duration ---
DURATION=0
START_TIME=""
if [ -f "${MARKERS_DIR}/start-time" ]; then
    START_TIME=$(cat "${MARKERS_DIR}/start-time")
    START_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$START_TIME" +%s 2>/dev/null || \
                 date -d "$START_TIME" +%s 2>/dev/null || echo "0")
    NOW_EPOCH=$(date +%s)
    if [ "$START_EPOCH" -gt 0 ]; then
        DURATION=$(( NOW_EPOCH - START_EPOCH ))
    fi
else
    printf '[session-terminator] warning: start-time marker missing — duration will be 0\n' >&2
fi

# --- Git metrics ---
COMMITS_CREATED=0
if [ -n "$START_TIME" ]; then
    COMMITS_CREATED=$(git -C "$CWD" log --since="$START_TIME" --oneline 2>/dev/null | wc -l | tr -d ' ')
fi

FILES_CHANGED=0
DEFAULT_BRANCH=$(git -C "$CWD" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's|.*/||' || echo "main")
MERGE_BASE=$(git -C "$CWD" merge-base HEAD "$DEFAULT_BRANCH" 2>/dev/null || echo "")
START_COMMIT=""
if [ -n "$START_TIME" ]; then
    START_COMMIT=$(git -C "$CWD" rev-list --after="$START_TIME" HEAD 2>/dev/null | tail -1 || echo "")
fi
if [ -n "$START_COMMIT" ]; then
    # Use parent if it exists; if START_COMMIT is the root commit, fall through to merge-base fallback
    if git -C "$CWD" rev-parse "${START_COMMIT}^" >/dev/null 2>&1; then
        FILES_CHANGED=$(git -C "$CWD" diff --name-only "${START_COMMIT}^"..HEAD 2>/dev/null | wc -l | tr -d ' ')
    fi
fi
# Fallback: cumulative from merge-base (no start-time marker or no commits this session)
if [ "${FILES_CHANGED:-0}" -eq 0 ] && [ -n "$MERGE_BASE" ]; then
    FILES_CHANGED=$(git -C "$CWD" diff --name-only "$MERGE_BASE"..HEAD 2>/dev/null | wc -l | tr -d ' ')
fi

# --- Merged PRs ---
PRS_MERGED=0
if command -v gh >/dev/null 2>&1; then
    PRS_MERGED=$(gh pr list --head "$BRANCH" --state merged --json number \
        2>/dev/null \
        | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" \
        2>/dev/null || echo "0")
fi

# --- PR review rounds ---
REVIEW_ROUNDS=0
if command -v gh >/dev/null 2>&1 && [ "${PRS_MERGED:-0}" -gt 0 ] 2>/dev/null; then
    LAST_MERGED_PR=$(gh pr list --head "$BRANCH" --state merged --json number \
        2>/dev/null \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[-1]['number'] if d else '')" \
        2>/dev/null || echo "")
    if [ -n "$LAST_MERGED_PR" ]; then
        REVIEW_ROUNDS=$(gh pr view "$LAST_MERGED_PR" --json reviews \
            2>/dev/null \
            | python3 -c "
import json,sys
d=json.load(sys.stdin)
rounds=[r for r in d.get('reviews',[]) if r.get('state') == 'CHANGES_REQUESTED']
print(len(rounds))
" 2>/dev/null || echo "0")
    fi
fi

# --- Tool use count ---
TOOL_USE_COUNT=0
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    TOOL_USE_COUNT=$(grep -c '"type":"tool_use"' "$TRANSCRIPT_PATH" 2>/dev/null || true)
    TOOL_USE_COUNT="${TOOL_USE_COUNT:-0}"
fi

# --- Workflow type ---
WORKFLOW_TYPE=""
if [ -f "${MARKERS_DIR}/workflow-type" ]; then
    WORKFLOW_TYPE=$(tr -d '[:space:]' < "${MARKERS_DIR}/workflow-type")
fi

# --- Append metrics ---
mkdir -p "$(dirname "$METRICS_FILE")"
METRICS_ENTRY=$(python3 - "$SESSION_ID" "$BRANCH" "$TICKET_NUMBER" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$TOOL_USE_COUNT" "$DURATION" "$COMMITS_CREATED" "$FILES_CHANGED" \
    "$WORKFLOW_TYPE" "$WAVES_DONE" "$TOTAL_WAVES" "$CURRENT_WAVE" "$PRS_MERGED" "$REVIEW_ROUNDS" <<'PY'
import json, sys
a = sys.argv[1:]
# sys.argv[1:] order: session_id branch ticket timestamp tool_use duration
#                     commits files workflow waves_done total_waves current_wave prs_merged review_rounds
print(json.dumps({
    "sessionId": a[0], "branch": a[1], "ticket": a[2], "timestamp": a[3],
    "toolUseCount": int(a[4]), "duration": int(a[5]),
    "commitsCreated": int(a[6]), "filesChanged": int(a[7]),
    "workflowType": a[8], "wavesCompleted": int(a[9]),
    "totalWaves": int(a[10]), "currentWave": int(a[11]),
    "prsMerged": int(a[12]), "reviewRounds": int(a[13])
}))
PY
) 2>/dev/null || METRICS_ENTRY=""
[ -n "$METRICS_ENTRY" ] && echo "$METRICS_ENTRY" >> "$METRICS_FILE"

# --- Clean up markers ---
rm -f "${MARKERS_DIR}/start-time" "${MARKERS_DIR}/workflow-type"

exit 0
