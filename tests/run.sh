#!/usr/bin/env bash
set -uo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
real_jq=$(command -v jq) || {
  printf 'jq is required to run the test suite\n' >&2
  exit 2
}
export BYC_REAL_JQ="$real_jq"
export PATH="$root/tests/fixtures/bin:$PATH"
command="$root/gh-before-you-contribute"
schema_python=${SCHEMA_PYTHON:-python3}
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
expected_ready=$'BEFORE-YOU-CONTRIBUTE  acme/project\n\nDISCLOSE  acme/project\n  source: acme/project/CONTRIBUTING.md\n  site:   https://example.test/project  (check /contributing by hand)\n  deciding phrases:\n    · AI tools are allowed, but contributors must disclose their use.\n\nFREE  acme/project#42  (open, author octocat, assigned to nobody)\n  Repair the flux capacitor\n  -> no open pull request, no visible claim\n\nREADY  acme/project'
if [[ $output == "$expected_ready" ]]; then
  pass "structured evidence preserves the exact text report"
else
  fail "structured evidence preserves the exact text report"
fi

json=$(GH_FIXTURE=ready "$command" acme/project 42 --json)
if jq -e '.repository == "acme/project" and .verdict == "READY" and .policy.verdict == "DISCLOSE" and .issue.verdict == "FREE"' >/dev/null <<<"$json"; then
  pass "json output is structured and valid"
else
  fail "json output is structured and valid"
fi
if jq -e '
  .schemaVersion == 1
  and (.policy.report | type == "string")
  and (.issue.report | type == "string")
  and (.policy.sources | type == "array" and length == 1)
  and (.policy.matches | type == "array" and length > 0)
  and (.issue.signals | type == "array")
  and all(.policy.matches[]; (.excerpt | length) <= 240)
  and all(.policy.sources[]; (has("content") or has("body")) | not)
' >/dev/null <<<"$json"; then
  pass "json v1 keeps legacy reports and adds bounded typed evidence"
else
  fail "json v1 keeps legacy reports and adds bounded typed evidence"
fi

attributed_json=$(GH_FIXTURE=attributed-policy "$command" acme/project --json)
if jq -e '
  .verdict == "READY"
  and .policy.verdict == "DISCLOSE"
  and any(.policy.matches[];
    .rule == "responsible_use"
    and .source.scope == "organization"
    and .source.repository == "acme/.github"
    and .source.path == "CONTRIBUTING.md")
  and any(.policy.matches[];
    .rule == "disclosure_required"
    and .source.scope == "repository"
    and .source.repository == "acme/project"
    and .source.path == "CONTRIBUTING.md")
' >/dev/null <<<"$attributed_json"; then
  pass "policy matches are attributed to the document that contains them"
else
  fail "policy matches are attributed to the document that contains them"
fi

constraint_json=$(GH_FIXTURE=constraint-policy "$command" acme/project --json)
if jq -e '
  .verdict == "READY"
  and .policy.verdict == "RESPONSIBLE-USE"
  and .policy.constraints == ["NO_AI_CREDIT"]
  and any(.policy.matches[]; .rule == "no_ai_credit" and .effect == "CONSTRAINT")
' >/dev/null <<<"$constraint_json"; then
  pass "policy constraints are separate from the stable verdict enum"
else
  fail "policy constraints are separate from the stable verdict enum"
fi

no_policy_json=$(GH_FIXTURE=no-policy "$command" acme/project --json)
if jq -e '
  .verdict == "REVIEW"
  and .policy.verdict == "NO-POLICY"
  and .policy.matches == []
  and (.policy.report | endswith("deciding phrases:"))
  and (.policy.report | contains("·") | not)
' >/dev/null <<<"$no_policy_json"; then
  pass "a document without an AI rule has no empty deciding phrase"
else
  fail "a document without an AI rule has no empty deciding phrase"
fi

unicode_json=$(LC_ALL=C GH_FIXTURE=unicode-evidence "$command" acme/project --json)
if jq -e '
  .schemaVersion == 1
  and .policy.verdict == "DISCLOSE"
  and any(.policy.matches[];
    .rule == "disclosure_required"
    and (.excerpt | contains("\"material\""))
    and (.excerpt | contains("revisión humana")))
' >/dev/null <<<"$unicode_json"; then
  pass "quoted Unicode evidence remains valid and attributable"
else
  fail "quoted Unicode evidence remains valid and attributable"
fi

unicode_boundary_json=$(LC_ALL=C GH_FIXTURE=unicode-boundary "$command" acme/project --json)
if jq -e '
  .policy.verdict == "DISCLOSE"
  and (.policy.report | contains("�") | not)
  and all(.policy.matches[]; (.excerpt | contains("�") | not))
  and any(.policy.matches[]; .excerpt | contains("éxAI tools"))
' >/dev/null <<<"$unicode_boundary_json"; then
  pass "multibyte context boundaries remain faithful in the C locale"
else
  fail "multibyte context boundaries remain faithful in the C locale"
fi

no_docs_json=$(GH_FIXTURE=no-docs "$command" acme/project --json)
if jq -e '.verdict == "REVIEW" and .policy.verdict == "NO-DOCS" and .issue == null' >/dev/null <<<"$no_docs_json"; then
  pass "missing policy documents produce a review result"
else
  fail "missing policy documents produce a review result"
fi
if jq -e '
  .policy.sources == []
  and .policy.matches == []
  and .policy.manualReview == [{"kind":"homepage","url":"https://example.test/project","reason":"not_fetched"}]
' >/dev/null <<<"$no_docs_json"; then
  pass "missing documents retain an explicit manual-review signal"
else
  fail "missing documents retain an explicit manual-review signal"
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
if jq -e '
  any(.issue.signals[];
    .kind == "linked_open_pull_request"
    and .strength == "decisive"
    and .source == "timeline_cross_reference"
    and .number == 43
    and .url == "https://github.com/acme/project/pull/43")
' >/dev/null <<<"$blocked_json"; then
  pass "linked pull requests are typed as decisive timeline evidence"
else
  fail "linked pull requests are typed as decisive timeline evidence"
fi

cross_repo_json=$(GH_FIXTURE=cross-repo-same-number "$command" acme/project 42 --json)
if jq -e '
  .verdict == "BLOCKED"
  and ([.issue.signals[] | select(.kind == "linked_open_pull_request")] | length) == 2
  and ([.issue.signals[] | select(.kind == "linked_open_pull_request") | .url] | unique | length) == 2
  and any(.issue.signals[]; .url == "https://github.com/acme/project/pull/43")
  and any(.issue.signals[]; .url == "https://github.com/fork/project/pull/43")
' >/dev/null <<<"$cross_repo_json"; then
  pass "cross-repository pull requests with the same number remain distinct"
else
  fail "cross-repository pull requests with the same number remain distinct"
fi

closed_json=$(GH_FIXTURE=closed "$command" acme/project 42 --json)
if jq -e '.verdict == "BLOCKED" and .issue.verdict == "TAKEN" and (.issue.report | contains("the issue is closed"))' >/dev/null <<<"$closed_json"; then
  pass "closed issues are unavailable"
else
  fail "closed issues are unavailable"
fi
if jq -e 'any(.issue.signals[]; .kind == "issue_closed" and .strength == "decisive")' >/dev/null <<<"$closed_json"; then
  pass "closed state is exposed as decisive evidence"
else
  fail "closed state is exposed as decisive evidence"
fi

assigned_json=$(GH_FIXTURE=assigned "$command" acme/project 42 --json)
if jq -e '.verdict == "BLOCKED" and .issue.verdict == "TAKEN" and (.issue.report | contains("assigned to maintainer"))' >/dev/null <<<"$assigned_json"; then
  pass "assigned issues are unavailable"
else
  fail "assigned issues are unavailable"
fi
if jq -e '
  .issue.assignee == "maintainer"
  and any(.issue.signals[]; .kind == "issue_assigned" and .actor == "maintainer" and .strength == "decisive")
' >/dev/null <<<"$assigned_json"; then
  pass "assignment is exposed without changing the legacy report"
else
  fail "assignment is exposed without changing the legacy report"
fi

mention_json=$(GH_FIXTURE=mention-only "$command" acme/project 42 --json)
if jq -e '.verdict == "REVIEW" and .issue.verdict == "REVIEW" and (.issue.report | contains("#99 someone"))' >/dev/null <<<"$mention_json"; then
  pass "ambiguous pull request mentions require review instead of blocking"
else
  fail "ambiguous pull request mentions require review instead of blocking"
fi
if jq -e '
  any(.issue.signals[];
    .kind == "unlinked_pull_request_mention"
    and .strength == "advisory"
    and .number == 99)
' >/dev/null <<<"$mention_json"; then
  pass "ambiguous pull request mentions are typed as advisory evidence"
else
  fail "ambiguous pull request mentions are typed as advisory evidence"
fi

author_pr_json=$(GH_FIXTURE=author-pr "$command" acme/project 42 --json)
if jq -e '
  .verdict == "READY"
  and .issue.verdict == "FREE"
  and any(.issue.signals[];
    .kind == "author_open_pull_request"
    and .strength == "context"
    and .number == 77)
' >/dev/null <<<"$author_pr_json"; then
  pass "an issue author's unrelated pull request remains contextual"
else
  fail "an issue author's unrelated pull request remains contextual"
fi

body_claim_json=$(GH_FIXTURE=body-claim "$command" acme/project 42 --json)
if jq -e '
  .verdict == "BLOCKED"
  and .issue.verdict == "TAKEN"
  and any(.issue.signals[];
    .kind == "work_claim"
    and .source == "issue_body"
    and .strength == "decisive"
    and .actor == "octocat"
    and (.excerpt | length) <= 180)
' >/dev/null <<<"$body_claim_json"; then
  pass "issue-body claims are attributed and excerpted"
else
  fail "issue-body claims are attributed and excerpted"
fi

comment_claim_json=$(GH_FIXTURE=comment-claim "$command" acme/project 42 --json)
if jq -e '
  .verdict == "BLOCKED"
  and .issue.verdict == "TAKEN"
  and any(.issue.signals[];
    .kind == "work_claim"
    and .source == "issue_comment"
    and .strength == "decisive"
    and .actor == "contributor"
    and .url == "https://github.com/acme/project/issues/42#issuecomment-1"
    and (.excerpt | length) <= 180)
' >/dev/null <<<"$comment_claim_json"; then
  pass "comment claims are attributed without storing the full comment"
else
  fail "comment claims are attributed without storing the full comment"
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
timeline_error_json=$(GH_FIXTURE=api-error "$command" acme/project 42 --json 2>/dev/null)
timeline_error_code=$?
if ((timeline_error_code == 2)) && jq -e '.error | contains("timeline")' >/dev/null <<<"$timeline_error_json"; then
  pass "timeline API failures retain valid json errors"
else
  fail "timeline API failures retain valid json errors"
fi

empty_timeline_json=$(GH_FIXTURE=empty-timeline-body "$command" acme/project 42 --json 2>/dev/null)
empty_timeline_code=$?
if ((empty_timeline_code == 2)) && jq -e '.error | contains("invalid timeline")' >/dev/null <<<"$empty_timeline_json"; then
  pass "an empty successful timeline response fails closed"
else
  fail "an empty successful timeline response fails closed"
fi

invalid_cross_reference_json=$(GH_FIXTURE=invalid-cross-reference "$command" acme/project 42 --json 2>/dev/null)
invalid_cross_reference_code=$?
if ((invalid_cross_reference_code == 2)) && jq -e '.error | contains("invalid pull request cross-reference")' >/dev/null <<<"$invalid_cross_reference_json"; then
  pass "a malformed pull request cross-reference cannot disappear"
else
  fail "a malformed pull request cross-reference cannot disappear"
fi

incomplete_search_json=$(GH_FIXTURE=incomplete-search "$command" acme/project 42 --json 2>/dev/null)
incomplete_search_code=$?
if ((incomplete_search_code == 2)) && jq -e '.error | contains("incomplete or invalid")' >/dev/null <<<"$incomplete_search_json"; then
  pass "incomplete search results cannot become a free issue"
else
  fail "incomplete search results cannot become a free issue"
fi

inconsistent_search_json=$(GH_FIXTURE=inconsistent-search "$command" acme/project 42 --json 2>/dev/null)
inconsistent_search_code=$?
if ((inconsistent_search_code == 2)) && jq -e '.error | contains("incomplete or invalid")' >/dev/null <<<"$inconsistent_search_json"; then
  pass "a positive search count with no items cannot become a free issue"
else
  fail "a positive search count with no items cannot become a free issue"
fi

empty_comments_json=$(GH_FIXTURE=empty-comments-body "$command" acme/project 42 --json 2>/dev/null)
empty_comments_code=$?
if ((empty_comments_code == 2)) && jq -e '.error | contains("invalid comments")' >/dev/null <<<"$empty_comments_json"; then
  pass "an empty successful comments response fails closed"
else
  fail "an empty successful comments response fails closed"
fi

if GH_FIXTURE=policy-api-error "$command" acme/project >/dev/null 2>&1; then
  fail "policy API failures stop the audit"
elif (($? == 2)); then
  pass "policy API failures stop the audit"
else
  fail "policy API failures use exit code 2"
fi
policy_error_json=$(GH_FIXTURE=policy-api-error "$command" acme/project --json 2>/dev/null)
policy_error_code=$?
if ((policy_error_code == 2)) && jq -e '.error | contains("HTTP 403")' >/dev/null <<<"$policy_error_json"; then
  pass "policy 403 failures retain valid json errors"
else
  fail "policy 403 failures retain valid json errors"
fi

if GH_FIXTURE=metadata-api-error "$command" acme/project >/dev/null 2>&1; then
  fail "metadata API failures stop the policy audit"
elif (($? == 2)); then
  pass "metadata API failures stop the policy audit"
else
  fail "metadata API failures use exit code 2"
fi
metadata_error_json=$(GH_FIXTURE=metadata-api-error "$command" acme/project --json 2>/dev/null)
metadata_error_code=$?
if ((metadata_error_code == 2)) && jq -e '.error | contains("HTTP 503")' >/dev/null <<<"$metadata_error_json"; then
  pass "metadata 5xx failures retain valid json errors"
else
  fail "metadata 5xx failures retain valid json errors"
fi

policy_emit_output=$(JQ_FIXTURE=fail-policy-emit GH_FIXTURE=ready \
  "$root/bin/ai-policy" acme/project --json 2>/dev/null)
policy_emit_code=$?
if ((policy_emit_code == 2)) && [[ -z $policy_emit_output ]]; then
  pass "a focused policy JSON emission failure exits 2"
else
  fail "a focused policy JSON emission failure exits 2"
fi

issue_emit_output=$(JQ_FIXTURE=fail-issue-emit GH_FIXTURE=closed \
  "$root/bin/issue-free" acme/project 42 --json 2>/dev/null)
issue_emit_code=$?
if ((issue_emit_code == 2)) && [[ -z $issue_emit_output ]]; then
  pass "a focused issue JSON emission failure exits 2"
else
  fail "a focused issue JSON emission failure exits 2"
fi

main_emit_output=$(JQ_FIXTURE=fail-main-emit GH_FIXTURE=ready \
  "$command" acme/project 42 --json 2>/dev/null)
main_emit_code=$?
if ((main_emit_code == 2)) && [[ -z $main_emit_output ]]; then
  pass "a combined JSON emission failure exits 2"
else
  fail "a combined JSON emission failure exits 2"
fi

if "$command" invalid-repository >/dev/null 2>&1; then
  fail "invalid repository syntax is rejected"
elif (($? == 2)); then
  pass "invalid repository syntax is rejected"
else
  fail "invalid input uses exit code 2"
fi

if jq -e '
  ."$schema" == "https://json-schema.org/draft/2020-12/schema"
  and .properties.schemaVersion.const == 1
  and (."$defs".policy.properties.matches.maxItems == 8)
  and (."$defs".policyMatch.properties.excerpt.maxLength == 240)
  and (."$defs".issueSignal.properties.excerpt.maxLength == 180)
' >/dev/null "$root/schema/audit-v1.schema.json"; then
  pass "the published schema fixes version and evidence bounds"
else
  fail "the published schema fixes version and evidence bounds"
fi

if ! "$schema_python" -c 'import jsonschema' >/dev/null 2>&1; then
  fail "the pinned jsonschema development dependency is installed"
else
  schema_validation_ok=true
  for schema_sample in \
    "$json" \
    "$attributed_json" \
    "$constraint_json" \
    "$no_policy_json" \
    "$unicode_json" \
    "$unicode_boundary_json" \
    "$no_docs_json" \
    "$blocked_json" \
    "$cross_repo_json" \
    "$closed_json" \
    "$assigned_json" \
    "$mention_json" \
    "$author_pr_json" \
    "$body_claim_json" \
    "$comment_claim_json"; do
    if ! printf '%s\n' "$schema_sample" \
      | "$schema_python" "$root/tests/validate-schema.py" "$root/schema/audit-v1.schema.json"; then
      schema_validation_ok=false
    fi
  done
  if [[ $schema_validation_ok == true ]]; then
    pass "all deterministic JSON variants validate against schema v1"
  else
    fail "all deterministic JSON variants validate against schema v1"
  fi

  invalid_format_json=$(jq '
    .policy.sources[0].url = "not a uri"
    | .issue.signals[0].createdAt = "yesterday"
  ' <<<"$blocked_json")
  if printf '%s\n' "$invalid_format_json" \
    | "$schema_python" "$root/tests/validate-schema.py" "$root/schema/audit-v1.schema.json" \
      >/dev/null 2>&1; then
    fail "schema validation rejects invalid URI and date-time formats"
  else
    pass "schema validation rejects invalid URI and date-time formats"
  fi
fi

if ((failures)); then
  printf '%s test(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'all tests passed\n'
