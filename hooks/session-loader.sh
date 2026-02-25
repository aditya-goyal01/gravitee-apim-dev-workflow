#!/usr/bin/env bash
# session-loader.sh — prompt-based SessionStart hook
# Writes context directive to stdout (injected into Claude's first turn).
# No /dev/tty, no interactive menu, no tty_read().
# Matcher: "startup"
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "${PLUGIN_ROOT}/lib/git.sh"

IFS= read -r INPUT || INPUT="{}"
CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
[ -z "$CWD" ] && exit 0

BRANCH=$(get_current_branch "$CWD")
TASK_STATE="$CWD/.claude/task-state.md"
MARKERS="$CWD/.claude/session-markers"
mkdir -p "$MARKERS"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$MARKERS/start-time"

if [ -f "$TASK_STATE" ]; then
    WAVE=$(grep "^Wave: " "$TASK_STATE" 2>/dev/null | head -1 | sed 's/^Wave: //' || echo "")
    STATUS=$(grep "^Status: " "$TASK_STATE" 2>/dev/null | head -1 | sed 's/^Status: //' || echo "")
    NEXT=$(grep "^- \[ \]" "$TASK_STATE" 2>/dev/null | head -1 | sed 's/^- \[ \] //' || echo "")
    printf "continue" > "$MARKERS/workflow-type"

    NEXT_MSG=""
    if [ -n "$NEXT" ]; then
        NEXT_MSG="Next step: $NEXT"
    else
        NEXT_MSG="All steps marked done — ready to commit Wave ${WAVE%%/*}."
    fi

    echo "[Session Context]"
    echo "Branch: $BRANCH | Wave: $WAVE | Status: $STATUS"
    echo "$NEXT_MSG"
    echo ""
    echo "Task state loaded. Invoke /gravitee-dev-workflow:implement-task to continue from the next step, or follow the Dev's intent."
elif [[ "$BRANCH" =~ ^apim-[0-9]+ ]]; then
    printf "new_task" > "$MARKERS/workflow-type"
    echo "[Session Context]"
    echo "Branch: $BRANCH — no task plan found."
    echo "If the Dev wants to work on this ticket, invoke /gravitee-dev-workflow:plan-task."
else
    printf "free_chat" > "$MARKERS/workflow-type"
    echo "[Session Context]"
    echo "Branch: $BRANCH — not a task branch."
    echo "If the Dev mentions a ticket number or asks to start work, help them create an apim-<N> branch and invoke /gravitee-dev-workflow:plan-task."
fi
