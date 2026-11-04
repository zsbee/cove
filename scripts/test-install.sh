#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
export INSTALL_DIR="$TEST_ROOT/Applications With Spaces"
export OPEN_APP=0

bash "$ROOT_DIR/scripts/install-app.sh"
APP="$INSTALL_DIR/Cove.app"
test -f "$APP/Contents/MacOS/Cove"
test -f "$APP/Contents/Resources/AppIcon.icns"
test -f "$APP/Contents/Frameworks/libduckdb.dylib"
test -f "$APP/Contents/Resources/OracleJDBC/CoveOracleBridge.class"
cmp "$ROOT_DIR/.build/Cove.app/Contents/MacOS/Cove" "$APP/Contents/MacOS/Cove"
codesign --verify --deep --strict "$APP"

# Upgrades replace the bundle rather than merging stale files, and leave siblings alone.
touch "$APP/stale-file" "$INSTALL_DIR/keep-me"
bash "$ROOT_DIR/scripts/install-app.sh"
test ! -e "$APP/stale-file"
test -f "$INSTALL_DIR/keep-me"
test "$(find "$INSTALL_DIR" -name '.cove-install.*' | wc -l | tr -d ' ')" = 0

expect_failure() {
    if "$@" >"$TEST_ROOT/rejection.log" 2>&1; then
        echo "Expected installer to refuse an unsafe destination or option." >&2
        exit 1
    fi
}

expect_failure env INSTALL_DIR=relative OPEN_APP=0 bash "$ROOT_DIR/scripts/install-app.sh"
expect_failure env OPEN_APP=invalid bash "$ROOT_DIR/scripts/install-app.sh"
expect_failure env INSTALL_DIR="$ROOT_DIR/.build" bash "$ROOT_DIR/scripts/install-app.sh"
ln -s "$ROOT_DIR/.build" "$TEST_ROOT/Build Alias"
expect_failure env INSTALL_DIR="$TEST_ROOT/Build Alias" bash "$ROOT_DIR/scripts/install-app.sh"

export INSTALL_DIR="$TEST_ROOT/File"
mkdir -p "$INSTALL_DIR"
echo "keep-me" >"$INSTALL_DIR/Cove.app"
expect_failure bash "$ROOT_DIR/scripts/install-app.sh"
test "$(cat "$INSTALL_DIR/Cove.app")" = keep-me

export INSTALL_DIR="$TEST_ROOT/Unrelated"
mkdir -p "$INSTALL_DIR/Cove.app"
touch "$INSTALL_DIR/Cove.app/keep-me"
expect_failure bash "$ROOT_DIR/scripts/install-app.sh"
test -f "$INSTALL_DIR/Cove.app/keep-me"

export INSTALL_DIR="$TEST_ROOT/Symlink"
mkdir -p "$INSTALL_DIR"
ln -s "$APP" "$INSTALL_DIR/Cove.app"
expect_failure bash "$ROOT_DIR/scripts/install-app.sh"
test -L "$INSTALL_DIR/Cove.app"
test -f "$APP/Contents/MacOS/Cove"

echo "Installer tests passed (fresh install, upgrade, paths with spaces, and safe refusals)."
