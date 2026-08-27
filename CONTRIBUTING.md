# Contributing

Thank you for improving `gh-before-you-contribute`.

1. Open or reference an issue that describes the user-facing problem.
2. Keep API access read-only and make every classification explainable from printed
   evidence.
3. Add a deterministic fixture for every new policy or issue-availability rule.
4. Run `tests/run.sh` and `shellcheck gh-before-you-contribute bin/* tests/run.sh
   tests/fixtures/bin/gh` before opening a pull request.

Never add telemetry, transmit tokens, or automate comments and contributions to other
repositories. A false `FREE` result wastes maintainers' time, so ambiguous signals should
be shown for human review rather than silently discarded.

## AI-assisted contributions

AI-assisted work is allowed, but the pull request author must disclose material use in
the pull request body, understand every changed line, verify all cited evidence, and run
the tests personally. Fabricated results, generated activity intended only to earn
profile credit, and automated replies to maintainers are not acceptable.
