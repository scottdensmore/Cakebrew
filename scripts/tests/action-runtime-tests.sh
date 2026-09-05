#!/bin/bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
workflow_dir="$script_dir/../../.github/workflows"

# These majors were checked against their upstream action.yml: all use node24.
# Compare the complete inventory so a missing workflow or empty scan cannot pass.
check_actions() {
  local workflow=$1
  shift
  local actual
  actual=$(sed -En 's/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]+([^[:space:]#]+).*$/\2/p' "$workflow_dir/$workflow")
  if ! diff -u <(printf '%s\n' "$@") <(printf '%s\n' "$actual"); then
    printf 'FAIL: %s must use the verified Node.js 24 action versions\n' "$workflow" >&2
    return 1
  fi
  printf 'PASS: %s (%s action references)\n' "$workflow" "$#"
}

check_actions ci.yml \
  actions/checkout@v5 \
  actions/upload-artifact@v6 \
  actions/checkout@v5 \
  actions/upload-artifact@v6 \
  actions/upload-artifact@v6
check_actions brew-compat.yml \
  actions/checkout@v5 \
  actions/upload-artifact@v6
check_actions release.yml \
  actions/checkout@v5 \
  actions/upload-artifact@v6 \
  softprops/action-gh-release@v3

printf '3 workflow action-runtime checks passed (10 references)\n'
