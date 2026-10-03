#!/usr/bin/env bash
# Runs Fragment's unit test suite via lune (https://lune-org.github.io/docs),
# a standalone Luau runtime. Downloads a pinned lune release into tests/.bin
# if it isn't already on PATH, so this works with zero setup.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

LUNE_VERSION="0.10.5"
BIN_DIR=".bin"
LUNE_BIN="$BIN_DIR/lune"

if command -v lune >/dev/null 2>&1; then
    LUNE_BIN="$(command -v lune)"
elif [ ! -x "$LUNE_BIN" ]; then
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64)   ASSET="lune-$LUNE_VERSION-linux-x86_64.zip" ;;
        Linux-aarch64)  ASSET="lune-$LUNE_VERSION-linux-aarch64.zip" ;;
        Darwin-x86_64)  ASSET="lune-$LUNE_VERSION-macos-x86_64.zip" ;;
        Darwin-arm64)   ASSET="lune-$LUNE_VERSION-macos-aarch64.zip" ;;
        *) echo "No prebuilt lune binary for $(uname -s)-$(uname -m); install lune manually: https://github.com/lune-org/lune" >&2; exit 1 ;;
    esac

    mkdir -p "$BIN_DIR"
    echo "Downloading lune $LUNE_VERSION..."
    curl -sL -o "$BIN_DIR/lune.zip" "https://github.com/lune-org/lune/releases/download/v$LUNE_VERSION/$ASSET"
    unzip -o -q "$BIN_DIR/lune.zip" -d "$BIN_DIR"
    rm "$BIN_DIR/lune.zip"
    chmod +x "$LUNE_BIN"
fi

status=0
for spec in *.spec.luau; do
    echo "--- $spec ---"
    "$LUNE_BIN" run "$spec" || status=1
done

exit $status
