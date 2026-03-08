```
gh repo clone sys-ax/tmux-setup-installme /tmp/installer && cd /tmp/installer && bash install.sh
```

or

```
curl -fsSL https://raw.githubusercontent.com/sys-ax/tmux-setup-installme/main/install.sh | bash
```

use `gh repo clone` if the curl method fails (GitHub's raw CDN can serve stale files for a few minutes after updates).

needs `gh` authenticated. piped input is never executed raw — it downloads, verifies sig + checksums, then runs the verified copy.

see `SECURITY.md` if you care how.
