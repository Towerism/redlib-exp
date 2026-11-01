#!/usr/bin/env bash
# Replicates the Ralph feedback-baseline experiment from a fresh clone.
# Requires: GNU make, omc (oh-my-claude-sisyphus) 5.7.19 on PATH.
# Uses a throwaway Ralph session under .omc/state/sessions/ and removes it on exit.
set -uo pipefail
cd "$(dirname "$0")/.."

S="replicate-$(date +%s)-$$"
SESSION_DIR=".omc/state/sessions/$S"
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
cleanup() { rm -f experiment/BREAK_LOUD experiment/BREAK_SILENT; rm -rf "$SESSION_DIR"; }
trap cleanup EXIT
cleanup

command -v make >/dev/null || { echo "FAIL: make not found"; exit 1; }
command -v omc >/dev/null || { echo "FAIL: omc not found (npm i -g oh-my-claude-sisyphus@5.7.19)"; exit 1; }
echo "omc $(omc --version), $(make --version | head -1), session $S"

# 1. The Makefile targets fail. GNU make exits 2 when a recipe fails.
make build >/dev/null 2>&1; rc=$?
[[ $rc == 2 ]] && pass "make build exits 2" || fail "make build exited $rc, expected 2"
make test >/dev/null 2>&1; rc=$?
[[ $rc == 2 ]] && pass "make test exits 2" || fail "make test exited $rc, expected 2"

# 2. Record the baseline using the experiment PRD (session-scoped, so it wins over any other PRD).
mkdir -p "$SESSION_DIR"
cp -f experiment/prd.json "$SESSION_DIR/prd.json"
out=$(omc ralph verify --write-baseline --session "$S" 2>&1); rc=$?
echo "$out"
baseline=$(sed -n 's/^ralph verify: baseline recorded at //p' <<<"$out")
[[ $rc == 0 && -f "$baseline" ]] && pass "baseline recorded (exit 0)" || fail "write-baseline exited $rc"
grep -q 'make: \*\*\* \[Makefile:[0-9]*: build\] Error 1' "${baseline:-/dev/null}" \
  && grep -q 'make: \*\*\* \[Makefile:[0-9]*: test\] Error 1' "${baseline:-/dev/null}" \
  && pass "baseline lists the make build and make test failures" \
  || fail "baseline is missing the make failures"

judge() { omc ralph verify --session "$S" 2>&1; }

# 3. Nothing changed: only baseline failures, so the gate passes.
out=$(judge); rc=$?; echo "$out"
[[ $rc == 0 ]] && pass "unchanged tree: gate exits 0" || fail "unchanged tree: gate exited $rc, expected 0"

# 4. A passing command starts failing with an error line: the gate catches it.
touch experiment/BREAK_LOUD
out=$(judge); rc=$?; echo "$out"
[[ $rc == 1 ]] && pass "new failure with output: gate exits 1" || fail "new failure with output: gate exited $rc, expected 1"
rm -f experiment/BREAK_LOUD

# 5. A passing command starts failing with no output: the gate does NOT catch it.
#    omc 5.7.19 diffs output lines only and ignores exit codes other than 126/127.
touch experiment/BREAK_SILENT
out=$(judge); rc=$?; echo "$out"
[[ $rc == 0 ]] && pass "known gap reproduced: silent new failure, gate still exits 0" \
  || fail "silent new failure: gate exited $rc (gap may be fixed in this omc version)"
rm -f experiment/BREAK_SILENT

echo
(( fails == 0 )) && { echo "ALL CHECKS PASSED"; exit 0; } || { echo "$fails CHECK(S) FAILED"; exit 1; }
