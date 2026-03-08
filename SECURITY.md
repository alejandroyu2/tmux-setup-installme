# how it works

nothing runs unverified. ever.

## the chain

1. ed25519 sig on `install.sh` — key fingerprint pinned in the script itself
2. sha256 checksums on all files
3. `setup.sh` from the private repo checksummed before execution
4. piped input (`curl | bash`) is downloaded to `/tmp`, verified, then `exec`d

no skip. no "continue anyway?". missing files get fetched and verified automatically.

## signing

the signing key lives in 1Password (`signing-installer-sysax` in the Keys vault). no disk keys — 1P is the single source of truth.

to re-sign after changes to `setup.sh` or `install.sh`:

```
cd /path/to/tmux-setup && bash sign.sh [/path/to/tmux-setup-installme]
```

this pulls the key from 1P, signs, updates checksums, and verifies. the key never touches disk outside a temp file that's cleaned up on exit.

## verify yourself

```
shasum -a 256 -c CHECKSUMS.sha256
ssh-keygen -lf signing-key.pub
# expect: SHA256:UWg7JA3vAQ2D/fN+tUUAzdkIhEoorKEY5KIbxrVlRE0
```

## what else

- gh token scope audit — warns if you have more access than needed
- install log at `~/.installer-log/`
- `set -euo pipefail`, trap on EXIT/INT/TERM

## found something?

open an issue or reach out directly. don't post exploits publicly.
