#!/bin/bash
#!/bin/bash
# Tmux Setup Installer
# Verifies access to private repo, then installs it

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
PRIVATE_REPO="alejandroyu2/tmux-setup"
INSTALLER_REPO="alejandroyu2/tmux-setup-installme"
SIGNING_KEY_ID="alejandroyu@github.com"
REPO_RAW="https://raw.githubusercontent.com/alejandroyu2/tmux-setup-installme/main"

echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}   ${BLUE}Tmux Setup Installer${NC}                       ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}   Secure installer for private repo          ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}\n"

# Step 0: Verify script signature (if downloaded from URL)
if [ -t 0 ]; then
  echo -e "${BLUE}[0/5]${NC} Verifying script signature..."

  # Check if signature files exist
  if [ ! -f "install.sh.sig" ] || [ ! -f "signing-key.pub" ]; then
    echo -e "  ${YELLOW}⚠${NC}  Signature files not found locally"
    echo "    (This is OK if you reviewed the source code)"
    read -p "    Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo -e "${RED}Aborted.${NC}"
      exit 1
    fi
  else
    # Verify signature
    if ssh-keygen -Y verify -f signing-key.pub -I "$SIGNING_KEY_ID" -n file -s install.sh.sig < install.sh &>/dev/null; then
      echo -e "  ${GREEN}✓${NC} Script signature verified"
    else
      echo -e "  ${RED}✗${NC} Signature verification failed!"
      echo "    Script may have been modified or corrupted."
      exit 1
    fi
  fi
  echo ""
fi

# Step 1: Check GitHub CLI
echo -e "${BLUE}[1/5]${NC} Checking GitHub CLI..."
if ! command -v gh &> /dev/null; then
  echo -e "  ${RED}✗${NC} GitHub CLI not found\n"
  echo "Install GitHub CLI:"
  echo -e "  ${YELLOW}brew install gh${NC}\n"
  echo "Then authenticate:"
  echo -e "  ${YELLOW}gh auth login${NC}\n"
  exit 1
fi
GH_VERSION=$(gh --version | head -1)
echo -e "  ${GREEN}✓${NC} GitHub CLI: $GH_VERSION"

# Step 2: Check GitHub authentication
echo -e "\n${BLUE}[2/5]${NC} Checking GitHub authentication..."
if ! gh auth status &>/dev/null; then
  echo -e "  ${RED}✗${NC} Not authenticated with GitHub\n"
  echo "Authenticate with:"
  echo -e "  ${YELLOW}gh auth login${NC}\n"
  exit 1
fi
AUTH_USER=$(gh api user -q '.login')
echo -e "  ${GREEN}✓${NC} Authenticated as: $AUTH_USER"

# Step 3: Verify access to private repo
echo -e "\n${BLUE}[3/5]${NC} Verifying access to $PRIVATE_REPO..."
if ! gh repo view "$PRIVATE_REPO" &>/dev/null; then
  echo -e "  ${RED}✗${NC} No access to $PRIVATE_REPO\n"
  echo "You need access to the private repository."
  echo "Request access at:"
  echo -e "  ${YELLOW}https://github.com/$PRIVATE_REPO${NC}\n"
  exit 1
fi
REPO_VISIBILITY=$(gh api "repos/$PRIVATE_REPO" -q '.visibility')
echo -e "  ${GREEN}✓${NC} Access verified (repo: $REPO_VISIBILITY)"

# Step 4: Clone and install
echo -e "\n${BLUE}[4/5]${NC} Cloning and installing...\n"

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

if ! gh repo clone "$PRIVATE_REPO" "$TEMP_DIR/tmux-setup" -- --depth 1 2>/dev/null; then
  echo -e "${RED}✗${NC} Failed to clone $PRIVATE_REPO"
  exit 1
fi

cd "$TEMP_DIR/tmux-setup"

# Run the setup script
bash setup.sh

echo -e "\n${CYAN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}   ${GREEN}✓ Installation Complete!${NC}                   ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}\n"

echo -e "Your tmux-setup is ready to use!"
echo -e "Configured connections are available immediately.\n"

connections-list 2>/dev/null || echo "Run: source ~/.zshrc"
