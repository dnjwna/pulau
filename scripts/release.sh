#!/usr/bin/env bash
#
# Build Pulau (Release, ad-hoc signed), zip it, and publish a GitHub release.
#
# Usage:   scripts/release.sh <version> [--draft]
# Example: scripts/release.sh 0.1.0
#
# Needs: Xcode 26+, GitHub CLI (`brew install gh` + `gh auth login`),
# a clean working tree that is already pushed to origin.
#
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: scripts/release.sh <version> [--draft]" >&2
  exit 64
fi
DRAFT_FLAG=""
[[ "${2:-}" == "--draft" ]] && DRAFT_FLAG="--draft"

TAG="v$VERSION"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/release"
APP_NAME="Pulau"
ZIP="$BUILD/$APP_NAME-$VERSION.zip"

cd "$ROOT"

fail() { echo "error: $*" >&2; exit 1; }

command -v xcodebuild >/dev/null || fail "xcodebuild not found (install Xcode)"
command -v gh >/dev/null || fail "GitHub CLI not found: brew install gh && gh auth login"
gh auth status >/dev/null 2>&1 || fail "not logged in to GitHub CLI: gh auth login"

[[ -z "$(git status --porcelain)" ]] || fail "working tree has uncommitted changes"
git fetch -q origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse '@{u}')" ]] || fail "local branch differs from origin; push (or pull) first"
if gh release view "$TAG" >/dev/null 2>&1; then
  fail "release $TAG already exists"
fi

echo "==> Building $APP_NAME $VERSION (Release, ad-hoc signed)…"
rm -rf "$BUILD"
mkdir -p "$BUILD"
if ! xcodebuild \
  -project boringNotch.xcodeproj \
  -scheme boringNotch \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD/DerivedData" \
  MARKETING_VERSION="$VERSION" \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" \
  -quiet \
  build; then
  fail "build failed (if the scheme is missing: open the project in Xcode once, then retry)"
fi

BUILT_APP="$(find "$BUILD/DerivedData/Build/Products/Release" -maxdepth 1 -name '*.app' | head -n 1)"
[[ -n "$BUILT_APP" ]] || fail "no .app found in build products"

echo "==> Packaging…"
ditto "$BUILT_APP" "$BUILD/$APP_NAME.app"
codesign --verify --deep --strict "$BUILD/$APP_NAME.app" || fail "code signature check failed"
ditto -c -k --sequesterRsrc --keepParent "$BUILD/$APP_NAME.app" "$ZIP"
SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
ARCHS="$(lipo -archs "$BUILD/$APP_NAME.app/Contents/MacOS/"* 2>/dev/null | head -n 1 || true)"

NOTES="$BUILD/notes.md"
sed -e "s/{{VERSION}}/$VERSION/g" -e "s/{{SHA256}}/$SHA256/g" -e "s/{{ARCHS}}/${ARCHS:-unknown}/g" \
  "$ROOT/scripts/release-notes.md" > "$NOTES"

echo "==> Publishing $TAG…"
gh release create "$TAG" "$ZIP" \
  --title "$APP_NAME $VERSION (beta)" \
  --notes-file "$NOTES" \
  --target "$(git rev-parse HEAD)" \
  --prerelease $DRAFT_FLAG

echo
echo "Done: $(gh release view "$TAG" --json url -q .url)"
echo "SHA-256: $SHA256"
