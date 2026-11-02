# fedora-bootc-niri-noctalia

A personal Fedora bootc image: Niri + Noctalia, built daily on GitHub Actions,
rechunked, signed with cosign, and published to GHCR.

## Layout

| Path | Purpose |
| --- | --- |
| `Containerfile` | The image definition |
| `files/` | Copied verbatim to `/` in the image |
| `build/` | Build-only helpers, removed before the final lint |
| `cosign.pub` | Public signing key (the private key lives only in a repo secret) |
| `.github/workflows/build.yml` | Daily build, rechunk, push, sign |
| `renovate.json` | Base-image digest, Actions, and Nerd Fonts bumps |

## One-time setup

1. Name the repo `fedora-bootc-niri-noctalia`, or change the name everywhere it
   appears (`policy.json`, `registries.d`, the `.pub` path, the Justfile).
2. Replace `OWNER` with your lowercase GitHub username:
   `grep -rl OWNER files | xargs sed -i 's/OWNER/<you>/g'`
3. Copy your existing config into `files/`:
   - `etc/yum.repos.d/1password.repo` and `etc/yum.repos.d/brave-browser.repo`
   - `etc/greetd/config.toml`
   - `etc/niri/config.kdl`
   - `etc/skel/.config/ghostty/config.ghostty`
   - `etc/skel/.config/noctalia/config.toml`
   - `usr/lib/tmpfiles.d/bootc-greetd.conf`
4. Generate a signing key with an empty password:
   `cosign generate-key-pair`. Commit `cosign.pub`. Add the contents of
   `cosign.key` as the repo secret `SIGNING_SECRET`, then delete the local copy
   or store it in 1Password.
5. Install the Renovate GitHub App on the repo. For automerge to work, require
   the `build` check on `main`.
6. Push, and confirm the first Actions run goes green.

## Moving a laptop over

From the current BlueBuild install:

```bash
getent group onepassword onepassword-mcp     # should be 950 and 951
sudo bootc switch ghcr.io/<you>/fedora-bootc-niri-noctalia:44
sudo systemctl reboot
# Now that the image's signing policy is on the machine, turn on enforcement:
sudo bootc switch --enforce-container-sigpolicy ghcr.io/<you>/fedora-bootc-niri-noctalia:44
```

Updates are staged automatically and applied on your next reboot.
To roll back: `sudo bootc rollback`. Every build also stays available as a
dated tag such as `44.20261101`.

## Still to check

- [ ] Package diff against `ublue-os/base-main:44` (`just packages`)
- [ ] `/etc/pam.d/greetd` includes `pam_gnome_keyring`
- [ ] Whether Fedora now packages Ghostty, Starship, or Lazygit (then drop the COPR)
- [ ] Whether the niri-session patch is still needed
- [ ] Installer ISO for fresh installs
