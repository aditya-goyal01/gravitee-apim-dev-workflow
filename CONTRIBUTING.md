# Contributing to gravitee-dev-workflow

Thank you for contributing to the gravitee-dev-workflow plugin — the state management system that keeps Gravitee APIM engineers in flow across sessions.

## Prerequisites

- **Bash 4.0+** (macOS: Homebrew `bash`)
- **Git 2.30+**
- **Claude Code** (plugin-enabled environment)
- **jq** (for JSON parsing in hooks)
- **python3** (for JSONL formatting in session-terminator)

Verify your setup:
```bash
bash --version
git --version
jq --version
python3 --version
```

## Development Setup

1. **Clone and navigate**:
   ```bash
   git clone https://github.com/aditya-goyal01/gravitee-apim-dev-workflow.git
   cd gravitee-apim-dev-workflow
   ```

2. **Install locally** (for testing before plugin publish):
   ```bash
   bash install.sh
   ```
   Or as a Claude plugin:
   ```bash
   claude plugin install ./dev-workflow
   ```

3. **Verify installation**:
   ```bash
   ls -la ~/.claude/plugins/dev-workflow/
   # or check .claude-plugin/plugin.json in this repo
   ```

## What You Can Contribute

### Skills (in `skills/`)
New or enhanced skills that integrate into the workflow:
- **Structure**: Each skill lives in `skills/<skill-name>/SKILL.md` + optional `resources/` or `agents/` subdirs
- **Format**: Markdown with structured sections (Purpose, Inputs, Outputs, Internal Phases, Error Handling)
- **Dependencies**: Skills can call other skills via `/gravitee-dev-workflow:skill-name`
- **Agents**: Skills can spawn parallel Claude agents (see `plan-task` for task-planner + test-writer example)

**Example contribution**: A new skill `/review-pr-quality` that runs code-reviewer on an open PR branch without needing /implement-task.

### Hooks (in `hooks/`)
Bash scripts that fire on SessionStart, SessionEnd, or as utilities:
- **Output contract**: stdout (injected to Claude) vs stderr (terminal only) — critical
  - `session-loader.sh` → stdout (injected context)
  - `session-reviewer.sh` → stderr (display only, never injected)
  - `session-terminator.sh` → no stdout/stderr, writes only to `.claude/session-metrics.jsonl`
  - Utilities like `branch-manager.sh` → may use stderr for user feedback
- **Sourcing pattern**: All hooks must source `lib/term.sh` and `lib/git.sh` via PLUGIN_ROOT
- **Error handling**: Use `TERR "message"` for errors, exit with `$?` status preserved

**Example contribution**: A new hook that runs on file write (via claude plugin hook system if future-enabled) to validate wave boundaries before commit.

### Library Functions (in `lib/`)
Shared bash utilities sourced by all hooks:

- **`lib/term.sh`**: Terminal output helpers with color/styling
  - `TL "Label"` — section label
  - `TOPT "option name"` — option list item
  - `TASK "task description"` — task checkpoint
  - `TOK "success message"` — success feedback
  - `TERR "error message"` — error feedback
  - All write to **stderr**

- **`lib/git.sh`**: Git state management
  - `get_current_branch` — returns `$(git rev-parse --abbrev-ref HEAD)`
  - `is_dirty` — returns 0 if working tree is clean, 1 if dirty
  - `auto_stash` — stashes uncommitted changes if dirty, returns stash ref
  - `find_auto_stash` — restores a stash by ref, offers user confirmation

**Contributing to lib/**: Changes to shared functions affect all hooks. Add unit test calls in `test-hooks.sh` before submitting.

## Testing Your Changes

### Run the hook test suite
```bash
bash test-hooks.sh
```

This executes:
- **Syntax checks**: `bash -n` on all .sh files
- **Shellcheck lint**: `shellcheck` on hooks/ and lib/ (if installed: `brew install shellcheck`)
- **Mock session lifecycle**: Simulates SessionStart (session-loader + session-reviewer) and SessionEnd (session-terminator)
- **Git state tests**: Creates a temp git repo and tests branch/stash logic
- **Output contract validation**: Verifies session-loader writes to stdout, session-reviewer to stderr, session-terminator to JSONL

### Test a single skill
```bash
# Manually test /hello
claude code
/gravitee-dev-workflow:hello

# Check output: should list all skills via Glob, check Java/Maven/Node, suggest next step
```

### Test a hook in isolation
```bash
# Test session-loader with a mock task-state.md
mkdir -p .claude
cat > .claude/task-state.md <<EOF
# Task: APIM-1234 — Test Ticket

## Progress
Wave: 1/2
Status: in-progress

### Wave 1 — Foundation → (in progress)
Steps:
- [x] Step one
- [ ] Step two — next
EOF

bash hooks/session-loader.sh
# Should inject: branch, wave context, next step to stdout
```

### Test git utilities in isolation
```bash
# Source and test
source lib/git.sh

current=$(get_current_branch)
echo "Current branch: $current"

if is_dirty; then
  echo "Working tree is dirty"
  stash=$(auto_stash)
  echo "Stashed as: $stash"
fi
```

## Code Style

### Shell conventions
- **Indentation**: 2 spaces (not tabs)
- **Quoting**: Quote all variables: `"$VAR"` not `$VAR`
- **Error handling**: Check exit codes, use `|| exit $?` for critical operations
- **Comments**: Explain **why**, not what. Code is self-documenting; comments explain intent.

```bash
# Good: explains intent
# Source lib first to ensure TL/TERR are available before any output
source "".$PLUGIN_ROOT/lib/term.sh" || exit $?"

# Avoid: states the obvious
# Source the lib
source lib.sh
```

### Bash best practices
1. **Use `set -e` at the top of scripts** (exit on first error)
2. **Avoid `eval`** — use `"$@"` or "${array[@]}" instead
3. **Check file existence** before sourcing: `[[ -f "$file" ]] || exit 1`
4. **Use `[[ ]]` not `[ ]`** — more robust, supports regex
5. **Capture output cleanly**: `output=$(command)` not backticks
6. **Preserve exit codes**: `command || exit $?` not `command && exit 0`

### Hook-specific patterns

**All hooks must follow this sourcing pattern**:
```bash
#!/bin/bash
set -e

PLUGIN_ROOT="
${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "${PLUGIN_ROOT}/lib/term.sh"
source "${PLUGIN_ROOT}/lib/git.sh"

# Hook logic follows
```

**Output contract enforcement**:
```bash
# session-loader.sh: write to stdout
echo "injected-context" 

# session-reviewer.sh: write to stderr
TL "Session Metrics" >&2

# session-terminator.sh: no stdout/stderr in normal operation
python3 -c "import json; ..." >> .claude/session-metrics.jsonl
```

### Documentation style
- **SKILL.md format**: Purpose → Inputs → Outputs → Internal Phases → Error Handling → Example
- **README updates**: Keep the Architecture diagram and Analytics table accurate; update if you add hooks or agents
- **Comments in code**: Link to which section of CLAUDE.md or README.md explains the broader context

## Submitting Changes

### Before you commit
1. **Run tests**: `bash test-hooks.sh` — must pass all checks
2. **Lint**: `shellcheck hooks/*.sh lib/*.sh` — zero warnings
3. **Manual validation**: Test the hook/skill in a real Claude session
4. **Update documentation**: If you change behavior, update CLAUDE.md or README.md

### Commit message format
Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(hooks): add session-checkpoint hook for mid-wave debugging
^    ^      ^
|    |      └─ Description, imperative mood, lowercase
|    └────────── Scope: hooks, skills, lib, docs, test
└────────────── Type: feat, fix, refactor, docs, test
```
Examples:
```
feat(skills): add /review-pr-quality skill for stand-alone PR analysis
fix(lib/git.sh): handle detached HEAD state in get_current_branch
refactor(hooks): consolidate output routing in session-loader
docs: update CONTRIBUTING.md with testing procedures
test: add shellcheck validation to test-hooks.sh
```

### Pull request checklist
- [ ] All tests pass: `bash test-hooks.sh`
- [ ] Shellcheck clean: `shellcheck hooks/*.sh lib/*.sh`
- [ ] Commit messages follow Conventional Commits
- [ ] CLAUDE.md or README.md updated if behavior changed
- [ ] Manual testing completed in Claude Code
- [ ] No breaking changes to output contract (stdout vs stderr)
- [ ] New hooks source lib/term.sh and lib/git.sh correctly

## Architecture Overview

For context on what you're contributing to:

- **Skills** are user-facing entry points (`/plan-task`, `/implement-task`, etc.)
- **Hooks** are auto-firing lifecycle events (SessionStart injects context, SessionEnd logs metrics)
- **Library functions** are shared by all scripts (terminal output, git state)
- **task-state.md** is the committed markdown state file — the heart of session continuity
- **`.claude-plugin/plugin.json`** registers skills + hooks to the Claude plugin system

Read `CLAUDE.md` for a full architecture walkthrough, including which agents run in parallel and why.

## Reporting Issues

If you find a bug:
1. **Verify it's reproducible**: Run `test-hooks.sh` again
2. **Check CLAUDE.md**: Your scenario may be documented as known behavior
3. **Isolate the hook**: Is it session-loader? session-terminator? A skill? A lib function?
4. **Include**: Bash version, Claude plugin version, step-by-step reproduction, expected vs actual output

Example issue title: `bug(hooks/session-loader): task-state.md not injected when wave status is "completed"`

## Questions?

- **Architecture**: See README.md (Why This Exists, Architecture) and CLAUDE.md (Context Management, Agents at Work)
- **Specific skill**: Check the skill's SKILL.md and the agents/ subdirectory
- **Output contracts**: See CLAUDE.md § Output contract
- **Testing**: See this file § Testing Your Changes
