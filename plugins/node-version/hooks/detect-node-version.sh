#!/usr/bin/env bash
#
# detect-node-version.sh
#
# Detects the required Node.js version from project files and activates it
# using whichever version manager is available on the system.
#
# Supported version files: .nvmrc, .node-version, .tool-versions, package.json (volta/engines)
# Supported managers: fnm, nvm, volta, mise, asdf, n

set -euo pipefail

# Read hook input from stdin (JSON with session context)
HOOK_INPUT=$(cat)
CWD=$(echo "$HOOK_INPUT" | grep -o '"cwd":"[^"]*"' | head -1 | cut -d'"' -f4 2>/dev/null || pwd)

# Use CWD from hook input, fall back to pwd
if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
  CWD=$(pwd)
fi

# ---------------------------------------------------------------------------
# Step 1: Detect required Node version from project files
# ---------------------------------------------------------------------------

REQUIRED_VERSION=""
VERSION_SOURCE=""

# Search upward from CWD for version files
find_version_file() {
  local dir="$CWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/$1" ]; then
      echo "$dir/$1"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

# 1. .nvmrc
if version_file=$(find_version_file ".nvmrc"); then
  REQUIRED_VERSION=$(cat "$version_file" | tr -d '[:space:]' | sed 's/^v//')
  VERSION_SOURCE=".nvmrc"

# 2. .node-version
elif version_file=$(find_version_file ".node-version"); then
  REQUIRED_VERSION=$(cat "$version_file" | tr -d '[:space:]' | sed 's/^v//')
  VERSION_SOURCE=".node-version"

# 3. .tool-versions (asdf/mise format)
elif version_file=$(find_version_file ".tool-versions"); then
  line=$(grep '^nodejs ' "$version_file" 2>/dev/null || true)
  if [ -n "$line" ]; then
    REQUIRED_VERSION=$(echo "$line" | awk '{print $2}' | sed 's/^v//')
    VERSION_SOURCE=".tool-versions"
  fi

# 4. package.json — volta.node
elif version_file=$(find_version_file "package.json"); then
  if command -v python3 &>/dev/null; then
    volta_version=$(python3 -c "
import json, sys
try:
    pkg = json.load(open('$version_file'))
    print(pkg.get('volta', {}).get('node', ''))
except: pass
" 2>/dev/null || true)
    if [ -n "$volta_version" ]; then
      REQUIRED_VERSION=$(echo "$volta_version" | sed 's/^v//')
      VERSION_SOURCE="package.json (volta)"
    fi
  fi

  # 5. package.json — engines.node (extract first concrete version from range)
  if [ -z "$REQUIRED_VERSION" ] && command -v python3 &>/dev/null; then
    engines_version=$(python3 -c "
import json, re, sys
try:
    pkg = json.load(open('$version_file'))
    engines = pkg.get('engines', {}).get('node', '')
    if engines:
        # Extract the first version number from the range
        match = re.search(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?', engines)
        if match:
            major = match.group(1)
            minor = match.group(2) or '0'
            patch = match.group(3) or '0'
            # For ranges like >=18, just use the major version
            if not match.group(2):
                print(major)
            else:
                print(f'{major}.{minor}.{patch}')
except: pass
" 2>/dev/null || true)
    if [ -n "$engines_version" ]; then
      REQUIRED_VERSION=$(echo "$engines_version" | sed 's/^v//')
      VERSION_SOURCE="package.json (engines)"
    fi
  fi
fi

# No version file found — exit silently
if [ -z "$REQUIRED_VERSION" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 2: Detect and initialize version manager
# ---------------------------------------------------------------------------

MANAGER=""
MANAGER_BIN=""

init_fnm() {
  local fnm_bin=""
  if command -v fnm &>/dev/null; then
    fnm_bin="fnm"
  elif [ -x "$HOME/.local/bin/fnm" ]; then
    fnm_bin="$HOME/.local/bin/fnm"
  elif [ -x "$HOME/.fnm/fnm" ]; then
    fnm_bin="$HOME/.fnm/fnm"
  elif [ -x "/opt/homebrew/bin/fnm" ]; then
    fnm_bin="/opt/homebrew/bin/fnm"
  elif [ -x "/usr/local/bin/fnm" ]; then
    fnm_bin="/usr/local/bin/fnm"
  fi
  if [ -n "$fnm_bin" ]; then
    eval "$($fnm_bin env)" 2>/dev/null
    MANAGER="fnm"
    MANAGER_BIN="$fnm_bin"
    return 0
  fi
  return 1
}

init_nvm() {
  # nvm is a shell function, not a binary — must source it
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$nvm_dir/nvm.sh" ]; then
    source "$nvm_dir/nvm.sh" 2>/dev/null
    MANAGER="nvm"
    MANAGER_BIN="nvm"
    return 0
  fi
  return 1
}

init_volta() {
  if command -v volta &>/dev/null; then
    MANAGER="volta"
    MANAGER_BIN="volta"
    return 0
  fi
  return 1
}

init_mise() {
  local mise_bin=""
  if command -v mise &>/dev/null; then
    mise_bin="mise"
  elif [ -x "$HOME/.local/bin/mise" ]; then
    mise_bin="$HOME/.local/bin/mise"
  elif [ -x "/opt/homebrew/bin/mise" ]; then
    mise_bin="/opt/homebrew/bin/mise"
  elif [ -x "/usr/local/bin/mise" ]; then
    mise_bin="/usr/local/bin/mise"
  fi
  if [ -n "$mise_bin" ]; then
    eval "$($mise_bin env -s bash 2>/dev/null)" 2>/dev/null || true
    MANAGER="mise"
    MANAGER_BIN="$mise_bin"
    return 0
  fi
  return 1
}

init_asdf() {
  local asdf_dir="${ASDF_DIR:-$HOME/.asdf}"
  if [ -s "$asdf_dir/asdf.sh" ]; then
    source "$asdf_dir/asdf.sh" 2>/dev/null
    MANAGER="asdf"
    MANAGER_BIN="asdf"
    return 0
  elif command -v asdf &>/dev/null; then
    MANAGER="asdf"
    MANAGER_BIN="asdf"
    return 0
  fi
  return 1
}

init_n() {
  if command -v n &>/dev/null; then
    MANAGER="n"
    MANAGER_BIN="n"
    return 0
  fi
  return 1
}

# Try managers in order of popularity
init_fnm || init_nvm || init_volta || init_mise || init_asdf || init_n || true

if [ -z "$MANAGER" ]; then
  echo "[node-version] Found $VERSION_SOURCE requesting Node $REQUIRED_VERSION, but no supported version manager found (fnm, nvm, volta, mise, asdf, n)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 3: Activate the required version
# ---------------------------------------------------------------------------

activate_version() {
  case "$MANAGER" in
    fnm)
      "$MANAGER_BIN" use "$REQUIRED_VERSION" --install-if-missing 2>&1 || {
        echo "[node-version] fnm failed to switch to Node $REQUIRED_VERSION"
        return 1
      }
      ;;
    nvm)
      # Try to use, install if not available
      "$MANAGER_BIN" use "$REQUIRED_VERSION" 2>/dev/null || {
        "$MANAGER_BIN" install "$REQUIRED_VERSION" 2>&1 && "$MANAGER_BIN" use "$REQUIRED_VERSION" 2>&1
      } || {
        echo "[node-version] nvm failed to switch to Node $REQUIRED_VERSION"
        return 1
      }
      ;;
    volta)
      # Volta auto-detects from package.json — just verify it's working
      ;;
    mise)
      "$MANAGER_BIN" install "node@$REQUIRED_VERSION" 2>/dev/null || true
      eval "$("$MANAGER_BIN" env -s bash 2>/dev/null)" 2>/dev/null || true
      ;;
    asdf)
      "$MANAGER_BIN" install nodejs "$REQUIRED_VERSION" 2>/dev/null || true
      "$MANAGER_BIN" shell nodejs "$REQUIRED_VERSION" 2>/dev/null || {
        echo "[node-version] asdf failed to switch to Node $REQUIRED_VERSION"
        return 1
      }
      ;;
    n)
      "$MANAGER_BIN" "$REQUIRED_VERSION" 2>&1 || {
        echo "[node-version] n failed to switch to Node $REQUIRED_VERSION"
        return 1
      }
      ;;
  esac
}

activate_version

# ---------------------------------------------------------------------------
# Step 4: Export environment for Claude's Bash tool
# ---------------------------------------------------------------------------

ACTIVE_NODE=$(node --version 2>/dev/null || echo "")

# Write updated PATH to CLAUDE_ENV_FILE so it persists across Bash tool calls
if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "${PATH:-}" ]; then
  echo "PATH=$PATH" >> "$CLAUDE_ENV_FILE"
fi

if [ -n "$ACTIVE_NODE" ]; then
  echo "[node-version] Activated Node ${ACTIVE_NODE} via ${MANAGER} (from ${VERSION_SOURCE})"
else
  echo "[node-version] Requested Node ${REQUIRED_VERSION} via ${MANAGER} (from ${VERSION_SOURCE}), but version is not installed. Run: ${MANAGER} install ${REQUIRED_VERSION}"
fi
