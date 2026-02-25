---
name: plan-task
description: Plan a coding task — resolves the ticket offline-first, decomposes into implementation waves with scoped TDD commands, and presents a unified plan for Dev approval
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Glob, Task, Write
---

## Phase 1 — Offline-first ticket resolution

Determine ticket number:
- If `$ARGUMENTS` set → use it
- Else → `git rev-parse --abbrev-ref HEAD` → extract number from `apim-<N>`
- If branch doesn't match → AskUserQuestion header="Ticket" options: ["Enter ticket number", "Describe the task"]

Check for cached description in task state:
- Run: `grep -A2 "^Cached:" .claude/task-state.md 2>/dev/null` to check if a task-state.md exists with a recent cached date
- If task-state.md exists and Cached date is within 7 days: use the ticket info from it. Tell Dev: "Using cached ticket [APIM-<N>] — Jira not queried."
- If no cache or stale: attempt Jira fetch via `getJiraIssue` (Atlassian MCP)
  - On success: use the title + description.
  - On failure: check task-state.md regardless of age. If found: use it with "[Cached - may be stale]" note.
  - If no cache at all: AskUserQuestion header="Jira unavailable" options:
    1. "Paste description" — "Type or paste the ticket's acceptance criteria."
    2. "Enter different ticket number"

## Phase 2 — Codebase orientation

Using Glob and Read directly (no Task agent — keep this fast):
1. Find Maven modules related to task keywords: `Glob("**/pom.xml")` then read names of top-level modules
2. Find existing files in the same domain: `Glob("**/*<keyword>*.java")` where keyword = main noun from ticket
3. Find existing test patterns: `Glob("**/*<keyword>*Test.java")` — note which modules they're in
4. Note test framework (JUnit 5 imports? TestNG? Jest?)
5. **Read primary interfaces**: Among files found in step 2, identify the top 1–2 that are
   Java interfaces (`public interface` keyword, no `Impl` in filename). Read them and extract
   method signatures only. If none, read the most central abstract class instead.
   Skip if no interface/abstract class found.
6. **Recent activity**: Run `git log --oneline -5 -- <path>` for the 1–2 most central files
   from step 2. Note commit messages — flag files with 3+ changes in last 5 commits as
   high-churn (needs extra care in wave decomposition).

Output a one-paragraph orientation to Dev: "Found X related files across Y modules. Test framework: Z.
Key interface: <Name> — methods: [list]. High-churn files: <list>."
This grounds both agents and all subsequent phases.

## Phase 3 — Wave decomposition

Based on Phase 2 findings, Claude (not an agent) groups files into waves:
- Foundation: interfaces, DTOs, models, enums
- Service: service classes, repository changes
- API: controllers, REST resources, mappers
- Integration: config, wiring, feature flags

For each wave: name it, list the files, identify the Maven module, draft the conventional commit.
Present the wave breakdown to Dev as a preview table before spawning agents.
AskUserQuestion header="Wave plan" options:
  1. "Looks good — spawn agents"
  2. "Adjust waves" — (ask what to change, re-present)

If Dev rejects the wave breakdown more than once, offer a third option:
  1. "Implement manually — skip agent planning"
If chosen: write task-state.md with a single wave containing all files and generic steps.

## Phase 4 — Parallel agent spawn

Output: "Spawning task-planner and test-writer in parallel…"

Launch both simultaneously (single message, two Task tool calls):
- task-planner (subagent_type: Plan, model: opus, max_turns: 15)
  Prompt: task description + wave breakdown from Phase 3 + task-planner.md template ({{TASK_DESCRIPTION}} replaced)
  Include: key interface name and methods, high-churn files list (from Phase 2 orientation)
- test-writer (subagent_type: Plan, model: sonnet)
  Prompt: task description + wave breakdown from Phase 3 + test-writer.md template ({{TASK_DESCRIPTION}} replaced)
  Include: key interface name and methods, high-churn files list (from Phase 2 orientation)

Wait for both to complete before proceeding.

## Phase 5 — Compatibility check

Score these 5 signals between planner and test-writer outputs:
1. File conflicts — same file listed with different intended changes
2. Missing coverage — planner modifies a file with no corresponding test
3. Interface mismatch — function signatures differ between plan and test expectations
4. Scope divergence — one output covers significantly more/less than the other
5. Testability objections — test-writer names a design from planner's Public Interfaces as hard to test

If ≥ 2 signals: proceed to Phase 5b. Else: skip to Phase 6.

## Phase 5b — Reconciliation (conditional)

Re-spawn both agents simultaneously. Each receives: task description + its own template + the OTHER agent's output as additional context.
Use reconciled outputs for Phase 6.

## Phase 6 — Unified wave plan

Merge planner and test-writer outputs into a single wave-structured plan:

### Wave Plan
Table: | Wave # | Name | Files | Test Command | Runtime | Conventional Commit |

**Test command rule:** Every test command MUST target a single test class:
`mvn test -pl <module> -Dtest=<TestClassName> -q`
A bare module run (`mvn test -pl module`) is not acceptable — it runs the full suite.
If a wave's tests aren't isolated to a single class, flag it as a testability objection
and ask Dev how to scope it before proceeding.

### Per-Wave Implementation Steps + Test Specs
For each wave:
**Wave N — <name>**
Steps (numbered):
1. <step description>
2. <step description>

Test spec: <what to test, from test-writer>
Failing test must show: <what error to expect before implementation>

### Testability Objections
(Merged from both agents. If none: "None.")

### Unresolved Disagreements
(If none: "None.")

### Phase 6b — Design Validation

After assembling the unified plan (Wave table + Per-Wave Steps + Testability Objections),
and BEFORE presenting to Dev:

Check if pr-review-toolkit is available. If not: skip silently, proceed to PR strategy question.

If available, launch ONE sub-task (model: sonnet):

**code-reviewer** used as design-review agent — prompt:
"Review this APIM implementation PLAN for architectural anti-patterns — not code.

PUBLIC INTERFACES: [insert ### Public Interfaces section from task-planner output]
TESTABILITY OBJECTIONS: [insert ### Testability Objections from test-writer output]
WAVE DECOMPOSITION: [insert Wave Plan table from Phase 6]

Check for:
1. Concrete coupling — new class takes concrete dependency instead of interface
2. Service layer violation — business logic in controller step, persistence in service
3. Missing null safety — public interface method accepts object without documented nullability
4. Overly broad wave — single wave with >6 files
5. Hard-to-mock interface — returns framework types, static deps, or side-effectful constructors

Report ONLY high-confidence architectural concerns. For each: anti-pattern category,
affected file/interface, one-sentence risk, suggested alternative."

Wait for sub-task. If concerns found:
  Append to the `### Testability Objections` section:
  ```
  **Design-Validator Findings:**
  - [concern 1]
  - [concern 2]
  ```
  Do NOT output a separate message — concerns appear in the plan Dev is about to review.

If no concerns: proceed silently.

Then ask PR strategy:
AskUserQuestion header="PR strategy" options:
  1. "One PR per wave" — "Fine-grained review, easy to revert individual waves"
  2. "One PR for all waves" — "Single review when ticket is done"
  3. "Two PRs: foundation + rest" — "Ship Wave 1 early if it's a clean interface"

Then ask for plan approval:
AskUserQuestion header="Plan" options:
  1. "Approve — start implementing"
  2. "Revise — adjust something"

If Revise: ask what to change, incorporate, re-present.

## Phase 7 — Write task-state.md and hand off

On approval, create `.claude/` if it doesn't exist, then write two files:

**1. Write `.claude/task-state.md`** using the Write tool:

```
# Task: APIM-<N> — <ticketTitle>

## Progress
Wave: 1/<total>
Status: pending
Ticket: APIM-<N>
Cached: <today's date>
PR Strategy: <one-pr-per-wave | one-pr-for-all | two-pr-foundation-rest>

## Waves

### Wave 1 — <name> ○ (pending)
Test: `<testCommand>` (~<testCommandRuntime>)
      ↑ must be single-class scoped — no bare module runs
Commit: <conventionalCommit>
Files: <comma-separated basenames>
Steps:
- [ ] <step 1>
- [ ] <step 2>
...

### Wave 2 — <name> ○ (pending)
Test: `<testCommand>` (~<testCommandRuntime>)
Commit: <conventionalCommit>
Files: <comma-separated basenames>
Steps:
- [ ] <step 1>
...

[continue for all waves]

## Session Log
(empty — implement-task will append entries)
```

**2. Write `.claude/plan-document.md`** with the full merged plan markdown from Phase 6 (for on-demand reference via "show full plan").

Do NOT write plan-steps.json or ticket-cache.json (retired formats).

Tell Dev: "Plan written to .claude/task-state.md."

AskUserQuestion header="Plan written" options:
  1. "Start Wave 1 now"
  2. "Pause — resume next session"

If "Start Wave 1 now": invoke /gravitee-dev-workflow:implement-task.
If "Pause": confirm task-state.md is committed and end.
