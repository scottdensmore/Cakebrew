# Security Policy

## Supported versions

Only the latest release is supported. Fixes land on `main` and ship in the next
release.

## Reporting a vulnerability

**Please do not open a public issue.**

Report privately through GitHub's
[private vulnerability reporting](https://github.com/scottdensmore/Cakebrew/security/advisories/new)
for this repository. If that is unavailable to you, contact the maintainer
directly through their GitHub profile.

Please include what you can: affected version, the steps to reproduce, and what
an attacker gains. A proof of concept helps but is not required to report.

You should get an acknowledgement within a week. Fixes are released as quickly
as the severity warrants, and you will be credited unless you ask otherwise.

## What is in scope

Cakebrew runs `brew` on the user's behalf and ships a privileged XPC helper, so
the areas most worth attention are:

* **Command construction.** Arguments reach the shell as positional parameters
  (`brew "$@"`) precisely so they are never re-parsed; anything that
  reintroduces interpolation is a vulnerability.
* **The privileged helper.** Its XPC connection pins the client's code-signing
  requirement in both directions. A way to talk to the helper from an unsigned
  or differently-signed process is in scope.
* **Parsing brew's output**, which is untrusted input from the user's taps.

## What is not

* Cakebrew is deliberately **not** App-Sandboxed — a sandboxed process cannot
  execute `brew` at all, and the exceptions that would allow it redirect the
  user's home directory, breaking `brew services` in ways that fail silently.
  AGENTS.md records the measurements behind that decision. Reports arguing that
  the app should be sandboxed are a design discussion, not a vulnerability.
* Anything requiring the attacker to already have code execution as the user.
