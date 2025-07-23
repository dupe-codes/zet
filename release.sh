#!/usr/bin/env bash
# release.sh ─ build zet.love  and install system-wide for the user

set -euo pipefail

# ───────────────────────── project paths ─────────────────────────
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
LOVE_FILE="$BUILD_DIR/zet.love"

# XDG-compatible user install locations
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
SHARE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zet"
INSTALLED_LOVE="$SHARE_DIR/zet.love"
LAUNCHER="$BIN_DIR/zet"

# ───────────────────────── build the .love ───────────────────────
echo "• Rebuilding $LOVE_FILE"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$PROJECT_ROOT"
zip -9r "$LOVE_FILE" . \
    -x "build/*" ".git/*" "*.DS_Store" "*.swp" "*.swo"
cd - >/dev/null

# ───────────────────────── install to user dirs ─────────────────
echo "• Installing to $SHARE_DIR and $BIN_DIR"
mkdir -p "$SHARE_DIR" "$BIN_DIR"
cp "$LOVE_FILE" "$INSTALLED_LOVE"

cat >"$LAUNCHER" <<SH
#!/usr/bin/env bash
exec love "$INSTALLED_LOVE" "\$@"
SH
chmod +x "$LAUNCHER"

# ───────────────────────── summary ──────────────────────────────
echo "✓ Build complete:"
echo "  - Local build:    $LOVE_FILE"
echo "  - Installed love: $INSTALLED_LOVE"
echo "  - Launcher:       $LAUNCHER"
echo
echo "Run with:  zet"
