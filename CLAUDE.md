# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this directory.

## Context

This directory is the `gravitee-dev-workflow` Claude Code plugin — hooks, skills, and shared library that form an integrated daily workflow for Gravitee APIM engineers.

Install: `claude plugin install ./dev-workflow`

## Directory Layout

```
dev-workflow/
├── .claude-plugin/
│   └── plugin.json          ← registers 6 skills + 3 hooks
├── README.md
├── CLAUDE.md
├── install.sh               ← fallback for non-plugin environments
├── test-hooks.sh            ← test suite
│
├── skills/
│   ├── hello/SKILL.md
│   ├── install-tools/SKILL.md + resources/
│   ├── install-plugins/SKILL.md
│   ├── install-mcp-servers/SKILL.md
│   ├── plan-task/SKILL.md + agents/{task-planner.md,test-writer.md}
│   └── implement-task/SKILL.md
│
├── hooks/
│   ├── session-loader.sh     ← prompt-based SessionStart; emits hookSpecificOutput JSON to stdout
│   ├── session-reviewer.sh   ← metrics display to stderr
│   ├── session-terminator.sh ← metrics append, marker cleanup
│   └── branch-manager.sh     ← standalone utility: bash branch-manager.sh <N>
│
└── lib/
    ├── term.sh               ← terminal output helpers
    └── git.sh                ← branch/stash helpers
```

`plan-document.md` is written by `plan-task` Phase 7 as a reference document. It is never
auto-injected into any session — zero token overhead per resume.

## Skills

| Skill | Description |
|-------|-------------|
| `hello` | Read-only onboarding — discovers skills via Glob, checks dev tools, suggests next step |
| `install-tools` | Guided macOS dev environment — Java 21, Maven, Node, Docker, aliases |
| `install-plugins` | Recommends and installs 8 Claude Code plugins |
| `install-mcp-servers` | Recommends and installs 8 MCP servers |
| `plan-task` | Offline-first ticket resolution, wave decomposition, parallel agents, writes `.claude/task-state.md` |
| `implement-task` | Wave-by-wave TDD execution, pre-commit quality gate (code-reviewer + silent-failure-hunter + type-design-analyzer on Foundation waves), updates task-state.md, delegates commit/PR to other plugins |

## Hooks

| Script | Event | Matcher | Purpose |
|--------|-------|---------|---------|
| `session-reviewer.sh` | SessionStart | `startup\|resume\|clear\|compact` | Print last session metrics + trend arrows to stderr; also displays branch compliance (percentage of sessions on an apim-* branch, computed from full JSONL history) |
| `session-loader.sh` | SessionStart | `startup\|resume\|clear\|compact` | Read task-state.md, inject branch + wave context to stdout; routes using unqualified skill names (`/implement-task`, `/plan-task`) |
| `session-terminator.sh` | SessionEnd | `""` | Grep wave progress from task-state.md, append JSONL metrics, clean markers |
| `branch-manager.sh` | — (utility) | — | Standalone tool: `bash branch-manager.sh <N>` — switches to apim-N, auto-stashes dirty work, offers stash restore. Not a hook; not called automatically. |

**Output contract:** `session-reviewer.sh` writes to **stderr** (terminal display only, never
injected into Claude's context). `session-loader.sh` writes to **stdout** (injected as the
first context block of every session). `session-terminator.sh` reads stdin (hook input JSON)
and writes only to `.claude/session-metrics.jsonl` — no stdout or stderr output in normal operation.

## lib/

Two shared bash files sourced by all hooks:

- `lib/term.sh` — `TL`, `TOPT`, `TASK`, `TOK`, `TERR` (all to stderr); `tty_read` with 60-second timeout
- `lib/git.sh` — `get_current_branch`, `is_dirty`, `auto_stash`, `find_auto_stash`

**Sourcing pattern** (all hooks use this):
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "${PLUGIN_ROOT}/lib/term.sh"
source "${PLUGIN_ROOT}/lib/git.sh"
```

`CLAUDE_PLUGIN_ROOT` is set by the plugin system. The fallback uses dirname so manual clones work too.

## Quality Gate

`implement-task` Phase 4.5 runs after all wave steps are GREEN, before commit:

- **code-reviewer** — naming, complexity, null safety, structural violations. Confidence threshold: 80%.
- **silent-failure-hunter** — swallowed exceptions, empty catch blocks, unchecked error returns.
- **type-design-analyzer** — Foundation waves only (interfaces, DTOs, models). Interface invariants + mockability.

All three run in parallel. Fix-or-acknowledge loop. Gate re-fires after fixes. Skip logged if pr-review-toolkit not installed.

The gate is AI-enforced through skill instructions — Claude is expected to follow them. It is not automated by a shell script and can be skipped if explicitly asked.

`plan-task` Phase 6b runs after unified plan assembly, before Dev review:
design-validator (code-reviewer on plan artefacts) checks APIM anti-patterns → findings merged into Testability Objections.

## State Management

Session state lives in `.claude/task-state.md` on the feature branch — committed with the wave's code.

```markdown
# Task: APIM-<N> — <title>

## Progress
Wave: 2/4
Status: in-progress
Ticket: APIM-<N>
Cached: 2026-02-25

## Waves

### Wave 1 — Foundation ✓ (commit: abc1234)
### Wave 2 — Service Layer → (in progress)
Test: `mvn test -pl module -Dtest=MyTest -q` (~60s)
Commit: feat(gateway): implement service
Files: ServiceImpl.java, Repository.java
Steps:
- [x] Step one done
- [ ] Step two — next

### Wave 3 — API Layer ○ (pending)

## Session Log
- 2026-02-25T10:30Z: Wave 1 complete (3 files)
```

**Why markdown not JSON:**
- Claude edits it with the `Edit` tool — no JSON schema production
- Hooks read it with `grep`/`sed` — no `jq` dependency
- Committed with the wave — git-versioned, team-visible, PR-diffable
- Schema "changes" are just markdown edits — no version mismatch

**Format contract:** The `## Progress` section fields are parsed with `grep "^<Field>: "` —
field order is irrelevant. Extra fields are ignored. Step lines MUST start with `- [ ]` or
`- [x]` at the beginning of the line. Wave headers MUST match `### Wave N — <name>` exactly
(case-sensitive, two spaces before marker symbols: ✓ → ○). Status has four valid values:
`pending | in-progress | awaiting-review | complete`.

`awaiting-review` causes `session-loader` to emit a different context block (PR waiting for
feedback, not mid-implementation) and `session-reviewer` to display `🔄` in the wave display.

## Analytics

`.claude/session-metrics.jsonl` — one JSON line per session. Fields:

| Field | Type | Description |
|-------|------|-------------|
| `sessionId` | string | Unique session identifier from hook input |
| `branch` | string | git branch at session end |
| `ticket` | string | Ticket number extracted from branch name (apim-N → N) |
| `timestamp` | string | ISO-8601 UTC timestamp at session end |
| `toolUseCount` | int | Total tool invocations counted in transcript |
| `duration` | int | Session wall time in seconds (0 if start-time marker missing) |
| `commitsCreated` | int | git commits created since session start |
| `filesChanged` | int | Files changed from merge-base with default branch |
| `workflowType` | string | `continue`, `new_task`, `awaiting_review`, or `free_chat` |
| `wavesCompleted` | int | Wave headers marked ✓ in task-state.md |
| `totalWaves` | int | Total wave headers in task-state.md |
| `currentWave` | int | Wave number from `Wave: N/T` in task-state.md |
| `prsMerged` | int | PRs merged on this branch (via gh CLI) |
| `reviewRounds` | int | CHANGES_REQUESTED + APPROVED review events on last merged PR |

**`branchCompliance`** is a derived display metric computed by `session-reviewer.sh` at session start
(`APIM_ENTRIES * 100 / TOTAL_SESSIONS`) — it is not stored in JSONL. It reflects the percentage
of all recorded sessions that ran on an apim-* branch.

**`extract_field` approach:** `session-reviewer.sh` parses JSONL with `grep -oE "\"field\":[^,}]+"`.
This works correctly for scalar string and numeric values. It would misparse nested JSON objects or
null values — neither is currently emitted.

## Conventions

- **Formatting**: Prettier — `printWidth: 140`, `tabWidth: 4`
- **Commits**: Conventional commits — `feat(scope):`, `fix(scope):`, `docs(scope):`, `chore(scope):`
- **Terminology**: Refer to the human partner as "Dev" (not "user")
- **Hook output**: stderr = terminal only; stdout = injected into Claude's context
- **No jq in hooks**: all field extraction uses `grep`/`sed`/`python3 -c "import json..."`
