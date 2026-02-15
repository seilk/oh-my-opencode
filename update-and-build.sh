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
LOG_DIR="$REPO_DIR/logs"
RUN_ID="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$LOG_DIR"

print_conflict_snippets() {
  local file="$1"
  local context="${2:-5}"

  if [[ ! -f "$file" ]]; then
    echo "(missing file: $file)"
    return
  fi

  local marker_lines
  marker_lines="$(grep -n -E '^(<<<<<<<|=======|>>>>>>>)' "$file" 2>/dev/null | cut -d: -f1 | tr '\n' ' ' || true)"
  if [[ -z "$marker_lines" ]]; then
    echo "(no conflict markers found)"
    return
  fi

  for ln in $marker_lines; do
    local start=$((ln - context))
    local end=$((ln + context))
    if (( start < 1 )); then start=1; fi

    echo
    echo "---- lines ${start}-${end} (around ${ln}) ----"
    sed -n "${start},${end}p" "$file" | nl -ba -w4 -s': ' -v "$start"
  done
}

write_patch_failure_report() {
  local stage="$1"        # e.g., "apply" or "apply --3way"
  local patch="$2"        # patch path
  local stderr_file="$3"  # captured stderr

  local report="$LOG_DIR/patch-failure_${LATEST_TAG}_${RUN_ID}.md"

  {
    echo "# Patch failure report (oh-my-opencode)"
    echo
    echo "- time: $(date)"
    echo "- repo: $REPO_DIR"
    echo "- worktree: $PLUGIN_DIR"
    echo "- upstream tag: $LATEST_TAG"
    echo "- target branch: $BRANCH_NAME"
    echo "- patch: $patch"
    echo "- stage: $stage"
    echo

    echo "## git status (worktree)"
    echo '```'
    git -C "$PLUGIN_DIR" status --porcelain=v1 || true
    echo '```'
    echo

    echo "## unmerged/conflicted files"
    echo '```'
    git -C "$PLUGIN_DIR" diff --name-only --diff-filter=U || true
    echo '```'
    echo

    echo "## apply stderr"
    echo '```'
    if [[ -f "$stderr_file" ]]; then
      cat "$stderr_file"
    else
      echo "(no stderr captured)"
    fi
    echo '```'
    echo

    echo "## conflict snippets"
    local files
    files="$(git -C "$PLUGIN_DIR" diff --name-only --diff-filter=U || true)"
    if [[ -z "$files" ]]; then
      echo "(no unmerged files reported by git)"
    else
      for f in $files; do
        echo
        echo "### $f"
        echo '```'
        print_conflict_snippets "$PLUGIN_DIR/$f" 6
        echo '```'
      done
    fi

    echo
    echo "## agent next steps (recipe)"
    echo
    echo "1) Open the worktree: \`cd $PLUGIN_DIR\`"
    echo "2) Resolve conflicts in the files listed above (remove conflict markers)."
    echo "3) Validate build: \`bun install && bun run build\`"
    echo "4) Regenerate the patch from the upstream tag:"
    echo
    echo '```bash'
    echo "cd $PLUGIN_DIR"
    echo "git diff $LATEST_TAG -- src/ > $REPO_DIR/patches/$(basename "$patch")"
    echo '```'
    echo
    echo "5) Re-run: \`cd $REPO_DIR && ./update-and-build.sh\`"
  } > "$report"

  echo
  echo "ERROR: Patch failed ($stage)." >&2
  echo "Wrote failure report: $report" >&2
  echo "Worktree left as-is for manual resolution: $PLUGIN_DIR" >&2
  echo
}

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
apply_stderr="$(mktemp)"
if git -C "$PLUGIN_DIR" apply --check "$PATCH_PATH" >/dev/null 2>&1; then
  if ! git -C "$PLUGIN_DIR" apply "$PATCH_PATH" 2>"$apply_stderr"; then
    write_patch_failure_report "apply" "$PATCH_PATH" "$apply_stderr"
    exit 1
  fi
else
  echo "Patch did not apply cleanly; trying 3-way..."
  if ! git -C "$PLUGIN_DIR" apply --3way "$PATCH_PATH" 2>"$apply_stderr"; then
    write_patch_failure_report "apply --3way" "$PATCH_PATH" "$apply_stderr"
    exit 1
  fi
fi
rm -f "$apply_stderr"

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
