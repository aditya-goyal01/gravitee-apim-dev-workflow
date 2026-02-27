# Honest Value Assessment — Gravitee Dev Workflow Plugin

> Scored evaluation for a skeptical senior engineer. Design context lives in README.md — this file records scores, honest caveats, and what changed.

---

## TL;DR

| Dimension | Score | One-sentence verdict |
|-----------|-------|----------------------|
| Session Continuity | **8.5/10** | Wave-scoped step lookup fixed; stale-step injection on resume eliminated |
| Planning / Agents | **8.5/10** | Live module layout + transitive deps at plan time; design validator now visible |
| TDD Enforcement | **7.5/10** | Structured "Unexpected GREEN" investigation; still AI-enforced only |
| Quality Gate | **7.5/10** | RxJava3 reactive silent failures added; 80% confidence threshold is a prompt, not an algorithm |
| Analytics | **7/10** | `filesChanged` per-session (Bug 1 fixed); `reviewRounds` is rework cycles only (Bug 2 fixed); N vs N-1 display |
| Portability | **9/10** | git+bash+python3 only; graceful degradation at every optional dependency |
| Testability | **8/10** | 195 tests covering failure modes; no E2E; malformed state from Claude's Edit untested |
| **Composite** | **~8.3/10** | Genuine workflow value; process-over-automation tradeoffs are explicit and deliberate |

---

## Dimension 1 — Session Continuity

### Score: 8.5/10

**What works**: `session-loader.sh` fires on every `SessionStart`, reads `task-state.md` via `grep`, and injects branch + wave + next step as the first context block before any user input. Four workflow routes: `continue`, `new_task`, `awaiting_review`, `free_chat`. `implement-task` Phase 3 skips the confirmation dialog when the injected step matches the first `- [ ]` line — zero-friction auto-resume.

**Fixed (Bug 3)**: `NEXT` step extraction now scoped to the current wave section via `sed -n "/^### Wave N /,/^### Wave N+1 /p"` (`session-loader.sh:36`). Two-stage fallback handles the last wave. Previously, `grep "^- \[ \]"` searched the entire file — stale steps from prior waves injected as "next step."

**Remaining limitations**:
- Interface signatures agreed on in planning are in `plan-document.md`, never auto-injected (zero token overhead by design). Sessions requiring interface alignment require an explicit "show full plan" request.
- Silent exit on hook timeout or cwd parse failure (`session-loader.sh:11,13`) — no error, no context injected. Developer sees a normal fresh session with no warning.

---

## Dimension 2 — Planning: Wave Decomposition + Parallel Agents

### Score: 8.5/10

**What works**: Offline-first ticket resolution (7-day cache → live Jira → stale cache → manual paste). Parallel Opus+Sonnet agent spawn. 5-signal compatibility check with Phase 5b reconciliation if ≥2 signals. Requirements-only constraint on test-writer (doesn't read implementation). Single-class test command scoping enforced. Design validator (Phase 6b) now emits a visible attribution line: "[Design Validator] Scanned Wave plan — N concern(s) found."

**Improved (Impr. A)**: Phase 2 now adds live module inventory (step 7: `Glob` groups files by module, flags inactive packages) and transitive dependency check (step 8: `Grep` finds classes that import the primary interface). Injected into task-planner as "Live Module Layout (scanned at plan time)" — overrides static prompt table where they conflict.

**Remaining limitations**:
- Phase 2 orientation depth is still keyword-based (`Glob("**/*<keyword>*.java")`). Cross-module dependencies not matching the keyword pattern may be missed.
- Phase 5b re-spawns both Opus+Sonnet agents — meaningful token cost for plans hitting ≥2 signals. No lightweight pre-check.

---

## Dimension 3 — TDD Enforcement

### Score: 7.5/10

**What works**: Explicit A→B→C→D step ordering. "Tests run: 0" named as a failure mode (not silent success). Scope enforcement via wave `Files:` list — no cross-wave contamination.

**Improved (Impr. B)**: Unexpected GREEN now has two concrete investigation steps (`implement-task/SKILL.md` Phase 4 Step B): (1) `git log --all --oneline -10 -- <test-file>` to detect pre-existing/reverted implementations, (2) explicit assertion quality review to catch trivially-passing tests (`assertNotNull`, `assertTrue(true)`).

**Remaining limitations**:
- Entirely AI-enforced. No shell script verifies test was written before production code. Process is as strong as session discipline.
- GREEN means tests pass, not tests are meaningful. No mutation testing, no coverage threshold.

---

## Dimension 4 — Quality Gate (Pre-Commit)

### Score: 7.5/10

**What works**: Three parallel agents after all wave steps are GREEN. `code-reviewer` (naming, complexity, null safety, business-logic placement; 80% confidence filter). `type-design-analyzer` conditional on Foundation waves. Fix-or-acknowledge loop; gate re-fires after fixes. Skipped (and logged) if pr-review-toolkit absent.

**Improved (Impr. C)**:
- `silent-failure-hunter` now includes RxJava3 reactive chain patterns: `subscribe()` with no `onError` handler, `flatMap`/`concatMap` with no `onErrorResumeNext`, `Single.fromCallable`/`Maybe.fromCallable` uncovered. These become silent gateway hangs with no stack trace — a catch-block scanner misses all of them.
- `code-reviewer` prompt enriched with APIM-specific reasoning per rule (why method size matters in RxJava3 chains, why null on reactive boundaries is fatal, why thin controllers matter).

**Remaining limitations**:
- "Confidence ≥ 80%" is a prompt instruction, not a calibrated algorithm. Nondeterminism is reduced, not eliminated.
- Gate silently skipped with only a Session Log entry if pr-review-toolkit not installed. No terminal warning.

---

## Dimension 5 — Analytics

### Score: 7/10

**Field-by-field**:

| Field | Computation | Known imprecision |
|-------|-------------|-------------------|
| `sessionId`, `branch`, `ticket`, `timestamp` | Direct from hook input / git | Reliable |
| `toolUseCount` | `grep -c '"type":"tool_use"'` in main transcript | Sub-agent tool calls may not appear — undercounts complex sessions |
| `duration` | `NOW_EPOCH - START_EPOCH` from start-time marker | 0 if marker missing |
| `commitsCreated` | `git log --since="$START_TIME"` | Counts fetched/merged commits too — overstates authoring in active repos |
| `filesChanged` | `git diff ${START_COMMIT}^..HEAD` (fixed, Bug 1) | Fallback to merge-base if no session commits — planning sessions show cumulative |
| `reviewRounds` | CHANGES_REQUESTED events only (fixed, Bug 2) | 0 = clean review, 1+ = rework cycles |
| `workflowType`, `wavesCompleted`, `totalWaves`, `currentWave`, `prsMerged` | grep / gh CLI | Accurate per format contract; gh degrades to 0 if absent |

**Improved (Impr. D)**: `session-reviewer.sh` now displays the N-1 session before the Last line for direct magnitude comparison. Developers see "tools went from 12 to 35" not just "↑".

**Remaining limitations**:
- `branchCompliance` conflates task-mix with discipline (10 sessions on one ticket = 100%, same as 1 task + 10 exploratory).
- Wave 1 exempt from stall detection tip — not communicated in output. A developer on Wave 1 for 5 sessions sees nothing.

---

## Dimension 6 — Portability

### Score: 9/10

bash, git, python3. No jq, no Docker, no npm. Every optional dependency (`gh`) guarded with explicit fallback. macOS/Linux date compatibility. Plugin auto-discovery via `skills/` directory. `install.sh` fallback for non-plugin environments (hooks only — skills require `claude plugin install .`).

**Remaining limitations**: date fallback branch (`date -d`) not covered by test-hooks.sh. PLUGIN_ROOT fallback assumes hooks/ is one level below root.

---

## Dimension 7 — Testability

### Score: 8/10

195 tests across 8 sections in plain bash (no bats, no shunit2). Failure mode coverage: missing markers, no gh CLI, malformed JSON input, timeout fallback, dirty tree stash/restore. ShellCheck on every push.

**Remaining limitations**: no test for malformed task-state.md written by Claude's `Edit` tool. No E2E tests (removed in `9e9bf7b` — requires a live Claude session).

---

## Composite

| Dimension | Score | Primary caveat |
|-----------|-------|----------------|
| Session Continuity | 8.5/10 | Silent exit on hook timeout |
| Planning / Agents | 8.5/10 | Keyword-based orientation; Phase 5b is expensive |
| TDD Enforcement | 7.5/10 | AI-enforced; GREEN ≠ meaningful tests |
| Quality Gate | 7.5/10 | 80% confidence is a prompt, not an algorithm |
| Analytics | 7/10 | toolUseCount undercounts; branchCompliance conflates task-mix |
| Portability | 9/10 | date fallback untested; install.sh hooks-only |
| Testability | 8/10 | No E2E; malformed Edit state untested |
| **Composite** | **~8.3/10** | |

The remaining gap to 10 is structural: AI-enforced TDD (no shell can force "write test first"), nondeterministic LLM quality gates, and analytics blind spots that require structured logging infrastructure. All are deliberate tradeoffs for zero-infrastructure reach.

---

*Grounded in codebase at commit `283b2f8` (2026-02-28).*
