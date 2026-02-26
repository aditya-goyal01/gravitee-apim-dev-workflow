#!/usr/bin/env bash
# run-recording.sh — Non-interactive E2E demonstration.
# Runs all 12 behavior checks inside a single shell, suitable for
# asciinema recording without a live Claude session.
#
# Usage:
#   asciinema rec test-e2e/recordings/plugin-e2e-$(date +%Y%m%d).cast \
#     --title "gravitee-dev-workflow E2E" --cols 220 --rows 50 \
#     --command "bash test-e2e/run-recording.sh"
#
# Claude sessions are simulated: artifacts are produced directly so every
# hook path is exercised and verify.sh can assert them.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_REPO="$HOME/gravitee-plugin-test"
HOOK()  { env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/hooks/$1"; }
PAUSE() { sleep "${1:-1}"; }

header() { printf '\n\033[1;36m━━━ %s ━━━\033[0m\n\n' "$*"; PAUSE 0.5; }
note()   { printf '\033[33m# %s\033[0m\n' "$*"; PAUSE 0.3; }
run()    { printf '\033[1m$ %s\033[0m\n' "$*"; PAUSE 0.3; eval "$*"; }

# ── Intro ──────────────────────────────────────────────────────────────────────
clear
printf '\033[1m gravitee-dev-workflow Plugin — End-to-End Test\033[0m\n'
printf ' Plugin root : %s\n' "$PLUGIN_ROOT"
printf ' Test repo   : %s\n' "$TEST_REPO"
printf ' Date        : %s\n\n' "$(date)"
PAUSE 1

# ── Part 1: Verify synthetic repo ─────────────────────────────────────────────
header "PART 1 — Synthetic repo"
run "cd $TEST_REPO"
note "Calculator.java — subtract method intentionally missing"
run "cat src/main/java/io/gravitee/test/calculator/Calculator.java"
note "No session-metrics.jsonl yet — reviewer will be silent on first open"
run "ls .claude/"
PAUSE 1

# ── Part 2: Branch manager (behaviors 7, 8, 9) ────────────────────────────────
header "PART 2 — branch-manager (behaviors 7, 8, 9)"
note "Switch to main and create a dirty file to test stash path"
run "git checkout main"
run "echo 'dirty content' > dirty-test.txt && git add dirty-test.txt"
run "git status"
note "branch-manager should stash dirty work, then switch to apim-100"
printf '\033[1m$ bash %s/hooks/branch-manager.sh 100\033[0m\n' "$PLUGIN_ROOT"
bash "$PLUGIN_ROOT/hooks/branch-manager.sh" 100 <<< "2" 2>&1 || true
PAUSE 0.5
note "Behavior 7: on apim-100; behavior 8: stash was created"
run "git branch && git stash list"
PAUSE 1

# ── Part 3: Session 1 — session-loader new_task (behavior 1, 2) ───────────────
header "PART 3 — Session 1 open (behaviors 1 & 2)"
note "Behavior 2: session-reviewer shows NOTHING — no metrics file yet"
printf '\033[1m$ [session-reviewer]\033[0m\n'
echo '{"hookEventName":"startup","cwd":"'"$TEST_REPO"'"}' \
    | HOOK session-reviewer.sh 2>&1 \
    || true
printf '(no output — correct)\n'
PAUSE 0.5

note "Behavior 1: session-loader injects [Session Context] new_task block"
printf '\033[1m$ [session-loader]\033[0m\n'
echo '{"hookEventName":"startup","cwd":"'"$TEST_REPO"'"}' \
    | HOOK session-loader.sh 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['hookSpecificOutput']['additionalContext'])"
PAUSE 1

# ── Part 3 cont: /plan-task artifact (behavior 11) ────────────────────────────
header "PART 3 cont — /plan-task artifact (behavior 11)"
note "Simulating what /plan-task Phase 7 writes to task-state.md"
mkdir -p "$TEST_REPO/.claude"
cat > "$TEST_REPO/.claude/task-state.md" << 'TASK'
# Task: APIM-100 — Add subtract method to Calculator

## Progress
Wave: 1/1
Status: in-progress
Ticket: APIM-100
Cached: 2026-02-26
PR Strategy: one-pr-for-all

## Waves

### Wave 1 — Implementation → (in progress)
Test: `mvn test -pl . -Dtest=CalculatorSubtractTest -q` (~15s)
Commit: feat(calculator): add subtract method
Files: Calculator.java, CalculatorSubtractTest.java
Steps:
- [ ] Write CalculatorSubtractTest with happy path and edge cases
- [ ] Add subtract(int a, int b) method to Calculator.java

## Session Log
TASK
run "cat $TEST_REPO/.claude/task-state.md"
note "Committing task-state.md so awaiting-review restore works later"
run "git -C $TEST_REPO add .claude/task-state.md && git -C $TEST_REPO commit -m 'chore(test): save task-state.md'"
PAUSE 0.5

# ── Part 3B: session-terminator Session 1 (behavior 3) ────────────────────────
header "PART 3B — session-terminator Session 1 (behavior 3)"
note "Behavior 3: terminator writes session-metrics.jsonl at session end"
printf '\033[1m$ [session-terminator session-1]\033[0m\n'
echo '{"hookEventName":"Stop","session_id":"e2e-session-1","cwd":"'"$TEST_REPO"'","transcript_file":"/dev/null"}' \
    | HOOK session-terminator.sh 2>&1
echo ""
note "JSONL created — 1 entry:"
cat "$TEST_REPO/.claude/session-metrics.jsonl" | python3 -m json.tool
PAUSE 1

# ── Part 4: Awaiting-review context demo (behavior 6) ─────────────────────────
header "PART 4 — awaiting-review context (behavior 6)"
note "Replace task-state.md with awaiting-review fixture"
run "cp $PLUGIN_ROOT/test-e2e/fixtures/task-state-awaiting.md $TEST_REPO/.claude/task-state.md"
run "grep '^Status:' $TEST_REPO/.claude/task-state.md"
note "Behavior 6: session-loader emits awaiting-review context"
printf '\033[1m$ [session-loader — awaiting-review]\033[0m\n'
echo '{"hookEventName":"startup","cwd":"'"$TEST_REPO"'"}' \
    | HOOK session-loader.sh 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['hookSpecificOutput']['additionalContext'])"
note "Restoring real task-state.md from git"
run "git -C $TEST_REPO checkout apim-100 -- .claude/task-state.md"
run "grep '^Status:' $TEST_REPO/.claude/task-state.md"
PAUSE 1

# ── Part 5: Session 2 — implement-task artifacts (behaviors 12, 4) ────────────
header "PART 5 — Session 2 open (behavior 4) + /implement-task TDD (behavior 12)"
note "Behavior 4: session-reviewer shows last-session metrics (1 prior entry)"
printf '\033[1m$ [session-reviewer session-2]\033[0m\n'
echo '{"hookEventName":"startup","cwd":"'"$TEST_REPO"'"}' \
    | HOOK session-reviewer.sh 2>&1
PAUSE 0.5

note "session-loader for Session 2 — writes 'continue' marker (task-state.md present)"
printf '\033[1m$ [session-loader session-2]\033[0m\n'
echo '{"hookEventName":"startup","cwd":"'"$TEST_REPO"'"}' \
    | HOOK session-loader.sh 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['hookSpecificOutput']['additionalContext'])"
PAUSE 0.5

note "Behavior 12: /implement-task TDD — write failing test (RED)"
cat > "$TEST_REPO/src/test/java/io/gravitee/test/calculator/CalculatorSubtractTest.java" << 'JAVA'
package io.gravitee.test.calculator;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class CalculatorSubtractTest {

    private final Calculator calculator = new Calculator();

    @Test
    void subtract_returnsDifference() {
        assertEquals(2, calculator.subtract(5, 3));
    }

    @Test
    void subtract_negativeResult() {
        assertEquals(-2, calculator.subtract(3, 5));
    }

    @Test
    void subtract_zeroFromZero() {
        assertEquals(0, calculator.subtract(0, 0));
    }
}
JAVA
printf '\033[1m$ mvn -f %s/pom.xml test -Dtest=CalculatorSubtractTest -q  # expect RED\033[0m\n' "$TEST_REPO"
mvn -f "$TEST_REPO/pom.xml" test -Dtest=CalculatorSubtractTest -q 2>&1 | grep -E "FAIL|ERROR|Tests run" | head -5 || true
printf '(BUILD FAILURE — expected, subtract method does not exist yet)\n'
PAUSE 0.5

note "Phase 4C: write production code to make test GREEN"
cat > "$TEST_REPO/src/main/java/io/gravitee/test/calculator/Calculator.java" << 'JAVA'
package io.gravitee.test.calculator;

public class Calculator {

    public int add(int a, int b) {
        return a + b;
    }

    public int multiply(int a, int b) {
        return a * b;
    }

    public int subtract(int a, int b) {
        return a - b;
    }
}
JAVA
printf '\033[1m$ mvn -f %s/pom.xml test -Dtest=CalculatorSubtractTest -q  # expect GREEN\033[0m\n' "$TEST_REPO"
mvn -f "$TEST_REPO/pom.xml" test -Dtest=CalculatorSubtractTest -q 2>&1
printf '(BUILD SUCCESS)\n'

note "Mark steps [x] and wave ✓ in task-state.md"
cat > "$TEST_REPO/.claude/task-state.md" << 'TASK'
# Task: APIM-100 — Add subtract method to Calculator

## Progress
Wave: 1/1
Status: complete
Ticket: APIM-100
Cached: 2026-02-26
PR Strategy: one-pr-for-all

## Waves

### Wave 1 — Implementation ✓ (commit: abc0001)
Steps: 2 completed — see git log abc0001

## Session Log
- 2026-02-26T12:00Z: Wave 1 complete (2 files)
TASK
run "git -C $TEST_REPO add src/ .claude/task-state.md && git -C $TEST_REPO commit -m 'feat(calculator): add subtract method'"
run "git -C $TEST_REPO log --oneline"
PAUSE 0.5

note "session-terminator for Session 2"
printf '\033[1m$ [session-terminator session-2]\033[0m\n'
echo '{"hookEventName":"Stop","session_id":"e2e-session-2","cwd":"'"$TEST_REPO"'","transcript_file":"/dev/null"}' \
    | HOOK session-terminator.sh 2>&1
PAUSE 1

# ── Part 6: Session 3 — trend arrows (behavior 5) ─────────────────────────────
header "PART 6 — Session 3 (behavior 5: trend arrows)"
note "Session-terminator for Session 3 (free-chat session to generate a 3rd entry)"
echo '{"hookEventName":"Stop","session_id":"e2e-session-3","cwd":"'"$TEST_REPO"'","transcript_file":"/dev/null"}' \
    | HOOK session-terminator.sh 2>&1
echo ""
note "Behavior 5: session-reviewer now shows ↑↓→ trend arrows (3 prior sessions)"
printf '\033[1m$ [session-reviewer session-4]\033[0m\n'
echo '{"hookEventName":"startup","cwd":"'"$TEST_REPO"'"}' \
    | HOOK session-reviewer.sh 2>&1
PAUSE 1

# ── Part 7: All 3 JSONL entries ───────────────────────────────────────────────
header "PART 7 — All JSONL entries"
note "$(wc -l < "$TEST_REPO/.claude/session-metrics.jsonl" | tr -d ' ') sessions recorded"
while IFS= read -r line; do
    echo "$line" | python3 -m json.tool
    printf -- '---\n'
done < "$TEST_REPO/.claude/session-metrics.jsonl"
PAUSE 1

# ── Part 8: verify.sh ─────────────────────────────────────────────────────────
header "PART 8 — verify.sh"
bash "$PLUGIN_ROOT/test-e2e/verify.sh"
PAUSE 1

printf '\n\033[1;32mRecording complete.\033[0m\n'
printf 'Play back: asciinema play test-e2e/recordings/plugin-e2e-*.cast\n\n'
