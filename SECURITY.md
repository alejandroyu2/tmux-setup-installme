# Security Policy

## Overview

This is a **hardened installer** for the private `tmux-setup` repository. Multiple layers of security verification ensure authenticity and integrity.

## Security Layers

### 1. Ed25519 Signature Verification ⭐⭐⭐⭐⭐

**Strongest modern cryptography (NSA Suite B)**

- **Key Type**: Ed25519 (256-bit)
- **Algorithm**: EdDSA (Elliptic Curve)
- **Security Level**: ~128-bit equivalent to RSA 3072-bit
- **Key ID**: `SHA256:UWg7JA3vAQ2D/fN+tUUAzdkIhEoorKEY5KIbxrVlRE0`
- **Owner**: alejandroyu@github.com

**How to verify:**
```bash
ssh-keygen -Y verify -f signing-key.pub -I alejandroyu@github.com -n file -s install.sh.sig < install.sh
```

### 2. SHA256 Checksum Verification

**Detects corruption and tampering**

All files have SHA256 checksums in `CHECKSUMS.sha256`:

```bash
# Verify file integrity
sha256sum -c CHECKSUMS.sha256

# Check specific file
sha256sum install.sh
# Expected: 0de713ea5ebfa3af08de5c273d6b89304ca114a06a9db4d851001ad3d7f21080
```

### 3. GitHub Commit Signing

**Verifies repo history authenticity**

All commits to this repo are signed with the Ed25519 key. Check:
- https://github.com/alejandroyu2/tmux-setup-installme/commits/main
- Look for "Verified" badge on commits

### 4. GitHub Repository Settings

**Server-side protections:**

- ✅ Require signed commits on main branch
- ✅ Require pull request reviews before merge
- ✅ Dismiss stale reviews on push
- ✅ Require branches to be up to date
- ✅ Enforce administrators follow protection rules

### 5. Code Transparency

**Source code is minimal and auditable**

- `install.sh` = 100 lines
- No dependencies besides `gh` CLI
- No embedded secrets
- No external URLs (except GitHub)
- Read before executing

### 6. Minimal Permissions

**Script requests only necessary permissions**

The installer:
- ✅ Checks GitHub CLI (read-only)
- ✅ Verifies authentication (read-only)
- ✅ Verifies repo access (read-only)
- ✅ Clones private repo
- ✅ Runs setup.sh (user chooses)

No passwords. No tokens. No sudo.

### 7. Transparency Manifest

**MANIFEST.md** documents:
- What each file does
- Why it's needed
- How it's verified
- Dependencies

## Verification Checklist

Before running `bash install.sh`:

- [ ] Download all three files (install.sh, install.sh.sig, signing-key.pub)
- [ ] Verify SHA256 checksums: `sha256sum -c CHECKSUMS.sha256`
- [ ] Verify signature: `ssh-keygen -Y verify ...`
- [ ] Read the install.sh source code
- [ ] Check GitHub repo status
- [ ] Ensure you have GitHub CLI and authentication

## Known Limitations

⚠️ **MITM on GitHub** (unlikely but possible)
- GitHub uses HTTPS and security infrastructure
- Signature verification catches tampering
- Mitigation: Always verify locally

⚠️ **GitHub Account Compromise** (your responsibility)
- Use strong passwords
- Enable 2FA on GitHub account
- Use hardware security keys if possible
- Mitigation: You control your account security

⚠️ **DNS Hijacking** (very unlikely)
- Attacker redirects github.com to fake server
- Mitigation: Check you're on official GitHub domain

⚠️ **Local Machine Compromise** (your responsibility)
- Malware on your Mac could intercept
- Mitigation: Keep your Mac secure and updated

## Security Best Practices

For users:

1. **Always verify before running**
   ```bash
   ssh-keygen -Y verify -f signing-key.pub -I alejandroyu@github.com -n file -s install.sh.sig < install.sh
   ```

2. **Check file integrity**
   ```bash
   sha256sum -c CHECKSUMS.sha256
   ```

3. **Review the script**
   ```bash
   cat install.sh
   ```

4. **Authenticate with GitHub**
   ```bash
   gh auth login
   ```

5. **Verify access to private repo**
   ```bash
   gh repo view alejandroyu2/tmux-setup
   ```

## Reporting Security Issues

If you find a security vulnerability:

1. **DO NOT** open a public issue
2. **DO** contact alejandroyu privately
3. **DO** include:
   - Description of vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

## Future Hardening

Potential improvements:

- [ ] Hardware security key signing
- [ ] Release signing with GPG/SSH certificates
- [ ] Build reproducibility/transparency
- [ ] Binary transparency log
- [ ] Notary/Cosign for supply chain security
- [ ] SLSA framework compliance

## Technical Details

### Ed25519 Key Information

```
Key Type: ssh-ed25519
Key ID: SHA256:UWg7JA3vAQ2D/fN+tUUAzdkIhEoorKEY5KIbxrVlRE0
Owner: alejandroyu@github.com
Algorithm: EdDSA (Edwards-curve Digital Signature Algorithm)
Curve: Curve25519
Key Size: 256-bit
Security: ~128-bit equivalent
```

### Why Ed25519?

- ✅ NSA Suite B recommended
- ✅ Faster than RSA
- ✅ Smaller keys
- ✅ Better security per bit
- ✅ Resistant to side-channel attacks
- ✅ Modern cryptography

### File Integrity

All downloadable files are cryptographically signed and checksummed:

- `install.sh` - Main installer script
- `install.sh.sig` - Ed25519 signature
- `signing-key.pub` - Public key for verification

Download any three files and verify both signature and checksum before execution.

## Changelog

### v1.1 (2026-03-08)

- ✅ Added Ed25519 signature verification
- ✅ Added SHA256 checksums
- ✅ Added SECURITY.md
- ✅ Signed all commits
- ✅ Full source code audit

### v1.0 (2026-03-08)

- Initial release

---

**Last Updated**: 2026-03-08
**Maintainer**: alejandroyu
**Key Fingerprint**: SHA256:UWg7JA3vAQ2D/fN+tUUAzdkIhEoorKEY5KIbxrVlRE0
