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

# OpenCode should point to: file://$REPO_DIR/plugin
# `plugin/` is a symlink that we atomically repoint after a successful update.
PLUGIN_LINK="$REPO_DIR/plugin"
SLOT_A="$REPO_DIR/plugin-a"
SLOT_B="$REPO_DIR/plugin-b"
WORKTREE_DIR=""  # set later (the slot we build into)

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
    echo "- worktree: $WORKTREE_DIR"
    echo "- upstream tag: $LATEST_TAG"
    echo "- target branch: $BRANCH_NAME"
    echo "- patch: $patch"
    echo "- stage: $stage"
    echo

    echo "## git status (worktree)"
    echo '```'
    git -C "$WORKTREE_DIR" status --porcelain=v1 || true
    echo '```'
    echo

    echo "## unmerged/conflicted files"
    echo '```'
    git -C "$WORKTREE_DIR" diff --name-only --diff-filter=U || true
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
    files="$(git -C "$WORKTREE_DIR" diff --name-only --diff-filter=U || true)"
    if [[ -z "$files" ]]; then
      echo "(no unmerged files reported by git)"
    else
      for f in $files; do
        echo
        echo "### $f"
        echo '```'
        print_conflict_snippets "$WORKTREE_DIR/$f" 6
        echo '```'
      done
    fi

    echo
    echo "## agent next steps (recipe)"
    echo
    echo "1) Open the worktree: \`cd $WORKTREE_DIR\`"
    echo "2) Resolve conflicts in the files listed above (remove conflict markers)."
    echo "3) Validate build: \`bun install && bun run build\`"
    echo "4) Regenerate the patch from the upstream tag:"
    echo
    echo '```bash'
    echo "cd $WORKTREE_DIR"
    echo "git diff $LATEST_TAG -- src/ > $REPO_DIR/patches/$(basename "$patch")"
    echo '```'
    echo
    echo "5) Re-run: \`cd $REPO_DIR && ./update-and-build.sh\`"
  } > "$report"

  echo
  echo "ERROR: Patch failed ($stage)." >&2
  echo "Wrote failure report: $report" >&2
  echo "Worktree left as-is for manual resolution: $WORKTREE_DIR" >&2
  echo
}

cd "$REPO_DIR"

resolve_abs_path() {
  local p="$1"
  if [[ -z "$p" ]]; then
    echo ""
    return
  fi
  if [[ "$p" != /* ]]; then
    p="$REPO_DIR/$p"
  fi
  local d
  d="$(cd "$(dirname "$p")" >/dev/null 2>&1 && pwd)"
  echo "$d/$(basename "$p")"
}

ensure_plugin_symlink_layout() {
  # Legacy layout: plugin/ is a real worktree directory.
  if [[ -d "$PLUGIN_LINK" && ! -L "$PLUGIN_LINK" ]]; then
    echo "=== Migrating legacy layout: plugin/ -> plugin-a/ + symlink ==="
    git worktree move "$PLUGIN_LINK" "$SLOT_A"
    ln -sfn "$SLOT_A" "$PLUGIN_LINK"
  fi

  # If no symlink exists but slot A exists, make plugin/ point to it.
  if [[ ! -e "$PLUGIN_LINK" && -d "$SLOT_A" ]]; then
    ln -sfn "$SLOT_A" "$PLUGIN_LINK"
  fi
}

get_active_worktree_dir() {
  if [[ -L "$PLUGIN_LINK" ]]; then
    resolve_abs_path "$(readlink "$PLUGIN_LINK")"
    return
  fi
  if [[ -d "$SLOT_A" ]]; then
    echo "$SLOT_A"
    return
  fi
  if [[ -d "$SLOT_B" ]]; then
    echo "$SLOT_B"
    return
  fi
  echo ""
}

get_inactive_slot_dir() {
  local active="$1"
  if [[ "$active" == "$SLOT_A" ]]; then
    echo "$SLOT_B"
  else
    echo "$SLOT_A"
  fi
}

get_active_tag_from_branch() {
  local dir="$1"
  if [[ -z "$dir" ]]; then
    echo ""
    return
  fi
  local b
  b="$(git -C "$dir" branch --show-current 2>/dev/null || true)"
  if [[ "$b" == custom-v* ]]; then
    echo "${b#custom-}"
    return
  fi
  echo ""
}

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
# Safe update strategy:
# - Keep the currently-working plugin worktree intact (active slot)
# - Build/update into the inactive slot
# - Repoint plugin/ symlink only after success
# =============================================================================
ensure_plugin_symlink_layout
ACTIVE_DIR="$(get_active_worktree_dir)"
ACTIVE_TAG="$(get_active_tag_from_branch "$ACTIVE_DIR")"
INACTIVE_DIR="$(get_inactive_slot_dir "$ACTIVE_DIR")"

if [[ -n "$ACTIVE_TAG" && "$ACTIVE_TAG" == "$LATEST_TAG" ]]; then
  echo "Already up to date: $LATEST_TAG"
  echo "Active plugin: $PLUGIN_LINK -> $ACTIVE_DIR"
  exit 0
fi

WORKTREE_DIR="$INACTIVE_DIR"

# =============================================================================
# Ensure inactive worktree exists (or refresh it)
# =============================================================================
if [[ ! -d "$WORKTREE_DIR" ]]; then
  echo "=== Creating inactive worktree: $WORKTREE_DIR ==="
  # If the branch already exists locally, check it out; else create it.
  if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    git worktree add "$WORKTREE_DIR" "$BRANCH_NAME"
    git -C "$WORKTREE_DIR" reset --hard "$LATEST_TAG"
  else
    git worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME" "$LATEST_TAG"
  fi
else
  if ! git -C "$WORKTREE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: '$WORKTREE_DIR' exists but is not a git worktree." >&2
    echo "Move it aside and re-run." >&2
    exit 1
  fi

  echo "=== Refreshing inactive worktree ==="
  git -C "$WORKTREE_DIR" reset --hard
  git -C "$WORKTREE_DIR" clean -fdx
  git -C "$WORKTREE_DIR" checkout -B "$BRANCH_NAME" "$LATEST_TAG"
fi

# =============================================================================
# Apply patch in plugin worktree
# =============================================================================
echo "=== Applying patch ==="
apply_stderr="$(mktemp)"
if git -C "$WORKTREE_DIR" apply --check "$PATCH_PATH" >/dev/null 2>&1; then
  if ! git -C "$WORKTREE_DIR" apply "$PATCH_PATH" 2>"$apply_stderr"; then
    write_patch_failure_report "apply" "$PATCH_PATH" "$apply_stderr"
    exit 1
  fi
else
  echo "Patch did not apply cleanly; trying 3-way..."
  if ! git -C "$WORKTREE_DIR" apply --3way "$PATCH_PATH" 2>"$apply_stderr"; then
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
  cd "$WORKTREE_DIR"
  bun install
)

echo "=== Building (plugin worktree) ==="
(
  cd "$WORKTREE_DIR"
  bun run build
)

# =============================================================================
# Commit so the plugin worktree remains clean (prevents future checkout issues)
# =============================================================================
(
  cd "$WORKTREE_DIR"
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

# Switch active plugin only after success
ln -sfn "$WORKTREE_DIR" "$PLUGIN_LINK"

echo "OpenCode plugin path (recommended):"
echo "  file://$PLUGIN_LINK"
echo

echo "If you previously used file://$REPO_DIR, update your OpenCode config to use /plugin."
