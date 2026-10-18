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
# Only CI is restored. The owner-deleted live Homebrew and release workflows
# are intentionally outside this build/test change.
printf '1 workflow action-runtime check passed (5 references)\n'
