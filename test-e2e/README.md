# E2E Recording Guide — gravitee-dev-workflow Plugin

Demonstrates 12 behaviors across hooks, branch-manager, and skills in one asciinema recording.
Three Claude sessions. ~15–20 minutes total.

## Behaviors Tested

| # | Behavior | Where |
|---|----------|-------|
| 1 | session-loader injects `[Session Context]` block | Session 1 open |
| 2 | session-reviewer silent on first-ever session | Session 1 stderr |
| 3 | session-terminator writes `session-metrics.jsonl` at session end | After Session 1 |
| 4 | session-reviewer shows last-session metrics on Session 2 | Session 2 stderr |
| 5 | session-reviewer shows trend arrows (↑↓→) on Session 3 | Session 3 stderr |
| 6 | session-loader emits awaiting-review context | Part 4 demo |
| 7 | branch-manager creates apim-100 branch | Part 2 |
| 8 | branch-manager stashes dirty work on switch | Part 2 |
| 9 | branch-manager offers stash restore interactively | Part 2 |
| 10 | /hello lists all 6 skills in a table | Session 1 |
| 11 | /plan-task creates task-state.md with waves | Session 1 |
| 12 | /implement-task runs TDD loop, updates task-state.md [x] | Session 2 |

---

## Prerequisites

```bash
# 1. Plugin installed
claude plugin list | grep gravitee-dev-workflow

# 2. Run setup — creates ~/gravitee-plugin-test/ with Calculator project
bash test-e2e/setup.sh

# 3. Recommended terminal size
# 220 cols × 50 rows — prevents line wrapping in the cast
```

---

## PART 0 — Start Recording

```bash
asciinema rec test-e2e/recordings/plugin-e2e-$(date +%Y%m%d).cast \
    --title "gravitee-dev-workflow E2E" \
    --cols 220 --rows 50
```

Once inside the asciinema shell:

```bash
echo "=== gravitee-dev-workflow Plugin — End-to-End Test ==="
echo "Date: $(date)"
echo "Repo: ~/gravitee-plugin-test"
```

---

## PART 1 — Verify Synthetic Repo

```bash
cd ~/gravitee-plugin-test
echo "--- [1] Repo structure ---"
ls -la
echo ""
echo "--- Calculator.java (no subtract method — the APIM-100 target) ---"
cat src/main/java/io/gravitee/test/calculator/Calculator.java
echo ""
echo "--- CalculatorTest.java (add + multiply only) ---"
cat src/test/java/io/gravitee/test/calculator/CalculatorTest.java
echo ""
echo "--- Git state ---"
git log --oneline
git branch
echo ""
echo "--- .claude/ has no metrics file yet ---"
ls .claude/
```

**Verify:** No `session-metrics.jsonl` in `.claude/`.

---

## PART 2 — Branch Manager (Behaviors 7, 8, 9)

```bash
echo "=== [BEHAVIORS 7+8+9] branch-manager: create + stash + restore prompt ==="

# Switch to main so branch-manager has work to do
git checkout main

# Create a dirty file to trigger the stash path
echo "dirty content" > dirty-test.txt
git add dirty-test.txt
echo "--- Dirty working tree ---"
git status

echo "--- Running branch-manager: should stash, then switch to apim-100 ---"
bash /Users/aditya.goyal/projects/dev-workflow/hooks/branch-manager.sh 100
```

At the `Choice [1/2]:` prompt, type **`2`** (Skip — keep stash for now).

```bash
echo "--- Stash was created (behavior 8) ---"
git stash list
echo ""
echo "--- Now on apim-100 (behavior 7) ---"
git branch
```

---

## PART 3 — Session 1: First Session + /hello + /plan-task

```bash
echo "=== [SESSION 1] First-ever session ==="
echo "Expected: session-reviewer shows NOTHING (no metrics yet) — behavior 2"
echo "Expected: session-loader injects [Session Context] new_task message — behavior 1"
echo "Starting claude..."
```

**Open Claude Code** in `~/gravitee-plugin-test/` on branch `apim-100`.

Watch the terminal **before Claude's first prompt**:
- No `[Session Reviewer]` line should appear (behavior **2** — silent first session)
- Claude's system context will contain the `[Session Context]` block (behavior **1**)

**Inside Claude, type:**

```
/gravitee-dev-workflow:hello
```

Verify: table of all 6 skills appears — `hello`, `install-tools`, `install-plugins`, `install-mcp-servers`, `plan-task`, `implement-task` (behavior **10**).

Then type:

```
/gravitee-dev-workflow:plan-task
```

When asked for the ticket, paste:

```
Ticket: APIM-100
Description: Add subtract(int a, int b) method to the Calculator class.
The method should return the arithmetic difference (a minus b).
Acceptance criteria:
- subtract(5, 3) returns 2
- subtract(3, 5) returns -2
- subtract(0, 0) returns 0
```

Walk through plan-task:
- Wave plan prompt → **"Looks good"**
- PR strategy → **"One PR for all waves"**
- Plan approval → **"Approve"**
- Start Wave 1 now → **"Pause — resume next session"** (forces a second session)

**Type `/exit`** to close Claude.

---

## PART 3B — Verify Session 1 Artifacts

```bash
echo "=== [VERIFY after Session 1] ==="
echo "--- task-state.md (behavior 11) ---"
cat .claude/task-state.md
echo ""
echo "--- session-metrics.jsonl (behavior 3: terminator wrote 1 line) ---"
cat .claude/session-metrics.jsonl | python3 -m json.tool
echo ""
echo "--- workflowType should be new_task ---"
grep workflowType .claude/session-metrics.jsonl

# Commit task-state.md so the awaiting-review restore in Part 4 can use git checkout
git add .claude/task-state.md
git commit -m "chore(test): save task-state.md for restore"
```

**Verify:** 1 JSONL line, `workflowType: new_task`, `branch: apim-100`, `wavesCompleted: 0`.

---

## PART 4 — Awaiting-Review Context Demo (Behavior 6)

```bash
echo "=== [BEHAVIOR 6] awaiting-review context injection ==="
echo "--- Replacing task-state.md with awaiting-review fixture ---"
cp /Users/aditya.goyal/projects/dev-workflow/test-e2e/fixtures/task-state-awaiting.md .claude/task-state.md
grep "^Status:" .claude/task-state.md
```

**Open Claude briefly.** Watch the injected context — it should say:
> `Wave 1 PR is open — waiting for reviewer feedback.`

**Exit Claude immediately**, then restore:

```bash
echo "--- Restoring real task-state.md ---"
git checkout apim-100 -- .claude/task-state.md
grep "^Status:" .claude/task-state.md
```

---

## PART 5 — Session 2: Metrics Display + /implement-task TDD Loop

```bash
echo "=== [SESSION 2] Second session ==="
echo "Expected: session-reviewer shows last session metrics — behavior 4"
echo "Expected: trend arrows show — (only 1 prior session, no average yet)"
echo "Starting claude..."
```

**Open Claude Code** in `~/gravitee-plugin-test/`.

Watch **stderr before Claude's prompt**:
```
[Session Reviewer] Last: apim-100 | ...s | tools N — | commits 0 — | files 0 — → [rating]
```
(behavior **4**). Trend arrows are `—` because there's only 1 prior session.

**Inside Claude, type:**

```
/gravitee-dev-workflow:implement-task
```

Watch the TDD loop:
- **Phase 4A**: Claude writes `CalculatorSubtractTest.java` (test only, no production code)
- **Phase 4B**: Claude runs `mvn test -pl . -Dtest=CalculatorSubtractTest -q` → `BUILD FAILURE` (RED — expected)
- **Phase 4C**: Claude adds `subtract(int a, int b)` to `Calculator.java`
- **Phase 4D**: Claude re-runs test → `BUILD SUCCESS` (GREEN)
- task-state.md step marked `[x]`

When Claude asks "Continue or pause?", choose **Continue** until the wave is complete.
After commit, choose **Pause**.

**Type `/exit`.**

---

## PART 5B — Verify Session 2 Artifacts

```bash
echo "=== [VERIFY after Session 2] ==="
echo "--- task-state.md: steps should be [x] ---"
cat .claude/task-state.md
echo ""
echo "--- Calculator.java: subtract method should exist ---"
cat src/main/java/io/gravitee/test/calculator/Calculator.java
echo ""
echo "--- CalculatorSubtractTest.java: created by TDD loop ---"
cat src/test/java/io/gravitee/test/calculator/CalculatorSubtractTest.java
echo ""
echo "--- Tests GREEN ---"
mvn test -pl . -Dtest=CalculatorSubtractTest -q && echo "PASS"
echo ""
echo "--- JSONL now has 2 lines ---"
wc -l .claude/session-metrics.jsonl
echo ""
echo "--- Git log: wave commit present ---"
git log --oneline
```

---

## PART 6 — Session 3: Trend Arrows (Behavior 5)

```bash
echo "=== [SESSION 3] Third session ==="
echo "Expected: session-reviewer shows ↑↓→ trend arrows (2 prior sessions to compare)"
echo "Starting claude..."
```

**Open Claude Code** in `~/gravitee-plugin-test/`.

Watch **stderr before Claude's prompt** — the reviewer line should now show real trend arrows (`↑`, `↓`, or `→`) instead of `—` (behavior **5**).

**Inside Claude, ask one question to generate tool use:**

```
What waves are in my task-state.md and what is the current status?
```

**Type `/exit`.**

```bash
echo "=== [VERIFY after Session 3] ==="
echo "--- JSONL: 3 lines ---"
wc -l .claude/session-metrics.jsonl
echo ""
echo "--- All 3 entries ---"
while IFS= read -r line; do
    echo "$line" | python3 -m json.tool
    echo "---"
done < .claude/session-metrics.jsonl
```

---

## PART 7 — Final verify.sh

```bash
echo "=== [FINAL] Running verify.sh — all 12 assertions ==="
bash /Users/aditya.goyal/projects/dev-workflow/test-e2e/verify.sh
```

All lines should print `PASS`. Script exits 0.

---

## PART 8 — Stop Recording

```bash
echo "=== Recording complete ==="
exit
```

The `.cast` file is saved to `test-e2e/recordings/`.

Play it back with:
```bash
asciinema play test-e2e/recordings/plugin-e2e-*.cast
```

---

## Timing Guide

| Part | Expected Duration |
|------|------------------|
| 0 — Start recording | 1 min |
| 1 — Verify repo | 1 min |
| 2 — Branch manager | 2 min |
| 3 — Session 1 (hello + plan-task) | 5–6 min |
| 4 — Awaiting-review demo | 1 min |
| 5 — Session 2 (implement-task) | 4–5 min |
| 6 — Session 3 (trend arrows) | 1–2 min |
| 7 — verify.sh | 30 sec |
| 8 — Stop recording | 30 sec |
| **Total** | **~15–20 min** |

---

## Known Constraints

- **All Claude sessions must be opened from `~/gravitee-plugin-test/` on branch `apim-100`.**
  `session-terminator.sh` only writes metrics on `apim-*` branches (line 18). Sessions on `main` produce no JSONL entry.

- **Trend arrows require 2 prior sessions.**
  After Session 1, the reviewer shows `—` (no average). After Session 2, real `↑↓→` arrows appear in Session 3.

- **task-state.md must be committed before Part 4.**
  The `git checkout apim-100 -- .claude/task-state.md` restore in Part 4 requires the file to be in git history. Part 3B commits it — do not skip that step.

- **Maven `-pl .` runs from `~/gravitee-plugin-test/`.**
  The test command in task-state.md uses `-pl .`. It only works when CWD is the project root. Always open Claude from within that directory.
