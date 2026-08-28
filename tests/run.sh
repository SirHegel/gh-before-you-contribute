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

no_docs_json=$(GH_FIXTURE=no-docs "$command" acme/project --json)
if jq -e '.verdict == "REVIEW" and .policy.verdict == "NO-DOCS" and .issue == null' >/dev/null <<<"$no_docs_json"; then
  pass "missing policy documents produce a review result"
else
  fail "missing policy documents produce a review result"
fi

if no_docs_report=$(GH_FIXTURE=no-docs "$root/bin/ai-policy" acme/project); then
  assert_contains "focused policy audit accepts genuine missing documents" "$no_docs_report" "NO-DOCS  acme/project"
else
  fail "focused policy audit accepts genuine missing documents"
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

closed_json=$(GH_FIXTURE=closed "$command" acme/project 42 --json)
if jq -e '.verdict == "BLOCKED" and .issue.verdict == "TAKEN" and (.issue.report | contains("the issue is closed"))' >/dev/null <<<"$closed_json"; then
  pass "closed issues are unavailable"
else
  fail "closed issues are unavailable"
fi

assigned_json=$(GH_FIXTURE=assigned "$command" acme/project 42 --json)
if jq -e '.verdict == "BLOCKED" and .issue.verdict == "TAKEN" and (.issue.report | contains("assigned to maintainer"))' >/dev/null <<<"$assigned_json"; then
  pass "assigned issues are unavailable"
else
  fail "assigned issues are unavailable"
fi

mention_json=$(GH_FIXTURE=mention-only "$command" acme/project 42 --json)
if jq -e '.verdict == "REVIEW" and .issue.verdict == "REVIEW" and (.issue.report | contains("#99 someone"))' >/dev/null <<<"$mention_json"; then
  pass "ambiguous pull request mentions require review instead of blocking"
else
  fail "ambiguous pull request mentions require review instead of blocking"
fi

if GH_FIXTURE=mention-only "$command" acme/project 42 --strict >/dev/null 2>&1; then
  pass "strict mode does not reject an ambiguous mention"
else
  fail "strict mode does not reject an ambiguous mention"
fi

if GH_FIXTURE=api-error "$command" acme/project 42 >/dev/null 2>&1; then
  fail "timeline API failures stop the audit"
elif (($? == 2)); then
  pass "timeline API failures stop the audit"
else
  fail "timeline API failures use exit code 2"
fi

if GH_FIXTURE=policy-api-error "$command" acme/project >/dev/null 2>&1; then
  fail "policy API failures stop the audit"
elif (($? == 2)); then
  pass "policy API failures stop the audit"
else
  fail "policy API failures use exit code 2"
fi

if GH_FIXTURE=metadata-api-error "$command" acme/project >/dev/null 2>&1; then
  fail "metadata API failures stop the policy audit"
elif (($? == 2)); then
  pass "metadata API failures stop the policy audit"
else
  fail "metadata API failures use exit code 2"
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
