#!/bin/bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
runner="$script_dir/../check-warnings.sh"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/cakebrew-warning-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
checks=0

expect_status() {
  local expected=$1
  local label=$2
  shift 2
  local actual=0
  "$@" > "$test_dir/output" 2>&1 || actual=$?
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s (expected %s, got %s)\n' "$label" "$expected" "$actual"
    cat "$test_dir/output"
    exit 1
  fi
  checks=$((checks + 1))
  printf 'PASS: %s\n' "$label"
}

expect_status 0 'clean command and argument boundaries' bash "$runner" "$test_dir/build.log" printf '%s\n' 'a path with spaces' '** BUILD SUCCEEDED **'
grep -Fx 'a path with spaces' "$test_dir/build.log"

while IFS= read -r diagnostic; do
  expect_status 1 "$diagnostic" bash "$runner" "$test_dir/build.log" printf '%s\n' "$diagnostic"
done < "$script_dir/fixtures/warnings.txt"

expect_status 1 'stderr warnings are gated' bash "$runner" "$test_dir/build.log" bash -c 'printf "warning: stderr diagnostic\n" >&2'
grep -Fx 'warning: stderr diagnostic' "$test_dir/build.log"
expect_status 0 'old warning logs are replaced' bash "$runner" "$test_dir/build.log" printf '%s\n' '** ANALYZE SUCCEEDED **'
expect_status 0 'clean stderr is captured' bash "$runner" "$test_dir/build.log" bash -c 'printf "tool progress\n" >&2'
grep -Fx 'tool progress' "$test_dir/build.log"
expect_status 37 'command failure is preserved' bash "$runner" "$test_dir/build.log" bash -c 'exit 37'
expect_status 37 'command failure wins over a warning' bash "$runner" "$test_dir/build.log" bash -c 'printf "warning: failed command\n"; exit 37'
expect_status 1 'tee cannot write the log' bash "$runner" "$test_dir" printf '%s\n' 'build output'
expect_status 37 'command failure wins over tee under errexit' bash -e "$runner" "$test_dir" bash -c 'printf "build output\n"; exit 37'
rm "$test_dir/build.log"
expect_status 2 'missing log cannot pass inspection' bash "$runner" "$test_dir/build.log" bash -c '
  for attempt in {1..100}; do
    if [[ -f "$1" ]]; then rm "$1"; exit 0; fi
    sleep 0.01
  done
  exit 3
' bash "$test_dir/build.log"
expect_status 2 'missing command is rejected' bash "$runner" "$test_dir/build.log"

# Exercise the actual CI destination arguments without launching Xcode or
# changing the host: Apple Silicon offers both native and translated targets.
check_ci_destinations() (
  architecture=$1
  uname() { [[ $# -eq 1 && "$1" == '-m' ]] && printf '%s\n' "$architecture"; }
  options=$(sed -n 's/^[[:space:]]*\(-destination .* \)\\$/\1/p' "$script_dir/../../.github/workflows/ci.yml")
  count=0
  while IFS= read -r option; do
    eval "set -- $option"
    if [[ $# -ne 2 || "$1" != '-destination' || "$2" != "platform=macOS,arch=$architecture" ]]; then
      printf 'Expected native %s destination, got: %s\n' "$architecture" "$*"
      exit 1
    fi
    count=$((count + 1))
  done <<< "$options"
  [[ $count -eq 5 ]]
)
expect_status 0 'all five CI destinations select native arm64' check_ci_destinations arm64
expect_status 0 'all five CI destinations select native x86_64' check_ci_destinations x86_64
printf '%s warning-gate checks passed\n' "$checks"
