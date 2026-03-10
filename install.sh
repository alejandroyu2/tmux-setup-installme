#!/bin/bash
# curl -fsSL https://raw.githubusercontent.com/sys-ax/agent-deploy-install/main/install.sh | bash
set -euo pipefail

echo "agent-deploy installer"
echo ""

# ─── Install gh if missing ───────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  echo "GitHub CLI not found. Installing..."
  if [[ "$(uname)" == "Darwin" ]]; then
    if command -v brew &>/dev/null; then
      brew install gh
    else
      echo "Homebrew not found. Install gh manually: https://cli.github.com"
      exit 1
    fi
  elif [[ "$(uname)" == "Linux" ]]; then
    # Try system install (root/sudo), fall back to standalone binary in ~/.local/bin
    _can_root() { [ "$(id -u)" -eq 0 ] || command -v sudo &>/dev/null; }
    _run() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

    if _can_root; then
      if command -v apt-get &>/dev/null; then
        (type -p wget >/dev/null || _run apt-get install wget -y) \
          && _run mkdir -p -m 755 /etc/apt/keyrings \
          && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | _run tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null \
          && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | _run tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
          && _run apt-get update && _run apt-get install gh -y
      elif command -v dnf &>/dev/null; then
        _run dnf install -y gh
      elif command -v yum &>/dev/null; then
        _run yum install -y gh
      fi
    fi

    # Fallback: standalone binary to ~/.local/bin (no root needed)
    if ! command -v gh &>/dev/null; then
      echo "No root access. Installing gh standalone to ~/.local/bin..."
      ARCH=$(uname -m)
      case "$ARCH" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
      esac
      GH_VERSION=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | grep -o '"tag_name": *"v[^"]*"' | head -1 | grep -o 'v[^"]*')
      GH_TAR="gh_${GH_VERSION#v}_linux_${ARCH}.tar.gz"
      GH_URL="https://github.com/cli/cli/releases/download/${GH_VERSION}/${GH_TAR}"
      T_GH=$(mktemp -d)
      curl -fsSL "$GH_URL" -o "$T_GH/$GH_TAR" \
        && tar xzf "$T_GH/$GH_TAR" -C "$T_GH" \
        && mkdir -p "$HOME/.local/bin" \
        && cp "$T_GH"/gh_*/bin/gh "$HOME/.local/bin/gh" \
        && chmod +x "$HOME/.local/bin/gh" \
        && rm -rf "$T_GH"
      export PATH="$HOME/.local/bin:$PATH"
      echo "Installed gh $(gh --version | head -1) to ~/.local/bin/gh"
    fi

    if ! command -v gh &>/dev/null; then
      echo "Could not install gh. Install manually: https://cli.github.com"
      exit 1
    fi
  else
    echo "Unsupported OS. Install gh manually: https://cli.github.com"
    exit 1
  fi
  echo ""
fi

# ─── Auth if not logged in ───────────────────────────────────────────────────
if ! gh auth status &>/dev/null; then
  echo "Not logged in to GitHub. Starting device auth flow..."
  echo ""
  gh auth login --hostname github.com --git-protocol https --web 2>&1
  echo ""
  if ! gh auth status &>/dev/null; then
    echo "Authentication failed."
    exit 1
  fi
fi

# ─── Clone + run ─────────────────────────────────────────────────────────────
T=$(mktemp -d)
trap "rm -rf '$T'" EXIT
gh repo clone sys-ax/agent-deploy "$T/agent-deploy" -- --depth 1 2>/dev/null || { echo "No access to sys-ax/agent-deploy"; exit 1; }
exec bash "$T/agent-deploy/install.sh"
