# Security

## Key

- Type: Ed25519
- ID: SHA256:UWg7JA3vAQ2D/fN+tUUAzdkIhEoorKEY5KIbxrVlRE0
- Owner: alejandroyu@github.com

## Verification

```bash
ssh-keygen -Y verify -f signing-key.pub -I alejandroyu@github.com -n file -s install.sh.sig < install.sh
```

## Integrity

- Script auto-verifies own signature on startup
- Signature in `install.sh.sig`
- Public key in `signing-key.pub`
- SHA256 checksums in `CHECKSUMS.sha256`

## Repo

- All commits signed (Ed25519)
- Releases tagged and signed
- No force pushes allowed
- Main branch protected

## Files

| File | Purpose |
|------|---------|
| install.sh | Installer (84 lines, fully auditable) |
| install.sh.sig | Ed25519 signature |
| signing-key.pub | Public key for verification |
| CHECKSUMS.sha256 | File integrity hashes |

## Threat Model

**Can detect:**
- Script tampering
- Man-in-the-middle attacks
- Corrupted downloads
- Unauthorized modifications

**Cannot prevent:**
- GitHub account compromise
- Local machine compromise
- DNS hijacking (unlikely with HTTPS)
- User running without verification

## Trust Chain

1. Clone from github.com/alejandroyu2/tmux-setup-installme
2. Script verifies its own signature
3. Script checks GitHub authentication
4. Script verifies access to private repo
5. Script clones private repo
6. Runs setup.sh

## Hardening

✅ Ed25519 signature verification
✅ Auto-verify on startup
✅ Signed commits (Git)
✅ Signed release tags
✅ SHA256 checksums
✅ Source code audit (84 lines)
✅ No embedded secrets
✅ Generic key name (no username)

## Version

v1.1 (2026-03-08)
Tag: [v1.1](https://github.com/alejandroyu2/tmux-setup-installme/releases/tag/v1.1)
