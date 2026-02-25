#!/usr/bin/env bash
# session-loader.sh — prompt-based SessionStart hook
# Writes context directive to stdout (injected into Claude's first turn).
# No /dev/tty, no interactive menu, no tty_read().
# Matcher: "startup|resume|clear|compact"
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "${PLUGIN_ROOT}/lib/git.sh"

IFS= read -r -t 3 INPUT 2>/dev/null || INPUT="{}"
CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
[ -z "$CWD" ] && exit 0

BRANCH=$(get_current_branch "$CWD")
TASK_STATE="$CWD/.claude/task-state.md"
MARKERS="$CWD/.claude/session-markers"
mkdir -p "$MARKERS"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$MARKERS/start-time"

emit_context() {
    python3 -c "
import json, sys
ctx = sys.argv[1]
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': ctx}}))
" "$1"
}

if [ -f "$TASK_STATE" ]; then
    WAVE=$(grep "^Wave: " "$TASK_STATE" 2>/dev/null | head -1 | sed 's/^Wave: //' || echo "")
    STATUS=$(grep "^Status: " "$TASK_STATE" 2>/dev/null | head -1 | sed 's/^Status: //' || echo "")
    NEXT=$(grep "^- \[ \]" "$TASK_STATE" 2>/dev/null | head -1 | sed 's/^- \[ \] //' || echo "")

    if [ "$STATUS" = "awaiting-review" ]; then
        printf "awaiting_review" > "$MARKERS/workflow-type"
        CONTEXT="[Session Context]
Branch: $BRANCH | Wave: $WAVE | Status: awaiting-review
Wave ${WAVE%%/*} PR is open — waiting for reviewer feedback.
When feedback arrives: /implement-task will stage a Review Feedback wave.
Nothing to implement right now. Start another ticket or close this session."
        emit_context "$CONTEXT"
    else
        printf "continue" > "$MARKERS/workflow-type"

        NEXT_MSG=""
        if [ -n "$NEXT" ]; then
            NEXT_MSG="Next step: $NEXT"
        else
            NEXT_MSG="All steps marked done — ready to commit Wave ${WAVE%%/*}."
        fi

        CONTEXT="[Session Context]
Branch: $BRANCH | Wave: $WAVE | Status: $STATUS
$NEXT_MSG

Task state loaded. Invoke /implement-task to continue from the next step, or follow the Dev's intent."
        emit_context "$CONTEXT"
    fi
elif [[ "$BRANCH" =~ ^apim-[0-9]+ ]]; then
    printf "new_task" > "$MARKERS/workflow-type"
    CONTEXT="[Session Context]
Branch: $BRANCH — no task plan found.
If the Dev wants to work on this ticket, invoke /plan-task."
    emit_context "$CONTEXT"
else
    printf "free_chat" > "$MARKERS/workflow-type"
    CONTEXT="[Session Context]
Branch: $BRANCH — not a task branch.
If the Dev mentions a ticket number or asks to start work, help them create an apim-<N> branch and invoke /plan-task."
    emit_context "$CONTEXT"
fi
