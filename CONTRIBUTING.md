# Contributing

Thank you — small, focused contributions keep this plugin useful for Gravitee APIM engineers. This file is intentionally concise: follow the checklist and examples below.

## Quick prerequisites
- Bash 4+, Git 2.30+, python3
- jq (required by `test-hooks.sh` only — not a runtime dependency of the hooks)
- Recommended: shellcheck for linting
- Claude Code (for end-to-end manual testing)

## Quick start
1. Clone:
   ```bash
   git clone https://github.com/aditya-goyal01/gravitee-apim-dev-workflow.git
   cd gravitee-apim-dev-workflow
   ```
2. Install for local testing:
   ```bash
   bash install.sh
   # or
   claude plugin install ./dev-workflow
   ```

## What to contribute
- Skills: add/modify `skills/<name>/SKILL.md` (+ resources/)
- Hooks: add/modify `hooks/*.sh` (SessionStart/SessionEnd or utilities)
- Lib: small shared helpers in `lib/` (term.sh, git.sh)
- Docs & tests: README, CLAUDE.md, `test-hooks.sh` additions

Keep each change focused (one logical change per PR).

## Hook output contract (critical)
- session-loader.sh → writes context to stdout (injected into Claude)
- session-reviewer.sh → writes only to stderr (terminal display)
- session-terminator.sh → writes only to `.claude/session-metrics.jsonl` (no stdout/stderr in normal op)
- Utilities may write to stderr for UX messages

Always preserve these contracts.

## Tests & validation
- Run full suite:
  ```bash
  bash test-hooks.sh
  ```
- Lint:
  ```bash
  shellcheck hooks/*.sh lib/*.sh
  ```
- Manual check: run a Claude session and verify injection/terminal output and JSONL append.

## Minimal style rules
- Use `set -e` and `set -u` where appropriate
- Quote variables: `"$VAR"`
- Use `[[ ... ]]` and prefer functions over long inline blocks
- Source libs using:
  ```bash
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
  source "${PLUGIN_ROOT}/lib/term.sh"
  source "${PLUGIN_ROOT}/lib/git.sh"
  ```
- Write short, intent-focused comments

## Commit & PR
- Use Conventional Commits:
  - feat(hooks): ...
  - fix(lib): ...
  - docs: ...
- PR checklist:
  - [ ] `bash test-hooks.sh` passed
  - [ ] `shellcheck` clean
  - [ ] Output contract unchanged (if relevant)
  - [ ] CLAUDE.md / README updated if behavior changed
  - [ ] Manual test in Claude completed (for skills/hooks)

## Reporting bugs
Include:
- Steps to reproduce
- Expected vs actual
- Bash/git/Claude versions
- Minimal reproduction (prefer a small repo or commands)

Suggested title: `bug(hooks/session-loader): task-state.md not injected when ...`

---

Short, focused changes are easiest to review. Thanks for improving the workflow.