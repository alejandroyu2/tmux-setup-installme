#!/bin/bash
# sign.sh — Generate and sign file checksums
#
# Usage:
#   bash sign.sh             Sign everything (needs 1P)
#   bash sign.sh verify      Verify only (no 1P needed)
#
# Pulls signing-sysax from 1P Keys vault, generates CHECKSUMS.sha256
# of all tracked files, and signs it.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Config ──────────────────────────────────────────────────────────────────
OP_VAULT="Keys"
OP_ITEM="signing-sysax"
OP_ACCOUNT="my.1password.com"
SIGNING_KEY_ID="signing-sysax@sys-ax"
EXPECTED_FINGERPRINT="SHA256:UQ35XoL3P8Uqc4I9/D02OWwwZJy5/yIenaDAvVF4IfU"

# ─── Paths ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWED="$SCRIPT_DIR/allowed_signers"
CHECKSUMS="$SCRIPT_DIR/CHECKSUMS.sha256"

# Files to checksum (relative to repo root)
TRACKED_FILES=(
  install.sh
)

# Handle verify mode
VERIFY_ONLY=false
if [ "${1:-}" = "verify" ] || [ "${1:-}" = "--verify" ]; then
  VERIFY_ONLY=true
fi

# ─── Verify mode ─────────────────────────────────────────────────────────────
if [ "$VERIFY_ONLY" = true ]; then
  echo -e "${CYAN}Verifying integrity${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  FAILED=false

  echo -e "[1/2] File checksums..."
  if [ -f "$CHECKSUMS" ]; then
    cd "$SCRIPT_DIR"
    if shasum -a 256 -c CHECKSUMS.sha256 >/dev/null 2>&1; then
      echo -e "  ${GREEN}OK${NC}  All checksums match"
    else
      echo -e "  ${RED}FAIL${NC}  Checksums stale — run sign.sh to regenerate"
      shasum -a 256 -c CHECKSUMS.sha256 2>&1 | grep FAILED || true
      FAILED=true
    fi
  else
    echo -e "  ${RED}FAIL${NC}  CHECKSUMS.sha256 missing"
    FAILED=true
  fi

  echo -e "[2/2] Checksums signature..."
  if [ ! -f "$ALLOWED" ]; then
    echo -e "  ${RED}FAIL${NC}  allowed_signers not found at $ALLOWED"
    FAILED=true
  elif [ ! -f "$CHECKSUMS.sig" ]; then
    echo -e "  ${RED}FAIL${NC}  CHECKSUMS.sha256.sig missing"
    FAILED=true
  else
    if ssh-keygen -Y verify -f "$ALLOWED" -I "$SIGNING_KEY_ID" -n file -s "$CHECKSUMS.sig" < "$CHECKSUMS" &>/dev/null; then
      echo -e "  ${GREEN}OK${NC}  CHECKSUMS.sha256 signature valid"
    else
      echo -e "  ${RED}FAIL${NC}  CHECKSUMS.sha256 signature invalid"
      FAILED=true
    fi
  fi

  echo ""
  if [ "$FAILED" = true ]; then
    echo -e "${RED}Verification FAILED.${NC} Run ${BOLD}bash sign.sh${NC} to fix."
    exit 1
  else
    echo -e "${GREEN}All checks passed.${NC}"
    exit 0
  fi
fi

# ─── Full signing mode ───────────────────────────────────────────────────────
echo -e "${CYAN}Signing checksums${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Repo:     ${BOLD}$SCRIPT_DIR${NC}"
echo -e "  1P item:  ${BOLD}$OP_ITEM${NC} (vault: $OP_VAULT)"
echo ""

# ─── Step 1: Pull signing key from 1Password ─────────────────────────────────
echo -e "[1/4] Pulling signing key from 1Password..."

KEY_RAW=$(mktemp)
KEY_FILE=$(mktemp)
trap "rm -f '$KEY_RAW' '$KEY_FILE'" EXIT INT TERM

if ! OP_ACCOUNT="$OP_ACCOUNT" op item get "$OP_ITEM" --vault "$OP_VAULT" --format json 2>/dev/null \
  | python3 -c "import sys, json; data=json.load(sys.stdin); print(next(f['value'] for f in data['fields'] if f.get('id')=='private_key' or f.get('label')=='private_key'))" > "$KEY_RAW" 2>/dev/null; then
  echo -e "  ${RED}FAIL${NC} Could not retrieve key from 1Password"
  echo -e "       Make sure you're signed in: ${BOLD}op signin${NC}"
  exit 1
fi
chmod 600 "$KEY_RAW"

if [ ! -s "$KEY_RAW" ]; then
  echo -e "  ${RED}FAIL${NC} Retrieved empty key from 1Password"
  exit 1
fi

# Convert PKCS8 to OpenSSH format if needed
if head -1 "$KEY_RAW" | grep -q "BEGIN OPENSSH"; then
  cp "$KEY_RAW" "$KEY_FILE"
else
  python3 -c "
from cryptography.hazmat.primitives import serialization
with open('$KEY_RAW', 'rb') as f:
    k = serialization.load_pem_private_key(f.read(), password=None)
with open('$KEY_FILE', 'wb') as f:
    f.write(k.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.OpenSSH, serialization.NoEncryption()))
" || { echo -e "  ${RED}FAIL${NC} Key format conversion failed"; exit 1; }
fi
chmod 600 "$KEY_FILE"

# ─── Step 2: Verify fingerprint ──────────────────────────────────────────────
echo -e "[2/4] Verifying key fingerprint..."

ACTUAL_FP="$(ssh-keygen -lf "$KEY_FILE" 2>/dev/null | awk '{print $2}')"
if [ "$ACTUAL_FP" != "$EXPECTED_FINGERPRINT" ]; then
  echo -e "  ${RED}FAIL${NC} Fingerprint mismatch!"
  echo -e "       Expected: $EXPECTED_FINGERPRINT"
  echo -e "       Got:      $ACTUAL_FP"
  exit 1
fi
echo -e "  ${GREEN}OK${NC}  $ACTUAL_FP"

# ─── Step 3: Generate checksums ──────────────────────────────────────────────
echo -e "[3/4] Generating checksums..."

cd "$SCRIPT_DIR"
: > "$CHECKSUMS"
for f in "${TRACKED_FILES[@]}"; do
  if [ -f "$f" ]; then
    shasum -a 256 "$f" >> "$CHECKSUMS"
  else
    echo -e "  ${RED}WARN${NC}  $f not found, skipping"
  fi
done
FILE_COUNT="$(wc -l < "$CHECKSUMS" | tr -d ' ')"
echo -e "  ${GREEN}OK${NC}  $FILE_COUNT files checksummed"

# ─── Step 4: Sign checksums file ─────────────────────────────────────────────
echo -e "[4/4] Signing CHECKSUMS.sha256..."

rm -f "$CHECKSUMS.sig"
ssh-keygen -Y sign -f "$KEY_FILE" -n file "$CHECKSUMS"
echo -e "  ${GREEN}OK${NC}  CHECKSUMS.sha256 signed"

# ─── Verify everything ───────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}Verification${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

shasum -a 256 -c CHECKSUMS.sha256 >/dev/null 2>&1 \
  && echo -e "  ${GREEN}OK${NC}  CHECKSUMS.sha256 valid" \
  || { echo -e "  ${RED}FAIL${NC}  Checksums broken"; exit 1; }

if ssh-keygen -Y verify -f "$ALLOWED" -I "$SIGNING_KEY_ID" -n file -s "$CHECKSUMS.sig" < "$CHECKSUMS" &>/dev/null; then
  echo -e "  ${GREEN}OK${NC}  CHECKSUMS.sha256 signature verified"
else
  echo -e "  ${RED}FAIL${NC}  CHECKSUMS.sha256 signature invalid"
  exit 1
fi

echo ""
echo -e "${GREEN}Done.${NC} Commit and push:"
echo -e "  git add CHECKSUMS.sha256 CHECKSUMS.sha256.sig allowed_signers sign.sh && git commit -m 'sign: add checksums + signature' && git push"
