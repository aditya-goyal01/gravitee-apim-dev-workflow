#!/bin/bash
# lib/term.sh — shared terminal output helpers
# Source this file: source "$(dirname "$0")/../lib/term.sh"
# All output goes to stderr (terminal display only, never captured by Claude)

TL()   { printf '%s\n'                                        "$*" >&2; }
TOPT() { printf '  \033[1;33m%s\033[0m  %s\n'                "$1" "$2" >&2; }
TASK() { printf '\n\033[1m%s\033[0m '                         "$*" >&2; }
TOK()  { printf '\033[32m✓ %s\033[0m\n'                       "$*" >&2; }
TERR() { printf '\033[31m✗ %s\033[0m\n'                       "$*" >&2; }

# Read one line from /dev/tty into named variable $1. Fallback: empty string.
tty_read() {
    if [ -e /dev/tty ]; then
        IFS= read -r -t 60 "$1" < /dev/tty || eval "$1=''"
    else
        eval "$1=''"
    fi
}
