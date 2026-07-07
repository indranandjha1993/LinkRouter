#!/bin/bash
# Publish a LinkRouter release end to end:
#   test → bump version → build → ad-hoc sign → zip → push → GitHub release
#   → update the Homebrew tap cask (version + sha256).
#
# Usage:
#   scripts/release.sh <version> [release notes]
#   scripts/release.sh 1.0.5 "Fix: picker no longer eats Tuesdays"
#
# Prerequisites:
#   - Feature changes already committed (the tree must be clean)
#   - gh CLI authenticated for the repo owner account
#   - The Homebrew tap checked out at $TAP_DIR
#
# The full bundle MUST be ad-hoc signed (codesign --deep): Xcode's default
# linker-only signature fails Gatekeeper's bundle validation.
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version> [notes]}"
NOTES="${2:-LinkRouter $VERSION}"
GH_USER="indranandjha1993"
REPO="LinkRouter"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAP_DIR="${TAP_DIR:-$HOME/Developer/personal/homebrew-tap}"

cd "$REPO_DIR"

[[ -z "$(git status --porcelain)" ]] || {
    echo "error: working tree is dirty — commit or stash first" >&2
    exit 1
}

echo "==> Unit tests"
swift test

echo "==> Bump version to $VERSION"
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" \
    LinkRouter.xcodeproj/project.pbxproj

echo "==> Build Release"
xcodebuild -project LinkRouter.xcodeproj -scheme LinkRouter \
    -configuration Release SYMROOT="$PWD/build" -quiet build

echo "==> Sign (ad-hoc, full bundle) and verify"
codesign --force --deep -s - build/Release/LinkRouter.app
codesign -v --deep --strict build/Release/LinkRouter.app

echo "==> Zip and checksum"
rm -f build/Release/LinkRouter.app.zip
ditto -c -k --keepParent build/Release/LinkRouter.app build/Release/LinkRouter.app.zip
SHA="$(shasum -a 256 build/Release/LinkRouter.app.zip | awk '{print $1}')"
echo "    sha256: $SHA"

echo "==> Commit and push"
if ! git diff --quiet; then
    git add -A
    git commit -m "release: v$VERSION"
fi
# SSH: not limited by OAuth token scopes (workflow files, etc.)
git push "git@github.com:$GH_USER/$REPO.git" main

echo "==> GitHub release v$VERSION"
PREV_ACCOUNT="$(gh api user --jq .login)"
[[ "$PREV_ACCOUNT" == "$GH_USER" ]] || gh auth switch --user "$GH_USER"
RELEASE_ID="$(gh api "repos/$GH_USER/$REPO/releases" \
    -f tag_name="v$VERSION" -f name="$REPO $VERSION" -f body="$NOTES" --jq '.id')"
curl -sS --fail -X POST \
    -H "Authorization: Bearer $(gh auth token)" \
    -H "Content-Type: application/zip" \
    --data-binary @build/Release/LinkRouter.app.zip \
    "https://uploads.github.com/repos/$GH_USER/$REPO/releases/$RELEASE_ID/assets?name=LinkRouter.app.zip" \
    >/dev/null
[[ "$PREV_ACCOUNT" == "$GH_USER" ]] || gh auth switch --user "$PREV_ACCOUNT"

echo "==> Update Homebrew tap cask"
sed -i '' \
    -e "s/version \"[^\"]*\"/version \"$VERSION\"/" \
    -e "s/sha256 \"[^\"]*\"/sha256 \"$SHA\"/" \
    "$TAP_DIR/Casks/linkrouter.rb"
git -C "$TAP_DIR" commit -am "linkrouter $VERSION"
git -C "$TAP_DIR" push

echo ""
echo "✅ v$VERSION published: https://github.com/$GH_USER/$REPO/releases/tag/v$VERSION"
echo "   Users update with: brew update && brew upgrade --cask linkrouter"
