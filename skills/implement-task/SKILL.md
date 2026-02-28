---
name: implement-task
description: Execute the approved wave plan — one wave at a time, with scoped TDD, auto-commit (via commit-commands), and PR creation (via pr-review-toolkit) at each wave boundary
user-invocable: true
allowed-tools: Bash, Read, Glob, Edit, Write, Task
---

> **Quick reference** — When to use: session continuation on an approved plan (`/implement-task`).
> Happy path: load wave state → confirm next step → write failing test (RED) →
> write production code (GREEN) → quality gate → commit → open PR → set awaiting-review or continue.
> Input: `.claude/task-state.md` written by `/plan-task`.

## Phase 1 — Load wave state

Read `.claude/task-state.md`. Extract:
- WAVE_NUM and TOTAL_WAVES from the `Wave: N/T` line in `## Progress`
- WAVE_NAME from the `### Wave N — <name>` line marked `(in progress)` or the first `(pending)` wave
- FILES from the `Files:` line in that wave section
- TEST_CMD from the `Test:` line in that wave section
- COMMIT_MSG from the `Commit:` line in that wave section
- NEXT_STEP: the first `- [ ]` line in that wave section

**Branch guard** — after reading task-state.md:
Extract the ticket number from the `Ticket: APIM-<N>` line. Run `git rev-parse --abbrev-ref HEAD`.
If the current branch does NOT contain `<N>` (case-insensitive):
  Tell Dev: "⚠ Current branch is `<current-branch>` but task is for APIM-<N>. Run `git checkout apim-<N>` before continuing."
  Stop — do not proceed to Phase 2.

If task-state.md does not exist: tell Dev no approved plan exists for this branch. Suggest running
/gravitee-dev-workflow:plan-task. Stop.

## Phase 2 — Wave orientation (compact — not the full plan)

Print this exact structure to Dev:

```
Wave N/T: <wave name>
Files: <basename list, comma-separated>
Test:  <testCommand>
Commit on complete: <commitMsg>

Steps:
  ▶ N.1  <first pending step>
  ○ N.2  <next step>
```

Do NOT print the full plan. If Dev asks "show full plan", Read `.claude/plan-document.md` and display only the current wave section.

## Phase 3 — Confirm next step

Find the first `- [ ]` line in the current wave section of task-state.md.

**Auto-resume:** Look at the opening of the current conversation for a `[Session Context]`
block injected by session-loader (will appear as the first assistant/system text of the
session). If found and it contains `Next step: <step>`, compare that step to the first
`- [ ]` line in task-state.md. If they match exactly, proceed to Phase 4 without asking.

**Manual or divergent:** If no [Session Context] was injected (user typed /implement-task
directly), or if the injected step differs from the first `- [ ]` line, show:
  AskUserQuestion header="Step N.M" options:
    1. "Start: <step description>"
    2. "Skip — implement manually"
    3. "Jump to wave" — list all wave headers with status markers (✓ done, → in progress, ○ pending)

If skip: confirm plan is in context, end.
If jump: set current wave to chosen wave, restart from Phase 2.

## Phase 4 — TDD execution

**Pre-step:** Read ALL files in the current wave's `Files:` list before writing any code.

**Step A — Write failing test**
Create or edit the test file. Write only the test for the current step.
Name the test class to match what the test command's `-Dtest=` flag expects.
Implement test logic only — zero production code.

**Step B — Run test → expect RED**
Run the `Test:` command from task-state.md.

Handle three outcomes:
- Compilation error → fix compilation, re-run Step B. (Not a TDD failure — fix and continue.)
- "No tests run" / "Tests run: 0" → the test class isn't in compiled output yet. Verify file path and re-run. If still 0: tell Dev and investigate.
- Test FAILS (expected) → proceed to Step C.
- Test unexpectedly PASSES → Tell Dev: "This test passes without implementation.
  Verify two things before continuing:
  1. Feature pre-existence: run `git log --all --oneline -10 -- <test-file>` — if this
     feature was recently committed and reverted, the implementation may exist elsewhere.
  2. Assertion quality: re-read the test you just wrote. Does it assert actual behaviour
     (specific return values, state changes, thrown exceptions) or just existence
     (assertNotNull, assertTrue(true))? If the latter, the test cannot go RED — rewrite
     it to assert specific expected output before proceeding."

**Step C — Write production code**
Write only what is needed to make the failing test pass.
Edit only files listed in the current wave's `Files:` — not files from other waves.
Minimum implementation: no speculative features, no cross-wave changes.

**Step D — Run test → expect GREEN**
Run the `Test:` command again.

If any test fails: read the failure output, fix it, re-run. Do not proceed until fully green.
Show Dev: test name + PASS/FAIL count.

**Mark step done** — immediately after GREEN, before anything else:

Use the Edit tool to mark the completed step in task-state.md:
```
old: "- [ ] <completed step description>"
new: "- [x] <completed step description>"
```

Do NOT rewrite the whole file — use a targeted Edit on that exact line.

Also update the wave header to show it is in progress:
```
old: "### Wave N — <name> ○ (pending)"
new: "### Wave N — <name> → (in progress)"
```

## Phase 4.5 — Pre-Commit Quality Gate

Runs after ALL steps in the current wave are `- [x]`, BEFORE Phase 5 commit.

Check if pr-review-toolkit is available (attempt to resolve `/pr-review-toolkit:code-reviewer`).

**If NOT available:** append to `## Session Log` in task-state.md:
```
- <ISO-date>: Quality gate skipped — pr-review-toolkit not installed
```
Proceed to Phase 5.

**If available — determine which agents to launch:**
- Always: `code-reviewer` + `silent-failure-hunter`
- Additionally `type-design-analyzer` IF: wave name contains "Foundation" OR any file in `Files:` contains `Interface`, `DTO`, or `Model` in its name

**Launch in parallel** (single Task tool message, 2–3 sub-tasks):

**code-reviewer** — prompt:
"Review these files from Wave N: [FILES_LIST]. Flag only issues with confidence ≥ 80%: naming
violations (camelCase methods, PascalCase types), methods >20 lines or >3 nesting levels,
missing null checks on public API boundary parameters, business logic in controllers,
persistence logic in service layer. For each: file, line range, issue, confidence.

Context for each rule:
- Method size > 20 lines: RxJava3 chains with nested operators are hard to debug;
  keep chains flat so backpressure handling is legible.
- Null on public API boundary: reactive chains cannot recover from null at subscription
  time — NullPointerException becomes a gateway hang with no stack trace.
- Business logic in controller: any permission or filtering logic in a controller
  requires a controller edit when business rules change — controllers must stay thin."

**silent-failure-hunter** — prompt:
"Scan Wave N files: [FILES_LIST]. Find: empty catch blocks, caught exceptions not rethrown
or logged, error returns (null, empty Optional, -1) not checked by callers in the same wave.
Report: file, line, one-sentence description of what failure becomes invisible.

Additionally, for RxJava3 reactive chains specifically:
- `subscribe()` calls with no `onError` handler: `source.subscribe(v -> ...)` with no
  second lambda or `onErrorResumeNext` upstream. Error silently terminates the stream.
- `flatMap`/`concatMap` operations where the inner observable has no error handler and
  the outer chain has no `onErrorResumeNext`. Error propagates silently.
- `Single.fromCallable(...)` or `Maybe.fromCallable(...)` without `.onErrorResumeNext`:
  checked exceptions from the callable are wrapped as errors and may go unhandled."

**type-design-analyzer** (Foundation waves only) — prompt:
"Review new interfaces and model types in: [FILES_LIST]. Check: do interfaces express
invariants beyond method signatures? Implementation details leaking through the interface?
Are types mockable without real infrastructure? Report only high-confidence concerns."

**Wait for all agents.** Collect results. Count total issues as N_ISSUES.

**If N_ISSUES > 0:**
Present to Dev: "Quality gate — Wave N caught N_ISSUES issue(s) before commit: [list]"
AskUserQuestion header="Pre-Commit Gate" options:
  1. "Fix issues — return to Phase 4 Step C"
  2. "Acknowledge and commit anyway (logged)"
If fix: return to Phase 4 Step C for affected files → re-run TDD → Phase 4.5 re-fires.
If acknowledge: append to Session Log, proceed to Phase 5.

**If N_ISSUES == 0:**
Tell Dev: "Quality gate passed. Proceeding to commit."
Proceed to Phase 5.

## Phase 5 — Wave completion

When all `- [ ]` lines in the current wave section are now `- [x]`:

1. Run the `Test:` command one final time. Show Dev: "Wave N complete: <name> — all tests pass."

2. Update task-state.md wave header using the Edit tool:
   ```
   old: "### Wave N — <name> → (in progress)"
   new: "### Wave N — <name> ✓ (commit: <7-char-hash>)"
   ```
   Also compact the wave's step list using the Edit tool.
   Replace all the "- [x] ..." lines for this wave with a single summary:
   ```
   new: "Steps: N completed — see git log <7-char-hash>"
   ```
   Do this as one Edit: old_string = the entire step block for this wave,
   new_string = the single summary line.

   Also update the Progress section:
   ```
   old: "Wave: N/T\nStatus: in-progress"
   new: "Wave: N+1/T\nStatus: pending"
   ```
   (Use `"Status: complete"` if this was the last wave.)

3. Append a log entry to the `## Session Log` section:
   ```
   - <ISO-date>: Wave N complete (<fileCount> files)
   ```

4. **Commit** — if commit-commands plugin is installed:
   > "Use /commit-commands:commit with message: `<COMMIT_MSG>`
   >  Include task-state.md as one of the committed files."
   If commit-commands is NOT installed, instruct Dev directly:
   > "Run: `git add <FILES_LIST> .claude/task-state.md && git commit -m '<COMMIT_MSG>'`"

5. **PR** — Read `PR Strategy:` from the Progress section of task-state.md.
   If absent, default to "one-pr-per-wave" and tell Dev: "PR Strategy not found —
   defaulting to one-pr-per-wave. Update task-state.md to change this."

   **Pre-PR coverage check** (if pr-review-toolkit available):
   Before opening PR, run as a sub-task:
   `pr-test-analyzer` — prompt: "Analyze test coverage for Wave N committed files:
   [FILES_LIST]. Identify business-logic paths with no test case. Rate each gap 1–10
   (10 = critical production risk). List only gaps with criticality ≥ 8."

   If gaps with criticality ≥ 8 found:
     Show Dev: "Coverage gaps before PR: [list with criticality]"
     AskUserQuestion header="Coverage Gaps" options:
       1. "Add missing tests — return to Phase 4 Step A"
       2. "Open PR anyway — address in review"
     If option 1: return to Phase 4 Step A, then come back here.
     If option 2: append gaps to Session Log.

   If prStrategy is "one-pr-per-wave": delegate:
   > "Use /pr-review-toolkit:review-pr or /commit-commands:commit-push-pr to open the PR."

6. **Review feedback wave**:

   **If prStrategy is "one-pr-per-wave" AND this is NOT the last wave:**
   After the PR is opened, update Status in the Progress section using the Edit tool:
   ```
   old: "Status: in-progress"
   new: "Status: awaiting-review"
   ```
   Tell Dev: "Wave N PR open. Status set to awaiting-review. Next session will show your branch is waiting — not mid-implementation."
   Do NOT stage a Review Feedback wave — that only happens after the final PR.

   **If this IS the last wave OR prStrategy is "one-pr-for-all":**
   Update Progress section — increment total:
   ```
   old: "Wave: N/T\nStatus: complete"
   new: "Wave: N+1/T+1\nStatus: pending"
   ```
   Append a new wave section before `## Session Log`:
   ```
   ### Wave N+1 — Review Feedback ○ (pending)
   Test: <same test command as Wave N>
   Commit: fix(scope): address PR review feedback
   Files: (TBD — update once feedback arrives)
   Steps:
   - [ ] Read reviewer comments and revise these steps accordingly
   ```
   Tell Dev: "Wave N+1 (Review Feedback) staged — resume after PR feedback lands."

## Phase 6 — Continue or pause

task-state.md is the handoff — no separate marker file needed.

If moving to next step within current wave:
  AskUserQuestion header="Progress" options:
    1. "Continue to step N.M+1 — <next step desc>"
    2. "Pause here"

If moving to next wave (current wave committed):
  AskUserQuestion header="Next wave" options:
    1. "Start Wave N+1: <wave name>"
    2. "Pause — resume next session"

If "Continue": go directly to Phase 4 for the next step. Do NOT re-run Phase 2 or 3.
If "Pause" or all waves done: "task-state.md has been updated — session continuity is guaranteed. Resume anytime."
