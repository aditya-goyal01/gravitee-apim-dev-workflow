#!/bin/bash
# lib/git.sh — shared git helpers

# get_current_branch [cwd]  — prints current branch name or ""
get_current_branch() {
    local cwd="${1:-}"
    if [ -n "$cwd" ]; then
        git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
    else
        git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
    fi
}

# is_dirty [cwd]  — exits 0 if tracked changes exist, 1 if clean
is_dirty() {
    local cwd="${1:-}"
    local dirty
    if [ -n "$cwd" ]; then
        dirty=$(git -C "$cwd" status --porcelain 2>/dev/null | grep -v '^??' || true)
    else
        dirty=$(git status --porcelain 2>/dev/null | grep -v '^??' || true)
    fi
    [ -n "$dirty" ]
}

# auto_stash <from_branch> <to_branch> [cwd]  — stashes with labelled message
auto_stash() {
    local from="$1" to="$2" cwd="${3:-}"
    local msg="auto-stash: ${from} → ${to} switch"
    if [ -n "$cwd" ]; then
        git -C "$cwd" stash push -m "$msg" >&2
    else
        git stash push -m "$msg" >&2
    fi
}

# find_auto_stash <branch_name>  — prints stash ref for branch, or ""
# Finds the stash created when switching AWAY from <branch_name>
find_auto_stash() {
    local branch="$1"
    local line
    line=$(git stash list 2>/dev/null | { grep "auto-stash: ${branch} → " || true; } | head -1)
    if [ -n "$line" ]; then
        local idx
        idx=$(echo "$line" | grep -oE 'stash@\{[0-9]+\}' | head -1)
        echo "$idx"
    fi
}

