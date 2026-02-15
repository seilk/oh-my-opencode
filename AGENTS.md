# omo-custom — Wrapper Repo for Upstream oh-my-opencode + Local Patch

This repo is intentionally **thin**.

- `main` stores only:
  - patch files (`patches/*.patch`)
  - one build script (`update-and-build.sh`)
  - docs
- Upstream oh-my-opencode source code lives in a **separate git worktree** at:
  - `~/omo-custom/plugin/`

Goal: reliably track the latest upstream release, apply the local patch, build the plugin, and keep branch switching clean.

---

## Quick Start

```bash
cd ~/omo-custom
./update-and-build.sh
```

What it does:
1) Fetches upstream tags.
2) Picks the latest tag like `v3.5.5`.
3) Refreshes the worktree (`plugin/`) deterministically:
   - `reset --hard` + `clean -fdx`
   - `checkout -B custom-<tag> <tag>`
4) Applies `patches/max-depth-feature.patch`.
5) Builds the plugin.
6) Commits the patched result inside the worktree branch so the worktree stays clean.

---

## Plugin Path

OpenCode should load the plugin from the worktree directory:
- `file:///Users/seil/omo-custom/plugin`

(Do not point OpenCode at `~/omo-custom` root.)

---

## Local Patch

Current patch: `patches/max-depth-feature.patch`

Purpose:
- adds `background_task.max_depth` config
- tracks `depth` per background task
- disables `call_omo_agent` when depth exceeds `max_depth` (default 2)

---

## Patch Failure Behavior (important)

If upstream changes and the patch cannot be applied:
- The script **stops immediately** (non-zero exit).
- The wrapper repo (`~/omo-custom`, `main`) stays clean.
- The worktree (`~/omo-custom/plugin/`) is left in the conflicted state for inspection.
- A **repair log** is written to:
  - `~/omo-custom/logs/patch-failure_<tag>_<timestamp>.md`

The log contains:
- which stage failed (`apply` vs `apply --3way`)
- `git status --porcelain`
- unmerged/conflicted files list
- conflict marker snippets
- a short “agent next steps” recipe

---

## Agent Repair Recipe (update patch for a new upstream tag)

1) Open the worktree:
```bash
cd ~/omo-custom/plugin
git status
```

2) Resolve conflicts and remove conflict markers.

3) Validate build:
```bash
bun install
bun run build
```

4) Regenerate the patch against the upstream tag:
```bash
cd ~/omo-custom/plugin
git diff <tag> -- src/ > ~/omo-custom/patches/max-depth-feature.patch
```

5) Re-run:
```bash
cd ~/omo-custom
./update-and-build.sh
```

---

## Repo Rules

- Do not vendor upstream source into wrapper `main`.
- All local changes must be expressed as `patches/*.patch`.
- Logs go under `logs/` (ignored by git).
