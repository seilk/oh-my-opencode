#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$REPO_DIR/patches"

cd "$REPO_DIR"

echo "=== Fetching latest from upstream ==="
git fetch upstream --tags

LATEST_TAG=$(git describe --tags --abbrev=0 upstream/master 2>/dev/null || git tag -l 'v*' --sort=-v:refname | head -1)
echo "Latest tag: $LATEST_TAG"

cp "$PATCH_DIR/max-depth-feature.patch" /tmp/max-depth-feature.patch.bak

BRANCH_NAME="custom-${LATEST_TAG}"
echo "=== Creating branch: $BRANCH_NAME ==="

if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    git checkout "$BRANCH_NAME"
    git reset --hard "$LATEST_TAG"
else
    git checkout -b "$BRANCH_NAME" "$LATEST_TAG"
fi

echo "=== Applying patch ==="
mkdir -p "$PATCH_DIR"
cp /tmp/max-depth-feature.patch.bak "$PATCH_DIR/max-depth-feature.patch"
git apply "$PATCH_DIR/max-depth-feature.patch"

echo "=== Building ==="
bun install
bun run build

VERSION="${LATEST_TAG#v}"
echo ""
echo "=== Done ==="
echo "Version: $VERSION (with max_depth patch)"
echo "Location: $REPO_DIR"
