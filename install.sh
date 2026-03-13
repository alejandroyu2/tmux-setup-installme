#!/bin/bash
set -euo pipefail

G='\033[0;32m' R='\033[0;31m' B='\033[1m' N='\033[0m'
C=$(tput cols 2>/dev/null || echo 80)

_ok() { local l="$1" s="${2:-Done}" p=$((C-${#l}-${#s}-4)); ((p<2))&&p=2; printf "${G}✔︎${N} %s%*s${G}%s${N}\n" "$l" "$p" "" "$s"; }
_err() { local l="$1" s="${2:-Failed}" p=$((C-${#l}-${#s}-4)); ((p<2))&&p=2; printf "${R}✗${N} %s%*s${R}%s${N}\n" "$l" "$p" "" "$s"; }

_gh() {
  command -v gh &>/dev/null && return
  if [[ "$(uname)" == "Darwin" ]]; then
    command -v brew &>/dev/null && brew install gh || { _err "gh" "Install: https://cli.github.com"; exit 1; }
  elif [[ "$(uname)" == "Linux" ]]; then
    _r() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }
    if [ "$(id -u)" -eq 0 ] || command -v sudo &>/dev/null; then
      if command -v apt-get &>/dev/null; then
        (type -p wget >/dev/null || _r apt-get install wget -y) \
          && _r mkdir -p -m 755 /etc/apt/keyrings \
          && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | _r tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null \
          && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | _r tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
          && _r apt-get update && _r apt-get install gh -y
      elif command -v dnf &>/dev/null; then _r dnf install -y gh
      elif command -v yum &>/dev/null; then _r yum install -y gh; fi
    fi
    if ! command -v gh &>/dev/null; then
      local a; a=$(uname -m); [[ "$a" == "x86_64" ]] && a=amd64; [[ "$a" == "aarch64" ]] && a=arm64
      local v; v=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | grep -o '"tag_name": *"v[^"]*"' | head -1 | grep -o 'v[^"]*')
      local t; t=$(mktemp -d)
      curl -fsSL "https://github.com/cli/cli/releases/download/${v}/gh_${v#v}_linux_${a}.tar.gz" -o "$t/gh.tar.gz" \
        && tar xzf "$t/gh.tar.gz" -C "$t" && mkdir -p "$HOME/.local/bin" \
        && cp "$t"/gh_*/bin/gh "$HOME/.local/bin/gh" && chmod +x "$HOME/.local/bin/gh" && rm -rf "$t"
      export PATH="$HOME/.local/bin:$PATH"
    fi
  fi
  command -v gh &>/dev/null || { _err "gh" "Install: https://cli.github.com"; exit 1; }
}

echo ""
_gh
_ok "gh" "Ready"

if ! gh auth status &>/dev/null; then
  echo ""; gh auth login --hostname github.com --git-protocol https --web 2>&1; echo ""
  gh auth status &>/dev/null || { _err "Auth" "Failed"; exit 1; }
fi
_ok "Auth" "OK"

T=$(mktemp -d); trap "rm -rf '$T'" EXIT
gh repo clone sys-ax/agent-deploy "$T/r" -- --depth 1 2>/dev/null || { _err "Repo" "No access"; exit 1; }
_ok "Repo" "Ready"
echo ""
exec bash "$T/r/install.sh"
