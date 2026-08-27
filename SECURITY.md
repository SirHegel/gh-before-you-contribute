# Security policy

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could expose credentials or private
repository data. Report it privately through GitHub's **Report a vulnerability** link in
the repository Security tab. If private reporting is unavailable, email
[alvarezruizj289@gmail.com](mailto:alvarezruizj289@gmail.com) with a minimal reproduction.

You can expect an acknowledgement within seven days. Please do not include real access
tokens or confidential repository content in a report.

## Data handling

The extension is read-only. It calls the GitHub API through the authenticated `gh` CLI,
prints the evidence used for its decision, and does not persist API responses or tokens.
