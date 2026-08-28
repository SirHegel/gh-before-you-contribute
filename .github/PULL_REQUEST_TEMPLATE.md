## Problem and evidence

Related issue:

Describe the contributor or maintainer problem, then link the public policy, issue timeline,
pull request, or API behavior that proves it.

## Change

Explain the new decision path and why its output remains understandable to a person running
the command.

## Validation

- [ ] Added or updated deterministic fixtures for every new signal and edge case.
- [ ] Ran `tests/run.sh`.
- [ ] Ran `shellcheck gh-before-you-contribute bin/* tests/run.sh tests/fixtures/bin/gh`.
- [ ] Confirmed that API failures and ambiguous evidence fail closed instead of returning `FREE`.
- [ ] Confirmed that the change is read-only and adds no comments, claims, pull requests, or telemetry.

## AI-assisted work

Mark exactly one option:

- [ ] No material AI assistance was used.
- [ ] Material AI assistance was used and is disclosed below; I verified every cited source,
      understand every changed line, and personally ran the checks above.

Disclosure, if applicable:
