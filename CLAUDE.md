# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this directory.

## Context

This directory is the `gravitee-dev-workflow` Claude Code plugin — hooks, skills, and shared library that form an integrated daily workflow for Gravitee APIM engineers.

Install: `claude plugin install .`

## Directory Layout

```
dev-workflow/
├── .claude-plugin/
│   └── plugin.json          ← auto-discovers skills/ dir; hooks ref → hooks/hooks.json
├── README.md
├── CLAUDE.md
├── install.sh               ← fallback for non-plugin environments
├── test-hooks.sh            ← unit test suite (195 tests)
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
│   ├── hooks.json            ← hook event config (SessionStart + SessionEnd)
│   ├── session-loader.sh     ← prompt-based SessionStart; emits hookSpecificOutput JSON to stdout
│   ├── session-reviewer.sh   ← metrics display to stderr
│   ├── session-terminator.sh ← metrics append, marker cleanup
│   └── branch-manager.sh     ← standalone utility: bash branch-manager.sh <N>
│
├── lib/
│   ├── term.sh               ← terminal output helpers
│   └── git.sh                ← branch/stash helpers
```

`plan-document.md` is written by `plan-task` Phase 7 as a reference document. It is never
auto-injected into any session — zero token overhead per resume.

## Skills

Six skills: `hello`, `install-tools`, `install-plugins`, `install-mcp-servers`, `plan-task`, `implement-task`. See README.md for descriptions.

## Hooks

Three hooks (Matcher: `startup|resume|clear|compact` for SessionStart, `""` for SessionEnd) + one standalone utility. See README.md for full descriptions. Matchers are the implementation detail:
- `session-reviewer.sh` / `session-loader.sh`: SessionStart — `startup\|resume\|clear\|compact`
- `session-terminator.sh`: SessionEnd — `""`
- `branch-manager.sh`: standalone utility, not a hook

## Quality Gate

`implement-task` Phase 4.5: `code-reviewer` (naming, complexity, null safety, structural violations; 80% confidence threshold) + `silent-failure-hunter` (swallowed exceptions, empty catch blocks, RxJava3 reactive silent failures) + `type-design-analyzer` (Foundation waves only: interface invariants, mockability). All parallel. Fix-or-acknowledge loop. Gate re-fires. Skip logged if pr-review-toolkit absent. AI-enforced, not shell-automated.

`plan-task` Phase 6b: design-validator (code-reviewer on plan artefacts) checks APIM anti-patterns → findings merged into Testability Objections.

## State Management

Session state lives in `.claude/task-state.md` on the feature branch — committed with the wave's code. See README.md for the full example and rationale.

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
| `filesChanged` | int | Files changed since session start (commits during this session only); fallback to merge-base if no session commits |
| `workflowType` | string | `continue`, `new_task`, `awaiting_review`, or `free_chat` |
| `wavesCompleted` | int | Wave headers marked ✓ in task-state.md |
| `totalWaves` | int | Total wave headers in task-state.md |
| `currentWave` | int | Wave number from `Wave: N/T` in task-state.md |
| `prsMerged` | int | PRs merged on this branch (via gh CLI) |
| `reviewRounds` | int | CHANGES_REQUESTED events only on last merged PR; 0 = clean review, 1+ = rework cycles |

**`branchCompliance`** is a derived display metric computed by `session-reviewer.sh` at session start
(`APIM_ENTRIES * 100 / TOTAL_SESSIONS`) — it is not stored in JSONL. It reflects the percentage
of all recorded sessions that ran on an apim-* branch.

**`extract_field` approach:** `session-reviewer.sh` parses JSONL with `grep -oE "\"field\":[^,}]+"`.
This works correctly for scalar string and numeric values. It would misparse nested JSON objects or
null values — neither is currently emitted.

## Testing

```bash
bash test-hooks.sh          # Run full test suite (195 tests)
```

## Conventions

- **Formatting**: Prettier — `printWidth: 140`, `tabWidth: 4`
- **Commits**: Conventional commits — `feat(scope):`, `fix(scope):`, `docs(scope):`, `chore(scope):`
- **Terminology**: Refer to the human partner as "Dev" (not "user")
- **Hook output**: stderr = terminal only; stdout = injected into Claude's context
- **No jq in hooks**: all field extraction uses `grep`/`sed`/`python3 -c "import json..."`
