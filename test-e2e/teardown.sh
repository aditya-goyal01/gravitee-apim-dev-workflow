#!/usr/bin/env bash
# teardown.sh — Remove all E2E test artifacts.
# Safe to run after the recording is saved (recordings/ dir is preserved).
set -euo pipefail

TEST_REPO="$HOME/gravitee-plugin-test"

printf '[teardown] Removing %s\n' "$TEST_REPO"
if [ -d "$TEST_REPO" ]; then
    rm -rf "$TEST_REPO"
    printf '  removed.\n'
else
    printf '  already gone.\n'
fi

printf '[teardown] Done. Recordings preserved in test-e2e/recordings/\n'
