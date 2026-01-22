#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$HOME/tmp"

cd "$REPO_DIR"

mkdir -p "$TMP_DIR"

if ! git remote get-url upstream &>/dev/null; then
    echo "=== Adding upstream remote ==="
    git remote add upstream https://github.com/code-yeongyu/oh-my-opencode.git
fi

echo "=== Fetching latest from upstream ==="
git fetch upstream --tags

LATEST_TAG=$(git tag -l 'v*' --sort=-v:refname | head -1)
if [ -z "$LATEST_TAG" ]; then
    echo "ERROR: No tags found. Make sure upstream is accessible."
    exit 1
fi
echo "Latest tag: $LATEST_TAG"

echo "=== Backing up patch ==="
cp "$REPO_DIR/patches/max-depth-feature.patch" "$TMP_DIR/max-depth-feature.patch"

BRANCH_NAME="custom-${LATEST_TAG}"
echo "=== Creating branch: $BRANCH_NAME ==="

git stash 2>/dev/null || true
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    git checkout "$BRANCH_NAME"
    git reset --hard "$LATEST_TAG"
else
    git checkout -b "$BRANCH_NAME" "$LATEST_TAG"
fi

echo "=== Applying patch ==="
if git apply --check "$TMP_DIR/max-depth-feature.patch" 2>/dev/null; then
    git apply "$TMP_DIR/max-depth-feature.patch"
else
    echo "Trying 3-way merge..."
    git apply --3way "$TMP_DIR/max-depth-feature.patch" || {
        echo "ERROR: Patch failed. Manual intervention required."
        exit 1
    }
fi

echo "=== Building ==="
bun install
bun run build

VERSION="${LATEST_TAG#v}"
echo ""
echo "=== Done ==="
echo "Version: $VERSION (with max_depth patch)"
echo "Location: $REPO_DIR"
