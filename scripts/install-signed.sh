#!/bin/sh
#
# Builds Cakebrew signed with your team identity and installs it to
# /Applications, which is where SMAppService expects to find an app that
# registers a background helper.
#
# Day-to-day development does NOT need this: a normal Xcode build (Cmd-R) is
# signed with your Apple Development certificate, which already satisfies the
# helper's designated requirement. Use this when you want to exercise helper
# registration and Login Items approval for real.
#
# Usage:  scripts/install-signed.sh [Debug|Release]
#
set -eu

CONFIG="${1:-Release}"
TEAM="27ZDER873F"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

cd "$(dirname "$0")/.."

echo "==> Building Cakebrew ($CONFIG), signed for team $TEAM"
xcodebuild build \
  -workspace Cakebrew.xcworkspace \
  -scheme Cakebrew \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM" \
  | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)|note: .*helper" || true

APP="$BUILD_DIR/Build/Products/$CONFIG/Cakebrew.app"
[ -d "$APP" ] || { echo "error: build produced no app at $APP" >&2; exit 1; }

echo "==> Verifying signatures"
codesign --verify --strict "$APP"
REQ="identifier \"com.scottdensmore.Cakebrew.Helper\" and anchor apple generic and certificate leaf[subject.OU] = \"$TEAM\""
codesign --verify -R="$REQ" "$APP/Contents/MacOS/CakebrewHelper" \
  || { echo "error: embedded helper would be rejected by the app" >&2; exit 1; }
echo "    app + helper signatures OK"

# A stale copy keeps its old registration; remove it so SMAppService sees this build.
if [ -d /Applications/Cakebrew.app ]; then
  echo "==> Replacing existing /Applications/Cakebrew.app"
  osascript -e 'tell application "Cakebrew" to quit' >/dev/null 2>&1 || true
  sleep 1
  rm -rf /Applications/Cakebrew.app
fi

echo "==> Installing to /Applications"
/usr/bin/ditto "$APP" /Applications/Cakebrew.app

echo
echo "Installed. Next:"
echo "  1. open -a Cakebrew"
echo "  2. Cakebrew > Settings (Cmd-,) and look at 'Homebrew access'"
echo "  3. Unsandboxed builds report 'Not required' - that is expected today."
echo "     Once the sandbox is enabled, use Install Helper, then approve it"
echo "     in System Settings > General > Login Items."
