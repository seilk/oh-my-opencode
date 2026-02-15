#!/usr/bin/env bash
set -euo pipefail

# update-and-build.sh
#
# This repo is a thin wrapper that stores local patches, and builds an upstream
# oh-my-opencode checkout in a *separate git worktree*.
#
# Why:
# - Avoids dirty working tree / branch checkout failures on this wrapper repo
# - Keeps a stable plugin directory for OpenCode

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_PATH="$REPO_DIR/patches/max-depth-feature.patch"
PLUGIN_DIR="$REPO_DIR/plugin"

cd "$REPO_DIR"

# =============================================================================
# Install bun if not available
# =============================================================================
if ! command -v bun >/dev/null 2>&1; then
  echo "=== Installing bun ==="
  curl -fsSL https://bun.sh/install | bash
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
  echo "Bun installed: $(bun --version)"
fi

# =============================================================================
# Setup upstream remote
# =============================================================================
if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "=== Adding upstream remote ==="
  git remote add upstream https://github.com/code-yeongyu/oh-my-opencode.git
fi

echo "=== Fetching latest from upstream ==="
git fetch upstream --tags

LATEST_TAG="$(git tag -l 'v*' --sort=-v:refname | head -1)"
if [[ -z "$LATEST_TAG" ]]; then
  echo "ERROR: No tags found. Make sure upstream is accessible." >&2
  exit 1
fi

BRANCH_NAME="custom-${LATEST_TAG}"
VERSION="${LATEST_TAG#v}"

echo "Latest tag: $LATEST_TAG"
echo "Target branch: $BRANCH_NAME"

# =============================================================================
# Ensure plugin worktree exists (or refresh it)
# =============================================================================
if [[ ! -d "$PLUGIN_DIR" ]]; then
  echo "=== Creating plugin worktree: $PLUGIN_DIR ==="
  git worktree add "$PLUGIN_DIR" -b "$BRANCH_NAME" "$LATEST_TAG"
else
  # Ensure this is a worktree of this repo
  if ! git -C "$PLUGIN_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: '$PLUGIN_DIR' exists but is not a git worktree." >&2
    echo "Move it aside and re-run." >&2
    exit 1
  fi

  echo "=== Refreshing plugin worktree ==="
  # Make sure we can switch branches deterministically
  git -C "$PLUGIN_DIR" reset --hard
  git -C "$PLUGIN_DIR" clean -fdx
  git -C "$PLUGIN_DIR" checkout -B "$BRANCH_NAME" "$LATEST_TAG"
fi

# =============================================================================
# Apply patch in plugin worktree
# =============================================================================
echo "=== Applying patch ==="
if git -C "$PLUGIN_DIR" apply --check "$PATCH_PATH" >/dev/null 2>&1; then
  git -C "$PLUGIN_DIR" apply "$PATCH_PATH"
else
  echo "Patch did not apply cleanly; trying 3-way..."
  git -C "$PLUGIN_DIR" apply --3way "$PATCH_PATH" || {
    echo "ERROR: Patch failed. Manual intervention required." >&2
    exit 1
  }
fi

# =============================================================================
# Build in plugin worktree
# =============================================================================
echo "=== Installing dependencies (plugin worktree) ==="
(
  cd "$PLUGIN_DIR"
  bun install
)

echo "=== Building (plugin worktree) ==="
(
  cd "$PLUGIN_DIR"
  bun run build
)

# =============================================================================
# Commit so the plugin worktree remains clean (prevents future checkout issues)
# =============================================================================
(
  cd "$PLUGIN_DIR"
  git add -A
  # Always commit with a local identity (no need to configure global git user)
  git -c user.name="omo-custom" -c user.email="omo-custom@local" \
    commit -m "feat: apply local patch on ${LATEST_TAG}" >/dev/null 2>&1 || true
)

# =============================================================================
# Done
# =============================================================================
echo
echo "=========================================="
echo "  Build complete: v$VERSION (patched)"
echo "=========================================="
echo

echo "OpenCode plugin path (recommended):"
echo "  file://$PLUGIN_DIR"
echo

echo "If you previously used file://$REPO_DIR, update your OpenCode config to use /plugin."
