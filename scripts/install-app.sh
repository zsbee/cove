#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
SOURCE_APP="$ROOT_DIR/.build/Cove.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
OPEN_APP="${OPEN_APP:-1}"

if [[ "$INSTALL_DIR" != /* ]]; then
    echo "INSTALL_DIR must be an absolute path." >&2
    exit 1
fi
if [[ "$OPEN_APP" != 0 && "$OPEN_APP" != 1 ]]; then
    echo "OPEN_APP must be 0 or 1." >&2
    exit 1
fi
if [[ ! -d "$SOURCE_APP" ]]; then
    echo "Built app not found. Run make install from the project directory." >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd -P)"
DESTINATION="$INSTALL_DIR/Cove.app"

case "$DESTINATION" in
    "$SOURCE_APP"|"$SOURCE_APP"/*)
        echo "Install somewhere other than the build bundle (for example ~/Applications)." >&2
        exit 1
        ;;
esac

if [[ -e "$DESTINATION" || -L "$DESTINATION" ]]; then
    if [[ -L "$DESTINATION" || ! -d "$DESTINATION" ]] ||
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist" 2>/dev/null || true)" != com.cove.app ]]; then
        echo "Refusing to replace an unrelated file, directory, or symlink: $DESTINATION" >&2
        exit 1
    fi
fi

while IFS= read -r executable; do
    if [[ "$executable" == "$DESTINATION/Contents/MacOS/Cove" ]] ||
        [[ "$OPEN_APP" == 1 && "$executable" == */Contents/MacOS/Cove ]]; then
        echo "Quit Cove before installing or updating, then run make install again." >&2
        exit 1
    fi
done < <(ps -ax -o comm=)

# Stage on the destination filesystem so a failed copy cannot damage the installed app.
STAGING="$(mktemp -d "$INSTALL_DIR/.cove-install.XXXXXX")"
cleanup() {
    local status=$?
    if [[ -d "$STAGING/Previous.app" && ! -e "$DESTINATION" ]]; then
        mv "$STAGING/Previous.app" "$DESTINATION" || {
            echo "Previous app preserved at $STAGING/Previous.app; restore it manually." >&2
            exit 1
        }
    fi
    rm -rf "$STAGING"
    exit "$status"
}
trap cleanup EXIT

ditto "$SOURCE_APP" "$STAGING/New.app"
codesign --verify --deep --strict "$STAGING/New.app"
if [[ -d "$DESTINATION" ]]; then
    mv "$DESTINATION" "$STAGING/Previous.app"
fi
mv "$STAGING/New.app" "$DESTINATION"

echo "Installed: $DESTINATION"
echo "Existing connections, query history, preferences, and Keychain entries have been preserved."
if [[ "$OPEN_APP" == 1 ]]; then
    open "$DESTINATION"
else
    echo "Launch with: open \"$DESTINATION\""
fi
