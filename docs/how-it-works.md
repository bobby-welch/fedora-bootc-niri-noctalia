# How it works

How this repo turns a Containerfile into the operating system on the laptop, and what keeps it secure and up to date. For day-to-day use, see the [README](../README.md).

## 1. The big idea

The whole OS is built elsewhere as one container image. The laptop doesn't install packages; it runs a complete, finished image.

```
recipe (Containerfile, in Git) ─► built and signed image (ghcr.io) ─► laptop runs exactly that (bootc)
```

- Every machine running image X is identical. No drift, nothing half-updated.
- An update is a switch to a newer image: downloaded in the background, active after a reboot.
- The previous image stays on disk, so rollback is built in.
- The OS (`/usr`) is read-only. Your data and settings (`/home`, `/etc`, `/var`) persist.
- Changing the system means changing the recipe and merging a PR.

**bootc** is the program on the laptop that downloads, verifies, stages and switches images. It was started by Red Hat, is a CNCF project, and underpins RHEL's "image mode". Fedora provides the base image, `quay.io/fedora/fedora-bootc:45`.

## 2. The recipe

### Containerfile instructions

| Instruction | Meaning |
| --- | --- |
| `ARG` | A build variable (the Nerd Fonts version and checksum) |
| `FROM` | The base image, pinned: `fedora-bootc:45@sha256:…` |
| `RUN` | A command run inside the image during the build (`dnf5 install`, `systemctl enable`) |
| `COPY` | Files from the repo into the image (`files/` → `/`, `cosign.pub`) |

### Containerfile sections, in order

1. **Base:** Fedora's bootc image, pinned by digest.
2. **Repositories:** vendor repos, with signature checking on.
3. **Hardware:** XPS 13 firmware and drivers, audio, video acceleration, power management.
4. **Desktop and CLI:** Niri, Noctalia, greetd, portals, and command-line tools. Weak dependencies off.
5. **Virtualization:** libvirt, QEMU, virt-manager.
6. **COPRs:** Ghostty, Starship, Lazygit. Single-maintainer repos, the most fragile part.
7. **Vendor apps:** Brave, 1Password.
8. **Font:** Nerd Font at a pinned version, checked against its SHA-256.
9. **Configuration:** `files/` copied to `/`, plus the public signing key.
10. **Checks:** the build fails if a repo lacks GPG checking, 1Password's permissions are wrong, the container policy doesn't reject by default, or the Niri config is invalid.
11. **Services:** enable what should run (greetd, firewalld, thermald, libvirt sockets, the SSH agent); disable sshd.
12. **Cleanup:** caches, build helpers, `/run` and `/tmp` leftovers, the random seed, authselect's build-time checksum.
13. **Lint:** `bootc container lint --fatal-warnings`. Any warning fails the build.

### Supporting files

| Path | Purpose |
| --- | --- |
| `files/` | Mirror of the laptop's filesystem: `files/etc/x` becomes `/etc/x` |
| `build/` | Build-time helpers, deleted in cleanup |
| `cosign.pub` | Public signing key, used by laptops to verify images |
| `.github/workflows/build.yml` | The CI workflow (section 3) |
| `renovate.json` | Renovate's rules (section 5) |
| `iso/` | The installer recipe (section 7) |
| `Justfile` | Shortcuts: `just build`, `just lint`, `just iso` and others |

Configs go under `/usr/lib/…` where the program supports it: that location is read-only and always matches the image. Only programs that read `/etc` exclusively (the container policy, greetd) get files there.

## 3. The factory: GitHub Actions

### Triggers

| Trigger | Result |
| --- | --- |
| Pull request to `main` | Build and lint only; nothing published |
| Push to `main` (a merged PR) | Build, publish, sign |
| Daily schedule (05:17 UTC) | Rebuild to pick up package updates |
| Manual (`workflow_dispatch`) | Run on demand |

### Jobs

```
check ─► build ─► sign
```

- **check:** for scheduled runs only. Fedora deletes superseded base images from quay soon after publishing new ones. If the pinned base is gone, the run skips until Renovate's bump merges, and fails if the pin hasn't moved for 3 days.
- **build:** `podman build`; rechunk (content-based layers, so updates download only what changed); verify (bootable label, strict lint); on `main` only, push once under the date tag (`45.YYYYMMDD`) and point `:45` and `latest` at the same digest.
- **sign:** on `main` only, a separate job in the protected `signing` environment, the only place the private key exists.

A `main` build is never cancelled: stopping between publish and sign could leave an unsigned image. Outdated PR builds are cancelled.

### How a pull request works

```
git switch -c my-change ─► edit, commit ─► git push ─► gh pr create
   ─► CI builds the branch (nothing published)
   ─► branch protection: merge allowed only with a green "build"
   ─► gh pr merge --squash: the branch becomes one commit on main
   ─► the main build publishes and signs
```

- A **branch** is a parallel line of work; `main` is untouched until the merge.
- The **PR build** proves the change works before it reaches `main`.
- **Branch protection** applies to everyone, Renovate and admins included.
- A **squash merge** turns the branch into one commit with the PR's title, so `git log` reads as a changelog.
- PR builds never publish or sign: unreviewed code can never produce an image the laptop accepts.

## 4. Trust: signatures

| Key half | Where it lives | Used by |
| --- | --- | --- |
| Private (signs) | GitHub environment `signing`; backup in 1Password; never on a laptop | CI's sign job, `main` only |
| Public (verifies) | `cosign.pub`; inside every image at `/etc/pki/containers/` | The laptop, `just iso`, anyone running `cosign verify` |

A **tag** (`:45`) is a movable label. A **digest** (`sha256:…`) is a fingerprint of the exact contents. Signatures are made over the digest, so moving a tag to another image gains an attacker nothing.

On the laptop, three files from `files/` define what is accepted:

- `/etc/containers/policy.json`: reject by default; our image only with a valid signature from our key; other images allowed per transport, so podman keeps working.
- `/etc/containers/registries.d/…yaml`: where to find our signatures (sigstore attachments next to the image).
- The public key in `/etc/pki/containers/`.

`bootc switch --enforce-container-sigpolicy …` (once, after install) makes bootc require that policy and follow signed images only (`signature: containerPolicy` in `bootc status`).

**Protects against:** tampered or substituted images, a compromised registry, pushes by anyone without the key. **Does not protect against** bad code merged to `main` (branch protection and CI guard that) or a leaked key (rotate; see the migration log).

**cosign** is Sigstore's signing tool. CI stays on cosign v2: bootc and podman verify through the containers/image library, which reads the classic `.sig` format, while cosign v3 defaults to a newer bundle format. Once containers/image supports bundles, CI can move to v3.

## 5. Freshness: Renovate

Every outside dependency is pinned: the base image by digest, GitHub Actions by commit SHA, cosign by version, the Nerd Font by version and checksum. Pins make builds reproducible and every change visible. **Renovate**, a bot hosted by Mend, keeps the pins current by opening PRs.

| Rule | Effect |
| --- | --- |
| Fedora base digest updates | Auto-merge |
| Fedora major (45 → 46) | Never proposed; upgrade by hand |
| GitHub Actions minor, patch, digest | Auto-merge; majors come as PRs for review |
| cosign and cosign-installer majors | Never proposed (stay on v2) |
| `minimumReleaseAge` 3 days (Actions, Nerd Fonts) | New releases wait 3 days; compromised releases are usually pulled by then |
| Nerd Fonts (regex manager) | PR opened; checksum updated by hand |

**Daily update flow:** Fedora publishes a base image → Renovate opens a PR with the new digest → CI builds and lints → GitHub auto-merges on green → the `main` build publishes and signs → the laptop stages it.

If any build fails, nothing merges and the published image stays on the last good version.

**Not pinned:** packages installed with `dnf` always come in at their latest version at build time. They're protected by mandatory GPG signature checks on every repository, and the daily builds are how their security fixes arrive.

**Dependency Dashboard** (issue #3): open and pending updates, errors, everything Renovate watches. It refreshes on each Renovate run.

### PRs that aren't auto-merged

| Situation | Action |
| --- | --- |
| Green (for example a major Action version) | Read the release notes, then `gh pr merge <n> --squash --delete-branch` |
| Red, needs a small fix (Nerd Fonts) | `gh pr checkout <n>`, fix, commit, push, wait for green, merge |
| Red, unclear | `gh run view --log-failed`; rerun with `gh run rerun <id>` if it was an upstream hiccup |
| Not wanted | Close the PR; Renovate ignores that version |
| Wanted later | Leave it open; nothing is published until it merges |

**Nerd Fonts example:** the PR changes only the version, so the build fails at the checksum check (on purpose). On the PR branch:

```bash
gh pr checkout <n>
v=$(sed -n 's/^ARG NERD_FONTS_VERSION=//p' Containerfile)
sum=$(curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/v$v/IosevkaTerm.tar.xz" | sha256sum | cut -d' ' -f1)
sed -i "s/^ARG NERD_FONTS_SHA256=.*/ARG NERD_FONTS_SHA256=$sum/" Containerfile
git commit -qam "Nerd Fonts $v checksum" && git push
sleep 20; gh pr checks <n> --watch && gh pr merge <n> --squash --delete-branch
git switch main && git pull --ff-only
```

Renovate stops rewriting a branch once someone else has pushed to it.

## 6. On the laptop

### Deployments

| Deployment | Meaning |
| --- | --- |
| booted | Running now |
| staged | Downloaded update, active after the next reboot |
| rollback | The previous image, kept as a fallback |

A daily timer runs `bootc upgrade`, which downloads, verifies and stages the update, and never reboots. A failed or interrupted download leaves the running system untouched.

### What persists

| Path | On update | On rollback |
| --- | --- | --- |
| `/usr` (programs, `/usr/lib` configs) | Replaced by the new image | Back to the old image |
| `/etc` | Merged: untouched files follow the image; edited files keep your version | Old image's defaults; your edits stay |
| `/var` (including `/home`, Flatpaks, VMs) | Never touched | Never touched |

A file in `/etc` that you have edited stops receiving image updates. `/var` is copied only at first install, so package directories there are declared in `files/usr/lib/tmpfiles.d/bootc-var.conf`.

No `dnf install` on the laptop: desktop apps come from Flatpak, system tools from the Containerfile, experiments run in podman containers.

### Rollback

| Situation | Steps |
| --- | --- |
| System works, something is off | `sudo bootc rollback`, then `systemctl reboot` (run again to undo) |
| Desktop broken, system boots | Ctrl+Alt+F3, log in, same two commands |
| System won't boot | Hold Shift (or tap Esc) after the Dell logo; pick the second GRUB entry (it boots once); then `sudo bootc rollback` |

To keep a bad update from returning, pin a known-good build, then return to `:45` later:

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/bobby-welch/fedora-bootc-niri-noctalia:45.YYYYMMDD
sudo bootc switch --enforce-container-sigpolicy ghcr.io/bobby-welch/fedora-bootc-niri-noctalia:45
```

Or pause updates: `sudo systemctl disable --now bootc-fetch-apply-updates.timer` (re-enable later with `enable --now`).

### Commands

| Command | Purpose |
| --- | --- |
| `bootc status` | Booted, staged and rollback images; version; signature mode |
| `sudo bootc upgrade --check` | Is there a newer image? |
| `sudo bootc upgrade` | Download and stage now |
| `systemctl reboot` | Switch to the staged image |
| `sudo bootc rollback` | Make the previous image the default |
| `sudo bootc switch <image>` | Follow another tag or image |

## 7. Installation: the ISO

The ISO is installer-only (Anaconda, Fedora's installer) and offline: the verified, signed image is inside it, so installing needs no network. The installed system then follows `ghcr.io/…:45`.

### `just iso`

1. **Verify:** resolve `:45` to a digest and copy it with skopeo, accepting only a valid signature from `cosign.pub`.
2. **Installer:** build `iso/Containerfile`, Anaconda on the same pinned base.
3. **Assemble:** image-builder (`bootc-generic-iso`) makes a bootable ISO and embeds the verified image.
4. **Output:** `iso/output/…/bootc-fedora-45-bootc-generic-iso-x86_64.iso`, with a built-in checksum (`checkisomd5`).

It runs locally (10–20 minutes), not in CI.

### `iso/` files

| File | Purpose |
| --- | --- |
| `iso/Containerfile` | Installer environment: permissive SELinux for the installer only, `/.buildstamp` (no pre-release warning), initramfs that boots into Anaconda |
| `iso/iso.yaml` | Volume label and boot menu: normal and basic-graphics entries |
| `iso/interactive-defaults.ks` | The kickstart (below) |

### Kickstart lines

| Line | Reason |
| --- | --- |
| `bootc --source-imgref containers-storage:… --target-imgref ghcr.io/…:45` | Install the embedded image; take updates from ghcr.io |
| `firewall --use-system-defaults` | Otherwise Anaconda re-opens SSH |
| `%post`: `setfiles …` | Fixes SELinux labels on files Anaconda writes (`restorecon` is a no-op there) |
| `%post`: drop `/` from `/etc/fstab` | Anaconda's line breaks `systemd-remount-fs` |

### Installing

1. `just iso`, write it to a USB stick with `dd` (README), optionally `checkisomd5` it.
2. Boot it (F12 on the Dell), choose **Install fedora-bootc-niri-noctalia**.
3. Pick the disk, tick **Encrypt my data**, set the hostname, create an administrator user.
4. First boot: `sudo bootc switch --enforce-container-sigpolicy ghcr.io/bobby-welch/fedora-bootc-niri-noctalia:45`, reboot, then follow the README.

The first update re-downloads some layers once: the ISO's local copy has its own digest.

## 8. Your role

**Every day:** nothing. Reboot when convenient; `bootc status` shows whether an update is waiting.

**When GitHub emails you:**

| You see | Meaning | Do |
| --- | --- | --- |
| Red Renovate PR | An update broke the build | `gh run view --log-failed`; often fixes itself next day, else a small fix PR |
| Nerd Fonts PR | Checksum needs updating | Section 5 |
| Major Action PR | Not auto-merged by design | Read the notes, merge |
| Scheduled run failed: "Is Renovate running?" | Base pin unchanged for 3 days | Dashboard and Mend logs |

**Changing the system:**

```
branch ─► edit Containerfile or files/ ─► just build / just lint ─► PR ─► green ─► merge
       ─► image published ─► bootc upgrade (or wait) ─► reboot
```

Test risky changes first with `just switch-local` (boot the local build; `just switch-registry bobby-welch` to return) or a VM install of `just iso`. If something slips through, roll back.

**Now and then:**

| When | Task |
| --- | --- |
| Every 6–12 months | Fedora release upgrade (README); releases get about 13 months of support |
| After a release upgrade, before a new machine | Rebuild the ISO, test it in a VM |
| Occasionally | `fwupdmgr refresh && fwupdmgr update`, charger plugged in |
| After adding packages | Add any new `/var` paths lint reports to `bootc-var.conf` |

**Rules:**

- Never bypass branch protection (`gh pr merge --admin`).
- Never put secrets in the repo.
- Don't layer packages on the laptop (`rpm-ostree install`); change the Containerfile.
- Keep signature enforcement on. A failed verification means the system is working.

**Where to look:**

| Question | Place |
| --- | --- |
| How do I use it? | `README.md` |
| Why is it built this way? | The migration log |
| Did the builds work? | Actions tab, `gh run list` |
| What is Renovate doing? | Dependency Dashboard (issue #3) |
| What is the laptop running? | `bootc status` |
