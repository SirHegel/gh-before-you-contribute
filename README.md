# before-you-contribute

Two shell scripts that answer the two questions worth asking before you write a line of
code for someone else's project:

1. **Does this project accept AI-assisted contributions, and on what terms?**
2. **Is anyone already working on this issue?**

Both are one command, both read GitHub rather than guessing, and both exist because
getting either one wrong wastes a maintainer's afternoon.

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
linked pull requests are. The script checks:

1. **Timeline cross-references** — pull requests GitHub has already linked
2. **Text search** — open pull requests mentioning the number
3. **The issue author's open pull requests** — people fix what they report
4. **A claim in prose** — the body or comments saying *"I have a patch"*, *"I'm working on
   this"*, *"I'll open a PR"*

Point 4 matters more than it looks. `python-jsonschema/jsonschema#1536` has no pull
request at all; its author wrote *"I have a working patch and tests, but I would rather
check the approach is welcome before sending it."* By every structural signal it is free.
It is not.

`TAKEN` is a prompt to look, not a verdict. In `scipy/scipy#25955` the linked pull request
was by the same author but touched a different file for a different bug — the issue really
was open. The script prints the candidates instead of deciding for you.

## Install

```bash
git clone https://github.com/SirHegel/before-you-contribute
export PATH="$PWD/before-you-contribute/bin:$PATH"
```

Requires [`gh`](https://cli.github.com/) authenticated, plus `jq`. No other dependencies,
no network calls beyond the GitHub API.

## Licence

MIT.
