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
mkdir -p "${HOME}/.claude/lib"
for lib in term.sh git.sh; do
    src="${SCRIPT_DIR}/lib/${lib}"
    [ -f "$src" ] || { printf '\033[31m✗ Missing: %s\033[0m\n' "$src"; exit 1; }
    cp "$src" "${HOME}/.claude/lib/${lib}"
done
OK "Installed lib/ (term.sh, git.sh)"

# ── Copy hooks/ ───────────────────────────────────────────────────────────────
mkdir -p "${HOME}/.claude/hooks"
for script in session-loader.sh session-reviewer.sh session-terminator.sh branch-manager.sh; do
    src="${SCRIPT_DIR}/hooks/${script}"
    [ -f "$src" ] || { printf '\033[31m✗ Missing: %s\033[0m\n' "$src"; exit 1; }
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

# Block-level union: for each event, append any block whose commands are not
# fully present in existing settings. Blocks are atomic (matcher semantics).
# Existing entries from other plugins are never removed. Idempotent for clean
# states; partial-state re-runs (manually edited settings.json) may duplicate
# commands — acceptable for a simple installer.
if "hooks" not in settings:
    settings["hooks"] = {}

for event, hook_list in hooks_patch["hooks"].items():
    if event not in settings["hooks"]:
        settings["hooks"][event] = hook_list
    else:
        existing_cmds = {
            h.get("command", "")
            for block in settings["hooks"][event]
            for h in block.get("hooks", [])
        }
        for block in hook_list:
            block_cmds = {h.get("command", "") for h in block.get("hooks", [])}
            if not block_cmds.issubset(existing_cmds):
                settings["hooks"][event].append(block)

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
