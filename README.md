# Gravitee Dev Workflow

You've been there: three sessions on the same ticket. Claude implements, you review, you close the session. Next morning, Claude asks what you're building. You explain again. The agreed interface? Forgotten. The test you wrote together? Re-implemented with different signatures. Three days in, you have a PR with swallowed exceptions, no coverage on the edge cases you discussed on Day 1, and a plan that drifted away from the Jira ticket.

This plugin closes that loop.

---

## Install

```bash
claude plugin install .
```

Registers 6 skills and 3 hook scripts across 2 lifecycle events (SessionStart, SessionEnd). No manual settings.json editing required.

**Fallback** (environments without plugin support):
```bash
bash install.sh
```

---

## Why This Exists

**The 3-session ticket death spiral:**

1. Session 1: You explain the ticket, agree on an architecture, sketch the interface. Claude implements Wave 1. You commit. Session ends.
2. Session 2: Claude opens fresh. You re-explain the ticket. "What was the interface we agreed on?" You paste it again. Half the session is re-grounding. Wave 2 starts late.
3. Session 3: Same re-grounding. By now the implementation has drifted from the Jira acceptance criteria. The PR has a catch block that swallows a `TechnicalException` because nobody was checking. Coverage is at 60%.

**The fix is `.claude/task-state.md`:**

One markdown file committed on the feature branch alongside your code. It knows what wave you're on, what step is next, what test command runs, and what the PR strategy is. `session-loader.sh` reads it and injects the context as the first block of every session. Claude opens and immediately says: "Wave 2/4 — next step: Add RateLimiterRepository interface." No re-explaining. No drift.

The rest — TDD gates, quality agents, analytics — all serve this central goal: every session produces a commit, and every commit is clean.

---

## Architecture

```
SESSION START
  ├─ session-reviewer.sh → stderr: last session metrics + trend arrows (↑↓→) + rating
  └─ session-loader.sh   → stdout → injected: branch, wave N/T, next step

PLANNING  /plan-task
  ├─ Phase 2: Glob + Read (interfaces, high-churn files)
  ├─ Phase 3: Wave breakdown preview → Dev approval
  ├─ Phase 4: task-planner (Opus) ∥ test-writer (Sonnet)   ← parallel
  ├─ Phase 5: 5-signal compatibility check → Phase 5b reconcile if ≥2 signals
  ├─ Phase 6: Unified wave plan assembled
  ├─ Phase 6b: design-validator (code-reviewer on plan artefacts)  ← silent pre-check
  └─ Phase 7: task-state.md + plan-document.md written → Dev approves → implement-task

IMPLEMENTATION  /implement-task
  ├─ Phase 1–3: Load state, orient, confirm step
  ├─ Phase 4:   TDD loop: A(write test) → B(RED) → C(write code) → D(GREEN) → mark [x]
  ├─ Phase 4.5: Quality gate  ← parallel agents after all steps GREEN
  │     ├─ code-reviewer + silent-failure-hunter (always)
  │     └─ type-design-analyzer (Foundation waves only)
  ├─ Phase 5:   commit → pr-test-analyzer → PR → review-feedback wave staged
  └─ Phase 6:   Continue or pause

SESSION END
  └─ session-terminator.sh → .claude/session-metrics.jsonl (branch, duration, tools, commits, waves)
```

---

## The Dev Journey

**Day 1 — onboarding:**
```
/hello → /install-tools → /install-plugins → /install-mcp-servers → /plan-task → /implement-task
```

**Day 2+ — every session:**
```
[open Claude] → session-loader injects task-state.md context
             → /implement-task continues from last step
             → commit at wave boundary (via commit-commands plugin)
             → [close Claude] → session-terminator logs metrics
```

---

## End-to-End Walkthrough

### Day 1 (30 min)
1. `claude plugin install .` — install the plugin
2. Open a new Claude Code session in your APIM checkout
3. `/gravitee-dev-workflow:hello` — run onboarding, check missing tools
4. `/gravitee-dev-workflow:install-tools` — if prompted (first time only)
5. `/gravitee-dev-workflow:install-plugins` — install commit-commands, pr-review-toolkit
6. `/gravitee-dev-workflow:install-mcp-servers` — connect Jira and GitHub

### Day 2 (first ticket)
1. `bash hooks/branch-manager.sh 1234` — create branch `apim-1234`
2. Open Claude Code session → session-loader injects: "no task plan found"
3. `/gravitee-dev-workflow:plan-task APIM-1234` — fetches ticket, spawns agents, writes plan
4. Approve wave plan → choose PR strategy → press "Start Wave 1 now"
5. `/gravitee-dev-workflow:implement-task` begins TDD: RED → write test → GREEN → mark done

### Day 3+ (resume)
1. Open Claude Code in the same directory
2. session-loader automatically injects: "Wave 2/4 — next step: Add repository interface"
3. `/gravitee-dev-workflow:implement-task` auto-resumes without asking confirmation
4. Repeat until all waves committed → PR created → Wave N+1 (Review Feedback) staged

### Recovery
- **Mid-wave crash**: Re-open session → session-loader re-injects exact next step → `/implement-task`
- **Corrupt task-state.md**: `git checkout .claude/task-state.md` (only works after first wave commit)
- **Abandon a ticket**: `git branch -D apim-1234` — task-state.md gone with the branch
- **Reset a step**: Edit task-state.md, change `- [x]` back to `- [ ]`

---

## Skills

| Skill | Purpose | When to use |
|-------|---------|-------------|
| `/hello` | Read-only onboarding — discovers available skills, checks dev tools, suggests next step | First time running Claude in this project |
| `/install-tools` | Guided macOS dev environment setup — Homebrew, Java 21, Maven, Node, Docker, aliases | Setting up a new machine |
| `/install-plugins` | Recommends 8 Claude Code plugins across 4 categories, installs via `claude plugin install` | After tools are installed |
| `/install-mcp-servers` | Recommends 8 MCP servers (GitHub, MongoDB, Elasticsearch, Docker, Jira, Maven, Sentry) | After plugins are installed |
| `/plan-task [ticket]` | Resolves Jira ticket offline-first, decomposes into implementation waves, spawns task-planner + test-writer agents in parallel, writes approved plan to `.claude/task-state.md` | Starting a new APIM ticket |
| `/implement-task` | Executes the current wave: enforces TDD (RED → GREEN per step), runs pre-commit quality gate (code-reviewer + silent-failure-hunter), marks steps done, delegates commit/PR to other plugins | After plan is approved, and on resume |

---

## Session Hooks (auto-installed)

| Hook | Event | Purpose |
|------|-------|---------|
| `session-reviewer.sh` | SessionStart | Prints last session metrics (tools, commits, files, duration, trend arrows ↑↓→, rating) to terminal |
| `session-loader.sh` | SessionStart | Reads `.claude/task-state.md`; injects branch + wave context into Claude's first turn; routes to implement-task, plan-task, or free chat |
| `session-terminator.sh` | SessionEnd | Reads wave progress from task-state.md via grep; appends metrics to `.claude/session-metrics.jsonl`; cleans up markers |

**Output contract:** `session-reviewer.sh` writes to **stderr** (terminal display only, never
injected into Claude's context). `session-loader.sh` writes to **stdout** (injected as the
first context block of every session). `session-terminator.sh` reads stdin (hook input JSON)
and writes only to `.claude/session-metrics.jsonl` — no stdout or stderr output in normal operation.

`branch-manager.sh` is a standalone utility (not a registered hook, not called automatically). Run it manually: `bash hooks/branch-manager.sh <ticket-number>`. It enforces `apim-<ticket>` branch naming, auto-stashes uncommitted changes on switch, and offers to restore stash on return.

---

## Context Management

The plugin's core design principle: **Claude should never need to be re-told what you're building.**

### How it works

Every session, `session-loader.sh` reads `.claude/task-state.md` from the feature branch and injects it as the very first context block before any user input. Claude opens knowing:
- Which ticket it's working on
- Which wave is in progress and how many total
- The exact next step to execute
- The scoped Maven test command to run
- The conventional commit message to use when done

This state is committed alongside the code at every wave boundary. There is no separate state store — the markdown file IS the state, versioned in git.

### Context hygiene

- **Phase 2 orientation is compact**: implement-task prints only the current wave, not the full plan. Full plan is available on demand via "show full plan" — zero automatic context cost.
- **plan-document.md is reference-only**: written once at plan approval, never auto-injected into any session. Zero token overhead per session.
- **Session log is append-only**: session-terminator writes metrics to a separate JSONL file, not into task-state.md body — structured fields stay clean as the log grows.
- **Ticket info is cached**: Jira data is stored in task-state.md and re-used for 7 days without another API call.

### What this eliminates

| Without this plugin | With this plugin |
|---------------------|-----------------|
| Re-explain ticket every session (5–10 min) | Zero — session-loader injects it automatically |
| Re-agree on interface signatures | Near-zero — interface names and steps are in task-state.md; full signatures are in plan-document.md (available on demand, not auto-injected) |
| Re-find the test command | Zero — `Test:` field is in every wave header |
| Claude drifts from the accepted plan | Zero — plan-document.md is the authoritative reference |
| "Where did we leave off?" | Zero — session-loader injects the exact next step |

---

## Agents at Work

Six specialized agents across three phases. Here is who they are, why they were chosen, when they run in parallel, and what each one catches.

### Planning Phase — Parallel (task-planner ∥ test-writer)

Two agents run simultaneously the moment you approve the wave breakdown in `/plan-task`:

**task-planner** (Claude Opus 4.6 — the strongest architectural reasoner available)
- **What it does**: produces implementation sequence, file decomposition, wave grouping, and public interface designs. Has Gravitee APIM module knowledge built into its prompt: module layout, RxJava3 reactive patterns, repository interface conventions, use-case command pattern.
- **Why Opus**: architectural plans require multi-step reasoning with many constraints simultaneously — wave independence, testability, conventional commit scope, APIM module boundaries. This is Opus territory, not Sonnet.
- **Why parallel with test-writer**: both agents analyse requirements; neither reads the other's output at analysis time. Running them sequentially adds time with no benefit.
- **Impact**: every ticket starts with a concrete implementation sequence AND APIM-specific file paths before a line of code is written.

**test-writer** (Claude Sonnet 4.6 — fast, accurate specification)
- **What it does**: specifies test cases (happy path, error, edge), mocking strategy, acceptance criteria, and testability objections — from requirements only, never reading the implementation.
- **Why Sonnet**: test specification is deterministic structured work. Sonnet is faster and equally accurate here; Opus cost is not justified.
- **Why "requirements only" constraint**: if test-writer reads the implementation, it tests what was written instead of what was required. The constraint is intentional — it keeps test specification honest.
- **Impact**: testability objections surface BEFORE implementation starts, when they're cheapest to fix.

**5-signal compatibility check**: after both complete, the orchestrator scores file conflicts, missing coverage, interface mismatches, scope divergence, and testability flags. ≥2 signals triggers a reconciliation re-spawn where each agent receives the other's output as additional context.

### Design Validation — Sequential (design-validator)

Runs after the unified plan is assembled, before the Dev reviews it:

**design-validator** (code-reviewer agent reading plan artefacts, not code)
- **What it does**: reviews Public Interfaces + Testability Objections + Wave Decomposition for APIM anti-patterns: concrete coupling, service layer violations, missing null safety, overly broad waves, hard-to-mock interfaces.
- **Why this agent**: code-reviewer is the purpose-built structural analysis tool. Applied to plan documents rather than code, it catches architectural errors at the cheapest possible point — before any implementation starts.
- **Why sequential**: must wait for the plan to exist. No parallelism opportunity here.
- **Impact**: findings appear silently inside the Testability Objections section the Dev is about to read. No separate interruption — just better information at decision time.

### Pre-Commit Quality Gate — Parallel (code-reviewer ∥ silent-failure-hunter ∥ type-design-analyzer)

Runs after all wave steps are GREEN, before the commit:

**code-reviewer**
- **What it catches**: naming violations (camelCase methods, PascalCase types), methods >20 lines or >3 nesting levels, missing null checks on public API boundary parameters, business logic in controllers, persistence logic in service layer.
- **Confidence threshold**: 80% — only high-confidence issues reported. No noise.
- **Why parallel with silent-failure-hunter**: each covers an independent quality dimension with no ordering dependency. Running both simultaneously costs one round-trip instead of two.

**silent-failure-hunter**
- **What it catches**: empty catch blocks, caught exceptions not rethrown or logged, error returns (null, empty Optional, -1) not checked by callers in the same wave.
- **Why this agent specifically**: Gravitee APIM uses RxJava3 reactive chains. In reactive code, a missing `onErrorResumeNext` or a swallowed exception in a `subscribe` callback becomes a silent gateway hang — no stack trace, no log, no alert. This is the #1 production risk class in APIM code. A general-purpose reviewer misses it; this agent is built to find it.

**type-design-analyzer** (Foundation waves only — wave name contains "Foundation", or files contain Interface/DTO/Model)
- **What it catches**: interfaces that don't express invariants beyond method signatures, implementation details leaking through the interface, types that require real infrastructure to instantiate and are therefore unmockable.
- **Why conditional**: Foundation waves define the contracts all subsequent waves build on. A poorly designed interface at Wave 1 multiplies maintenance cost across Waves 2–4. Service and controller waves don't introduce new interface contracts — running this agent there adds noise with no signal.
- **Impact**: interface quality is reviewed before implementations are built on top of them.

### Pre-PR Coverage Check — Sequential (pr-test-analyzer)

Runs after commit, before the PR opens:

**pr-test-analyzer**
- **What it catches**: business-logic paths with no test case, rated 1–10 by production risk (10 = critical). Reports only gaps with criticality ≥ 8.
- **Why sequential**: depends on committed files existing.
- **Impact**: coverage gaps caught before PR open = zero "please add tests for X" review comments. PRs arrive with substantive coverage; review cycles focus on logic, not hygiene.

---

## What Catches Problems

Three layers, all AI-enforced through skill instructions (Claude is expected to follow them — any step can be skipped if explicitly asked):

**Layer 1 — TDD gate**: every step in every wave requires a failing test (RED) before production code. The workflow does not advance until Step B fails. This gate catches missing test coverage at the smallest possible granularity: one step, one test, one class.

**Layer 2 — Pre-commit quality gate**: after all wave steps are GREEN, `code-reviewer` + `silent-failure-hunter` run in parallel. Foundation waves additionally run `type-design-analyzer`. Issues trigger a fix-or-acknowledge loop — the gate re-fires after fixes. Nothing commits without passing or explicitly acknowledging every reported issue. Requires `pr-review-toolkit` to be installed; skipped (and logged) if not present.

**Layer 3 — Pre-PR coverage check**: `pr-test-analyzer` runs on committed files before the PR opens. Critical coverage gaps (criticality ≥ 8) block the PR until addressed or acknowledged.

**Optional always-on**: `security-guidance` (separate install: `claude plugin install security-guidance@claude-plugins-official`) fires as a hook on every file write during the session — OWASP-style warnings before code reaches any review stage. Not installed by this plugin by default.

---

## Analytics: What the Numbers Mean

`session-reviewer.sh` displays metrics from the last session every time Claude opens. Here is what each number actually tells you:

| Metric | What it measures | Red flag |
|--------|-----------------|----------|
| `duration` | Session wall time in minutes | < 15 min — session ended before meaningful work; check if Claude hit a silent blocker |
| `toolUseCount` | Tool invocations in the main session transcript (Read, Edit, Bash, Task, etc.; sub-agent tool calls may not be counted) | < 5 — Claude responded without acting; likely a re-explanation session with no output |
| `commitsCreated` | git commits created in the session | 0 after 45+ min — work happened but nothing committed; wave boundary was not reached |
| `filesChanged` | Files changed from merge-base with main (cumulative across all waves on the branch, not per-session) | > 20 by Wave 2 — wave scope may be too broad; split before continuing |
| `wavesCompleted` | Waves with ✓ marker added in this session | 0 over 3+ sessions — wave-stall; reassess wave size or step clarity |
| `branchCompliance` | Percentage of total sessions run on an apim-* branch | < 100% — work ran on non-task branches; context injection may have been absent |
| `workflowType` | `continue` (resumed from task-state.md), `new_task`, `awaiting_review`, or `free_chat` | `free_chat` repeatedly — task-state.md absent or broken |
| `reviewRounds` | CHANGES_REQUESTED events on last merged PR (0 = clean review, 1+ = rework cycles) | ≥ 2 — PR needed rework; check test coverage or wave scope before next ticket |

**Trend arrows** (4-session rolling average): ↑ improving, ↓ declining, → stable. Tracked for tools, commits, and files. No single metric determines the session rating.

**Wave-stall tip**: 3+ sessions on the same `currentWave` (Wave 2 or higher — Wave 1 is excluded as Foundation waves are expected to take longer) triggers: "Consider splitting Wave N into smaller steps."

**Rating**: `❤️ Awesome` (a PR merged last session, or a commit landed with no declining trends),
`😊 Good` (a commit landed, or the session exceeded 10 tool uses),
`😞 Do better` (no commit, no significant tool activity).

A high-performing session is 45+ min, 15+ tools, 1+ commits, `workflowType=continue`, wave completed, all metrics trending ↑. The reviewer tells you this in one line, every time Claude opens.

---

## Architecture Details

### lib/

Two shared bash files sourced by all hooks:

| File | Functions |
|------|-----------|
| `lib/term.sh` | `TL` (label), `TOPT` (option), `TASK` (task item), `TOK` (success), `TERR` (error) — all to stderr |
| `lib/git.sh` | `get_current_branch`, `is_dirty`, `auto_stash`, `find_auto_stash` |

All hooks source them via `${CLAUDE_PLUGIN_ROOT}` (plugin install) or a `$(cd "$(dirname "$0")/.." && pwd)` fallback (manual clone). One fix to a shared function propagates to all consumers.

### task-state.md — why markdown beats JSON

Old approach used `.claude/session-states/apim-<N>.json` — Claude had to produce exact JSON schema; one malformed field broke session continuity; schema changes broke all prior sessions.

New approach: `.claude/task-state.md` committed on the feature branch.

```markdown
# Task: APIM-1234 — Rate Limiter for API Gateway

## Progress
Wave: 2/4
Status: in-progress
PR Strategy: one-pr-per-wave

## Waves

### Wave 1 — Foundation ✓ (commit: abc1234)
### Wave 2 — Service Layer → (in progress)
Steps:
- [x] Create TokenBucket algorithm class
- [ ] Add RateLimiterRepository interface   ← next
- [ ] Wire service with Spring @Service

### Wave 3 — API Layer ○ (pending)
### Wave 4 — Integration ○ (pending)

## Session Log
- 2026-02-25T10:30Z: Wave 1 complete (2 commits, 9 files)
```

**Why this is better:**
- Claude updates it with the `Edit` tool — no JSON schema production
- `session-terminator` reads it with `grep` — no `jq` dependency
- `session-loader` reads it with `grep` — no state parser
- It's committed with the wave's code — git-versioned, team-visible, diffable in PRs
- Schema "changes" are just markdown edits — no version mismatch

---

## Contributing

Run `./test-hooks.sh` before submitting. Conventional commits (`feat(scope):`, `fix(scope):`). Prettier `printWidth: 140`, `tabWidth: 4`.

---

## Design Trade-offs

### What this plugin does
- Keeps Claude oriented across sessions without re-explaining the ticket or the plan.
- Enforces a consistent process: plan before code, test before implementation, quality gate before commit.
- Records what happened in each session (metrics), surfaces it at session start (reviewer), and routes
  the next session to the right place (loader).

### What this plugin does not do
- It does not automate quality checks with shell scripts. The TDD gate, pre-commit agents, and
  pre-PR coverage check are enforced through skill instructions that Claude is expected to follow.
  Claude can be asked to skip any step. The process is as strong as the discipline of the session.
- It does not provide CI enforcement. shellcheck is recommended in install-tools but not wired into
  a build pipeline. The test suite (`bash test-hooks.sh`) is the only automated verification.
- It does not track which developer wrote which step, or produce reporting across multiple developers.
  All state is per-branch, per-developer.

### Why process over automation
The system runs on any developer machine with git, bash, and python3. There is no infrastructure:
no database, no CI pipeline, no registry. Every design decision that adds a dependency or requires
a network call is a decision to break on some machines. The choice is explicit: reach zero vs. reach
high. Zero wins for a workflow tool.

### Known limitations
- task-state.md is parsed with grep. If a developer edits the file manually and deviates from the
  exact format contract, the hooks read empty strings and emit wrong context. The format contract
  is documented (CLAUDE.md — State Management) but not enforced.
- The reviewRounds metric counts CHANGES_REQUESTED events from the GitHub API. 0 = clean review,
  1+ = rework cycles. It does not count how many reviewers approved — only how many times changes
  were explicitly requested.
- Wave-stall detection (3+ sessions on the same currentWave) does not trigger for Wave 1.
  Wave 1 (Foundation) is expected to take longer; the exception is intentional but not documented
  in the session-reviewer output.
- session-loader exits silently if it cannot read the cwd from hook input (e.g., hook timeout).
  No context is injected. The developer sees a normal session start with no orientation. There is
  no error message.

### What 10/10 looks like for a system like this
Formal CI enforcement (shellcheck + test-hooks.sh as build gates), runtime codebase awareness
in task-planner (git log history injected at plan time, not just static module knowledge), and
schema-validated task-state.md writes. None of these are present. Each requires either infrastructure
or a dependency this plugin deliberately avoids.
