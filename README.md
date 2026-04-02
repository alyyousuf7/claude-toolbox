# claude-toolbox

Personal collection of useful Claude Code plugins.

## Plugins

| Plugin | Description |
|--------|-------------|
| [node-version](plugins/node-version/) | Auto-detect and activate the correct Node.js version on session start |

## Installation

Add this marketplace to your Claude Code settings:

```json
// ~/.claude/settings.json
{
  "extraKnownMarketplaces": {
    "claude-toolbox": {
      "source": {
        "source": "github",
        "repo": "alyyousuf/claude-toolbox"
      }
    }
  }
}
```

Then install plugins via `/plugins install node-version@claude-toolbox`.

## License

MIT
