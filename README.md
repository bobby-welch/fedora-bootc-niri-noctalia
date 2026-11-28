# fedora-bootc-niri-noctalia

[![build](https://github.com/bobby-welch/fedora-bootc-niri-noctalia/actions/workflows/build.yml/badge.svg)](https://github.com/bobby-welch/fedora-bootc-niri-noctalia/actions/workflows/build.yml)

My personal laptop OS: [Niri](https://github.com/YaLTeR/niri) and [Noctalia](https://noctalia.dev/) on Fedora's official [`fedora-bootc:45`](https://docs.fedoraproject.org/en-US/bootc/) image.

The whole system is one container image, built daily by GitHub Actions. A laptop downloads new versions in the background and switches to them on the next reboot; if something breaks, the previous version is one command away.

- **Image:** `ghcr.io/bobby-welch/fedora-bootc-niri-noctalia:45`
- **Tested on:** Dell XPS 13 DX13260 (Intel Core 5 320, Wildcat Lake), with Secure Boot on

## How it works

```
Containerfile ──► GitHub Actions (daily) ──► signed image on ghcr.io ──► laptop (bootc)
       ▲                                                                       │
       └──── Renovate keeps pinned versions current          stages updates ◄──┘
```

- **Containerfile:** starts from Fedora's image and adds the desktop, apps, hardware support and config.
- **GitHub Actions:** builds the image, checks it with `bootc container lint`, pushes it and signs it.
- **bootc** (on the laptop): downloads updates, keeps the previous version for rollback.
- **Renovate:** a bot that opens pull requests when something pinned has a new version. See [Renovate](#renovate).

The full explanation, from the Containerfile to rollbacks, is in [docs/how-it-works.md](docs/how-it-works.md).

## Security

- **Signed images.** CI signs every published image with a cosign key. The key lives only in a GitHub environment that just the `main` branch can use, so pull requests (including Renovate's) can never reach it.
- **Enforced on the laptop.** The image's container policy rejects images by default and accepts this one only with a valid signature from our key. After install you turn on bootc's enforcement (see [First boot](#first-boot)).
- **Verified installer.** `just iso` checks the same signature before embedding the image in the ISO.
- **Locked-down defaults.** SSH server off and closed in the firewall (key-only config if you ever start it), Xwayland off, every package repository must have GPG checks on (the build fails otherwise).
- **DMA protection.** The image turns on the Intel IOMMU (`intel_iommu=on`; Fedora's kernel leaves it off), so devices on Thunderbolt/USB4 ports can only reach the memory they're given. `fwupdmgr security` shows `IOMMU: Enabled`. With it on, `bolt` authorizes Thunderbolt devices (docks, drives) automatically; `boltctl list` shows them.
- **No surprise reboots.** Updates are downloaded and staged automatically, but only apply when you reboot.

Verify any published image yourself, from a checkout of this repo (needs [cosign](https://docs.sigstore.dev/cosign/system_config/installation/)):

```bash
cosign verify --key cosign.pub ghcr.io/bobby-welch/fedora-bootc-niri-noctalia:45
```

## Install

You build the installer ISO yourself; the ISO contains the image, so installing needs no network.

### 1. Build the ISO

On any Linux machine with `podman`, `skopeo` and `just` (this image has all three). Needs about 15 GB free and 15–30 minutes.

```bash
git clone https://github.com/bobby-welch/fedora-bootc-niri-noctalia.git
cd fedora-bootc-niri-noctalia
just iso 2>&1 | tee /tmp/iso.log | tail -n 15; echo "exit: ${PIPESTATUS[0]}"
```

`just iso` checks the published image's signature against `cosign.pub` (and refuses it if the check fails), embeds that exact image, and writes the ISO to `iso/output/bootc-fedora-45-bootc-generic-iso-x86_64/`. The full log goes to `/tmp/iso.log`; the last lines and the exit code (`0` means success) print at the end.

To watch progress, run this in a second terminal:

```bash
tail -f /tmp/iso.log | grep --line-buffered -E '^STEP|Pipeline|Stage|error|Error'
```

If the build fails, the end of the log usually says why: `tail -n 60 /tmp/iso.log`.

### 2. Write it to a USB drive

Find the drive (check the size and model carefully):

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
```

Write the ISO to the **whole device**, replacing `/dev/sdX`. Everything on it is erased.

```bash
sudo umount /dev/sdX?* 2>/dev/null
sudo dd if=iso/output/bootc-fedora-45-bootc-generic-iso-x86_64/bootc-fedora-45-bootc-generic-iso-x86_64.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Optionally check the ISO before writing (`checkisomd5` isn't in the image, so it runs in a container; it prints its result on stderr) and compare the drive with it afterwards:

```bash
podman run --rm -v "$PWD/iso/output/bootc-fedora-45-bootc-generic-iso-x86_64:/iso:ro,z" registry.fedoraproject.org/fedora:45 \
  sh -c 'dnf -yq install isomd5sum && checkisomd5 /iso/bootc-fedora-45-bootc-generic-iso-x86_64.iso 2>&1' | grep 'result is: PASS'
sudo cmp -n "$(stat -c %s iso/output/bootc-fedora-45-bootc-generic-iso-x86_64/bootc-fedora-45-bootc-generic-iso-x86_64.iso)" \
  iso/output/bootc-fedora-45-bootc-generic-iso-x86_64/bootc-fedora-45-bootc-generic-iso-x86_64.iso /dev/sdX && echo "USB matches ISO"
```

### 3. Install

Back up the laptop first: the install erases the disk.

1. Boot from the USB drive (on a Dell or ThinkPad, press F12 at the logo for the boot menu). Choose **Install fedora-bootc-niri-noctalia**. If the screen stays black or shows "Pane is dead", reboot and choose **basic graphics**. Leave Secure Boot on: the installer and the installed system boot with it. On a ThinkPad, first turn on **Security → Secure Boot → Allow Microsoft 3rd Party UEFI CA** in the firmware setup (F1 at the logo): it's off by default on recent models, and without it the USB drive won't boot with Secure Boot on.
2. **Installation Destination:** select only the internal disk (not the USB drive) and tick **Encrypt my data**. If the disk holds an old system, choose **Reclaim space → Delete all**. Choose a strong passphrase; you type it at every boot.
3. **Network & Host Name:** set the hostname (you can change it later). No network is needed, so "No network devices available" is fine.
4. **User Creation:** create your user and tick **Make this user administrator**.
5. **Begin Installation**, then reboot and remove the USB drive.

## First boot

Log in at the text login screen; Niri starts. `Mod` is the Super (Windows) key.

### Turn on signature enforcement

The installer can't do this step, so do it once. It fetches the signature from ghcr.io, so connect to Wi-Fi first (Noctalia's Wi-Fi panel, or `nmcli device wifi connect "<SSID>" --ask`).

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/bobby-welch/fedora-bootc-niri-noctalia:45
systemctl reboot
```

After the reboot, `sudo bootc status` shows `signature: containerPolicy` under the image: every update is now checked against the signing key. `No changes in …` from the switch is normal when the installer's image is still the newest.

### Check Secure Boot

```bash
mokutil --sb-state      # SecureBoot enabled
```

If it says disabled, turn it on in the firmware setup: `systemctl reboot --firmware-setup` opens it directly. On the XPS 13 it's under **Security → Secure Boot**. With Secure Boot on, the kernel also runs in lockdown mode.

### Hostname

If you didn't set one in the installer:

```bash
sudo hostnamectl set-hostname my-laptop
```

### GitHub and SSH

Create a passphrase-protected key and log in to GitHub:

```bash
ssh-keygen -t ed25519 -a 100 -C "my-laptop"
gh auth login        # GitHub.com → SSH → upload your public key → browser login
gh auth status && ssh -T git@github.com
```

Only the **public** key (`.pub`) is uploaded; the private key never leaves the laptop.

Upload the same key again as a **signing** key, or your commits won't show as Verified on GitHub (signing keys need one extra token scope):

```bash
gh auth refresh -h github.com -s admin:ssh_signing_key
gh ssh-key add ~/.ssh/id_ed25519.pub --type signing --title my-laptop
gh ssh-key list          # the new key, once for authentication and once for signing
```

Reinstalling? Delete the old installation's keys (both types) under GitHub's **Settings → SSH and GPG keys** once a commit from the new key shows as Verified.

The first `ssh -T` asks you to trust GitHub's host key. Answer `yes` only if the ED25519 fingerprint is `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU` ([GitHub's fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)).

### SSH agent

The image runs OpenSSH's agent for you, so you type the key's passphrase once per session. The SSH config, with GitHub's host keys pinned, comes with the dotfiles below; until then, run `ssh-add` once so the agent holds the passphrase.

### 1Password

Open 1Password from the launcher and sign in. In **Settings → Browser**, turn on browser integration, then install the 1Password extension in Brave. The extension should unlock through the app without its own sign-in.

Check that they're connected: lock the app (`Ctrl+Shift+L`) and the extension locks too. If the extension asks for its own sign-in or stays unlocked, the app has refused it; the reason is in its log:

```bash
grep -iE 'invalid group|Extension connect' ~/.config/1Password/logs/1Password_rCURRENT.log | tail -n 4
```

`invalid group attempted to connect` means the helper's group isn't one the app trusts; the image keeps the 1Password groups at GIDs 1500 and 1501 for this (the app rejects groups below 1000).

### Dotfiles

Personal configuration (Niri, Noctalia, Ghostty, shell, git, SSH) comes from a private chezmoi repo, cloned over SSH:

```bash
chezmoi init --apply git@github.com:bobby-welch/dotfiles.git
```

Its README covers the rest: checking the git hooks and setting up Dropbox.

### Display scaling

```bash
niri msg outputs                    # find the output name, e.g. eDP-1
niri msg output eDP-1 scale 1.6     # try a scale for this session
```

To keep it, set `scale` in the matching `output` block of `~/.config/niri/config.kdl`.

### Fingerprint

On laptops with a supported reader (`lsusb` lists it; most ThinkPads use Synaptics, `06cb:…`), enroll a finger and test it:

```bash
fprintd-enroll          # touch the sensor until it says enroll-completed
fprintd-verify          # verify-match
```

Noctalia's lock screen then accepts the finger or the password (`fingerprint = true` under `[lockscreen]` in its config). The login screen and `sudo` still ask for the password: logging in needs it to unlock the keyring. If enrolling fails on a reader that was used with Windows, clear it in the firmware setup (on a ThinkPad: **Security → Fingerprint → Reset Fingerprint Data**).

### Flatpak apps

Flathub is added automatically on the first boot with a network connection:

```bash
flatpak install flathub <app-id>
```

### Printing

Network printers that support AirPrint or IPP Everywhere print without a driver (the Brother HL-L2340DW does). List the printers CUPS finds, add yours as a queue, make it the default and print a test page:

```bash
lpinfo --include-schemes dnssd -v      # e.g. dnssd://Brother%20HL-L2340D%20series._ipp._tcp.local/?uuid=…
sudo lpadmin -p <name> -D "<description>" -E -v '<dnssd address>' -m everywhere
sudo lpadmin -d <name>
lp /usr/share/cups/data/testprint
```

The `dnssd://` address finds the printer by name, so the queue keeps working when the printer's IP address changes. Remove a queue with `sudo lpadmin -x <name>`.

## Updates and rollback

A daily timer downloads the newest image and **stages** it; nothing changes until you reboot.

```bash
sudo bootc status        # what's running, what's staged
sudo bootc upgrade       # fetch and stage now instead of waiting
systemctl reboot         # switch to the staged image
```

Something broke after an update? Go back to the previous version:

```bash
sudo bootc rollback
systemctl reboot
```

Your files in `/home` and your changes in `/etc` are kept across updates and rollbacks; everything in `/usr` comes from the image.

### Firmware (BIOS, SSD, dock)

Dell publishes firmware through LVFS; `fwupd` is in the image:

```bash
fwupdmgr refresh
fwupdmgr get-updates
fwupdmgr update          # plug in the charger first
fwupdmgr security        # the platform's security checks (HSI)
```

### Moving to a new Fedora release

Renovate never proposes this; you do it when you're ready, usually a few weeks after a release.

1. Check that the three COPRs (Ghostty, Starship, Lazygit) have builds for the new release.
2. On a branch, change every `45` that means the Fedora version. Find them with:

   ```bash
   git grep -nE 'fedora-bootc:45|:45\b|FEDORA_VERSION'
   ```

   That covers both `FROM` lines (drop the `@sha256:…`; Renovate re-pins it), `FEDORA_VERSION` in `build.yml`, the `Justfile`, the kickstart and this README.
3. Open a PR, let `build` pass, merge. CI publishes the `:46` tag.
4. On the laptop:

   ```bash
   sudo bootc switch --enforce-container-sigpolicy ghcr.io/bobby-welch/fedora-bootc-niri-noctalia:46
   systemctl reboot
   ```

   If anything is wrong, `sudo bootc rollback` returns to the old release.

## Renovate

[Renovate](https://docs.renovatebot.com/) is a bot (a GitHub app) that watches every pinned version in this repo and opens a pull request when a newer one exists. Pinning means the build always uses an exact, known version; Renovate is what keeps those pins from going stale.

### What it watches

| What | Where | What happens |
| --- | --- | --- |
| Fedora base image (digest) | `FROM` line in `Containerfile` and `iso/Containerfile` | Merges itself once the `build` check passes. This is how Fedora updates, including new kernels, reach the image. |
| GitHub Actions | `.github/workflows/build.yml` (pinned to commit SHAs) | Waits 3 days after a release, then merges itself once `build` passes. |
| Nerd Fonts | `NERD_FONTS_VERSION` in `Containerfile` | Waits 3 days, opens a PR. **Needs you:** update the checksum (below). |
| Fedora release (45 → 46) | | Never proposed. Upgrading Fedora is a deliberate manual change. |
| cosign v3 / cosign-installer v4 | | Never proposed. bootc verifies the signature format cosign v2 produces. |

"Merges itself" is safe because branch protection requires the `build` check: a pull request that fails to build can't merge.

The 3-day wait exists because compromised releases are usually discovered and pulled within days.

### What you do

- **Glance at the Dependency Dashboard now and then:** issue #3, or `gh issue view 3 --web`. It lists everything pending or waiting.
- **If Renovate stops, CI tells you.** Fedora publishes a new base image almost daily and deletes the old one. A scheduled run with the notice "Pinned base superseded" is normal: Renovate's bump is on its way and its merge rebuilds the image. If the pin hasn't moved for 3 days, the `check` job fails with "Is Renovate running?". Then look at the dashboard and Renovate's run logs at [developer.mend.io](https://developer.mend.io).
- **Nerd Fonts PRs** fail the build until the checksum matches the new version. Fix it on the PR's branch:

  ```bash
  gh pr checkout <number>
  v=$(sed -n 's/^ARG NERD_FONTS_VERSION=//p' Containerfile)
  sum=$(curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/v$v/IosevkaTerm.tar.xz" | sha256sum | cut -d' ' -f1)
  sed -i "s/^ARG NERD_FONTS_SHA256=.*/ARG NERD_FONTS_SHA256=$sum/" Containerfile
  git commit -am "Nerd Fonts $v checksum" && git push
  ```

## Virtual machines

virt-manager, libvirt and QEMU are in the image, for trying installers and risky changes before they reach the laptop. Nothing runs until you use them: the libvirt services start on first connection.

```bash
virt-manager --connect qemu:///system     # asks for your password once
```

UEFI with Secure Boot, an emulated TPM and a NAT network (`virbr0`, 192.168.122.0/24) are available. Copy ISOs to `/var/lib/libvirt/images` first: QEMU isn't allowed to read files in your home directory.

## Building and testing locally

| Command | What it does |
| --- | --- |
| `just build` | Build the image locally as `localhost/fedora-bootc-niri-noctalia:dev` |
| `just lint` | Build, then run bootc's checks |
| `just shell` | Build, then open a shell inside the image |
| `just packages` | List every package in the image |
| `just switch-local` | Boot this machine into the local build (to test before pushing) |
| `just switch-registry bobby-welch` | Go back to the signed published image, with enforcement |
| `just iso` | Build the installer ISO |

### Where things live

Anything that should exist on the installed system goes in `files/` (copied to `/` in the image); anything only needed to build goes in `build/`.

| Path | Purpose |
| --- | --- |
| `Containerfile` | The image: packages, hardware support, services, checks |
| `files/` | System config: greetd login, Niri and starter app configs, container signature policy, package repos, SSH, DNS, boot and update settings |
| `build/` | Build-time checks and helpers |
| `iso/` | The installer ISO: Anaconda environment, boot menu, kickstart |
| `cosign.pub` | Public half of the signing key |
| `.github/workflows/build.yml` | Daily build, push and sign |
| `renovate.json` | Renovate's rules |
| `Justfile` | The `just` commands above |

## Troubleshooting

- **The laptop won't boot after an update:** `bootc rollback` needs a running system, so use the boot menu instead. It shows for only one second: tap an arrow key as soon as the Dell logo goes away, which stops the countdown, then pick the second entry (the previous version), log in, and run `sudo bootc rollback` to make it the default again.
- **No sound:** check `wpctl status` lists the speakers. This laptop's audio needs `alsa-ucm`, which is in the image; a missing device after an update is worth a rollback.
- **Video stutters or drains the battery:** run `vainfo`. It should name the `Intel iHD driver` and list `VAProfileAV1Profile0` and `VAProfileVP9Profile0`; an error means videos are decoded on the CPU. Fedora's build of the driver leaves out H.264 and HEVC, so those always decode on the CPU.
- **Niri is stuck or the screen is unusable:** `Ctrl+Alt+Delete` quits Niri back to the login screen, after a confirmation. It works even if Noctalia is frozen.
- **An X11-only app won't start:** Xwayland is off on purpose. Re-enable it in the Niri config only if you need that app.
- **`bootc upgrade` reports a signature error:** don't override it. Check `cosign verify` (see [Security](#security)) and the latest run in GitHub Actions; a failed or unsigned build should never be installed.
- **Installer screen stays black, or shows "Pane is dead (signal 11)":** use the **basic graphics** boot entry. Its `nomodeset` stays in the installer; the installed system uses the normal graphics driver.
- **"Failed to start systemd-cryptsetup@… Unit … not found" next to the disk passphrase prompt:** harmless. Two parts of the boot process both try to start the disk unlock; the one asking for your passphrase is the one that works.
