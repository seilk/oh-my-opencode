# oh-my-opencode Custom Build

Fork of [code-yeongyu/oh-my-opencode](https://github.com/code-yeongyu/oh-my-opencode) with custom patches.

## Patch: Background Task Max Depth

Limits recursion depth for background agents to prevent infinite nested agent calls.

**Config** (`opencode.json`):
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

## Usage

```bash
git clone git@github.com:seilk/oh-my-opencode.git ~/omo-custom
cd ~/omo-custom
./update-and-build.sh
```

This will:
1. Fetch the latest tag from upstream
2. Create a patched branch `custom-vX.X.X`
3. Apply the patch
4. Build the plugin (`bun run build`)

## OpenCode Plugin Setup

In `~/.config/opencode/opencode.json`:
```json
{
  "plugin": [
    "/path/to/omo-custom"
  ]
}
```

## Files

- `update-and-build.sh` - Build script
- `patches/max-depth-feature.patch` - The patch file

## Branch Structure

- `main` - Scripts and patches only (this branch)
- `custom-vX.X.X` - Patched builds based on upstream tags

## Upstream

https://github.com/code-yeongyu/oh-my-opencode
