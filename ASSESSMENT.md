# Honest Value Assessment — Gravitee Dev Workflow Plugin

> Written as a transparent evaluation for a skeptical senior engineer.
> Every claim references an exact file and line. Scores have honest caveats, not marketing.

---

## TL;DR (30-second scan)

| Dimension | Score | One-sentence verdict |
|-----------|-------|----------------------|
| Session Continuity | **8.5/10** | Wave-scoped step lookup fixed; eliminates stale-step injection on resume |
| Planning / Agents | **8.5/10** | Live module layout + transitive deps at plan time; design validator now visible |
| TDD Enforcement | **7.5/10** | Actionable "Unexpected GREEN" guidance with pre-existence + assertion quality checks |
| Quality Gate | **7.5/10** | RxJava3 reactive silent failures added; code-reviewer context explains APIM reasoning |
| Analytics | **7/10** | `filesChanged` per-session (Bug 1 fixed); `reviewRounds` is rework cycles only (Bug 2 fixed); N vs N-1 display |
| Portability | **9/10** | git+bash+python3 only; graceful degradation at every optional dependency |
| Testability | **8/10** | 195 tests covering failure modes; no E2E; malformed state from Claude's Edit is untested |
| **Composite** | **~8.3/10** | Genuine workflow value; process-over-automation tradeoffs are explicit and deliberate |

---

## The Problem Being Solved

The README names it the "3-session death spiral." Here is the concrete failure mode:

**Session 1**: You explain the ticket. Claude implements Wave 1. You agree on an interface. Session ends.

**Session 2**: Claude opens fresh. No memory. "What are we building?" You paste the ticket again. "What interface did we agree on?" You paste it again. Half the session is re-grounding. Wave 2 starts late.

**Session 3**: Re-grounding again. By now implementation has drifted from Jira acceptance criteria. There is a `catch` block that silently swallows a `TechnicalException` — no reviewer noticed because reviewers look for logic, not exception chains. Coverage is 60%.

**This plugin's answer**: `.claude/task-state.md` — a markdown file committed on the feature branch alongside the code. `session-loader.sh` reads it at every `SessionStart` and injects branch, wave number, next step, and test command as the first context block before any user input. Claude opens knowing exactly where it left off. The rest — TDD gates, quality agents, analytics — serve this central goal.

---

## Design Strategy: Why Process Over Automation

Three deliberate choices underpin every design decision:

**1. Zero infrastructure.** No database. No CI pipeline. No network requirement for hooks. No npm, no Java, no jq. Requirements: bash, git, python3 — all universally available on any development machine. `README.md:363`: "The choice is explicit: reach zero vs. reach high. Zero wins for a workflow tool." This means the plugin runs identically on a new MacBook and a CI runner.

**2. Markdown over JSON for state.** Previous approach used `.claude/session-states/apim-<N>.json` — Claude had to produce valid JSON; one malformed field broke session continuity; schema changes broke prior sessions. `task-state.md` is plain markdown: Claude edits it with the `Edit` tool, hooks read it with `grep`/`sed`, it's committed with the wave's code (git-versioned, PR-diffable), and "schema changes" are just markdown edits. `README.md:299–334`.

**3. AI-enforced process, not shell-enforced automation.** TDD gates, quality agents, and coverage checks are enforced through skill instructions Claude is expected to follow. Claude can skip any step if explicitly asked. The tradeoff is acknowledged: `README.md:354`: "The process is as strong as the discipline of the session." This is not a bug — it's the cost of zero infrastructure.

---

## Dimension 1 — Session Continuity / Context Management

### What the code actually does

`session-loader.sh` (72 lines) fires on every `SessionStart` matching `startup|resume|clear|compact`. It:

1. Reads hook input JSON with `python3` to extract `cwd` (`session-loader.sh:12`)
2. Writes a start-time marker: `date -u +"%Y-%m-%dT%H:%M:%SZ" > "$MARKERS/start-time"` (`session-loader.sh:19`)
3. Reads three fields from `task-state.md` via `grep`:
   - `WAVE` from `^Wave: ` (`session-loader.sh:30`)
   - `STATUS` from `^Status: ` (`session-loader.sh:31`)
   - `NEXT` from the first `^- \[ \]` line in the entire file (`session-loader.sh:32`)
4. Routes to one of four workflow types based on status and branch name:
   - `awaiting_review` → "PR is open, nothing to implement" (`session-loader.sh:34–41`)
   - `continue` → wave context + next step injected (`session-loader.sh:43–58`)
   - `new_task` → apim-N branch detected, no plan found (`session-loader.sh:59–64`)
   - `free_chat` → not a task branch (`session-loader.sh:65–71`)
5. Emits `hookSpecificOutput` JSON to stdout (injected as first context block before any user input) (`session-loader.sh:22–27`)
6. Silent failure: exits `0` on timeout or if `cwd` is empty — no context injected, no error (`session-loader.sh:13`)

### Genuine value

Re-orientation time at session start — the 5–10 minutes of "what are we building, where did we leave off" — is eliminated. The injected context block tells Claude: branch, current wave, status, and the exact next step. `implement-task` Phase 3 checks for this block and skips the confirmation dialog if the injected step matches the first `- [ ]` line (`implement-task/SKILL.md:50–52`). This is zero-friction auto-resume.

Workflow routing is clean: four states, explicit transitions. The `awaiting_review` state specifically prevents Claude from trying to implement on a branch where a PR is waiting for feedback — a real failure mode where Claude would make progress in the wrong direction.

### Honest limitations

**Step lookup is now wave-scoped** (`session-loader.sh:32–40`, fixed): `sed -n "/^### Wave ${WAVE_NUM} /,/^### Wave ${NEXT_WAVE} /p"` scopes extraction to the current wave section. Two-stage fallback handles the last wave (no following wave header). File-wide grep was the bug — stale steps from prior waves no longer appear as "next step."

**Interface signatures not in hot-path context**: the injected context contains branch, wave, status, and next step — not the interface method signatures agreed on in planning. Those are in `plan-document.md`, which is never auto-injected (zero token overhead design goal). For a session that requires interface alignment, the Dev must explicitly ask for the full plan.

**Silent exit on timeout** (`session-loader.sh:11,13`): `IFS= read -r -t 3` times out after 3 seconds; `[ -z "$CWD" ] && exit 0` exits if cwd parsing fails. No error is shown — Claude starts with no context injection, appearing as a normal fresh session.

### Score: 8.5/10

---

## Dimension 2 — Planning: Wave Decomposition + Parallel Agents

### What the code actually does

`plan-task/SKILL.md` runs 7 sequential phases. The high-value mechanics:

**Offline-first ticket resolution** (Phase 1): checks `task-state.md` for a `Cached:` date within 7 days before querying Jira. Fallback chain: cache → live Jira → stale cache → manual paste (`plan-task/SKILL.md:22–30`). Zero network requirement for resumed tickets.

**Parallel agent spawn** (Phase 4): both agents launch in a single Task tool message:
- `task-planner`: `subagent_type: Plan`, `model: opus`, `max_turns: 15`, with APIM module knowledge embedded in `agents/task-planner.md` (module layout, RxJava3 patterns, use-case command pattern, repository interface conventions, error types) (`plan-task/SKILL.md:73–76`, `agents/task-planner.md:48–92`)
- `test-writer`: `subagent_type: Plan`, `model: sonnet`, with explicit constraint: "Derive tests from REQUIREMENTS ONLY — do not read the implementation" (`agents/test-writer.md:41`)

**5-signal compatibility check** (Phase 5): after both complete, Claude scores:
1. File conflicts (same file, different changes)
2. Missing coverage (file modified, no test)
3. Interface mismatch (signature disagreements)
4. Scope divergence (one agent covered significantly more)
5. Testability objections (design flagged as hard to test)

If ≥2 signals: Phase 5b re-spawns both agents, each receiving the other's full output. Explicit disagreements surface as `### Unresolved Disagreements` for Dev to resolve (`plan-task/SKILL.md:84–103`).

**Design validation** (Phase 6b): after unified plan assembly, a `code-reviewer` sub-task reviews plan artefacts (not code) for APIM architectural anti-patterns — concrete coupling, service layer violations, null safety gaps, overly broad waves, hard-to-mock interfaces. Findings merge into `### Testability Objections` before Dev review, and now emit a visible attribution line: "[Design Validator] Scanned Wave plan — N concern(s) found and merged into Testability Objections." (`plan-task/SKILL.md`, Phase 6b).

### Genuine value

**Model assignment is principled**: Opus for architectural reasoning (wave independence, APIM module boundaries, RxJava3 constraint satisfaction simultaneously) and Sonnet for structured test specification. This is the right split by capability and cost.

**Requirements-only constraint on test-writer is the single most valuable design decision in the skill**: if test-writer reads the implementation, it tests what was written. The constraint forces test specification to reflect requirements, not code shape. Testability objections then surface at the planning stage, when they're cheapest to fix. `agents/test-writer.md:41–44`.

**5-signal check prevents the most common plan failure**: plan/test misalignment discovered after Wave 2 is implemented is expensive. Discovered before a line of code is written, it's a 20-minute reconciliation.

**Test command scoping is enforced**: every test command must be `mvn test -pl <module> -Dtest=<ClassName> -q` — no bare module runs. If a wave can't be isolated to a single test class, it's a testability objection before plan approval (`plan-task/SKILL.md:112–117`).

### Honest limitations

**Codebase orientation is shallow** (Phase 2): `Glob("**/pom.xml")` + `Glob("**/*<keyword>*.java")` + `git log --oneline -5` — useful but not deep. For large APIM codebases with many modules, this may miss relevant dependencies or recent changes outside the keyword pattern. `plan-task/SKILL.md:33–46`.

**APIM module knowledge is now supplemented at plan time** (`plan-task/SKILL.md` Phase 2 steps 7–8, added): Phase 2 now builds a live module→package summary and transitive dependency map via `Glob` + `Grep`, injected into the task-planner prompt as "Live Module Layout (scanned at plan time)" overriding the static table where they conflict. Static prompt text is the fallback baseline, not the primary source.

**Phase 5b reconciliation re-spawns both agents**: this is the right behavior, but it means a second set of Opus+Sonnet calls — meaningful token cost for plans that hit ≥2 signals. There is no lightweight pre-check to avoid full re-spawn.

### Score: 8.5/10

---

## Dimension 3 — TDD Enforcement

### What the code actually does

`implement-task/SKILL.md` Phase 4 enforces TDD with explicit step ordering:

**Step A**: Write failing test only. Zero production code. Test class name must match `-Dtest=` flag in test command (`implement-task/SKILL.md:67–70`).

**Step B**: Run test, expect RED. Three explicit outcomes (`implement-task/SKILL.md:72–78`):
- Compilation error → fix and re-run (not a TDD failure)
- "Tests run: 0" → file path issue, investigate before continuing
- Test FAILS → expected, proceed to Step C
- Test unexpectedly PASSES → **explicit warning**: "This test passes without implementation. Either the feature already exists or the test doesn't assert the right thing. Investigate before continuing." This case is not treated as a gift.

**Step C**: Write only what makes the failing test pass. Only files in current wave's `Files:` list — "not files from other waves" (`implement-task/SKILL.md:81–83`).

**Step D**: Run test, expect GREEN. If any test fails: read failure output, fix, re-run. Do not proceed until fully green (`implement-task/SKILL.md:86–89`).

**Step marking**: immediately after GREEN, a targeted `Edit` (not file rewrite) marks the step done in task-state.md (`implement-task/SKILL.md:91–99`). Wave header updated to `→ (in progress)` on first GREEN.

### Genuine value

**Unexpected GREEN now has structured investigation steps** (`implement-task/SKILL.md` Phase 4 Step B, updated): the vague "Investigate before continuing" is replaced with two concrete checks — (1) `git log --all --oneline -10 -- <test-file>` to detect pre-existing or reverted implementations, (2) explicit assertion quality review to catch trivially-passing tests (`assertNotNull`, `assertTrue(true)`). Removes ambiguity for junior engineers and edge cases.

**"Tests run: 0" as a named outcome**: this failure mode (test class not in compiled output, wrong path, wrong module) is common in Maven multi-module projects and is usually invisible — the build reports success with 0 tests. Naming it explicitly and requiring investigation prevents silent coverage gaps.

**Scope enforcement via wave Files list**: "Edit only files listed in current wave's `Files:`" prevents cross-wave contamination — a common cause of wave interdependencies that break independent testability.

### Honest limitations

**Entirely AI-enforced**: there is no shell script that verifies a test was written before production code. Claude can skip Step A if asked. The process is as strong as the session's discipline. `README.md:354`.

**GREEN means tests pass, not tests are meaningful**: there is no mutation testing, no coverage threshold enforcement. A test that asserts `assertNotNull(result)` and nothing else will pass Step D and advance the workflow. Test quality depends on Step A discipline, not automated verification.

**No cross-wave test isolation verification**: the skill enforces that only wave-scoped files are edited, but does not verify that the test command doesn't accidentally depend on Wave N+1 implementations. If Wave 2's test runner happens to compile Wave 3 files, silent coupling goes undetected.

### Score: 7.5/10

---

## Dimension 4 — Quality Gate (Pre-Commit)

### What the code actually does

Phase 4.5 fires after ALL steps in the current wave are `- [x]`, before the commit (`implement-task/SKILL.md:107`):

**Conditional on pr-review-toolkit**: checks if the plugin is available. If not: appends "Quality gate skipped — pr-review-toolkit not installed" to Session Log and proceeds (`implement-task/SKILL.md:112–117`).

**Agent selection** (`implement-task/SKILL.md:119–122`):
- Always: `code-reviewer` + `silent-failure-hunter`
- Additionally `type-design-analyzer` if wave name contains "Foundation" OR any file contains `Interface`, `DTO`, or `Model` in its name

**Parallel launch** (single Task tool message):

`code-reviewer` — named categories with explicit thresholds (`implement-task/SKILL.md:126–130`):
- Naming violations (camelCase methods, PascalCase types)
- Methods >20 lines or >3 nesting levels
- Missing null checks on public API boundary parameters
- Business logic in controllers, persistence logic in service layer
- Confidence ≥ 80% filter

`silent-failure-hunter` — RxJava3-specific failure modes (`implement-task/SKILL.md`, Phase 4.5, updated):
- Empty catch blocks
- Caught exceptions not rethrown or logged
- Error returns (null, empty Optional, -1) not checked by callers in the same wave
- **Added**: `subscribe()` with no `onError` handler — silent stream termination
- **Added**: `flatMap`/`concatMap` with no error handler and no `onErrorResumeNext` upstream
- **Added**: `Single.fromCallable`/`Maybe.fromCallable` without `.onErrorResumeNext`

`type-design-analyzer` (Foundation waves only) (`implement-task/SKILL.md:138–141`):
- Interfaces that don't express invariants beyond method signatures
- Implementation details leaking through the interface
- Types unmockable without real infrastructure

**Fix-or-acknowledge loop**: issues trigger an `AskUserQuestion`. If fix chosen: return to Phase 4 Step C → re-run TDD → Phase 4.5 re-fires. If acknowledge: logged, proceed. Gate is not one-shot (`implement-task/SKILL.md:143–153`).

### Genuine value

**Three independent dimensions in one gate**: structural correctness (code-reviewer), runtime failure modes (silent-failure-hunter), and type contract quality (type-design-analyzer). Each catches what the others miss. Running all three in parallel costs one round-trip instead of three sequential ones.

**silent-failure-hunter now catches the #1 production risk in APIM**: RxJava3 reactive chains with no `onError` handler — `subscribe()` without a second lambda, `flatMap` with no `onErrorResumeNext`, `Single.fromCallable` uncovered. These become silent gateway hangs with no stack trace. A catch-block scanner misses all of them. (`implement-task/SKILL.md` Phase 4.5, updated)

**Gate re-fires after fixes**: unlike a one-shot review, Phase 4.5 re-launches all agents after the fix loop. Fixes that introduce new issues are caught before they commit.

**type-design-analyzer conditional on Foundation waves**: Foundation waves define the contracts all subsequent waves build on. A poorly designed interface at Wave 1 multiplies maintenance cost through Waves 2–4. Service and controller waves don't introduce new interface contracts — running this agent there adds noise with no signal. The conditional is architecturally motivated.

### Honest limitations

**"Confidence ≥ 80%" is a prompt instruction to an LLM, not a calibrated algorithm**: different runs of code-reviewer on identical files may surface different issues or apply the threshold differently. There is no reproducibility guarantee. The instruction reduces noise — it does not eliminate nondeterminism.

**Conditional on pr-review-toolkit install, silently skipped if absent**: if the plugin is not installed, the gate is skipped with only a Session Log entry. There is no terminal warning to the developer. A developer who has not installed pr-review-toolkit gets zero quality gate with no visible signal (`implement-task/SKILL.md:112–117`).

**AI-enforced discipline**: the same limitation as TDD enforcement. Claude can acknowledge all findings and proceed. "Acknowledge and commit anyway (logged)" is a valid workflow path — the logging is not the same as prevention.

### Score: 7.5/10

---

## Dimension 5 — Analytics: What Is Measured and Why

### Field-by-field analysis

All 14 JSONL fields are written by `session-terminator.sh:111–128`. Here is each field's exact computation and honest assessment:

| Field | Computation (exact line) | What it tells you | Known imprecision |
|-------|--------------------------|-------------------|-------------------|
| `sessionId` | Passed through from hook input (`terminator.sh:11`) | Unique session identifier | Reliable |
| `branch` | `git rev-parse --abbrev-ref HEAD` (`terminator.sh:15`) | Branch at session end | Accurate |
| `ticket` | `sed 's/^apim-//'` from branch name (`terminator.sh:22`) | Ticket number | Accurate for apim-N branches only |
| `timestamp` | `date -u +%Y-%m-%dT%H:%M:%SZ` (`terminator.sh:112`) | Session end time UTC | Accurate |
| `toolUseCount` | `grep -c '"type":"tool_use"' "$TRANSCRIPT_PATH"` (`terminator.sh:99`) | Tool invocations in main session | Sub-agent tool calls may not appear in main transcript — undercounts complex sessions |
| `duration` | `NOW_EPOCH - START_EPOCH` (start-time marker written at SessionStart) (`terminator.sh:44–49`) | Session wall time in seconds | Accurate; 0 if start-time marker missing |
| `commitsCreated` | `git log --since="$START_TIME" --oneline \| wc -l` (`terminator.sh:57`) | git commits since session start | Counts ALL commits in period including fetched, cherry-picked, merged — not just authored |
| `filesChanged` | `git diff --name-only ${START_COMMIT}^..HEAD \| wc -l` (`terminator.sh:65–72`, fixed) | Files changed in commits made during this session | Fallback to merge-base if no session commits; was previously cumulative across all sessions |
| `workflowType` | Reads marker file written by session-loader (`terminator.sh:105–107`) | Session routing: continue/new_task/awaiting_review/free_chat | Accurate |
| `wavesCompleted` | `grep -c "^### Wave.*✓" "$TASK_STATE"` (`terminator.sh:32`) | Waves marked done in task-state.md | Accurate per format contract |
| `totalWaves` | `grep -c "^### Wave " "$TASK_STATE"` (`terminator.sh:34`) | Total waves in plan | Accurate |
| `currentWave` | `grep "^Wave: " \| grep -oE "[0-9]+" \| head -1` (`terminator.sh:36`) | Current wave number | Accurate |
| `prsMerged` | `gh pr list --head "$BRANCH" --state merged` count (`terminator.sh:71–74`) | PRs merged on this branch | Accurate when gh installed; 0 when absent (graceful degradation) |
| `reviewRounds` | Count of CHANGES_REQUESTED events only (`terminator.sh:85–93`, fixed) | Rework cycles on last PR | 0 = clean review (no rework); 1+ = actual change requests. APPROVED no longer counted. |

### Trend logic (session-reviewer.sh)

4-session rolling average (`session-reviewer.sh:87–99`): takes the last 4 entries before the current session, computes per-field average. Trend arrows computed at ±10% threshold (`session-reviewer.sh:79`). Three fields tracked: `toolUseCount`, `commitsCreated`, `filesChanged`.

**What trend arrows actually measure**: direction of change relative to recent history, not against any absolute threshold. A session that goes from 5 tools to 6 tools shows ↑. This is session-relative, not absolute productivity — a useful signal for detecting drift, not for comparing across developers.

### Wave-stall detection (session-reviewer.sh:162–172)

Triggers at ≥3 sessions on same `currentWave`, Wave 1 exempt: `grep -c "\"currentWave\":${CURRENT_WAVE_NUM}[,}]" "$METRICS_FILE"`. Wave 1 exemption reflects the reality that Foundation waves take longer; however, the exemption is not communicated in the displayed tip — a developer on Wave 1 for 5 sessions sees nothing.

### Rating logic (session-reviewer.sh:105–125)

Three levels:
- `❤️ Awesome`: PR merged last session (`prsMerged ≥ 1`), OR committed code with no declining trends (`SHIPPED=1 && TREND_DOWN=0`)
- `😊 Good`: any commit (`SHIPPED=1`), OR `toolUseCount ≥ 10`
- `😞 Do better`: default

`SHIPPED=1` requires both `commitsCreated ≥ 1` AND `filesChanged ≥ 1`. Because `filesChanged` is cumulative, it is always ≥ 1 on any apim-* branch after the first commit — making the `filesChanged` condition trivially true after Wave 1.

### Branch compliance (session-reviewer.sh:127–134)

`APIM_ENTRIES * 100 / TOTAL_SESSIONS` — the percentage of recorded sessions that ran on an apim-* branch. Derived at display time, not stored. **What this conflates**: a developer who does one ticket with 10 sessions (10/10 apim-* = 100%) reads the same as a developer who does one task session and ten exploratory sessions (1/11 = 9%). The metric reflects task-mix more than it reflects "discipline."

### Genuine value

- `workflowType`, `wavesCompleted`, `duration`, `prsMerged`, and `reviewRounds` are meaningful signals read together
- Trend arrows give session-over-session direction without requiring absolute thresholds — useful for detecting sudden changes without needing calibrated baselines
- `reviewRounds` now correctly counts rework cycles only (0 = clean; 1+ = rework needed) — `reviewRounds ≥ 1` is a genuine quality signal
- **New**: session-reviewer.sh displays N-1 (previous session) alongside last session for direct magnitude comparison — developers can see "tools went from 12 to 35" not just "↑"
- `filesChanged` now measures files changed in this session's commits (not cumulative from branch divergence) — per-session scope is correct for wave-scope tips

### Honest limitations

- `commitsCreated` counts fetched and merged commits from the period — overstates authoring activity in repositories with active team pushing during the session
- `toolUseCount` undercounts in sessions that spawned sub-agents via Task tool — the most complex sessions are the ones most likely to be undercounted
- `filesChanged` fallback to merge-base still applies when no commits were made during the session — planning sessions show cumulative total, not 0

### Score: 7/10

---

## Dimension 6 — Infrastructure & Portability

### What the code actually does

**Runtime requirements**: bash, git, python3. All hooks use only these three (`hooks/hooks.json`, all `.sh` files). The `gh` CLI is optional: every usage is guarded by `command -v gh >/dev/null 2>&1` (`session-terminator.sh:70`, `session-terminator.sh:79`), with explicit `|| echo "0"` fallback.

**No jq**: all JSON field extraction uses `grep -oE "\"field\":[^,}]+"` + `sed` + `python3 -c "import json..."`. This is the deliberate "no jq" convention documented in CLAUDE.md. Works on any machine without jq installed.

**Platform compatibility**: macOS primary date format: `date -j -u -f "%Y-%m-%dT%H:%M:%SZ"` with Linux fallback `date -d "$START_TIME"` (`session-terminator.sh:44–45`). The fallback is present but not tested in CI.

**Plugin auto-discovery**: `plugin.json` references `skills/` directory — new skills added to that directory are auto-discovered without explicit enumeration in the manifest.

**install.sh fallback** (non-plugin environments): idempotent Python merger for settings.json — merges `hooks` from the plugin into existing settings without overwriting existing configuration. Skills are NOT installed by install.sh — only hooks. The README was corrected to reflect this.

**lib/ sourcing pattern** (all hooks): `PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"` — uses plugin system path when available, falls back to relative path from script location for manual clones (`lib/term.sh:1`, `lib/git.sh` sourcing in each hook).

### Genuine value

git+bash+python3 is the lowest common dependency baseline for any active development machine. A tool that requires Docker, jq, npm, or a specific Java version will break on some machines and in some CI environments. This one will not.

Graceful degradation is explicit and tested: no gh CLI → PR metrics emit 0 (not a failure). Missing metrics file → session-reviewer exits cleanly (`session-reviewer.sh:16–18`). Timeout on hook input → session-loader exits 0. Every external dependency has a fallback path.

### Honest limitations

**install.sh installs hooks only, not skills**: a developer using `bash install.sh` gets session continuity (loader + reviewer + terminator hooks) but zero skills — no `/plan-task`, no `/implement-task`. This is a material capability difference from `claude plugin install`, documented in README but not immediately obvious.

**date fallback is untested in CI**: `code-scanning.yml` runs on ubuntu, but the date command fallback branch is not covered by test-hooks.sh tests. This is a low-probability gap (the fallback handles Linux correctly) but it is untested code.

**PLUGIN_ROOT fallback has a path assumption**: `$(cd "$(dirname "$0")/.." && pwd)` assumes the hook is one directory below the plugin root. Any non-standard installation layout would break sourcing silently.

### Score: 9/10

---

## Dimension 7 — Testing & Verifiability

### What the code actually does

`test-hooks.sh` — a self-contained bash test runner with no external test framework dependencies. Runs with `bash test-hooks.sh`. **195 tests** across 8 sections:

1. `lib/git.sh` function tests — `get_current_branch`, `is_dirty`, `auto_stash`, `find_auto_stash`
2. `lib/term.sh` output tests — all 5 terminal helper functions
3. `session-loader.sh` — workflow routing (continue, awaiting_review, new_task, free_chat), JSON output format, start-time marker creation
4. `session-terminator.sh` — JSONL output, duration computation, git metric collection, missing marker fallback, no-gh-cli graceful degradation
5. `session-reviewer.sh` — trend computation, rating logic, wave-stall detection, branch compliance calculation
6. `task-state.md` format contract — step markers (`- [ ]`, `- [x]`), wave header patterns, Progress section fields
7. Plugin structure — `plugin.json` validity, skills/ directory discovery
8. PLUGIN_ROOT sourcing — fallback path computation

**Failure mode coverage**: dirty working tree stash/restore, missing metrics file (reviewer exits cleanly), no gh CLI available, malformed JSON hook input, 3-second timeout fallback, start-time marker missing (duration = 0 with warning).

**ShellCheck**: `code-scanning.yml` runs ShellCheck on all `.sh` files on every push and pull request. Catches POSIX compliance violations, quoting errors, and undefined variables.

### Genuine value

195 tests covering failure paths that hook scripts almost never have tests for. Most Claude Code hook repositories have zero tests. The failure mode tests are the most valuable: a hook that fails silently on missing input or unexpected state is worse than no hook.

Test infrastructure is zero-dependency: plain bash, no bats, no shunit2, no npm test runner. Any developer with bash can run the suite with no setup.

### Honest limitations

**Test suite controls task-state.md content via temp files**: the tests exercise hooks with well-formed markdown inputs. There is no test for malformed `task-state.md` content written by Claude's `Edit` tool — e.g., an `Edit` that introduces extra whitespace before `- [ ]`, breaking the `^- \[ \]` pattern match.

**No E2E tests**: E2E tests were removed in commit `9e9bf7b`. End-to-end coverage — a full session lifecycle from SessionStart through wave completion to SessionEnd — requires a live Claude session and is not automated.

**ShellCheck runs on ubuntu (CI) but date fallback is not verified**: see Dimension 6.

### Score: 8/10

---

## Composite Score

| Dimension | Score | Primary honest caveat |
|-----------|-------|-----------------------|
| Session Continuity | 8.5/10 | Wave-scoped step lookup fixed; silent-exit on timeout unchanged |
| Planning / Agents | 8.5/10 | Live module layout at plan time; static agent prompt is now fallback only |
| TDD Enforcement | 7.5/10 | Structured GREEN investigation; AI-enforced only — no shell verification |
| Quality Gate | 7.5/10 | RxJava3 reactive patterns added; "80% confidence" is still a prompt, not an algorithm |
| Analytics | 7/10 | Per-session filesChanged (fixed); rework-only reviewRounds (fixed); N vs N-1 display added |
| Portability | 9/10 | git+bash+python3 only; graceful degradation at every optional dep |
| Testability | 8/10 | 195 tests; no E2E; malformed state from Edit tool untested |
| **Composite** | **~8.3/10** | |

---

## What 10/10 Would Look Like

From `README.md:381–386` (Design Trade-offs, already acknowledged by the authors):

> Formal CI enforcement (shellcheck + test-hooks.sh as build gates), runtime codebase awareness
> in task-planner (git log history injected at plan time, not just static module knowledge), and
> schema-validated task-state.md writes. None of these are present. Each requires either infrastructure
> or a dependency this plugin deliberately avoids.

The honest constraint is not engineering capability — it is the deliberate design choice to reach zero infrastructure. Formal CI requires a CI pipeline. Runtime codebase awareness requires a language server or indexer. Schema validation requires a schema format with a parser. Each addition moves the tool from "runs anywhere with git and bash" toward "requires a specific environment."

Whether that tradeoff is correct depends on the team. For a tool targeting engineers who switch between machines, environments, and contexts frequently, "zero infrastructure" is a meaningful property, not a limitation to be ashamed of.

---

*Assessment grounded in codebase at commit `9e9bf7b`, updated for CLAUDE.md trim + Bug 1/2/3 fixes + Improvements A–E applied in 2026-02-28.*
