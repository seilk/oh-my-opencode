# oh-my-opencode Custom Build

Fork of [code-yeongyu/oh-my-opencode](https://github.com/code-yeongyu/oh-my-opencode) with custom patches.

## Quick Start

```bash
git clone https://github.com/seilk/oh-my-opencode.git ~/omo-custom
cd ~/omo-custom
./update-and-build.sh
```

The script will:
1. Install `bun` if not available
2. Fetch the latest upstream tag
3. Apply custom patches
4. Build the plugin

Then add to `~/.config/opencode/opencode.json`:
```json
{
  "plugin": ["file:///Users/seil/omo-custom/plugin"]
}
```

## Patch: Background Task Max Depth

Limits recursion depth for background agents to prevent infinite nested agent calls.

**Optional config** (default: 2):
```json
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

## Updating

Run the same script to update:
```bash
cd ~/omo-custom
./update-and-build.sh
```

## Files

| File | Purpose |
|------|---------|
| `update-and-build.sh` | Build script (auto-installs bun) |
| `patches/*.patch` | Custom patch files |

## Branch Structure

| Branch | Content |
|--------|---------|
| `main` | Scripts and patches only |
| `custom-vX.X.X` | Built plugin (created by script) |

## Troubleshooting

### Toast shows wrong version (e.g. `3.0.0-beta.10` instead of current build)

If the startup toast displays an old version despite the plugin being correctly built,
the cause is a stale npm-installed `oh-my-opencode` left in the OpenCode config directory.

OmO's version detection (`getCachedVersion()`) checks
`~/.config/opencode/node_modules/oh-my-opencode/package.json` **first**.
If that file exists with an old version, it wins over the actual `file://` plugin.

This happens when a machine previously had OmO installed via npm/bun and later
switched to the `file://` local build approach without cleaning up the old install.

**Fix:**

```bash
# Remove the stale cached package
rm -rf ~/.config/opencode/node_modules/oh-my-opencode

# Remove the leftover dependency entry
# Edit ~/.config/opencode/package.json and delete the "oh-my-opencode" line
```

After restarting OpenCode, the toast should show the correct version from
`plugin/package.json` (e.g. `3.11.2 (dev)`).

## Upstream

https://github.com/code-yeongyu/oh-my-opencode
