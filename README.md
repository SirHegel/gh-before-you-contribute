# gh-before-you-contribute

A read-only GitHub CLI extension and GitHub Action that checks the two questions worth
asking before you write a line of code for someone else's project:

1. **Does this project accept AI-assisted contributions, and on what terms?**
2. **Is anyone already working on this issue?**

Both checks are one command. They read evidence from GitHub instead of guessing, and they
exist because getting either one wrong wastes a maintainer's afternoon.

## Quick start

Install the extension:

```bash
gh extension install SirHegel/gh-before-you-contribute
```

Audit a repository, optionally including an issue:

```console
$ gh before-you-contribute pallets/click
BLOCKED  pallets/click

$ gh before-you-contribute pytest-dev/pytest 14819 --strict
BLOCKED  pytest-dev/pytest
```

The complete report includes the policy sources, deciding phrases, linked pull requests,
claims of active work, and the repository's final `READY`, `REVIEW`, or `BLOCKED` state.
Use JSON for automation:

```bash
gh before-you-contribute owner/repository 123 --json | jq .verdict
```

`--strict` exits with status 1 for a documented prohibition or a taken issue. Invalid
input, a missing dependency, or an API failure exits with status 2.

## Structured evidence

Successful JSON reports use the checked-in
[`schema/audit-v1.schema.json`](schema/audit-v1.schema.json) contract and include
`schemaVersion: 1`. The original `policy.report` and `issue.report` strings remain present
throughout the 1.x series, but automation no longer needs to parse them:

```bash
gh before-you-contribute owner/repository 123 --json \
  | jq '{verdict, policySources: .policy.sources, issueSignals: .issue.signals}'
```

Policy evidence is source-attributed:

- `policy.sources` identifies the organisation or repository document by path and URL.
- `policy.matches` identifies the typed rule, its effect, its source, and a deciding
  excerpt limited to 240 characters.
- `policy.constraints` keeps rules such as `NO_AI_CREDIT` separate from the stable policy
  verdict.
- `policy.manualReview` records a linked homepage that the read-only GitHub API audit did
  not fetch. For `NO-DOCS`, sources and matches are empty while this reason remains
  explicit.

Issue signals record why work is unavailable or needs review:

| Signal | Strength | Effect on the current verdict |
|---|---|---|
| closed issue, assignment, linked open PR, explicit work claim | `decisive` | `TAKEN` |
| unlinked PR text-search match | `advisory` | `REVIEW` |
| another open PR by the issue author | `context` | printed for review; not decisive |

Claim excerpts are limited to 180 characters. Structured output has no raw document,
issue-body, or comment-body fields; it emits only the bounded matching excerpts. A short
source can fit entirely inside that bound, so treat reports from private repositories as
sensitive. API failures still exit with status 2 and, in JSON mode, return an `error`
object instead of a partial audit.

## The underlying checks

The extension preserves two focused commands in `bin/` for users who want to run only
one check:

```console
$ ai-policy pallets/click
FORBIDDEN  pallets/click
  source: pallets/.github/CONTRIBUTING.md
  deciding phrases:
    · AI-generated PRs and issues are closed on sight, without review or discussion.
    · This applies regardless of code quality or correctness.

$ issue-free pytest-dev/pytest 14819
TAKEN  pytest-dev/pytest#14819  (open, author RonnyPfannschmidt, assigned to nobody)
  Assertion rewriting does not short-circuit chained comparisons
  pull requests GitHub has linked:
  #14822 RonnyPfannschmidt 2026-07-31 fix(rewrite): short-circuit chained comparisons
```

## `ai-policy` — where the rules actually live

Projects publish their position on AI-assisted contributions in four different places,
and the one people check is usually not the one that matters.

Pallets' prohibition is not in the Click repository. It is in `pallets/.github`, the
organisation-wide defaults repo, and on the project website. Reading
`pallets/click/CONTRIBUTING` and finding nothing tells you nothing.

So the script reads, in order:

1. `<org>/.github` — `CONTRIBUTING.md`, `AI_POLICY.md`, `profile/README.md`
2. the repository — `CONTRIBUTING*`, `AI_POLICY.md`, `AGENTS.md`, the pull request
   template, the code of conduct, `docs/contributing*`, `Documentation/HOWTO-CONTRIBUTING.md`
3. the site in the repository's `homepage` field, which it prints for you to open

and classifies:

| Verdict | Meaning |
|---|---|
| `FORBIDDEN` | Do not contribute. |
| `DISCLOSE` | Allowed if you declare the tool, in the form that project asks for. |
| `RESPONSIBLE-USE` | Allowed; you must understand and defend the change. |
| `NO-POLICY` | Nothing written down. Check the site by hand. |
| `[NO-AI-CREDIT]` | Extra flag: the work is accepted, the model is not credited. |

### The rules contradict each other, so read them one at a time

This is the part that surprises people. There is no common convention:

| Project | What it asks for |
|---|---|
| **pip** | `Assisted-by: <tool>` trailer, and **forbids** an LLM in `Co-authored-by` |
| **pytest** | The opposite — `Co-authored-by` is appreciated |
| **Linux kernel** | `Assisted-by: AGENT:MODEL`, and an AI may never sign `Signed-off-by` |
| **systemd**, **util-linux** | Work accepted, crediting the model forbidden |
| **scipy**, **numpy**, **django**, **deno**, **rust** | Disclosure in the pull request body |
| **astral-sh** (uv, ruff) | Code allowed, AI-written replies to maintainers are not |
| **Pallets** | Closed on sight |

Copying pytest's trailer into a pip pull request is a policy violation in both directions.

### A note on the matcher

The verdict comes from unambiguous phrases only. An earlier version used
`(are|is) (not )?(banned|forbidden)`, and the optional `not` made Rust's
*"LLM contributions are **not banned**"* read as a prohibition. Negation inverts meaning;
a matcher that treats it as noise will confidently tell you the opposite of the truth.

## `issue-free` — "no assignee, no comments" is not free

An issue can have no assignee, no comments, and a finished pull request sitting on it.
A maintainer who files an issue and fixes it does not assign it to themselves and does not
comment on it. `pytest-dev/pytest#14819` is exactly that: filed by a core maintainer, open,
unassigned, silent, with their own fix three weeks old.

The reliable signal is the issue timeline's `cross-referenced` events, which is where the
linked pull requests are. A closed issue or an issue assigned to someone is unavailable
without needing further inference. For an open, unassigned issue, the script checks:

1. **Timeline cross-references** — pull requests GitHub has already linked
2. **Text search** — open pull requests mentioning the number
3. **The issue author's open pull requests** — people fix what they report
4. **A claim in prose** — the body or comments saying *"I have a patch"*, *"I'm working on
   this"*, *"I'll open a PR"*

Point 4 matters more than it looks. `python-jsonschema/jsonschema#1536` has no pull
request at all; its author wrote *"I have a working patch and tests, but I would rather
check the approach is welcome before sending it."* By every structural signal it is free.
It is not.

For a closed or assigned issue, a linked open pull request, or an explicit claim, `TAKEN`
is decisive. A text-search hit without a timeline link produces `REVIEW`, because a pull
request can mention the same number as an example, a dependency issue, or a rejected
alternative. In `scipy/scipy#25955` the candidate pull request was by the same author but
touched a different file for a different bug — the issue really was open. The script
prints weaker candidates instead of deciding for you. If a required API request fails,
the audit exits with status 2 rather than turning missing evidence into `FREE`.

## GitHub Action

The same audit can stop automated work before a contributor or agent duplicates an open
pull request:

```yaml
permissions:
  contents: read
  issues: read
  pull-requests: read

steps:
  - uses: SirHegel/gh-before-you-contribute@v1
    with:
      repository: pytest-dev/pytest
      issue: '14819'
      format: text
      strict: 'true'
```

The Action uses `github.token` and performs read-only API requests. It never writes a
comment, modifies an issue, submits a pull request, or sends telemetry.

## Requirements and development

The extension requires an authenticated [`gh`](https://cli.github.com/) command and
`jq`. It makes no network calls beyond the GitHub API.

To work on it locally:

```bash
git clone https://github.com/SirHegel/gh-before-you-contribute
cd gh-before-you-contribute
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
SCHEMA_PYTHON=.venv/bin/python tests/run.sh
shellcheck gh-before-you-contribute bin/* tests/run.sh tests/fixtures/bin/*
```

The tests replace `gh` with deterministic fixtures, so they neither consume API quota nor
depend on changing third-party repositories. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
evidence and safety rules.

## Support and security

Open a [GitHub issue](https://github.com/SirHegel/gh-before-you-contribute/issues) for
reproducible bugs and feature requests. Private support is available at
[alvarezruizj289@gmail.com](mailto:alvarezruizj289@gmail.com); see [SUPPORT.md](SUPPORT.md).
Report vulnerabilities through GitHub private vulnerability reporting as described in
[SECURITY.md](SECURITY.md).

## Licence

MIT.
