#!/usr/bin/env bash
# setup.sh — Creates ~/gravitee-plugin-test/ synthetic repo for E2E recording.
# Idempotent: safe to run multiple times (removes and recreates the test repo).
# Does NOT start asciinema — start it manually per README.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
TEST_REPO="$HOME/gravitee-plugin-test"
SRC_DIR="$TEST_REPO/src/main/java/io/gravitee/test/calculator"
TEST_DIR="$TEST_REPO/src/test/java/io/gravitee/test/calculator"

OK()   { printf '\033[32m  ok  %s\033[0m\n' "$*"; }
INFO() { printf '      %s\n' "$*"; }
STEP() { printf '\n\033[1m[%s]\033[0m %s\n' "$1" "$2"; }
ERR()  { printf '\033[31m  err %s\033[0m\n' "$*"; }

# ── Pre-flight ─────────────────────────────────────────────────────────────────
STEP "0" "Pre-flight checks"

for tool in git java mvn python3; do
    if command -v "$tool" >/dev/null 2>&1; then
        OK "$tool found: $(command -v "$tool")"
    else
        ERR "$tool not found — required"
        exit 1
    fi
done

if command -v asciinema >/dev/null 2>&1; then
    OK "asciinema found: $(command -v asciinema)"
else
    INFO "asciinema not found (needed for recording, not for dry-run)"
    INFO "Install later with: brew install asciinema"
fi

# ── Clean existing test repo ───────────────────────────────────────────────────
STEP "1" "Creating synthetic test repo at $TEST_REPO"

if [ -d "$TEST_REPO" ]; then
    INFO "Removing existing test repo..."
    rm -rf "$TEST_REPO"
fi

mkdir -p "$SRC_DIR" "$TEST_DIR"
OK "Directory structure created"

# ── Copy fixture files ─────────────────────────────────────────────────────────
STEP "2" "Copying fixture files"

cp "$FIXTURES_DIR/pom.xml"             "$TEST_REPO/pom.xml"
cp "$FIXTURES_DIR/Calculator.java"     "$SRC_DIR/Calculator.java"
cp "$FIXTURES_DIR/CalculatorTest.java" "$TEST_DIR/CalculatorTest.java"
OK "pom.xml, Calculator.java, CalculatorTest.java copied"

# ── Verify Maven build ─────────────────────────────────────────────────────────
STEP "3" "Verifying Maven build (existing tests must pass before recording)"

cd "$TEST_REPO"
if mvn test -pl . -Dtest=CalculatorTest -q 2>&1; then
    OK "Existing tests pass (add + multiply)"
else
    ERR "Maven test failed — fix before recording"
    exit 1
fi

# ── Git init ───────────────────────────────────────────────────────────────────
STEP "4" "Initialising git repo on main branch"

git init -b main
git config user.email "e2e-test@gravitee.io"
git config user.name "E2E Test"
git add pom.xml src/
git commit -m "chore: initial calculator project"
OK "Initial commit on main"

# ── .claude/ scaffold ──────────────────────────────────────────────────────────
STEP "5" "Creating .claude/ scaffold"

mkdir -p .claude/session-markers
# Ensure no metrics file — session-reviewer must be silent on first session
rm -f .claude/session-metrics.jsonl
OK ".claude/ ready — no session-metrics.jsonl (reviewer will be silent on first open)"

# ── Create apim-100 branch ─────────────────────────────────────────────────────
STEP "6" "Creating apim-100 branch"

git checkout -b apim-100
OK "On branch apim-100"

# ── Recording output dir ───────────────────────────────────────────────────────
STEP "7" "Ensuring recordings/ directory exists"

mkdir -p "$SCRIPT_DIR/recordings"
OK "test-e2e/recordings/ ready"

# ── Summary ────────────────────────────────────────────────────────────────────
printf '\n\033[1mSetup complete — all checks passed.\033[0m\n\n'
INFO "Synthetic repo : $TEST_REPO"
INFO "Branch         : apim-100"
INFO "Missing method : Calculator.subtract — the APIM-100 task target"
INFO ""
INFO "Next step — start the asciinema recording, then follow README.md:"
INFO ""
INFO "  asciinema rec test-e2e/recordings/plugin-e2e-\$(date +%Y%m%d).cast \\"
INFO "    --title 'gravitee-dev-workflow E2E' --cols 220 --rows 50"
INFO ""
