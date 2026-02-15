# omo-custom — Wrapper Repo for Upstream oh-my-opencode + Local Patch

This repo is intentionally **thin**.

- `main` stores only:
  - patch files (`patches/*.patch`)
  - one build script (`update-and-build.sh`)
  - docs
- Upstream oh-my-opencode source code lives in a **separate git worktree**.
  - The path `~/omo-custom/plugin` is a **symlink** to the currently-active worktree slot.
  - Actual worktrees live in:
    - `~/omo-custom/plugin-a/`
    - `~/omo-custom/plugin-b/`

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
3) Uses a **safe two-slot update strategy**:
   - keep the currently-working plugin slot intact
   - build the update into the inactive slot
   - repoint `plugin` symlink only after success
4) Refreshes the inactive slot deterministically:
   - `reset --hard` + `clean -fdx`
   - `checkout -B custom-<tag> <tag>`
5) Applies `patches/max-depth-feature.patch`.
6) Builds the plugin.
7) Commits the patched result inside the worktree branch so the slot stays clean.
8) Switches `~/omo-custom/plugin` symlink to the newly-built slot.

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

## Update Failure Behavior (important)

If upstream changes and the update fails (patch apply or build):
- The script **stops immediately** (non-zero exit).
- The wrapper repo (`~/omo-custom`, `main`) stays clean.
- The update work happens only in the *inactive slot*.
- The active plugin (the `plugin` symlink target) is **not touched**, so the previously-working plugin keeps working.

If the failure is during patch apply, a **repair log** is written to:
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
