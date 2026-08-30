# Contributing

**[AGENTS.md](AGENTS.md) is the single source of truth** for how work happens
here — the workflow, the conventions, and the decisions already made. It is
written for human contributors and coding agents alike.

This file deliberately does not restate any of it. Two documents describing one
workflow drift apart, and then neither can be trusted.

## Start here

1. Read [AGENTS.md](AGENTS.md) once, end to end. It is not long, and most of it
   is things that cost someone a wasted afternoon to learn.
2. Branch off `main`, take one thin slice, write the failing test first.
3. Open a PR with `gh`. Green CI is the merge gate.

## The commands you will need every time

```sh
# App build, both configurations — both must be warning-free
xcodebuild build -workspace Cakebrew.xcworkspace -scheme Cakebrew \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

xcodebuild build -workspace Cakebrew.xcworkspace -scheme Cakebrew \
  -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# Unit tests — seconds, run them every time
xcodebuild test -workspace Cakebrew.xcworkspace -scheme CakebrewTests \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

# UI tests — a pre-PR step, not an inner-loop one (~8 minutes)
xcodebuild test -scheme CakebrewUITests -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

If you touch `CakebrewUITests.m`, compile that target — neither test command
above does, so a syntax error there passes locally and fails on CI:

```sh
xcodebuild build-for-testing -scheme CakebrewUITests -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

## Reporting bugs

Please use the issue templates. The environment questions are not boilerplate:
the macOS version, the Homebrew version and prefix, and whether the problem
reproduces under `-BPMockBrew` are what separate a parser bug from an
environment one.

Security issues go through [SECURITY.md](SECURITY.md), not a public issue.
