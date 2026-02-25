#!/bin/bash
# install.sh — Fallback installer for environments without plugin support.
#
# Plugin install is preferred:
#   claude plugin install ./dev-workflow
#
# Use this script only when the Claude Code plugin system is unavailable.
# Copies hooks and lib to ~/.claude/hooks/ and registers them in ~/.claude/settings.json.
# Idempotent: safe to run multiple times.
#
# Requirements:
#   - ~/.claude/ must exist (created by Claude Code on first run)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

OK()  { printf '\033[32m✓ %s\033[0m\n' "$*"; }
INFO(){ printf '  %s\n' "$*"; }
WARN(){ printf '\033[33m⚠ %s\033[0m\n' "$*"; }

# ── Pre-flight checks ─────────────────────────────────────────────────────────
if [ ! -d "${HOME}/.claude" ]; then
    printf '\033[31m✗ ~/.claude not found. Run Claude Code at least once to initialise it, then re-run this script.\033[0m\n'
    exit 1
fi

printf '\n\033[1mNote:\033[0m Plugin install is preferred:\n'
INFO "  claude plugin install ${SCRIPT_DIR}"
INFO ""
INFO "Continuing with manual install (hooks only — no skill registration)..."
INFO ""

# ── Copy lib/ (term.sh and git.sh — state.sh retired) ────────────────────────
mkdir -p "${HOME}/.claude/hooks/lib"
for lib in term.sh git.sh; do
    cp "${SCRIPT_DIR}/lib/${lib}" "${HOME}/.claude/hooks/lib/${lib}"
done
OK "Installed lib/ (term.sh, git.sh)"

# ── Copy hooks/ ───────────────────────────────────────────────────────────────
mkdir -p "${HOME}/.claude/hooks"
for script in session-loader.sh session-reviewer.sh session-terminator.sh branch-manager.sh; do
    src="${SCRIPT_DIR}/hooks/${script}"
    dst="${HOME}/.claude/hooks/${script}"
    cp "$src" "$dst"
    chmod +x "$dst"
    OK "Installed ${script}"
done

# ── Patch ~/.claude/settings.json ────────────────────────────────────────────
SETTINGS="${HOME}/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
    printf '{}\n' > "$SETTINGS"
fi

# Merge hook configuration using python3 (no jq dependency)
python3 - "$SETTINGS" <<'PYEOF'
import json, sys

path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)

hooks_patch = {
    "hooks": {
        "SessionStart": [
            {
                "matcher": "startup",
                "hooks": [
                    {"type": "command", "command": "bash ~/.claude/hooks/session-reviewer.sh"},
                    {"type": "command", "command": "bash ~/.claude/hooks/session-loader.sh"}
                ]
            }
        ],
        "SessionEnd": [
            {
                "matcher": "",
                "hooks": [
                    {"type": "command", "command": "bash ~/.claude/hooks/session-terminator.sh"}
                ]
            }
        ]
    }
}

# Deep merge: preserve existing keys, merge hooks
if "hooks" not in settings:
    settings["hooks"] = {}
settings["hooks"].update(hooks_patch["hooks"])

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF

OK "Registered hooks in ~/.claude/settings.json"

# ── Done ──────────────────────────────────────────────────────────────────────
printf '\n\033[1mInstallation complete.\033[0m\n'
INFO "Session hooks will fire the next time you run: claude"
INFO ""
INFO "For full plugin support (skill registration, auto-updates):"
INFO "  claude plugin install ${SCRIPT_DIR}"
