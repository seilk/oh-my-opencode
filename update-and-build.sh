#!/usr/bin/env bash
set -euo pipefail

# update-and-build.sh
#
# Thin wrapper: shallow-clone upstream oh-my-opencode by tag, apply local
# patches, inject the correct version, build, and activate via symlink swap.
#
# Usage:
#   ./update-and-build.sh              # update to latest upstream tag
#   ./update-and-build.sh --reset      # nuke all local state, rebuild fresh
#   ./update-and-build.sh --tag v3.10.0  # build a specific version
#   ./update-and-build.sh --help

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_URL="https://github.com/code-yeongyu/oh-my-opencode.git"
PATCH_DIR="$REPO_DIR/patches"
LOG_DIR="$REPO_DIR/logs"
STATE_DIR="$REPO_DIR/state"
RUN_ID="$(date +%Y%m%d-%H%M%S)"

PLUGIN_LINK="$REPO_DIR/plugin"
SLOT_A="$REPO_DIR/plugin-a"
SLOT_B="$REPO_DIR/plugin-b"

# Parsed from CLI args
FLAG_RESET=0
FLAG_TAG=""

# =============================================================================
# CLI argument parsing
# =============================================================================
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Update oh-my-opencode plugin from upstream, apply local patches, and build.

Options:
  --reset       Remove all local build state and rebuild from scratch
  --tag TAG     Build a specific upstream tag (e.g. v3.10.0) instead of latest
  --help        Show this help message

Examples:
  $(basename "$0")                # update to latest
  $(basename "$0") --reset        # clean slate rebuild
  $(basename "$0") --tag v3.10.0  # pin to specific version
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset)  FLAG_RESET=1; shift ;;
    --tag)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --tag requires a value (e.g. --tag v3.10.0)" >&2
        exit 1
      fi
      FLAG_TAG="$2"; shift 2 ;;
    --help|-h) usage ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      echo "Run with --help for usage." >&2
      exit 1 ;;
  esac
done

# =============================================================================
# Helpers
# =============================================================================
mkdir -p "$LOG_DIR" "$STATE_DIR"

write_patch_failure_report() {
  local stage="$1"
  local patch="$2"
  local stderr_file="$3"
  local build_dir="$4"

  local report="$LOG_DIR/patch-failure_${TARGET_TAG}_${RUN_ID}.md"

  {
    echo "# Patch failure report (oh-my-opencode)"
    echo
    echo "- time: $(date)"
    echo "- repo: $REPO_DIR"
    echo "- build dir: $build_dir"
    echo "- upstream tag: $TARGET_TAG"
    echo "- patch: $patch"
    echo "- stage: $stage"
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

    echo "## git status"
    echo '```'
    git -C "$build_dir" status --porcelain=v1 2>/dev/null || true
    echo '```'
    echo

    echo "## agent next steps"
    echo
    echo "1) Inspect the build dir: \`cd $build_dir\`"
    echo "2) Resolve conflicts, then validate: \`bun install && bun run build\`"
    echo "3) Regenerate the patch:"
    echo '```bash'
    echo "cd $build_dir"
    echo "git diff HEAD -- src/ > $REPO_DIR/patches/$(basename "$patch")"
    echo '```'
    echo "4) Re-run: \`cd $REPO_DIR && ./update-and-build.sh\`"
  } > "$report"

  echo
  echo "ERROR: Patch failed ($stage): $(basename "$patch")" >&2
  echo "Report: $report" >&2
  echo "Build dir left for inspection: $build_dir" >&2
  echo
}

get_active_slot() {
  if [[ -L "$PLUGIN_LINK" ]]; then
    local target
    target="$(readlink "$PLUGIN_LINK")"
    # Resolve relative symlinks
    if [[ "$target" != /* ]]; then
      target="$REPO_DIR/$target"
    fi
    echo "$target"
    return
  fi
  echo ""
}

get_inactive_slot() {
  local active="$1"
  if [[ "$active" == "$SLOT_A" ]]; then
    echo "$SLOT_B"
  else
    echo "$SLOT_A"
  fi
}

get_active_tag() {
  if [[ -f "$STATE_DIR/current-tag" ]]; then
    cat "$STATE_DIR/current-tag"
    return
  fi
  echo ""
}

inject_version() {
  local dir="$1"
  local version="$2"

  INJECT_DIR="$dir" INJECT_VERSION="$version" bun -e "
    const dir = process.env.INJECT_DIR
    const version = process.env.INJECT_VERSION
    const pkg = await Bun.file(dir + '/package.json').json()
    pkg.version = version
    await Bun.write(dir + '/package.json', JSON.stringify(pkg, null, 2) + '\n')
  "
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
# Handle --reset
# =============================================================================
if (( FLAG_RESET == 1 )); then
  echo "=== Resetting all local build state ==="
  rm -rf "$SLOT_A" "$SLOT_B"
  rm -f "$PLUGIN_LINK"
  rm -f "$STATE_DIR/current-tag"
  echo "Cleared: plugin-a, plugin-b, plugin symlink, state"
fi

# =============================================================================
# Resolve target tag
# =============================================================================
if [[ -n "$FLAG_TAG" ]]; then
  TARGET_TAG="$FLAG_TAG"
  echo "Target tag (pinned): $TARGET_TAG"
else
  echo "=== Querying latest upstream tag ==="
  TARGET_TAG="$(git ls-remote --tags --sort=-v:refname "$UPSTREAM_URL" 'v[0-9]*' \
    | grep -v '\^{}$' \
    | head -1 \
    | sed 's|.*refs/tags/||')"

  if [[ -z "$TARGET_TAG" ]]; then
    echo "ERROR: No tags found at $UPSTREAM_URL" >&2
    exit 1
  fi
  echo "Latest tag: $TARGET_TAG"
fi

VERSION="${TARGET_TAG#v}"

# =============================================================================
# Skip if already up to date (unless --reset was used)
# =============================================================================
ACTIVE_SLOT="$(get_active_slot)"
ACTIVE_TAG="$(get_active_tag)"

if (( FLAG_RESET == 0 )) && [[ -n "$ACTIVE_TAG" && "$ACTIVE_TAG" == "$TARGET_TAG" && -d "$ACTIVE_SLOT" ]]; then
  echo "Already up to date: $TARGET_TAG"
  echo "Active plugin: $PLUGIN_LINK -> $ACTIVE_SLOT"
  exit 0
fi

# =============================================================================
# Determine build slot (inactive slot, or slot-a if both empty)
# =============================================================================
if [[ -n "$ACTIVE_SLOT" && -d "$ACTIVE_SLOT" ]]; then
  BUILD_DIR="$(get_inactive_slot "$ACTIVE_SLOT")"
else
  BUILD_DIR="$SLOT_A"
fi

echo "Build slot: $BUILD_DIR"

# =============================================================================
# Shallow clone upstream into build slot
# =============================================================================
rm -rf "$BUILD_DIR"

echo "=== Cloning $TARGET_TAG (shallow) ==="
git clone --depth 1 --branch "$TARGET_TAG" "$UPSTREAM_URL" "$BUILD_DIR" 2>&1

# =============================================================================
# Inject version from tag into package.json
# =============================================================================
echo "=== Injecting version: $VERSION ==="
inject_version "$BUILD_DIR" "$VERSION"

# =============================================================================
# Apply patches (sorted glob)
# =============================================================================
if [[ -d "$PATCH_DIR" ]]; then
  shopt -s nullglob
  PATCHES=("$PATCH_DIR"/*.patch)
  shopt -u nullglob

  if (( ${#PATCHES[@]} > 0 )); then
    echo "=== Applying patches (${#PATCHES[@]}) ==="
    for p in "${PATCHES[@]}"; do
      echo "- $(basename "$p")"
      apply_stderr="$(mktemp)"
      if ! git -C "$BUILD_DIR" apply "$p" 2>"$apply_stderr"; then
        write_patch_failure_report "apply" "$p" "$apply_stderr" "$BUILD_DIR"
        rm -f "$apply_stderr"
        exit 1
      fi
      rm -f "$apply_stderr"
    done
  else
    echo "=== No patches found (skipping) ==="
  fi
fi

# =============================================================================
# Build
# =============================================================================
echo "=== Installing dependencies ==="
(cd "$BUILD_DIR" && bun install)

echo "=== Building ==="
(cd "$BUILD_DIR" && bun run build)

# =============================================================================
# Activate: atomic symlink swap
# =============================================================================
ln -sfn "$BUILD_DIR" "$PLUGIN_LINK"
echo "$TARGET_TAG" > "$STATE_DIR/current-tag"

echo
echo "=========================================="
echo "  Build complete: v$VERSION (patched)"
echo "=========================================="
echo
echo "Active plugin: $PLUGIN_LINK -> $BUILD_DIR"
echo "OpenCode plugin path: file://$PLUGIN_LINK"
