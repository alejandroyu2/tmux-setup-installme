#!/bin/bash
# Tmux Setup Installer — Hardened Edition
# Verifies integrity and access before installing from private repo
#
# Security controls:
#   - Mandatory signature verification (no bypass, no skip)
#   - Pipe-to-bash safety (downloads + verifies before executing)
#   - setup.sh checksum verification after cloning private repo
#   - GitHub token scope auditing
#   - Full install logging to ~/.installer-log/
#   - All sensitive values in auditable config section

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — All hardcoded values in one auditable block
# ─────────────────────────────────────────────────────────────────────────────
readonly PRIVATE_REPO="sys-ax/tmux-setup"
readonly INSTALLER_REPO="sys-ax/tmux-setup-installme"
readonly SIGNING_KEY_ID="alejandroyu@github.com"
readonly REPO_RAW="https://raw.githubusercontent.com/${INSTALLER_REPO}/main"

# Expected SHA256 of setup.sh inside the private repo.
# Update this value every time setup.sh changes.
# Generate with: shasum -a 256 setup.sh
readonly SETUP_SH_CHECKSUM="94330c64eb27caff166e276e5f9045172c89378e110771a2e4015ae2683dbf88"

# Minimum required files from the public installer repo
readonly REQUIRED_FILES="install.sh install.sh.sig signing-key.pub CHECKSUMS.sha256"

# Token scopes considered safe for this operation (read-only repo access)
readonly SAFE_SCOPES="repo read:org"

# Known signing key fingerprint for pinning
readonly SIGNING_KEY_FINGERPRINT="SHA256:UWg7JA3vAQ2D/fN+tUUAzdkIhEoorKEY5KIbxrVlRE0"

# ─────────────────────────────────────────────────────────────────────────────
# COLORS
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING — Every action is recorded to ~/.installer-log/[timestamp].log
# ─────────────────────────────────────────────────────────────────────────────
LOG_DIR="$HOME/.installer-log"
LOG_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/${LOG_TIMESTAMP}.log"

mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"

# Initialize log with environment context
{
  echo "=== Tmux Setup Installer Log ==="
  echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "User: $(whoami)"
  echo "Host: $(hostname)"
  echo "Shell: $SHELL"
  echo "PWD: $(pwd)"
  echo "Piped: $([ -t 0 ] && echo 'no' || echo 'yes')"
  echo "Args: $*"
  echo "================================="
  echo ""
} > "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Log a message to both the log file and optionally stdout
log() {
  local level="$1"
  shift
  local msg="$*"
  echo "[$(date -u +%H:%M:%S)] [$level] $msg" >> "$LOG_FILE"
}

# Print to terminal and log simultaneously
say() {
  echo -e "$1"
  # Strip ANSI codes for the log
  echo "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
}

# Fatal error: log, print, and exit
die() {
  say "  ${RED}ERROR:${NC} $1"
  log "FATAL" "$1"
  exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP — Secure temp directory removal on exit
# ─────────────────────────────────────────────────────────────────────────────
TEMP_DIR=""
cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    log "INFO" "Cleaning up temp directory: $TEMP_DIR"
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT INT TERM

make_temp_dir() {
  TEMP_DIR="$(mktemp -d)"
  chmod 700 "$TEMP_DIR"
  log "INFO" "Created secure temp directory: $TEMP_DIR"
}

# ─────────────────────────────────────────────────────────────────────────────
# SIGNATURE VERIFICATION — Mandatory, no bypass
# ─────────────────────────────────────────────────────────────────────────────

# Verify that the signing key fingerprint matches what we expect.
# This prevents substitution of the public key file.
verify_key_fingerprint() {
  local keyfile="$1"
  local actual_fp
  actual_fp="$(ssh-keygen -lf "$keyfile" 2>/dev/null | awk '{print $2}')"
  if [ -z "$actual_fp" ]; then
    die "Could not read fingerprint from signing key: $keyfile"
  fi
  if [ "$actual_fp" != "$SIGNING_KEY_FINGERPRINT" ]; then
    die "Signing key fingerprint mismatch!\n    Expected: $SIGNING_KEY_FINGERPRINT\n    Got:      $actual_fp\n    The signing key may have been tampered with."
  fi
  log "INFO" "Signing key fingerprint verified: $actual_fp"
}

# Verify install.sh against its SSH signature using the pinned public key.
# This function NEVER offers to skip or continue without verification.
verify_script_signature() {
  local script_path="$1"
  local sig_path="$2"
  local key_path="$3"

  # Verify key fingerprint first (key pinning)
  verify_key_fingerprint "$key_path"

  # Build the allowed signers file that ssh-keygen requires
  local allowed_signers
  allowed_signers="$(mktemp)"
  echo "${SIGNING_KEY_ID} $(cat "$key_path")" > "$allowed_signers"

  log "INFO" "Verifying signature: script=$script_path sig=$sig_path key=$key_path"

  if ssh-keygen -Y verify \
    -f "$allowed_signers" \
    -I "$SIGNING_KEY_ID" \
    -n file \
    -s "$sig_path" < "$script_path" &>/dev/null; then
    rm -f "$allowed_signers"
    log "INFO" "Signature verification PASSED"
    return 0
  else
    rm -f "$allowed_signers"
    log "FATAL" "Signature verification FAILED"
    return 1
  fi
}

# Verify SHA256 checksums of all repo files
verify_checksums() {
  local base_dir="$1"
  local checksums_file="${base_dir}/CHECKSUMS.sha256"

  if [ ! -f "$checksums_file" ]; then
    die "CHECKSUMS.sha256 not found in $base_dir"
  fi

  log "INFO" "Verifying SHA256 checksums from $checksums_file"

  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local expected_hash file_name
    expected_hash="$(echo "$line" | awk '{print $1}')"
    file_name="$(echo "$line" | awk '{print $2}')"

    if [ ! -f "${base_dir}/${file_name}" ]; then
      die "Checksum references missing file: $file_name"
    fi

    local actual_hash
    actual_hash="$(shasum -a 256 "${base_dir}/${file_name}" | awk '{print $1}')"

    if [ "$actual_hash" != "$expected_hash" ]; then
      die "Checksum mismatch for ${file_name}!\n    Expected: ${expected_hash}\n    Got:      ${actual_hash}"
    fi
    log "INFO" "Checksum OK: $file_name ($actual_hash)"
  done < "$checksums_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# PIPE-TO-BASH SAFETY
# If stdin is not a terminal, we are being piped (curl ... | bash).
# In that case, we must NOT execute the piped input directly.
# Instead: download script + sig + key to temp dir, verify, then exec.
# ─────────────────────────────────────────────────────────────────────────────
handle_piped_execution() {
  say "${YELLOW}[!]${NC} Detected piped execution (curl | bash)"
  say "    Entering safe mode: download, verify, then execute.\n"
  log "INFO" "Piped execution detected — entering safe download mode"

  make_temp_dir
  local dl_dir="${TEMP_DIR}/verified-installer"
  mkdir -p "$dl_dir"

  # Download all required files from the public repo
  local file
  for file in $REQUIRED_FILES; do
    say "    Downloading ${file}..."
    if ! curl -fsSL --max-time 30 --retry 2 \
        "${REPO_RAW}/${file}" -o "${dl_dir}/${file}" 2>/dev/null; then
      die "Failed to download ${file} from ${REPO_RAW}/${file}"
    fi
    log "INFO" "Downloaded: ${REPO_RAW}/${file} -> ${dl_dir}/${file}"
  done

  # Verify SHA256 checksums of all downloaded files
  say "\n    Verifying checksums..."
  verify_checksums "$dl_dir"
  say "  ${GREEN}OK${NC}  All checksums verified"

  # Verify the script signature
  say "    Verifying signature..."
  if ! verify_script_signature \
      "${dl_dir}/install.sh" \
      "${dl_dir}/install.sh.sig" \
      "${dl_dir}/signing-key.pub"; then
    die "Signature verification failed on downloaded script.\n    The script may have been tampered with in transit."
  fi
  say "  ${GREEN}OK${NC}  Script signature verified\n"

  # Mark the downloaded copy as executable and exec it with a flag
  # to indicate it has already been verified (skip re-verification loop)
  chmod +x "${dl_dir}/install.sh"
  log "INFO" "Re-executing verified copy from $dl_dir"

  # Pass a special env var so the re-executed script knows it was
  # already verified and can skip the pipe-safety path.
  # Also pass the log file path so logging continues to the same file.
  export __INSTALLER_VERIFIED=1
  export __INSTALLER_LOG_FILE="$LOG_FILE"
  exec bash "${dl_dir}/install.sh" "$@"
}

# ─────────────────────────────────────────────────────────────────────────────
# TOKEN SCOPE AUDITING
# Check what permissions the current gh token has and warn about excess.
# ─────────────────────────────────────────────────────────────────────────────
audit_token_scopes() {
  log "INFO" "Auditing GitHub token scopes"

  local token_scopes
  token_scopes="$(gh auth status 2>&1 || true)"

  # Extract scopes from gh auth status output
  local scopes_line
  scopes_line="$(echo "$token_scopes" | grep -i 'token scopes' || echo "")"

  if [ -n "$scopes_line" ]; then
    log "INFO" "Token info: $scopes_line"
    say "  ${GREEN}OK${NC}  Token scopes: $(echo "$scopes_line" | sed "s/.*: *//")"

    # Check for dangerous scopes
    local dangerous_scopes="admin:org admin:repo_hook admin:ssh_signing_key admin:gpg_key delete_repo admin:public_key"
    local scope
    for scope in $dangerous_scopes; do
      if echo "$scopes_line" | grep -q "$scope"; then
        say "  ${YELLOW}WARNING:${NC} Token has elevated scope: ${BOLD}${scope}${NC}"
        say "           Consider creating a fine-grained token with only repo read access."
        log "WARN" "Elevated token scope detected: $scope"
      fi
    done
  else
    # Fine-grained tokens do not report scopes the same way
    say "  ${GREEN}OK${NC}  Token authenticated (fine-grained or scopes not reported)"
    log "INFO" "Token scopes not reported (likely fine-grained token)"
  fi

  # Recommend fine-grained token if using a classic token
  if echo "$token_scopes" | grep -qi "classic\|oauth"; then
    say ""
    say "  ${YELLOW}RECOMMENDATION:${NC} You are using a classic token."
    say "  For better security, create a fine-grained personal access token"
    say "  scoped to ${BOLD}${PRIVATE_REPO}${NC} with ${BOLD}Contents: Read${NC} permission only."
    say "  See: https://github.com/settings/personal-access-tokens/new"
    log "WARN" "Classic token in use — fine-grained token recommended"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# SETUP.SH VERIFICATION
# After cloning the private repo, verify setup.sh integrity.
# ─────────────────────────────────────────────────────────────────────────────
verify_setup_script() {
  local setup_path="$1"

  if [ ! -f "$setup_path" ]; then
    die "setup.sh not found in cloned repository at: $setup_path"
  fi

  log "INFO" "Verifying setup.sh integrity"

  # Verify against the embedded checksum
  local actual_hash
  actual_hash="$(shasum -a 256 "$setup_path" | awk '{print $1}')"

  if [ "$actual_hash" != "$SETUP_SH_CHECKSUM" ]; then
    die "setup.sh checksum mismatch!\n    Expected: ${SETUP_SH_CHECKSUM}\n    Got:      ${actual_hash}\n    The private repo may have been tampered with."
  fi
  say "  ${GREEN}OK${NC}  setup.sh checksum verified ($actual_hash)"
  log "INFO" "setup.sh checksum verified: $actual_hash"

  # Log the file details for forensic purposes
  local file_size file_lines
  file_size="$(wc -c < "$setup_path" | tr -d ' ')"
  file_lines="$(wc -l < "$setup_path" | tr -d ' ')"
  log "INFO" "setup.sh: ${file_size} bytes, ${file_lines} lines"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

# If we were re-executed from the pipe-safety handler, pick up the
# existing log file so everything goes to one place.
if [ -n "${__INSTALLER_LOG_FILE:-}" ]; then
  LOG_FILE="$__INSTALLER_LOG_FILE"
fi

# --- Pipe-to-bash safety gate ---
# If stdin is not a terminal and we haven't already been verified,
# we are running via pipe. Refuse to execute until verified.
if [ ! -t 0 ] && [ -z "${__INSTALLER_VERIFIED:-}" ]; then
  handle_piped_execution "$@"
  # exec above means we never reach here, but just in case:
  exit 1
fi

# ─── Banner ──────────────────────────────────────────────────────────────────
say "${CYAN}+================================================+${NC}"
say "${CYAN}|${NC}   ${BLUE}Tmux Setup Installer${NC}                       ${CYAN}|${NC}"
say "${CYAN}|${NC}   Secure installer for private repo          ${CYAN}|${NC}"
say "${CYAN}+================================================+${NC}"
say ""

# ─── Step 0: Verify script signature (mandatory) ────────────────────────────
say "${BLUE}[0/6]${NC} Verifying installer signature..."
log "INFO" "Step 0: Script signature verification"

# Determine where the script lives on disk
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/install.sh"
SIG_PATH="${SCRIPT_DIR}/install.sh.sig"
KEY_PATH="${SCRIPT_DIR}/signing-key.pub"
CHECKSUMS_PATH="${SCRIPT_DIR}/CHECKSUMS.sha256"

# If signature files are missing, download them from the repo.
# No prompt, no skip — they are required.
MISSING_FILES=0
for required in install.sh.sig signing-key.pub CHECKSUMS.sha256; do
  if [ ! -f "${SCRIPT_DIR}/${required}" ]; then
    MISSING_FILES=1
    break
  fi
done

if [ "$MISSING_FILES" -eq 1 ]; then
  say "  Signature files not found locally. Downloading from repo..."
  log "INFO" "Downloading missing signature files from $REPO_RAW"

  for required in install.sh.sig signing-key.pub CHECKSUMS.sha256; do
    if [ ! -f "${SCRIPT_DIR}/${required}" ]; then
      if ! curl -fsSL --max-time 30 --retry 2 \
          "${REPO_RAW}/${required}" -o "${SCRIPT_DIR}/${required}" 2>/dev/null; then
        die "Failed to download ${required} from ${REPO_RAW}/${required}\n    Cannot proceed without signature verification files."
      fi
      say "  Downloaded: ${required}"
      log "INFO" "Downloaded ${required} to ${SCRIPT_DIR}/"
    fi
  done
fi

# Verify SHA256 checksums of all installer files
verify_checksums "$SCRIPT_DIR"
say "  ${GREEN}OK${NC}  File checksums verified"

# Verify the script signature — no fallback, no bypass
if ! verify_script_signature "$SCRIPT_PATH" "$SIG_PATH" "$KEY_PATH"; then
  die "Script signature verification FAILED.\n    This script may have been modified or corrupted.\n    Re-download from: https://github.com/${INSTALLER_REPO}"
fi
say "  ${GREEN}OK${NC}  Script signature verified (Ed25519)"
say ""

# ─── Step 1: Check GitHub CLI ───────────────────────────────────────────────
say "${BLUE}[1/6]${NC} Checking GitHub CLI..."
log "INFO" "Step 1: GitHub CLI check"

if ! command -v gh &> /dev/null; then
  say "  ${YELLOW}!${NC} GitHub CLI not found — installing..."
  log "INFO" "gh not found, attempting install"

  if command -v apt-get &>/dev/null; then
    # debian/ubuntu
    (type -p wget >/dev/null || sudo apt-get install wget -y) \
      && sudo mkdir -p -m 755 /etc/apt/keyrings \
      && out=$(mktemp) && wget -qO "$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      && sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg < "$out" >/dev/null \
      && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
      && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
      && sudo apt-get update -qq \
      && sudo apt-get install gh -y -qq
  elif command -v brew &>/dev/null; then
    brew install gh
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y gh
  elif command -v yum &>/dev/null; then
    sudo yum install -y gh
  else
    die "Could not install gh — unknown package manager. Install manually: https://cli.github.com"
  fi

  if ! command -v gh &>/dev/null; then
    die "gh installation failed."
  fi
  say "  ${GREEN}OK${NC}  GitHub CLI installed"
  log "INFO" "gh installed successfully"
fi

GH_VERSION="$(gh --version | head -1)"
say "  ${GREEN}OK${NC}  $GH_VERSION"
log "INFO" "GitHub CLI found: $GH_VERSION"

# ─── Step 2: Check GitHub authentication ────────────────────────────────────
say ""
say "${BLUE}[2/6]${NC} Checking GitHub authentication..."
log "INFO" "Step 2: GitHub authentication check"

if ! gh auth status &>/dev/null; then
  say "  ${YELLOW}!${NC} Not authenticated — starting login..."
  log "INFO" "gh not authenticated, launching login flow"
  if ! gh auth login; then
    die "GitHub authentication failed."
  fi
  say "  ${GREEN}OK${NC}  Authenticated"
fi

AUTH_USER="$(gh api user -q '.login' 2>/dev/null)" || die "Failed to query authenticated user."
say "  ${GREEN}OK${NC}  Authenticated as: ${BOLD}$AUTH_USER${NC}"
log "INFO" "Authenticated as: $AUTH_USER"

# ─── Step 3: Audit token scopes ─────────────────────────────────────────────
say ""
say "${BLUE}[3/6]${NC} Auditing token permissions..."
log "INFO" "Step 3: Token scope audit"
audit_token_scopes

# ─── Step 4: Verify access to private repo ──────────────────────────────────
say ""
say "${BLUE}[4/6]${NC} Verifying access to ${BOLD}$PRIVATE_REPO${NC}..."
log "INFO" "Step 4: Private repo access check"

if ! gh repo view "$PRIVATE_REPO" &>/dev/null; then
  say "  ${RED}FAIL${NC} No access to $PRIVATE_REPO"
  say ""
  say "  You need access to the private repository."
  say "  Request access at:"
  say "    ${YELLOW}https://github.com/$PRIVATE_REPO${NC}"
  die "Cannot access private repository: $PRIVATE_REPO"
fi

REPO_VISIBILITY="$(gh api "repos/$PRIVATE_REPO" -q '.visibility' 2>/dev/null)" || REPO_VISIBILITY="unknown"
say "  ${GREEN}OK${NC}  Access verified (visibility: $REPO_VISIBILITY)"
log "INFO" "Repo access verified: $PRIVATE_REPO ($REPO_VISIBILITY)"

# ─── Step 5: Clone and verify private repo ──────────────────────────────────
say ""
say "${BLUE}[5/6]${NC} Cloning and verifying private repo..."
log "INFO" "Step 5: Clone and verify"

make_temp_dir
CLONE_DIR="${TEMP_DIR}/tmux-setup"

if ! gh repo clone "$PRIVATE_REPO" "$CLONE_DIR" -- --depth 1 2>/dev/null; then
  die "Failed to clone $PRIVATE_REPO"
fi
say "  ${GREEN}OK${NC}  Repository cloned"
log "INFO" "Cloned $PRIVATE_REPO to $CLONE_DIR"

# Verify setup.sh before executing it
verify_setup_script "${CLONE_DIR}/setup.sh"

# ─── Step 6: Execute setup ──────────────────────────────────────────────────
say ""
say "${BLUE}[6/6]${NC} Running setup..."
log "INFO" "Step 6: Executing setup.sh"

# Log the exact command being run
log "INFO" "Executing: bash ${CLONE_DIR}/setup.sh"

# Run setup.sh from the cloned directory
cd "$CLONE_DIR"
if ! bash setup.sh; then
  die "setup.sh exited with an error."
fi
log "INFO" "setup.sh completed successfully"

# ─── Complete ────────────────────────────────────────────────────────────────
say ""
say "${CYAN}+================================================+${NC}"
say "${CYAN}|${NC}   ${GREEN}Installation Complete${NC}                       ${CYAN}|${NC}"
say "${CYAN}+================================================+${NC}"
say ""
say "Your tmux-setup is ready to use."
say "Configured connections are available immediately."
say ""
say "Install log: ${BOLD}${LOG_FILE}${NC}"
log "INFO" "Installation completed successfully"

connections-list 2>/dev/null || say "Run: ${YELLOW}source ~/.zshrc${NC}"
