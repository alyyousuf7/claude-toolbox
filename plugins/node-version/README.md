# node-version

Claude Code plugin that auto-detects and activates the correct Node.js version when a session starts or the working directory changes.

## Problem

When working across multiple repositories with different Node.js version requirements, Claude Code sessions start with whatever Node version happens to be active — often the wrong one.

## How it works

On session start and directory change, the plugin:

1. **Detects** the required Node version from project files
2. **Initializes** the available version manager
3. **Switches** to the correct version
4. **Exports** the updated PATH so all subsequent Bash commands use it

## Supported version files

Checked in priority order:

| File | Example |
|------|---------|
| `.nvmrc` | `20.11.0` |
| `.node-version` | `20.11.0` |
| `.tool-versions` | `nodejs 20.11.0` |
| `package.json` volta section | `{"volta": {"node": "20.11.0"}}` |
| `package.json` engines field | `{"engines": {"node": ">=20"}}` |

## Supported version managers

| Manager | Initialization | Activation |
|---------|---------------|------------|
| **fnm** | `eval "$(fnm env)"` | `fnm use --install-if-missing` |
| **nvm** | `source $NVM_DIR/nvm.sh` | `nvm use` (auto-installs if missing) |
| **volta** | None (shim-based) | Auto-detects from package.json |
| **mise** | `eval "$(mise env -s bash)"` | `mise install` + `mise env` |
| **asdf** | `source asdf.sh` | `asdf install` + `asdf shell` |
| **n** | None (standalone binary) | `n <version>` |

## Installation

```
/plugins install node-version@claude-toolbox
```

## What you'll see

On session start in a repo with `.nvmrc` containing `20.11.0`:

```
[node-version] Activated Node v20.11.0 via fnm (from .nvmrc)
```

If no version file is found, the plugin stays silent.
