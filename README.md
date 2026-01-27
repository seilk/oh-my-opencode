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
  "plugin": ["~/omo-custom"]
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

## Upstream

https://github.com/code-yeongyu/oh-my-opencode
