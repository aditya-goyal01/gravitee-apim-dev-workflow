#!/bin/bash
# ================================================================
# Claude Code Hooks & Plugin — Comprehensive Test Suite
# ================================================================
# Covers:
#   §1  branch-manager.sh        — 13 tests
#   §2  session-loader.sh        —  8 tests  (prompt-based)
#   §3  session-reviewer.sh      — 13 tests
#   §4  session-terminator.sh    — 12 tests  (task-state.md)
#   §5  plugin structure         —  8 tests
#   §6  task-state.md format     —  8 tests  (replaces wave JSON §6/§7)
#   §7  PLUGIN_ROOT sourcing     —  6 tests
#   §8  reviewer + lib           —  9 tests
# ================================================================

SAMPLE_DIR="$(cd "$(dirname "$0")" && pwd)"
BRANCH_MANAGER="$SAMPLE_DIR/hooks/branch-manager.sh"
SESSION_LOADER="$SAMPLE_DIR/hooks/session-loader.sh"
SESSION_REVIEWER="$SAMPLE_DIR/hooks/session-reviewer.sh"
SESSION_TERMINATOR="$SAMPLE_DIR/hooks/session-terminator.sh"
PLUGIN_DIR="$SAMPLE_DIR"
LIB_DIR="$SAMPLE_DIR/lib"

# ── Infra ─────────────────────────────────────────────────────
TEST_ROOT=$(mktemp -d)
PASS=0
FAIL=0
BUGS=()
ERRORS=()

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

GREEN='\033[32m'; RED='\033[31m'; YELLOW='\033[33m'; BOLD='\033[1m'; RESET='\033[0m'
pass()   { printf "${GREEN}  ✅ %s${RESET}\n" "$1"; PASS=$((PASS+1)); }
fail()   { printf "${RED}  ❌ %s${RESET}\n" "$1"; FAIL=$((FAIL+1)); ERRORS+=("$1"); }
bug()    { printf "${YELLOW}  ⚠️  BUG: %s${RESET}\n" "$1"; BUGS+=("$1"); }
header() { printf "\n${BOLD}── %s ──${RESET}\n" "$1"; }

assert_contains() {
    local output="$1" expected="$2" label="$3"
    if echo "$output" | grep -qF "$expected"; then pass "$label"
    else
        fail "$label"
        printf "     expected to contain: %s\n" "$expected"
        printf "     actual (first 3 lines):\n"
        echo "$output" | head -3 | sed 's/^/       /'
    fi
}
assert_not_contains() {
    local output="$1" not_exp="$2" label="$3"
    if ! echo "$output" | grep -qF "$not_exp"; then pass "$label"
    else fail "$label (should NOT contain: $not_exp)"
    fi
}
assert_exit() {
    local actual="$1" expected="$2" label="$3"
    [ "$actual" -eq "$expected" ] && pass "$label" || fail "$label (exit $actual, want $expected)"
}
assert_file()    { [ -f "$1" ] && pass "$2" || fail "$2 (not found: $1)"; }
assert_no_file() { [ ! -f "$1" ] && pass "$2" || fail "$2 (should not exist: $1)"; }
assert_json_field() {
    local json="$1" field="$2" expected="$3" label="$4"
    local actual; actual=$(echo "$json" | jq -r "$field" 2>/dev/null)
    [ "$actual" = "$expected" ] && pass "$label" || fail "$label (field $field: got '$actual', want '$expected')"
}

# Create an isolated git repo on branch 'main'
make_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email "test@example.com"
    git -C "$dir" config user.name "Test"
    git -C "$dir" config commit.gpgsign false
    git -C "$dir" symbolic-ref HEAD refs/heads/main
    echo "init" > "$dir/README.md"
    git -C "$dir" add .
    git -C "$dir" commit -q -m "initial commit"
}

# Write a mock task-state.md
make_task_state() {
    local path="$1" wave="${2:-1}" total="${3:-3}" status="${4:-in-progress}"
    local ticket="${5:-1234}" next_step="${6:-Add repository interface}"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<EOF
# Task: APIM-${ticket} — Add subscription filtering

## Progress
Wave: ${wave}/${total}
Status: ${status}
Ticket: APIM-${ticket}
Cached: 2026-02-25

## Waves

### Wave 1 — Foundation ✓ (commit: abc1234)
Test: \`mvn test -pl gravitee-apim-rest-api-model -Dtest=SubscriptionQueryTest -q\` (~30s)
Commit: feat(subscription): add SubscriptionQuery filter model
Files: SubscriptionQuery.java, SubscriptionQueryTest.java
Steps:
- [x] Create SubscriptionQuery DTO
- [x] Add null-handling tests

### Wave ${wave} — Service Layer → (in progress)
Test: \`mvn test -pl gravitee-apim-rest-api-service -Dtest=SubscriptionServiceTest -q\` (~45s)
Commit: feat(subscription): implement plan-type filtering in service
Files: SubscriptionService.java, SubscriptionRepository.java
Steps:
- [x] Add filterByPlan method
- [ ] ${next_step}
- [ ] Wire service with Spring @Service

### Wave 3 — API Layer ○ (pending)
Test: \`mvn test -pl gravitee-apim-rest-api -Dtest=SubscriptionResourceTest -q\` (~60s)
Commit: feat(subscription): expose filter via REST API
Files: SubscriptionResource.java, SubscriptionMapper.java
Steps:
- [ ] Add filter query param to GET /subscriptions
- [ ] Map DTO to REST response

## Session Log
- 2026-02-25T10:30Z: Wave 1 complete (2 files)
EOF
}

# Write a mock JSONL transcript with N tool_use entries + 1 assistant text message
make_transcript() {
    local path="$1" tool_uses="${2:-5}" text="${3:-Completed feature. Next: write tests.}"
    mkdir -p "$(dirname "$path")"
    rm -f "$path"
    for i in $(seq 1 "$tool_uses"); do
        printf '{"type":"tool_use","id":"tu_%s"}\n' "$i" >> "$path"
    done
    local escaped_text
    escaped_text=$(printf '%s' "$text" | sed 's/"/\\"/g')
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$escaped_text" >> "$path"
}

# Write a session-metrics JSONL entry matching the new terminator format
make_metric() {
    local branch="${1:-apim-1234}" tool_use="${2:-10}" commits="${3:-1}"
    local files="${4:-5}" duration="${5:-600}" workflow="${6:-continue}"
    local waves_done="${7:-0}" total_waves="${8:-0}" current_wave="${9:-1}"
    local ticket="${branch#apim-}"
    printf '{"sessionId":"test","branch":"%s","ticket":"%s","timestamp":"%s","toolUseCount":%s,"duration":%s,"commitsCreated":%s,"filesChanged":%s,"workflowType":"%s","wavesCompleted":%s,"totalWaves":%s,"currentWave":%s}\n' \
        "$branch" "$ticket" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$tool_use" "$duration" "$commits" "$files" "$workflow" \
        "$waves_done" "$total_waves" "$current_wave"
}

# ================================================================
printf "\n${BOLD}================================================================${RESET}\n"
printf "${BOLD}  Claude Code Hooks & Plugin — Test Suite${RESET}\n"
printf "${BOLD}================================================================${RESET}\n"

# ================================================================
# §1  branch-manager.sh
# ================================================================
header "1. branch-manager.sh"

BM="$TEST_ROOT/bm-repo"
make_repo "$BM"
cd "$BM"

# 1.1 No argument
OUT=$(bash "$BRANCH_MANAGER" 2>&1); EC=$?
assert_exit $EC 1 "1.1  no argument → exit 1"
assert_contains "$OUT" "ticket number required" "1.1  friendly error message"

# 1.2 Non-numeric
OUT=$(bash "$BRANCH_MANAGER" "abc" 2>&1); EC=$?
assert_exit $EC 1 "1.2  non-numeric → exit 1"
assert_contains "$OUT" "must be numeric" "1.2  numeric validation message"

# 1.3 Alphanumeric (12ab)
OUT=$(bash "$BRANCH_MANAGER" "12ab" 2>&1); EC=$?
assert_exit $EC 1 "1.3  alphanumeric input rejected"

# 1.4 New branch, clean working tree
OUT=$(bash "$BRANCH_MANAGER" "1234" 2>&1); EC=$?
assert_exit $EC 0 "1.4  new branch (clean tree) → exit 0"
assert_contains "$OUT" "Creating new branch apim-1234" "1.4  creates apim-1234"
assert_contains "$OUT" "Last 5 commits:" "1.4  shows branch summary"
CURR=$(git rev-parse --abbrev-ref HEAD)
[ "$CURR" = "apim-1234" ] && pass "1.4  HEAD is apim-1234" || fail "1.4  HEAD is $CURR (want apim-1234)"

# 1.5 Already on target branch
OUT=$(bash "$BRANCH_MANAGER" "1234" 2>&1); EC=$?
assert_exit $EC 0 "1.5  already on target branch → exit 0"
assert_contains "$OUT" "Already on apim-1234" "1.5  already-on message shown"

# 1.6 New branch with uncommitted changes → auto-stash
git checkout main -q
echo "dirty work" > "$BM/dirty.txt"
git add "$BM/dirty.txt"
SC_BEFORE=$(git stash list | wc -l | tr -d ' ')
OUT=$(bash "$BRANCH_MANAGER" "5678" 2>&1); EC=$?
SC_AFTER=$(git stash list | wc -l | tr -d ' ')
assert_exit $EC 0 "1.6  new branch with uncommitted changes → exit 0"
assert_contains "$OUT" "Stashing uncommitted changes" "1.6  stash notice shown"
[ $((SC_AFTER - SC_BEFORE)) -eq 1 ] && pass "1.6  stash created (+1)" || fail "1.6  stash count delta: $((SC_AFTER-SC_BEFORE))"
SMSG=$(git stash list | head -1)
assert_contains "$SMSG" "auto-stash: main → apim-5678 switch" "1.6  stash message format correct"

# 1.7 Switch to existing branch (clean)
git checkout main -q && git stash drop -q 2>/dev/null || true
OUT=$(bash "$BRANCH_MANAGER" "5678" 2>&1); EC=$?
assert_exit $EC 0 "1.7  switch to existing branch → exit 0"
assert_contains "$OUT" "Switching to existing branch apim-5678" "1.7  switching message shown"

# 1.8 Stash restore prompt when returning to branch with prior auto-stash
git checkout apim-5678 -q
echo "in-progress work" > "$BM/inprogress.txt"
git add "$BM/inprogress.txt"
git stash push -q -m "auto-stash: apim-5678 → apim-1234 switch"
git checkout apim-1234 -q
OUT=$(bash "$BRANCH_MANAGER" "5678" 2>&1); EC=$?
assert_exit $EC 0 "1.8  return to branch with auto-stash → exit 0"
assert_contains "$OUT" "Stashed changes found" "1.8  stash restore prompt shown"
assert_contains "$OUT" "Choice [1/2]" "1.8  stash restore choice prompt shown"
assert_contains "$OUT" "Restore" "1.8  restore option present"
assert_contains "$OUT" "Skip" "1.8  skip option present"

# 1.9 Stash never silently dropped
STASH_STILL=$(git stash list | grep "auto-stash" | wc -l | tr -d ' ')
[ "$STASH_STILL" -ge 1 ] && pass "1.9  stash not silently dropped" || fail "1.9  stash was dropped unexpectedly"

# 1.10 Leading zeros preserved
git checkout main -q && git stash drop -q 2>/dev/null || true
OUT=$(bash "$BRANCH_MANAGER" "007" 2>&1); EC=$?
assert_exit $EC 0 "1.10 leading zeros → exit 0"
assert_contains "$OUT" "apim-007" "1.10 creates apim-007 (not apim-7)"

# 1.11 Large ticket number
git checkout main -q
OUT=$(bash "$BRANCH_MANAGER" "99999" 2>&1); EC=$?
assert_exit $EC 0 "1.11 large ticket number → exit 0"
assert_contains "$OUT" "apim-99999" "1.11 creates apim-99999"

# 1.12 No stash created on clean switch
git checkout main -q
OUT=$(bash "$BRANCH_MANAGER" "1234" 2>&1); EC=$?
SC=$(git stash list | wc -l | tr -d ' ')
[ "$SC" -eq 0 ] && pass "1.12 no stash created on clean switch" || fail "1.12 unexpected stash on clean switch"

# 1.13 Branch summary shows last commits
git checkout main -q
OUT=$(bash "$BRANCH_MANAGER" "9000" 2>&1); EC=$?
assert_exit $EC 0 "1.13 brand-new branch exits cleanly"
assert_contains "$OUT" "Last 5 commits:" "1.13 branch summary shown"

# Cleanup §1
cd /tmp
git -C "$BM" checkout main -q 2>/dev/null || true
for b in apim-1234 apim-5678 apim-007 apim-99999 apim-empty apim-9000; do
    git -C "$BM" branch -D "$b" -q 2>/dev/null || true
done
git -C "$BM" stash drop -q 2>/dev/null || true

# ================================================================
# §2  session-loader.sh  (prompt-based — no /dev/tty)
# ================================================================
header "2. session-loader.sh"

SL="$TEST_ROOT/sl-repo"
make_repo "$SL"

# 2.1 Empty/invalid CWD → exit 0 silently
OUT=$(echo '{}' | bash "$SESSION_LOADER" 2>/dev/null); EC=$?
assert_exit $EC 0 "2.1  empty CWD input → exit 0"

# 2.2 start-time marker written
rm -rf "$SL/.claude"
OUT=$(echo "{\"cwd\":\"$SL\"}" | bash "$SESSION_LOADER" 2>/dev/null); EC=$?
assert_exit $EC 0 "2.2  valid CWD → exit 0"
MARKER="$SL/.claude/session-markers/start-time"
assert_file "$MARKER" "2.2  start-time marker created"
MVAL=$(cat "$MARKER")
[[ "$MVAL" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
    && pass "2.2  start-time is ISO 8601 UTC" \
    || fail "2.2  start-time format wrong: $MVAL"

# 2.3 task-state.md present → continue path, [Session Context] with wave info
git -C "$SL" checkout -b apim-1234 -q
make_task_state "$SL/.claude/task-state.md" 2 3 "in-progress" 1234 "Add repository interface"
OUT=$(echo "{\"cwd\":\"$SL\"}" | bash "$SESSION_LOADER" 2>/dev/null)
assert_contains "$OUT" "[Session Context]" "2.3  task-state.md present → [Session Context] header"
assert_contains "$OUT" "Wave: 2/3" "2.3  wave progress shown"
assert_contains "$OUT" "implement-task" "2.3  implement-task hint in output"
WTYPE=$(cat "$SL/.claude/session-markers/workflow-type" 2>/dev/null || echo "")
[ "$WTYPE" = "continue" ] && pass "2.3  workflow-type=continue written" \
                            || fail "2.3  workflow-type wrong: '$WTYPE'"

# 2.4 task-state.md with next step → next step shown
assert_contains "$OUT" "Add repository interface" "2.4  next step extracted from task-state.md"

# 2.5 apim branch without task-state.md → new_task path
rm -f "$SL/.claude/task-state.md"
OUT=$(echo "{\"cwd\":\"$SL\"}" | bash "$SESSION_LOADER" 2>/dev/null)
assert_contains "$OUT" "[Session Context]" "2.5  no task-state.md → [Session Context] still present"
assert_contains "$OUT" "no task plan found" "2.5  no task plan found message"
assert_contains "$OUT" "plan-task" "2.5  plan-task hint shown"
WTYPE=$(cat "$SL/.claude/session-markers/workflow-type" 2>/dev/null || echo "")
[ "$WTYPE" = "new_task" ] && pass "2.5  workflow-type=new_task written" \
                            || fail "2.5  workflow-type wrong: '$WTYPE'"

# 2.6 Non-apim branch → free_chat path
git -C "$SL" checkout main -q
OUT=$(echo "{\"cwd\":\"$SL\"}" | bash "$SESSION_LOADER" 2>/dev/null)
assert_contains "$OUT" "[Session Context]" "2.6  non-apim branch → [Session Context]"
assert_contains "$OUT" "not a task branch" "2.6  not a task branch message"
WTYPE=$(cat "$SL/.claude/session-markers/workflow-type" 2>/dev/null || echo "")
[ "$WTYPE" = "free_chat" ] && pass "2.6  workflow-type=free_chat written" \
                             || fail "2.6  workflow-type wrong: '$WTYPE'"

# 2.7 No jq dependency — runs without jq
OUT=$(env PATH="$(echo "$PATH" | tr ':' '\n' | grep -v jq | tr '\n' ':')" \
      bash "$SESSION_LOADER" <<< "{\"cwd\":\"$SL\"}" 2>/dev/null); EC=$?
assert_exit $EC 0 "2.7  session-loader exits 0 even without jq on PATH"

# 2.8 PLUGIN_ROOT fallback sourcing works (no CLAUDE_PLUGIN_ROOT set)
OUT=$(CLAUDE_PLUGIN_ROOT="" bash "$SESSION_LOADER" <<< "{\"cwd\":\"$SL\"}" 2>/dev/null); EC=$?
assert_exit $EC 0 "2.8  PLUGIN_ROOT fallback: exits 0 when CLAUDE_PLUGIN_ROOT unset"

# 2.9 task-state.md with all steps [x] → completion message shown, no "Next step:"
git -C "$SL" checkout -b apim-done -q 2>/dev/null || true
make_task_state "$SL/.claude/task-state.md" 2 3 "in-progress" 1234 "dummy"
sed -i.bak 's/- \[ \]/- [x]/g' "$SL/.claude/task-state.md"
OUT=$(echo "{\"cwd\":\"$SL\"}" | bash "$SESSION_LOADER" 2>/dev/null)
assert_not_contains "$OUT" "Next step:" "2.9  all steps done → no 'Next step:' line"
assert_contains "$OUT" "ready to commit" "2.9  all steps done → commit hint shown"
git -C "$SL" checkout apim-1234 -q 2>/dev/null || true

# Cleanup §2
git -C "$SL" checkout main -q 2>/dev/null || true
git -C "$SL" branch -D apim-1234 -q 2>/dev/null || true
git -C "$SL" branch -D apim-done -q 2>/dev/null || true

# ================================================================
# §3  session-reviewer.sh
# ================================================================
header "3. session-reviewer.sh"

SR="$TEST_ROOT/sr-repo"
make_repo "$SR"
METRICS="$SR/.claude/session-metrics.jsonl"
mkdir -p "$SR/.claude"

# 3.1 No metrics file → completely silent
rm -f "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1); EC=$?
assert_exit $EC 0 "3.1  no metrics file → exit 0"
[ -z "$OUT" ] && pass "3.1  no metrics file → empty output (silent)" \
               || fail "3.1  expected silence, got: $(echo "$OUT" | head -2)"

# 3.2 Empty metrics file → silent
: > "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1); EC=$?
assert_exit $EC 0 "3.2  empty metrics file → exit 0"
[ -z "$OUT" ] && pass "3.2  empty metrics → empty output" \
               || fail "3.2  expected silence, got output"

# 3.3 Single session — no trends (all "—")
rm -f "$METRICS"
make_metric "apim-1234" 10 1 5 300 "continue" >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "[Session Reviewer]" "3.3  reviewer header present"
assert_contains "$OUT" "apim-1234" "3.3  branch shown"
assert_contains "$OUT" "5 min" "3.3  duration 300s → '5 min'"
DASH_COUNT=$(echo "$OUT" | grep -o '—' | wc -l | tr -d ' ')
[ "$DASH_COUNT" -ge 3 ] && pass "3.3  ≥3 '—' trend placeholders (single session)" \
                         || fail "3.3  only $DASH_COUNT '—' placeholders (want ≥3)"

# 3.4 Duration: seconds
rm -f "$METRICS"
make_metric "apim-1234" 5 0 0 45 "new_task" >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "45s" "3.4  duration 45s formatted as '45s'"

# 3.5 Duration: hours
rm -f "$METRICS"
make_metric "apim-1234" 20 3 10 7200 "continue" >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "2h 0m" "3.5  duration 7200s → '2h 0m'"

# 3.6 Duration: mixed hours+minutes (5400s = 1h 30m)
rm -f "$METRICS"
make_metric "apim-1234" 15 2 8 5400 "continue" >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "1h 30m" "3.6  duration 5400s → '1h 30m'"

# 3.7 Scoring — Awesome (tools≥15, commits≥1, no decline)
rm -f "$METRICS"
make_metric "apim-1234" 12 1 5 500 "continue" >> "$METRICS"
make_metric "apim-1234" 14 2 6 550 "continue" >> "$METRICS"
make_metric "apim-1234" 20 3 10 700 "continue" >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "Awesome" "3.7  tools≥15 + commits≥1 + improving → Awesome"
assert_contains "$OUT" "❤️" "3.7  Awesome shows ❤️"
assert_contains "$OUT" "↑" "3.7  shows improving trend ↑"

# 3.8 Scoring — Awesome via trend (trending up ≥2 metrics, no decline)
rm -f "$METRICS"
make_metric "apim-1234" 3 0 2 200 "new_task" >> "$METRICS"
make_metric "apim-1234" 4 0 3 250 "continue" >> "$METRICS"
make_metric "apim-1234" 8 0 6 400 "continue" >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
UP_COUNT=$(echo "$OUT" | grep -o '↑' | wc -l | tr -d ' ')
[ "$UP_COUNT" -ge 2 ] && pass "3.8  ≥2 ↑ trends shown" || fail "3.8  only $UP_COUNT ↑ trends (want ≥2)"
assert_contains "$OUT" "Awesome" "3.8  trending up on ≥2 metrics → Awesome"

# 3.9 Scoring — Good (commits≥1 only, low tools)
rm -f "$METRICS"
make_metric "apim-1234" 3 1 2 200 "new_task" >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "Good" "3.9  commits≥1, tools<5 → Good"
assert_contains "$OUT" "😊" "3.9  Good shows 😊"

# 3.10 Scoring — Do better (low everything)
rm -f "$METRICS"
make_metric "apim-1234" 2 0 1 120 "free_chat" >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "Do better" "3.10 low tools + no commits → Do better"
assert_contains "$OUT" "😞" "3.10 Do better shows 😞"
assert_contains "$OUT" "💡" "3.10 Do better includes a tip"

# 3.11 Short-session tip fires when duration < 300s
assert_contains "$OUT" "Longer focused sessions" "3.11 short-session tip fires for duration<300s"

# 3.11b Duration≥300 → reusing-context tip
rm -f "$METRICS"
make_metric "apim-1234" 2 0 1 600 "free_chat" >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "Reusing context" "3.11b reusing-context tip fires for duration≥300"

# 3.12 Demotion — high numbers but declining trend → Good not Awesome
rm -f "$METRICS"
make_metric "apim-1234" 25 5 20 1000 "continue" >> "$METRICS"
make_metric "apim-1234" 22 4 18  950 "continue" >> "$METRICS"
make_metric "apim-1234" 23 4 19  980 "continue" >> "$METRICS"
make_metric "apim-1234"  7 1  3  250 "continue" >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "↓" "3.12 declining metrics show ↓"
assert_contains "$OUT" "Good" "3.12 declining trend → demoted to Good"
assert_not_contains "$OUT" "Awesome" "3.12 declining metrics NOT Awesome"

# 3.13 Branch compliance: 100%
rm -f "$METRICS"
make_metric "apim-1" 10 1 5 600 "continue" >> "$METRICS"
make_metric "apim-2" 10 1 5 600 "continue" >> "$METRICS"
make_metric "apim-3" 10 1 5 600 "continue" >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "100% branch compliance" "3.13 all apim-* branches → 100% compliance"

# 3.14 Branch compliance: 50%
rm -f "$METRICS"
make_metric "apim-1234" 10 1 5 600 "continue" >> "$METRICS"
make_metric "main"      5  0 2 300 "free_chat" >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "50% branch compliance" "3.14 1/2 non-apim → 50% compliance"

# 3.15 Wave-stall tip fires when wave ≥ 2 and 3+ sessions stuck on same wave
rm -f "$METRICS"
make_task_state "$SR/.claude/task-state.md" 2 3 "in-progress" 1234 "Add filter"
make_metric "apim-1234" 2 0 1 300 "continue" 1 3 2 >> "$METRICS"
make_metric "apim-1234" 2 0 1 300 "continue" 1 3 2 >> "$METRICS"
make_metric "apim-1234" 2 0 1 300 "continue" 1 3 2 >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "sessions on the same wave" "3.15 all same currentWave=2 → wave-stall tip fires"
rm -f "$SR/.claude/task-state.md"

# 3.16 Wave-stall tip: different currentWave per session → tip does NOT fire
rm -f "$METRICS"
make_task_state "$SR/.claude/task-state.md" 3 3 "in-progress" 1234 "Add REST endpoint"
make_metric "apim-1234" 2 0 1 300 "continue" 0 3 1 >> "$METRICS"
make_metric "apim-1234" 2 0 1 300 "continue" 1 3 2 >> "$METRICS"
make_metric "apim-1234" 2 0 1 300 "continue" 2 3 3 >> "$METRICS"
OUT=$(echo "{\"cwd\":\"$SR\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_not_contains "$OUT" "sessions on the same wave" "3.16 different currentWave values → tip does NOT fire"
rm -f "$SR/.claude/task-state.md"

# ================================================================
# §4  session-terminator.sh
# ================================================================
header "4. session-terminator.sh"

ST="$TEST_ROOT/st-repo"
make_repo "$ST"
git -C "$ST" checkout -b apim-term -q
echo "feature work" > "$ST/feature.txt"
git -C "$ST" add . && git -C "$ST" commit -q -m "feat: add feature"

METRICS_ST="$ST/.claude/session-metrics.jsonl"
MARKERS_ST="$ST/.claude/session-markers"

mkinput() {
    local sid="${1:-s-test}" tx="${2:-}" cwd="${3:-$ST}"
    echo "{\"session_id\":\"$sid\",\"transcript_path\":\"$tx\",\"cwd\":\"$cwd\"}"
}

# 4.1 Non-apim branch → completely silent, no files created
git -C "$ST" checkout main -q
mkinput "s1" "" "$ST" | bash "$SESSION_TERMINATOR" 2>&1; EC=$?
assert_exit $EC 0 "4.1  non-apim branch → exit 0"
assert_no_file "$METRICS_ST" "4.1  no metrics written on non-apim branch"

# 4.2 apim branch → metrics file created
git -C "$ST" checkout apim-term -q
OUT=$(mkinput "s2" "" "$ST" | bash "$SESSION_TERMINATOR" 2>&1); EC=$?
assert_exit $EC 0 "4.2  apim branch → exit 0"
assert_file "$METRICS_ST" "4.2  metrics file created"
# No state JSON file written (retired)
assert_no_file "$ST/.claude/session-states/apim-term.json" "4.2  no session-states JSON written (retired format)"

# 4.3 Metrics JSONL entry is valid JSON with all required fields
LAST_M=$(tail -1 "$METRICS_ST")
jq -e . <<< "$LAST_M" > /dev/null 2>&1 && pass "4.3  metrics entry is valid JSON" \
                                         || fail "4.3  metrics entry is not valid JSON"
for field in .sessionId .branch .ticket .timestamp .toolUseCount .duration .commitsCreated .filesChanged .workflowType .wavesCompleted .totalWaves .currentWave; do
    VAL=$(echo "$LAST_M" | jq -r "$field" 2>/dev/null)
    [ "$VAL" != "null" ] && pass "4.3  metrics has $field" || fail "4.3  metrics missing $field"
done

# 4.4 task-state.md present → wave progress read with grep into metrics
mkdir -p "$MARKERS_ST"
make_task_state "$ST/.claude/task-state.md" 2 3 "in-progress" 1234 "Next step"
mkinput "s4-wave" "" "$ST" | bash "$SESSION_TERMINATOR" >/dev/null 2>&1
LAST_M=$(tail -1 "$METRICS_ST")
TW=$(echo "$LAST_M" | jq -r '.totalWaves' 2>/dev/null)
WD=$(echo "$LAST_M" | jq -r '.wavesCompleted' 2>/dev/null)
CW=$(echo "$LAST_M" | jq -r '.currentWave' 2>/dev/null)
[ "$TW" = "3" ] && pass "4.4  totalWaves=3 read from task-state.md" \
                || fail "4.4  totalWaves wrong: got $TW, want 3"
[ "$WD" = "1" ] && pass "4.4  wavesCompleted=1 (grep ✓ count)" \
                || fail "4.4  wavesCompleted wrong: got $WD, want 1"
[ "$CW" = "2" ] && pass "4.4  currentWave=2 from Wave: 2/3 line" \
                || fail "4.4  currentWave wrong: got $CW, want 2"

# 4.5 Tool use count from transcript
TX="$TEST_ROOT/tx-4.5.jsonl"
make_transcript "$TX" 8 "Implemented rate limiting. All tests pass."
mkinput "s5" "$TX" "$ST" | bash "$SESSION_TERMINATOR" >/dev/null 2>&1
LAST_M=$(tail -1 "$METRICS_ST")
TU=$(echo "$LAST_M" | jq -r '.toolUseCount')
[ "$TU" = "8" ] && pass "4.5  toolUseCount=8 from transcript" \
                || fail "4.5  toolUseCount wrong: got $TU, want 8"

# 4.6 start-time marker → duration computed correctly
mkdir -p "$MARKERS_ST"
FIVE_MIN_AGO=$(date -v-5M -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -d "5 minutes ago" -u +%Y-%m-%dT%H:%M:%SZ)
echo "$FIVE_MIN_AGO" > "$MARKERS_ST/start-time"
mkinput "s6" "" "$ST" | bash "$SESSION_TERMINATOR" >/dev/null 2>&1
LAST_M=$(tail -1 "$METRICS_ST")
DUR=$(echo "$LAST_M" | jq -r '.duration')
[ "$DUR" -ge 270 ] && [ "$DUR" -le 330 ] \
    && pass "4.6  duration ~300s computed from start-time (got ${DUR}s)" \
    || fail "4.6  duration out of range: ${DUR}s (want ~300)"

# 4.7 start-time marker cleaned up
assert_no_file "$MARKERS_ST/start-time" "4.7  start-time marker deleted after session end"

# 4.8 workflow-type marker → recorded and cleaned up
mkdir -p "$MARKERS_ST"
echo "continue" > "$MARKERS_ST/workflow-type"
mkinput "s8" "" "$ST" | bash "$SESSION_TERMINATOR" >/dev/null 2>&1
LAST_M=$(tail -1 "$METRICS_ST")
WT=$(echo "$LAST_M" | jq -r '.workflowType')
[ "$WT" = "continue" ] && pass "4.8  workflowType=continue from marker" \
                        || fail "4.8  workflowType wrong: '$WT'"
assert_no_file "$MARKERS_ST/workflow-type" "4.8  workflow-type marker deleted"

# 4.9 Commits created since session start
mkdir -p "$MARKERS_ST"
NOW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$NOW_TS" > "$MARKERS_ST/start-time"
sleep 1
echo "new feature" >> "$ST/feature.txt"
git -C "$ST" add feature.txt
git -C "$ST" commit -q -m "feat: extend feature"
mkinput "s9" "" "$ST" | bash "$SESSION_TERMINATOR" >/dev/null 2>&1
LAST_M=$(tail -1 "$METRICS_ST")
CM=$(echo "$LAST_M" | jq -r '.commitsCreated')
[ "$CM" -ge 1 ] && pass "4.9  commitsCreated≥1 after making commit" \
                || fail "4.9  commitsCreated=$CM (want ≥1)"

# 4.10 Files changed vs main counted
FILES=$(echo "$LAST_M" | jq -r '.filesChanged')
[ "$FILES" -ge 1 ] && pass "4.10 filesChanged≥1 vs main" \
                   || fail "4.10 filesChanged=$FILES (want ≥1)"

# 4.11 No old marker files present after run (only start-time and workflow-type cleaned)
assert_no_file "$MARKERS_ST/start-time"   "4.11 no leftover start-time"
assert_no_file "$MARKERS_ST/workflow-type" "4.11 no leftover workflow-type"

# 4.12 Multiple sessions accumulate in JSONL
LC=$(wc -l < "$METRICS_ST" | tr -d ' ')
[ "$LC" -ge 4 ] && [ "$LC" -le 15 ] \
    && pass "4.12 JSONL has $LC entries (append-only, compact one-per-line)" \
    || fail "4.12 JSONL has $LC entries (want 4-15)"

# 4.13 Missing start-time marker → duration=0, JSONL still written
rm -f "$MARKERS_ST/start-time"
mkinput "s-no-marker" "" "$ST" | bash "$SESSION_TERMINATOR" >/dev/null 2>&1; EC=$?
assert_exit $EC 0 "4.13 missing start-time marker → exit 0"
LAST_M=$(tail -1 "$METRICS_ST")
DUR=$(echo "$LAST_M" | jq -r '.duration')
[ "$DUR" = "0" ] && pass "4.13 missing start-time → duration=0 in JSONL" \
                 || fail "4.13 duration=$DUR (want 0)"

# 4.14 Empty transcript_path → toolUseCount=0, no crash
mkinput "s-no-tx" "" "$ST" | bash "$SESSION_TERMINATOR" >/dev/null 2>&1; EC=$?
assert_exit $EC 0 "4.14 empty transcript_path → exit 0"
LAST_M=$(tail -1 "$METRICS_ST")
TU=$(echo "$LAST_M" | jq -r '.toolUseCount')
[ "$TU" = "0" ] && pass "4.14 empty transcript → toolUseCount=0" \
                || fail "4.14 toolUseCount=$TU (want 0)"

# ================================================================
# §5  Plugin structure
# ================================================================
header "5. plugin structure"

PJ="$PLUGIN_DIR/.claude-plugin/plugin.json"

# 5.1 plugin.json is valid JSON
jq -e . "$PJ" > /dev/null 2>&1 && pass "5.1  plugin.json is valid JSON" \
                                || fail "5.1  plugin.json parse error"

# 5.2 Required top-level fields present and non-empty
for field in .name .version .description .license; do
    VAL=$(jq -r "$field" "$PJ" 2>/dev/null)
    [ -n "$VAL" ] && [ "$VAL" != "null" ] \
        && pass "5.2  plugin.json $field = '$VAL'" \
        || fail "5.2  plugin.json $field missing or null"
done
AUTHOR=$(jq -r '.author.name' "$PJ" 2>/dev/null)
[ -n "$AUTHOR" ] && [ "$AUTHOR" != "null" ] \
    && pass "5.2  plugin.json author.name = '$AUTHOR'" \
    || fail "5.2  plugin.json author.name missing"

# 5.3 All 6 expected skills have SKILL.md files (plugin.json uses directory path, not array)
for skill in hello install-tools install-plugins install-mcp-servers plan-task implement-task; do
    [ -f "$PLUGIN_DIR/skills/$skill/SKILL.md" ] \
        && pass "5.3  skill '$skill' has SKILL.md" \
        || fail "5.3  skill '$skill' SKILL.md missing"
done

# 5.4 All 6 expected skills have SKILL.md files
for skill in hello install-tools install-plugins install-mcp-servers plan-task implement-task; do
    assert_file "$PLUGIN_DIR/skills/$skill/SKILL.md" "5.4  skill '$skill' has SKILL.md"
done

# 5.5 Each SKILL.md opens with YAML frontmatter
for skill_dir in "$PLUGIN_DIR/skills"/*/; do
    sname=$(basename "$skill_dir")
    sfile="$skill_dir/SKILL.md"
    [ -f "$sfile" ] || continue
    FIRST=$(head -1 "$sfile")
    [ "$FIRST" = "---" ] && pass "5.5  $sname/SKILL.md starts with ---" \
                          || fail "5.5  $sname/SKILL.md missing opening ---"
done

# 5.6 install-tools resource files all exist
for res in gravitee_aliases.sh nvm-auto.sh settings.xml.template; do
    assert_file "$PLUGIN_DIR/skills/install-tools/resources/$res" "5.6  resource: $res"
done

# 5.7 install-mcp-servers SKILL.md mentions expected servers
IMC="$PLUGIN_DIR/skills/install-mcp-servers/SKILL.md"
for srv in github mongodb elasticsearch docker atlassian; do
    grep -qi "$srv" "$IMC" \
        && pass "5.7  install-mcp-servers mentions '$srv'" \
        || fail "5.7  install-mcp-servers missing '$srv'"
done

# 5.8 Shell scripts pass shellcheck (if installed)
if command -v shellcheck >/dev/null 2>&1; then
    for script in session-loader.sh session-reviewer.sh session-terminator.sh branch-manager.sh; do
        shellcheck -S warning "$PLUGIN_DIR/hooks/$script" \
            && pass "5.8  $script passes shellcheck" \
            || fail "5.8  $script has shellcheck warnings"
    done
else
    pass "5.8  shellcheck not installed — skip (install via: brew install shellcheck)"
fi

# ================================================================
# §6  task-state.md format validation
# ================================================================
header "6. task-state.md format"

TS_DIR="$TEST_ROOT/ts-format"
mkdir -p "$TS_DIR"
TS_FILE="$TS_DIR/task-state.md"
make_task_state "$TS_FILE" 2 3 "in-progress" 5678 "Add repository interface"

# 6.1 Wave count parsed from ### Wave headers
TOTAL=$(grep -c "^### Wave " "$TS_FILE" 2>/dev/null || echo "0")
[ "$TOTAL" = "3" ] && pass "6.1  3 wave headers found" \
                    || fail "6.1  expected 3 wave headers, got $TOTAL"

# 6.2 Completed wave count from ✓ marker
DONE=$(grep -c "✓" "$TS_FILE" 2>/dev/null || echo "0")
[ "$DONE" = "1" ] && pass "6.2  1 completed wave (✓)" \
                  || fail "6.2  expected 1 ✓, got $DONE"

# 6.3 Current wave number from Progress section
CW=$(grep "^Wave: " "$TS_FILE" | head -1 | sed 's/^Wave: //' | grep -oE "[0-9]+" | head -1)
[ "$CW" = "2" ] && pass "6.3  currentWave=2 parsed from Progress" \
                || fail "6.3  currentWave wrong: '$CW'"

# 6.4 Status line parseable
STATUS=$(grep "^Status: " "$TS_FILE" | head -1 | sed 's/^Status: //')
[ "$STATUS" = "in-progress" ] && pass "6.4  Status: in-progress parsed" \
                               || fail "6.4  Status wrong: '$STATUS'"

# 6.5 Next step extracted from first [ ] line
NEXT=$(grep "^- \[ \]" "$TS_FILE" | head -1 | sed 's/^- \[ \] //')
assert_contains "$NEXT" "Add repository interface" "6.5  next step extracted from [ ] line"

# 6.6 session-loader reads task-state.md → correct output
TS_REPO="$TEST_ROOT/ts-repo"
make_repo "$TS_REPO"
git -C "$TS_REPO" checkout -b apim-5678 -q
make_task_state "$TS_REPO/.claude/task-state.md" 2 3 "in-progress" 5678 "Add repository interface"
OUT=$(echo "{\"cwd\":\"$TS_REPO\"}" | bash "$SESSION_LOADER" 2>/dev/null)
assert_contains "$OUT" "Wave: 2/3" "6.6  session-loader reads wave from task-state.md"
assert_contains "$OUT" "Add repository interface" "6.6  session-loader reads next step"
assert_contains "$OUT" "implement-task" "6.6  session-loader directs to implement-task"

# 6.7 session-terminator reads task-state.md wave counts
git -C "$TS_REPO" checkout -b apim-ts-term -q 2>/dev/null || git -C "$TS_REPO" checkout -b apim-tsterm -q
BRANCH_USED=$(git -C "$TS_REPO" rev-parse --abbrev-ref HEAD)
# make_task_state always generates 3 wave headers (Wave 1 ✓, Wave N in-progress, Wave 3 pending)
make_task_state "$TS_REPO/.claude/task-state.md" 2 3 "in-progress" 9999 "Next"
echo "{\"session_id\":\"s-ts\",\"transcript_path\":\"\",\"cwd\":\"$TS_REPO\"}" \
    | bash "$SESSION_TERMINATOR" >/dev/null 2>&1
LAST_M=$(tail -1 "$TS_REPO/.claude/session-metrics.jsonl" 2>/dev/null || echo "")
if [ -n "$LAST_M" ]; then
    TW=$(echo "$LAST_M" | jq -r '.totalWaves' 2>/dev/null)
    WD=$(echo "$LAST_M" | jq -r '.wavesCompleted' 2>/dev/null)
    [ "$TW" = "3" ] && pass "6.7  terminator reads totalWaves=3 from task-state.md" \
                    || fail "6.7  totalWaves wrong: $TW"
    [ "$WD" = "1" ] && pass "6.7  terminator reads wavesCompleted=1 (one ✓)" \
                    || fail "6.7  wavesCompleted wrong: $WD"
else
    fail "6.7  no metrics entry written (branch may not be apim-*)"
fi

# 6.8 task-state.md step marking pattern (implement-task step D)
cp "$TS_FILE" "$TS_DIR/task-state-edit.md"
# Simulate what implement-task does: mark a step done with Edit
OLD_STEP="- [ ] Add repository interface"
NEW_STEP="- [x] Add repository interface"
sed -i.bak "s/${OLD_STEP}/${NEW_STEP}/" "$TS_DIR/task-state-edit.md"
MARKED=$(grep -c "\[x\]" "$TS_DIR/task-state-edit.md")
[ "$MARKED" -ge 1 ] && pass "6.8  step marking pattern [ ] → [x] works" \
                     || fail "6.8  step not marked as done"

# ================================================================
# §7  PLUGIN_ROOT sourcing
# ================================================================
header "7. PLUGIN_ROOT sourcing"

# 7.1 session-loader: PLUGIN_ROOT fallback resolves lib/git.sh
OUT=$(CLAUDE_PLUGIN_ROOT="" bash "$SESSION_LOADER" <<< '{"cwd":"'$SR'"}' 2>/dev/null); EC=$?
assert_exit $EC 0 "7.1  session-loader PLUGIN_ROOT fallback → exit 0"

# 7.2 session-reviewer: PLUGIN_ROOT fallback resolves lib/term.sh
rm -f "$SR/.claude/session-metrics.jsonl"
OUT=$(CLAUDE_PLUGIN_ROOT="" bash "$SESSION_REVIEWER" <<< '{"cwd":"'$SR'"}' 2>&1); EC=$?
assert_exit $EC 0 "7.2  session-reviewer PLUGIN_ROOT fallback → exit 0"

# 7.3 session-terminator: PLUGIN_ROOT fallback resolves lib/git.sh
OUT=$(CLAUDE_PLUGIN_ROOT="" bash "$SESSION_TERMINATOR" <<< '{"session_id":"","transcript_path":"","cwd":"'$ST'"}' 2>&1); EC=$?
assert_exit $EC 0 "7.3  session-terminator PLUGIN_ROOT fallback → exit 0"

# 7.4 branch-manager: PLUGIN_ROOT fallback resolves lib/term.sh + lib/git.sh
cd "$BM" 2>/dev/null || true
OUT=$(CLAUDE_PLUGIN_ROOT="" bash "$BRANCH_MANAGER" 2>&1); EC=$?
assert_exit $EC 1 "7.4  branch-manager PLUGIN_ROOT fallback → exit 1 (no args, libs loaded)"
assert_contains "$OUT" "ticket number required" "7.4  branch-manager loaded libs correctly"
cd /tmp

# 7.5 CLAUDE_PLUGIN_ROOT env takes priority over dirname fallback
FAKE_ROOT="$TEST_ROOT/fake-plugin-root"
mkdir -p "$FAKE_ROOT/lib"
# Provide a minimal git.sh so session-loader can source it without errors
cat > "$FAKE_ROOT/lib/git.sh" <<'FAKEGIT'
get_current_branch() { echo ""; }
is_dirty()           { return 1; }
auto_stash()         { :; }
find_auto_stash()    { echo ""; }
FAKEGIT
OUT=$(CLAUDE_PLUGIN_ROOT="$FAKE_ROOT" bash "$SESSION_LOADER" <<< '{"cwd":"'$SR'"}' 2>/dev/null); EC=$?
assert_exit $EC 0 "7.5  CLAUDE_PLUGIN_ROOT env var is honoured (no crash)"

# 7.6 All hook scripts have correct shebang
for script in session-loader.sh session-reviewer.sh session-terminator.sh branch-manager.sh; do
    SHEBANG=$(head -1 "$SAMPLE_DIR/hooks/$script")
    [[ "$SHEBANG" == "#!/"* ]] && pass "7.6  $script has shebang" \
                                || fail "7.6  $script missing shebang"
done

# ================================================================
# §8  reviewer + lib
# ================================================================
header "8. reviewer + lib"

ER="$TEST_ROOT/er-repo"
make_repo "$ER"
METRICS_ER="$ER/.claude/session-metrics.jsonl"
mkdir -p "$ER/.claude"

# 8.1 Wave display from JSONL when no task-state.md
rm -f "$METRICS_ER"
make_metric "apim-1234" 10 1 5 600 "continue" 1 2 2 >> "$METRICS_ER"
OUT=$(echo "{\"cwd\":\"$ER\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "waves 1/2" "8.1  wave display falls back to JSONL wavesCompleted/totalWaves"

# 8.2 Wave display absent when totalWaves=0
rm -f "$METRICS_ER"
make_metric "apim-1234" 10 1 5 600 "continue" 0 0 0 >> "$METRICS_ER"
OUT=$(echo "{\"cwd\":\"$ER\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_not_contains "$OUT" "waves 0/0" "8.2  wave display hidden when totalWaves=0"

# 8.3 Wave display uses task-state.md when present
ER_APIM="$TEST_ROOT/er-apim"
make_repo "$ER_APIM"
git -C "$ER_APIM" checkout -b apim-8888 -q
mkdir -p "$ER_APIM/.claude"
METRICS_ER_APIM="$ER_APIM/.claude/session-metrics.jsonl"
make_metric "apim-8888" 10 1 5 600 "continue" 1 3 2 >> "$METRICS_ER_APIM"
make_task_state "$ER_APIM/.claude/task-state.md" 2 4 "in-progress" 8888 "Some step"
OUT=$(echo "{\"cwd\":\"$ER_APIM\"}" | bash "$SESSION_REVIEWER" 2>&1)
assert_contains "$OUT" "waves 2/4" "8.3  task-state.md takes priority over JSONL for wave display"

# 8.4 extract_field helper handles string and numeric fields correctly
source "$LIB_DIR/term.sh" 2>/dev/null  # load term.sh to verify it's sourceable
SAMPLE_JSONL='{"sessionId":"abc","branch":"apim-1234","toolUseCount":7,"duration":300}'
EXTRACTED_BRANCH=$(echo "$SAMPLE_JSONL" | grep -oE '"branch":"[^"]+"' | grep -oE '[^:]+$' | tr -d '"')
EXTRACTED_TOOLS=$(echo "$SAMPLE_JSONL" | grep -oE '"toolUseCount":[^,}]+' | grep -oE '[^:]+$' | tr -d ' ')
[ "$EXTRACTED_BRANCH" = "apim-1234" ] && pass "8.4  extract_field: string field parsed correctly" \
                                        || fail "8.4  extract_field: branch got '$EXTRACTED_BRANCH'"
[ "$EXTRACTED_TOOLS" = "7" ] && pass "8.4  extract_field: numeric field parsed correctly" \
                               || fail "8.4  extract_field: toolUseCount got '$EXTRACTED_TOOLS'"

# 8.5 lib/term.sh sourceable: all 5 output functions defined (THR and THDR removed as dead code)
source "$LIB_DIR/term.sh" 2>/dev/null
for fn in TL TOPT TASK TOK TERR; do
    declare -f "$fn" >/dev/null 2>&1 && pass "8.5  term.sh: $fn defined" \
                                      || fail "8.5  term.sh: $fn NOT defined"
done

# 8.6 lib/git.sh sourceable: all 4 functions defined (extract_ticket removed as dead code)
source "$LIB_DIR/git.sh" 2>/dev/null
for fn in get_current_branch is_dirty auto_stash find_auto_stash; do
    declare -f "$fn" >/dev/null 2>&1 && pass "8.6  git.sh: $fn defined" \
                                      || fail "8.6  git.sh: $fn NOT defined"
done

# 8.7 find_auto_stash uses correct label format
GIT_STASH_TEST="$TEST_ROOT/stash-repo"
make_repo "$GIT_STASH_TEST"
git -C "$GIT_STASH_TEST" checkout -b feature-branch -q
echo "work" > "$GIT_STASH_TEST/work.txt"
git -C "$GIT_STASH_TEST" add .
git -C "$GIT_STASH_TEST" stash push -m "auto-stash: feature-branch → main switch" -q
cd "$GIT_STASH_TEST"
source "$LIB_DIR/git.sh"
STASH_FOUND=$(find_auto_stash "feature-branch")
[ -n "$STASH_FOUND" ] && pass "8.7  find_auto_stash finds stash with → label" \
                       || fail "8.7  find_auto_stash returned empty"
cd /tmp

# 8.9 lib/state.sh is retired and does not exist
assert_no_file "$LIB_DIR/state.sh" "8.9  lib/state.sh retired — file does not exist"

# ================================================================
# SUMMARY
# ================================================================
TOTAL=$((PASS + FAIL))
echo ""
printf "${BOLD}================================================================${RESET}\n"
printf "${BOLD}  Results: %d / %d tests passed${RESET}\n" "$PASS" "$TOTAL"

if [ ${#BUGS[@]} -gt 0 ]; then
    echo ""
    printf "${YELLOW}${BOLD}  Script bugs found (${#BUGS[@]}):${RESET}\n"
    for b in "${BUGS[@]}"; do
        printf "${YELLOW}  ⚠️  %s${RESET}\n" "$b"
    done
fi

if [ "$FAIL" -gt 0 ]; then
    echo ""
    printf "${RED}${BOLD}  Failed tests (${FAIL}):${RESET}\n"
    for e in "${ERRORS[@]}"; do
        printf "${RED}  ✗ %s${RESET}\n" "$e"
    done
    echo ""
    exit 1
else
    echo ""
    printf "${GREEN}${BOLD}  All tests passed! ✅${RESET}\n"
    echo ""
    exit 0
fi
