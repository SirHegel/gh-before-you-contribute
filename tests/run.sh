#!/usr/bin/env bash
set -uo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="$root/tests/fixtures/bin:$PATH"
command="$root/gh-before-you-contribute"
failures=0

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_contains() {
  local name=$1
  local haystack=$2
  local needle=$3
  if [[ $haystack == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (missing '$needle')"
  fi
}

output=$(GH_FIXTURE=ready "$command" acme/project 42)
assert_contains "ready audit includes policy" "$output" "DISCLOSE"
assert_contains "ready audit includes issue state" "$output" "FREE  acme/project#42"
assert_contains "ready audit has combined verdict" "$output" "READY  acme/project"

json=$(GH_FIXTURE=ready "$command" acme/project 42 --json)
if jq -e '.repository == "acme/project" and .verdict == "READY" and .policy.verdict == "DISCLOSE" and .issue.verdict == "FREE"' >/dev/null <<<"$json"; then
  pass "json output is structured and valid"
else
  fail "json output is structured and valid"
fi

if GH_FIXTURE=blocked "$command" acme/project 42 --strict >/dev/null 2>&1; then
  fail "strict mode rejects a blocker"
elif (($? == 1)); then
  pass "strict mode rejects a blocker"
else
  fail "strict mode uses exit code 1 for a blocker"
fi

blocked_json=$(GH_FIXTURE=blocked "$command" acme/project 42 --json)
if jq -e '.verdict == "BLOCKED" and .policy.verdict == "FORBIDDEN" and .issue.verdict == "TAKEN"' >/dev/null <<<"$blocked_json"; then
  pass "blocked signals are preserved in json"
else
  fail "blocked signals are preserved in json"
fi

if "$command" invalid-repository >/dev/null 2>&1; then
  fail "invalid repository syntax is rejected"
elif (($? == 2)); then
  pass "invalid repository syntax is rejected"
else
  fail "invalid input uses exit code 2"
fi

if ((failures)); then
  printf '%s test(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'all tests passed\n'
