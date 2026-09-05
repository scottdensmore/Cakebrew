#!/bin/bash
# Stream a build/test/analyzer command and fail on warnings from either stream.
set -uo pipefail
# Inspect both pipeline statuses ourselves, even when invoked with bash -e.
set +e

if [[ $# -lt 2 ]]; then
  printf 'Usage: bash %s LOG COMMAND [ARG ...]\n' "$0" >&2
  exit 2
fi
log=$1
shift

"$@" 2>&1 | tee "$log"
statuses=("${PIPESTATUS[@]}")
if [[ ${statuses[0]} -ne 0 ]]; then
  exit "${statuses[0]}"
fi
if [[ ${statuses[1]} -ne 0 ]]; then
  exit "${statuses[1]}"
fi

# Xcode's analyzer exits zero with findings. Match the diagnostic, not its
# checker suffix: real output uses [deadcode.*] and [optin.*], not just clang-analyzer.
grep -Ei '(^|[[:space:]])warning:' "$log"
result=$?
case "$result" in
  0) printf '::error::Command emitted warnings; see %s\n' "$log" >&2; exit 1 ;;
  1) exit 0 ;;
  *) printf '::error::Could not inspect warning log %s\n' "$log" >&2; exit "$result" ;;
esac
