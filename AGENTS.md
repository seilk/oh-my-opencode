# oh-my-opencode Custom Patch Guide

This document explains how to manage custom patched versions of oh-my-opencode plugin.

## Repository Structure

```
~/omo-custom/
├── AGENTS.md                        # This document
├── README.md                        # Usage summary
├── .gitignore
├── patches/
│   └── max-depth-feature.patch      # Patch files
└── update-and-build.sh              # Build script
```

### Branch Structure

| Branch | Purpose |
|--------|---------|
| `main` | Scripts and patch files only (no upstream code) |
| `custom-vX.X.X` | Patched branch based on specific version |

### Remote Structure

| Remote | URL | Purpose |
|--------|-----|---------|
| `origin` | `git@github.com:seilk/oh-my-opencode.git` | My fork |
| `upstream` | `https://github.com/code-yeongyu/oh-my-opencode.git` | Original repository |

---

## Key Difference from OpenCode

**OpenCode**: Standalone binary → Installed to `~/.opencode/bin/`

**oh-my-opencode**: OpenCode plugin → Directly references local directory

```json
// ~/.config/opencode/opencode.json
{
  "plugin": ["/home/USER/omo-custom"]
}
```

Therefore, OMO only requires `bun run build` without binary installation.

---

## Current Patches

### 1. max-depth-feature.patch

**Feature**: Limits recursion depth for background agents to prevent infinite nested agent calls.

**Modified Files**:
- `src/config/schema.ts` - Added `max_depth` config option
- `src/features/background-agent/types.ts` - Added `depth` field
- `src/features/background-agent/manager.ts` - Depth calculation and limit logic

**Configuration**:
```json
// ~/.config/opencode/opencode.json
{
  "plugins": {
    "oh-my-opencode": {
      "backgroundTasks": {
        "max_depth": 2
      }
    }
  }
}
```

**Default**: `max_depth: 2` (background agent can call sub-agents up to 2 levels deep)

---

## Adding a New Patch

### Step 1: Identify Files to Modify

```bash
cd ~/omo-custom

# Create temporary branch from latest upstream tag
git fetch upstream --tags
LATEST=$(git tag -l 'v*' --sort=-v:refname | head -1)
git checkout -b temp-patch $LATEST
```

### Step 2: Modify Code

```bash
# Example: modify manager.ts
vim src/features/background-agent/manager.ts
```

### Step 3: Generate Patch File

```bash
# Extract source files only (exclude bun.lock, schema.json, etc.)
git diff HEAD -- src/ > /tmp/my-new-feature.patch

# Or specific files only
git diff HEAD -- src/config/schema.ts src/features/background-agent/*.ts > /tmp/my-new-feature.patch
```

### Step 4: Add Patch File to main Branch

```bash
git checkout main
cp /tmp/my-new-feature.patch patches/my-new-feature.patch
git add patches/my-new-feature.patch
git commit -m "Add patch: my-new-feature"
git push origin main
```

### Step 5: Update update-and-build.sh

If multiple patches need to be applied:

```bash
# Modify update-and-build.sh
git apply patches/max-depth-feature.patch
git apply patches/my-new-feature.patch  # Add this line
```

### Step 6: Delete Temporary Branch

```bash
git branch -D temp-patch
```

---

## Modifying Existing Patches

When you need to update an existing patch:

### Step 1: Work on Patched Branch

```bash
cd ~/omo-custom
git checkout custom-v3.0.0-beta.12  # Current patched branch
```

### Step 2: Modify Code

```bash
vim src/features/background-agent/manager.ts
```

### Step 3: Generate New Patch File

```bash
# Generate patch by comparing with upstream tag (source files only)
git diff v3.0.0-beta.12 -- src/ > /tmp/updated-patch.patch
```

### Step 4: Update main Branch

```bash
git checkout main
cp /tmp/updated-patch.patch patches/max-depth-feature.patch
git add patches/max-depth-feature.patch
git commit -m "Update patch: max-depth-feature"
git push origin main
```

---

## Following Upstream Updates

When a new version is released:

```bash
cd ~/omo-custom
./update-and-build.sh
```

The script automatically:
1. `git fetch upstream --tags` - Fetch latest tags
2. Create new branch based on latest tag
3. Apply patches
4. `bun install && bun run build`

### Resolving Patch Conflicts

If the patch fails to apply:

```bash
# If script fails, proceed manually
LATEST=$(git tag -l 'v*' --sort=-v:refname | head -1)
git checkout -b custom-$LATEST $LATEST

# Try patch with 3-way merge
git apply --3way patches/max-depth-feature.patch

# If conflict occurs, resolve manually
vim src/features/background-agent/manager.ts
# ... make fixes ...

git add .
git commit -m "feat: add max_depth config for background task recursion limit"

# Build
bun install && bun run build

# Update patch file
git diff $LATEST -- src/ > patches/max-depth-feature.patch
git checkout main
git add patches/max-depth-feature.patch
git commit -m "Update patch for $LATEST"
git push origin main
```

---

## Build Output

After build completion:

```
~/omo-custom/
├── dist/           # Built JS files
│   ├── index.js
│   └── ...
├── node_modules/   # Dependencies
└── ...
```

OpenCode loads this directory directly as a plugin.

---

## Configuration Example

`~/.config/opencode/opencode.json`:

```json
{
  "plugin": [
    "/home/USER/omo-custom"
  ],
  "plugins": {
    "oh-my-opencode": {
      "backgroundTasks": {
        "max_depth": 2,
        "staleTimeoutMs": 180000
      }
    }
  }
}
```

---

## Troubleshooting

### Patch Fails to Apply

```bash
# Validate patch
git apply --check patches/max-depth-feature.patch

# Check which parts conflict
git apply --verbose patches/max-depth-feature.patch
```

### Build Fails

```bash
# Check bun version
bun --version

# Reinstall dependencies
rm -rf node_modules dist
bun install

# Rebuild
bun run build
```

### Plugin Not Loading

```bash
# Verify build output exists
ls -la ~/omo-custom/dist/

# Check opencode.json path (use absolute path)
cat ~/.config/opencode/opencode.json
```

### Missing upstream Remote

```bash
git remote add upstream https://github.com/code-yeongyu/oh-my-opencode.git
git fetch upstream --tags
```

---

## Patch File Best Practices

### Good Patch Scope

```bash
# Source files only (recommended)
git diff HEAD -- src/ > patch.patch

# Specific feature-related files only
git diff HEAD -- src/features/background-agent/ src/config/schema.ts > patch.patch
```

### Avoid These Patch Scopes

```bash
# Full diff (not recommended - includes generated files)
git diff HEAD > patch.patch  # Includes bun.lock, schema.json, etc.
```

### Validating Patch Files

```bash
# Check patch content
cat patches/max-depth-feature.patch

# Verify applicability
git apply --check patches/max-depth-feature.patch

# Dry-run (doesn't actually apply)
git apply --stat patches/max-depth-feature.patch
```

---

## Complete Workflow Example

Here's a complete example of adding a new feature patch:

```bash
# 1. Setup
cd ~/omo-custom
git fetch upstream --tags
LATEST=$(git tag -l 'v*' --sort=-v:refname | head -1)
echo "Latest version: $LATEST"

# 2. Create working branch
git checkout -b temp-my-feature $LATEST

# 3. Make your changes
vim src/features/some-feature/index.ts
vim src/config/schema.ts  # If config changes needed

# 4. Test your changes (optional but recommended)
bun install
bun run build
# Test manually with OpenCode...

# 5. Generate patch (source files only!)
git diff $LATEST -- src/ > /tmp/my-feature.patch

# 6. Add to main branch
git checkout main
cp /tmp/my-feature.patch patches/my-feature.patch

# 7. Update build script if needed
vim update-and-build.sh
# Add: git apply patches/my-feature.patch

# 8. Commit and push
git add .
git commit -m "Add patch: my-feature"
git push origin main

# 9. Cleanup
git branch -D temp-my-feature

# 10. Test full build
./update-and-build.sh
```

---

## References

- **Upstream**: https://github.com/code-yeongyu/oh-my-opencode
- **OpenCode**: https://github.com/anomalyco/opencode
- **OpenCode Docs**: https://opencode.ai/docs
