#!/usr/bin/env bash
# verify.sh — Post-recording assertions.
# Run after the asciinema recording to confirm all 12 behaviors produced
# the expected artifacts on disk.
set -euo pipefail

TEST_REPO="$HOME/gravitee-plugin-test"
METRICS="$TEST_REPO/.claude/session-metrics.jsonl"
TASK_STATE="$TEST_REPO/.claude/task-state.md"
CALC="$TEST_REPO/src/main/java/io/gravitee/test/calculator/Calculator.java"
SUBTRACT_TEST="$TEST_REPO/src/test/java/io/gravitee/test/calculator/CalculatorSubtractTest.java"

PASS=0; FAIL=0
ok()   { printf '\033[32m  PASS\033[0m  %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '\033[31m  FAIL\033[0m  %s\n' "$*"; FAIL=$((FAIL + 1)); }

printf '\n[verify.sh] Post-recording assertions\n\n'

# 1. JSONL exists and has 3+ lines
if [ -f "$METRICS" ]; then
    LINES=$(wc -l < "$METRICS" | tr -d ' ')
    if [ "$LINES" -ge 3 ]; then
        ok "JSONL exists with $LINES lines (expected >= 3)"
    else
        fail "JSONL has only $LINES lines — expected >= 3 (one per Claude session)"
    fi
else
    fail "JSONL does not exist at $METRICS"
fi

# 2. All JSONL entries are on apim-100
if [ -f "$METRICS" ]; then
    TOTAL=$(wc -l < "$METRICS" | tr -d ' ')
    APIM=$(grep -c '"branch": *"apim-100"' "$METRICS" 2>/dev/null || true)
    APIM="${APIM:-0}"
    if [ "$APIM" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
        ok "All $TOTAL JSONL entries on branch apim-100"
    else
        fail "Branch mismatch: $APIM/$TOTAL entries on apim-100"
    fi
fi

# 3. workflowType=new_task present (Session 1: plan-task)
if grep -q '"workflowType": *"new_task"' "$METRICS" 2>/dev/null; then
    ok "workflowType=new_task present (Session 1 plan-task flow)"
else
    fail "workflowType=new_task missing — session-loader may not have run"
fi

# 4. workflowType=continue present (Session 2: implement-task resume)
if grep -q '"workflowType": *"continue"' "$METRICS" 2>/dev/null; then
    ok "workflowType=continue present (Session 2 resume flow)"
else
    fail "workflowType=continue missing — task-state.md may not have been created"
fi

# 5. task-state.md exists
if [ -f "$TASK_STATE" ]; then
    ok "task-state.md exists"
else
    fail "task-state.md missing — /plan-task did not write it"
fi

# 6. task-state.md has correct ticket
if grep -q "^Ticket: APIM-100" "$TASK_STATE" 2>/dev/null; then
    ok "Ticket: APIM-100 in task-state.md"
else
    fail "Ticket: APIM-100 missing from task-state.md"
fi

# 7. task-state.md has at least 1 wave
WAVE_COUNT=$(grep -c "^### Wave " "$TASK_STATE" 2>/dev/null || echo "0")
if [ "$WAVE_COUNT" -ge 1 ]; then
    ok "task-state.md has $WAVE_COUNT wave(s)"
else
    fail "task-state.md has no waves — /plan-task phase 7 may not have completed"
fi

# 8. At least one completed step (implement-task TDD loop)
if grep -q "^- \[x\]" "$TASK_STATE" 2>/dev/null || grep -q "completed — see git log" "$TASK_STATE" 2>/dev/null; then
    ok "task-state.md has completed step(s) — TDD loop ran"
else
    fail "No completed steps in task-state.md — /implement-task TDD loop may not have run"
fi

# 9. CalculatorSubtractTest.java created by implement-task
if [ -f "$SUBTRACT_TEST" ]; then
    ok "CalculatorSubtractTest.java exists (Phase 4A — RED test written)"
else
    fail "CalculatorSubtractTest.java missing — TDD loop did not write the test"
fi

# 10. subtract method exists in Calculator.java (Phase 4C — GREEN code written)
if grep -q "subtract" "$CALC" 2>/dev/null; then
    ok "subtract method present in Calculator.java (Phase 4C — GREEN code written)"
else
    fail "subtract method missing from Calculator.java — Phase 4C did not run"
fi

# 11. Maven tests pass post-implementation
cd "$TEST_REPO"
if mvn test -pl . -Dtest=CalculatorSubtractTest -q 2>/dev/null; then
    ok "CalculatorSubtractTest passes — GREEN confirmed"
else
    fail "CalculatorSubtractTest failed — implementation incomplete or broken"
fi

# 12. At least 1 commit on apim-100 beyond initial (wave committed)
COMMIT_COUNT=$(git -C "$TEST_REPO" log --oneline main..apim-100 2>/dev/null | wc -l | tr -d ' ')
if [ "$COMMIT_COUNT" -ge 1 ]; then
    ok "apim-100 has $COMMIT_COUNT commit(s) beyond main (wave was committed)"
else
    fail "No commits on apim-100 beyond main — wave commit did not happen"
fi

# ── Summary ────────────────────────────────────────────────────────────────────
printf '\n[verify.sh] Results: \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
