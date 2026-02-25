#!/bin/bash
# Usage: branch-manager.sh <ticket-number>
# Creates or switches to apim-<ticket-number> with stash safety.
# All terminal output via stderr. Uses /dev/tty for interactive prompts.
# Produces no stdout — safe to call from within other hooks.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "${PLUGIN_ROOT}/lib/term.sh"
source "${PLUGIN_ROOT}/lib/git.sh"

TICKET_NUMBER="${1:-}"

# ── Validate input ────────────────────────────────────────────────────────────
if [ -z "$TICKET_NUMBER" ]; then
    TERR "ticket number required."
    TL "Usage: branch-manager.sh <ticket-number>"
    exit 1
fi

if ! echo "$TICKET_NUMBER" | grep -qE '^[0-9]+$'; then
    TERR "ticket number must be numeric. Got: ${TICKET_NUMBER}"
    exit 1
fi

BRANCH_NAME="apim-${TICKET_NUMBER}"
CURRENT_BRANCH=$(get_current_branch)

# ── Already on target branch ──────────────────────────────────────────────────
if [ "$CURRENT_BRANCH" = "$BRANCH_NAME" ]; then
    TOK "Already on ${BRANCH_NAME}"
    git log --oneline -5 >&2 || true
    exit 0
fi

# ── Stash uncommitted tracked changes ────────────────────────────────────────
if is_dirty; then
    TL "Stashing uncommitted changes on ${CURRENT_BRANCH}..."
    auto_stash "$CURRENT_BRANCH" "$BRANCH_NAME"
fi

# ── Switch or create branch ───────────────────────────────────────────────────
if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
    TL "Switching to existing branch ${BRANCH_NAME}..."
    git checkout "$BRANCH_NAME" >&2
else
    TL "Creating new branch ${BRANCH_NAME}..."
    git checkout -b "$BRANCH_NAME" >&2
fi

TOK "${BRANCH_NAME}"

# ── Offer to restore prior auto-stash for this branch ────────────────────────
# Look for a stash that was created when previously leaving BRANCH_NAME
STASH_REF=$(find_auto_stash "$BRANCH_NAME")
if [ -n "$STASH_REF" ]; then
    STASH_MSG=$(git stash list 2>/dev/null | grep "auto-stash: ${BRANCH_NAME} → " | head -1)
    TL ""
    TL "\033[33mStashed changes found from a previous switch:\033[0m"
    TL "  ${STASH_MSG}"
    TL ""
    TOPT 1 "Restore — pop the stash now"
    TOPT 2 "Skip — keep stash for later  (git stash pop ${STASH_REF})"
    TASK "Choice [1/2]:"
    tty_read STASH_CHOICE
    if [ "${STASH_CHOICE:-2}" = "1" ]; then
        git stash pop "$STASH_REF" >&2
        TOK "Stash restored."
    else
        TL "Stash kept. Restore with: git stash pop ${STASH_REF}"
    fi
fi

# ── Branch summary ────────────────────────────────────────────────────────────
TL ""
TL "\033[1mLast 5 commits:\033[0m"
git log --oneline -5 >&2 2>/dev/null || TL "  (no commits yet)"
TL ""
TL "\033[1mWorking tree:\033[0m"
git status --short >&2 2>/dev/null || TL "  (clean)"
TL ""
