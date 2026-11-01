#!/usr/bin/env bash
# setup.sh — создаёт .xcodeproj из project.yml
# Запускать из корня репозитория: ./setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "▸ Checking for XcodeGen..."

if ! command -v xcodegen &>/dev/null; then
    if command -v brew &>/dev/null; then
        echo "▸ Installing XcodeGen via Homebrew..."
        brew install xcodegen
    elif command -v mint &>/dev/null; then
        echo "▸ Installing XcodeGen via Mint..."
        mint install yonaskolb/XcodeGen
    else
        echo "✗ XcodeGen not found. Install it:"
        echo "  brew install xcodegen"
        echo "  OR: mint install yonaskolb/XcodeGen"
        exit 1
    fi
fi

echo "▸ Generating Xcode project..."
xcodegen generate

echo "✓ Done! Open phoneApp.xcodeproj in Xcode."
echo ""
echo "Next steps:"
echo "  1. Open phoneApp.xcodeproj"
echo "  2. Select your Apple ID in Signing & Capabilities for both targets"
echo "  3. Run on your iPhone (⌘R)"
