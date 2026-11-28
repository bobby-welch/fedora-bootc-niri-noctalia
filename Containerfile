# Renovate pins this to a digest and auto-merges digest bumps.
# Fedora release upgrades (45 -> 46) are a deliberate manual change.
FROM quay.io/fedora/fedora-bootc:45@sha256:27650ded85a0319c30d8978a1c10c89084de07fbbb125f85bb054910be081244

# renovate: datasource=github-releases depName=ryanoasis/nerd-fonts
ARG NERD_FONTS_VERSION=3.5.1
# Update by hand with NERD_FONTS_VERSION; a mismatch fails the build.
ARG NERD_FONTS_SHA256=054a4a369cdcc5d57e9bc91ea56dfefd66c71c253dcb0c0d7b72c0810373da26

# Build-only helpers, removed before the final lint.
COPY build/ /tmp/build/

# Third-party repo definitions are needed before installing packages.
# The rest of files/ is copied after packages so our configs always win.
COPY files/etc/yum.repos.d/ /etc/yum.repos.d/

# Hardware enablement. Weak deps allowed so firmware pulls in vendor subpackages.
# cups-filters is explicit: driverless (IPP Everywhere) printing needs it.
# bolt authorizes Thunderbolt/USB4 devices (automatically with the IOMMU on);
# fprintd drives fingerprint readers (Noctalia's lock screen uses it over D-Bus).
# Both start on demand, so nothing runs on laptops without the hardware.
RUN dnf5 install -y \
      linux-firmware \
      alsa-sof-firmware \
      alsa-ucm \
      alsa-utils \
      iwlwifi-mld-firmware \
      iwlbluetooth-firmware \
      mesa-dri-drivers \
      mesa-va-drivers \
      mesa-vulkan-drivers \
      libva-intel-media-driver \
      libva-utils \
      fwupd \
      upower \
      thermald \
      intel-lpmd \
      bolt \
      fprintd \
      bluez \
      NetworkManager-wifi \
      NetworkManager-bluetooth \
      zram-generator-defaults \
      firewalld \
      cups \
      cups-filters \
    && dnf5 clean all

# Desktop, applications, and CLI tools.
# plymouth-system-theme: Fedora's boot splash (bgrt), which draws the disk
# passphrase prompt; with an encrypted disk it waits for the graphics driver.
RUN dnf5 --setopt=install_weak_deps=False install -y \
      plymouth-system-theme \
      greetd \
      greetd-selinux \
      tuigreet \
      niri \
      noctalia \
      polkit \
      gnome-keyring \
      gnome-keyring-pam \
      xdg-desktop-portal \
      xdg-desktop-portal-gnome \
      xdg-desktop-portal-gtk \
      xdg-user-dirs \
      xdg-utils \
      pipewire \
      pipewire-alsa \
      pipewire-pulseaudio \
      wireplumber \
      playerctl \
      brightnessctl \
      wl-clipboard \
      tuned \
      tuned-ppd \
      gvfs \
      gvfs-fuse \
      gvfs-smb \
      flatpak \
      nautilus \
      adw-gtk3-theme \
      gnome-calculator \
      swayimg \
      zathura \
      zathura-pdf-poppler \
      sound-theme-freedesktop \
      rsms-inter-vf-fonts \
      git-core \
      git-delta \
      git-lfs \
      betterleaks \
      ShellCheck \
      gh \
      just \
      jq \
      tldr \
      chezmoi \
      neovim \
      gcc \
      tree-sitter-cli \
      nodejs \
      nodejs-npm \
      bat \
      btop \
      eza \
      fd-find \
      fzf \
      ripgrep \
      wget2-wget \
      yq \
      zoxide \
      dnf5-plugins \
    && dnf5 clean all

# Virtualization for testing images and installers. Socket-activated:
# no daemon runs until a VM tool connects. Only the libvirt drivers these
# VMs use: libvirt-daemon-kvm adds every storage backend (iSCSI, Gluster,
# RBD, LVM...), and iSCSI's NetworkManager hook made the login wait for
# Wi-Fi. Weak deps off, so virt-manager doesn't pull the bundle back; kept
# from them: SELinux policy for the TPM emulator and user-mode networking,
# and PipeWire's JACK library (instead of JACK2) for QEMU's audio.
RUN dnf5 --setopt=install_weak_deps=False install -y \
      virt-manager \
      virt-install \
      virt-viewer \
      libvirt-daemon-driver-qemu \
      libvirt-daemon-driver-network \
      libvirt-daemon-driver-storage-core \
      libvirt-daemon-driver-nodedev \
      libvirt-daemon-driver-secret \
      libvirt-daemon-driver-nwfilter \
      libvirt-daemon-driver-interface \
      libvirt-daemon-lock \
      libvirt-daemon-config-network \
      qemu-kvm \
      edk2-ovmf \
      swtpm-selinux \
      passt-selinux \
      pipewire-jack-audio-connection-kit-libs \
    && dnf5 clean all

# Single-maintainer COPRs: the most fragile dependencies here.
# Replace each with a Fedora package once one exists.
RUN dnf5 -y copr enable scottames/ghostty "fedora-$(rpm -E %fedora)-$(uname -m)" \
    && dnf5 -y copr enable atim/starship \
    && dnf5 -y copr enable magnusrc/lazygit \
    && dnf5 --setopt=install_weak_deps=False install -y ghostty starship lazygit \
    && dnf5 clean all

RUN dnf5 --setopt=install_weak_deps=False install -y brave-origin \
    && dnf5 clean all

# 1Password's setgid helpers need stable GIDs, present before the RPM installs.
# Not system GIDs: the app rejects helpers whose group is below 1000.
RUN cat /tmp/build/1password-groups >> /usr/lib/group \
    && test "$(getent group onepassword | cut -d: -f3)" = 1500 \
    && test "$(getent group onepassword-mcp | cut -d: -f3)" = 1501

RUN dnf5 --setopt=install_weak_deps=False install -y 1password \
    && dnf5 clean all

# IosevkaTerm Nerd Font: pinned release, verified checksum.
RUN set -eu; \
    archive=/tmp/IosevkaTerm.tar.xz; \
    fontdir=/usr/share/fonts/iosevka-term-nerd-font; \
    curl --fail --location --show-error --silent --output "$archive" \
      "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONTS_VERSION}/IosevkaTerm.tar.xz"; \
    echo "${NERD_FONTS_SHA256}  ${archive}" | sha256sum --check; \
    mkdir -p "$fontdir"; \
    tar --no-same-owner -xJf "$archive" -C "$fontdir" \
      IosevkaTermNerdFont-Regular.ttf \
      IosevkaTermNerdFont-Bold.ttf \
      IosevkaTermNerdFont-Italic.ttf \
      IosevkaTermNerdFont-BoldItalic.ttf; \
    chmod 0644 "$fontdir"/*.ttf; \
    fc-cache -f "$fontdir"; \
    rm -f "$archive"

# System configuration. Also restores 1password.repo, which its RPM rewrites.
COPY files/ /
COPY cosign.pub /etc/pki/containers/fedora-bootc-niri-noctalia.pub

RUN test "$(stat -c '%g:%a' /opt/1Password/1Password-BrowserSupport)" = 1500:2755 \
    && test "$(stat -c '%g:%a' /opt/1Password/1password-mcp)" = 1501:2755 \
    && grep -qx 'gpgcheck=1' /etc/yum.repos.d/1password.repo \
    && grep -qx 'repo_gpgcheck=1' /etc/yum.repos.d/1password.repo \
    && /tmp/build/check-repo-gpgcheck.sh \
    && yq -e '.default[0].type == "reject"' /etc/containers/policy.json > /dev/null

# Rebuild the initramfs so it includes Plymouth, whose dracut module brings in
# the graphics drivers (drm module, minus our omit_drivers), then check it has
# Plymouth, the Intel drivers and the console font from kargs.d, and not the
# omitted drivers.
# /root links to /var/roothome, which only exists on a booted system: create it
# for the run. No syslog in a build container: a temporary drop-in turns it off
# (dracut has no command-line option for it).
# Any dracut error, or a dracut module the base initramfs had, fails the build.
RUN set -eu; \
    kver=$(ls /usr/lib/modules); \
    test "$(echo "$kver" | wc -w)" = 1; \
    img="/usr/lib/modules/$kver/initramfs.img"; \
    lsinitrd -f usr/lib/dracut/modules.txt "$img" | sort > /tmp/modules.base; \
    test -s /tmp/modules.base; \
    mkdir /var/roothome; \
    mkdir -p /etc/dracut.conf.d; \
    echo 'sysloglvl=0' > /etc/dracut.conf.d/99-build-no-syslog.conf; \
    DRACUT_NO_XATTR=1 dracut --force --kver "$kver" "$img" > /tmp/dracut.log 2>&1 \
      || { cat /tmp/dracut.log; exit 1; }; \
    rm /etc/dracut.conf.d/99-build-no-syslog.conf; \
    rmdir --ignore-fail-on-non-empty /etc/dracut.conf.d; \
    rmdir /var/roothome; \
    if grep -E 'dracut\[E\]|ERROR' /tmp/dracut.log; then exit 1; fi; \
    lsinitrd -f usr/lib/dracut/modules.txt "$img" | sort > /tmp/modules.new; \
    missing=$(comm -23 /tmp/modules.base /tmp/modules.new); \
    if [ -n "$missing" ]; then echo "dracut modules lost: $missing"; exit 1; fi; \
    grep -qx plymouth /tmp/modules.new; \
    grep -qx drm /tmp/modules.new; \
    lsinitrd "$img" > /tmp/initramfs.lst; \
    grep -q 'plymouth/themes/bgrt/bgrt\.plymouth' /tmp/initramfs.lst; \
    grep -q '/drm/xe/xe\.ko' /tmp/initramfs.lst; \
    grep -q '/drm/i915/i915\.ko' /tmp/initramfs.lst; \
    grep -q 'consolefonts/latarcyrheb-sun32' /tmp/initramfs.lst; \
    if grep -E '/drm/(nouveau|amd|radeon|nova)/|/nova-core/|firmware/(nvidia|amdgpu|radeon)/' /tmp/initramfs.lst; then exit 1; fi; \
    echo "initramfs: $(du -h "$img" | cut -f1), dracut modules: $(wc -l < /tmp/modules.base) -> $(wc -l < /tmp/modules.new)"; \
    rm /tmp/initramfs.lst /tmp/dracut.log /tmp/modules.base /tmp/modules.new

# niri-session still calls import-environment without names; systemd 262 only
# warns. Recheck if the session loses its environment after a systemd update.
RUN niri validate --config /etc/niri/config.kdl

# TEMPORARY: package list to compare with the current image (remove before merge).
RUN rpm -qa --qf 'pkg: %{NAME}\n' | sort

# Explicit, so the image doesn't depend on Fedora's presets.
RUN systemctl enable \
      greetd.service \
      tuned.service \
      tuned-ppd.service \
      bluetooth.service \
      thermald.service \
      intel_lpmd.service \
      firewalld.service \
      flathub-setup.service \
      virtqemud.socket \
      virtnetworkd.socket \
      virtstoraged.socket \
      virtnodedevd.socket \
      virtsecretd.socket

# Every user gets OpenSSH's agent; SSH_AUTH_SOCK comes from environment.d.
RUN systemctl --global enable ssh-agent.socket

# Laptop: no inbound SSH. Start sshd manually when needed.
RUN systemctl disable sshd.service \
    && firewall-offline-cmd --remove-service=ssh \
    && echo "Firewall zone $(firewall-offline-cmd --get-default-zone) allows: $(firewall-offline-cmd --list-services)"

# The base image's tmpfiles config (rpm-ostree-0-integration-opt-usrlocal.conf)
# lists /usr/local/sbin, which the image lacks; on the read-only /usr it would
# fail at every boot, so ship the empty directory.
RUN mkdir -p /usr/local/sbin

# Remove build helpers, caches, and repo metadata; keep service state in /var/lib.
# A random seed must never ship: every install would start from the same one.
# /run and /tmp are runtime-only: tmpfiles recreates their contents at boot.
# Podman mounts .containerenv, secrets and run/systemd/resolve during builds.
# authselect's checksum comes from nss-mdns's install script; the base image
# has none, and authselect works without it.
RUN find /run /tmp -mindepth 1 -maxdepth 1 \
      ! -name .containerenv ! -name secrets ! -name systemd -exec rm -rf {} + \
    && find /run/systemd -mindepth 1 -maxdepth 1 ! -name resolve -exec rm -rf {} + \
    && rm -rf \
      /var/cache/ldconfig \
      /var/cache/libX11 \
      /var/cache/libdnf5 \
      /var/cache/swcatalog \
      /var/lib/authselect \
      /var/lib/dnf/repos \
    && rm -f /var/log/dnf5.log* \
          /var/lib/systemd/random-seed \
          /var/lib/systemd/catalog/database

RUN bootc container lint --fatal-warnings
