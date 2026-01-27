#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$HOME/tmp"

cd "$REPO_DIR"

# =============================================================================
# Install bun if not available
# =============================================================================
if ! command -v bun &> /dev/null; then
    echo "=== Installing bun ==="
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
    echo "Bun installed: $(bun --version)"
fi

mkdir -p "$TMP_DIR"

# =============================================================================
# Setup upstream remote
# =============================================================================
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

# =============================================================================
# Check if already up to date
# =============================================================================
BRANCH_NAME="custom-${LATEST_TAG}"
CURRENT_BRANCH=$(git branch --show-current)

# If already on the target branch and dist/ exists, skip
if [ "$CURRENT_BRANCH" = "$BRANCH_NAME" ] && [ -f "$REPO_DIR/dist/index.js" ]; then
    echo "Already up to date: $LATEST_TAG"
    echo ""
    echo "=== Ready to use ==="
    echo "Add to ~/.config/opencode/opencode.json:"
    echo "  \"plugin\": [\"$REPO_DIR\"]"
    exit 0
fi

# =============================================================================
# Backup patch and create branch
# =============================================================================
echo "=== Backing up patch ==="
cp "$REPO_DIR/patches/max-depth-feature.patch" "$TMP_DIR/max-depth-feature.patch"

echo "=== Creating branch: $BRANCH_NAME ==="

if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    git checkout "$BRANCH_NAME"
    # If dist/ already exists, just rebuild
    if [ -f "$REPO_DIR/dist/index.js" ]; then
        echo "Branch exists with build. Rebuilding..."
        bun install
        bun run build
        echo ""
        echo "=== Done ==="
        echo "Add to ~/.config/opencode/opencode.json:"
        echo "  \"plugin\": [\"$REPO_DIR\"]"
        exit 0
    fi
    git reset --hard "$LATEST_TAG"
else
    git checkout -b "$BRANCH_NAME" "$LATEST_TAG"
fi

# =============================================================================
# Apply patch
# =============================================================================
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

# =============================================================================
# Build
# =============================================================================
echo "=== Installing dependencies ==="
bun install

echo "=== Building ==="
bun run build

# =============================================================================
# Commit (optional, skip if no git user configured)
# =============================================================================
if git config user.email &>/dev/null; then
    echo "=== Committing changes ==="
    git add -A
    git commit -m "feat: apply custom patch on $LATEST_TAG" || true
else
    echo "=== Skipping commit (no git user configured) ==="
fi

# =============================================================================
# Done
# =============================================================================
VERSION="${LATEST_TAG#v}"
echo ""
echo "=========================================="
echo "  Build complete: v$VERSION (with max_depth patch)"
echo "=========================================="
echo ""
echo "Add to ~/.config/opencode/opencode.json:"
echo ""
echo "  {"
echo "    \"plugin\": [\"$REPO_DIR\"]"
echo "  }"
echo ""
