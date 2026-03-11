# omo-custom

Thin wrapper repo: local patches on upstream [oh-my-opencode](https://github.com/code-yeongyu/oh-my-opencode).

```
~/omo-custom/
├── patches/*.patch        # local patches (tracked)
├── update-and-build.sh    # build script (tracked)
├── state/current-tag      # active version (gitignored)
├── plugin → plugin-a/     # symlink to active slot (gitignored)
├── plugin-a/              # shallow clone + build (gitignored)
├── plugin-b/              # shallow clone + build (gitignored)
└── logs/                  # failure reports (gitignored)
```

---

## Quick Start

```bash
cd ~/omo-custom
./update-and-build.sh              # update to latest upstream tag
./update-and-build.sh --reset      # nuke all local state, rebuild from scratch
./update-and-build.sh --tag v3.10.0  # build a specific version
```

On a fresh machine:
```bash
git clone <this-repo> ~/omo-custom
cd ~/omo-custom
./update-and-build.sh
# If bun is missing, the script installs it automatically.
# Then configure OpenCode: plugin = file:///Users/<you>/omo-custom/plugin
```

---

## How It Works

1. Queries latest upstream tag via `git ls-remote` (no local upstream remote needed).
2. Shallow-clones the target tag into the inactive slot.
3. Injects the correct version (from the tag) into `package.json` before building.
4. Applies all `patches/*.patch` in sorted order via `git apply`.
5. Runs `bun install && bun run build`.
6. On success: atomic symlink swap (`ln -sfn`) to activate the new build.
7. On failure: inactive slot left for inspection, active plugin untouched.

Each slot is a fully independent shallow clone. No shared git state, no branch management.

---

## Plugin Path

OpenCode loads the plugin from:
- `file:///Users/seil/omo-custom/plugin`

Do not point at `~/omo-custom` root.

---

## Local Patches

Current: `patches/001-max-depth-feature.patch`

Adds `background_task.max_depth` config to limit background task recursion depth.

Patches are applied in alphabetical order. Prefix with `NNN-` for deterministic ordering.

---

## Failure Behavior

If a patch fails to apply:
- Script stops immediately.
- Active plugin (symlink target) is untouched.
- A failure report is written to `logs/patch-failure_<tag>_<timestamp>.md`.
- The build slot is left as-is for manual inspection.

---

## Agent Repair Recipe

1. Inspect the failed build slot:
```bash
cd ~/omo-custom/plugin-a  # or plugin-b, whichever failed
git status
```

2. Fix the patch conflicts, then validate:
```bash
bun install && bun run build
```

3. Regenerate the patch:
```bash
git diff HEAD -- src/ > ~/omo-custom/patches/001-max-depth-feature.patch
```

4. Re-run:
```bash
cd ~/omo-custom
./update-and-build.sh --reset
```

---

## Repo Rules

- Wrapper `main` contains only patches, script, and docs.
- All local modifications are expressed as `patches/*.patch`.
- Build slots (`plugin-a/`, `plugin-b/`) are disposable shallow clones.
- Never vendor upstream source into this repo.
