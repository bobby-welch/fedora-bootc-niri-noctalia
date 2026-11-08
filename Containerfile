# Renovate pins this to a digest and auto-merges digest bumps.
# Fedora release upgrades (45 -> 46) are a deliberate manual change.
FROM quay.io/fedora/fedora-bootc:45@sha256:0c0d822e8545efe843e72f4a216295e9fd3d8a8213709fff0db6844b5d9aad29

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
      fwupd \
      upower \
      thermald \
      intel-lpmd \
      bluez \
      NetworkManager-wifi \
      NetworkManager-bluetooth \
      zram-generator-defaults \
      firewalld \
      cups \
    && dnf5 clean all

# Desktop, applications, and CLI tools.
RUN dnf5 --setopt=install_weak_deps=False install -y \
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
      gh \
      just \
      chezmoi \
      neovim \
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
# no daemon runs until a VM tool connects. Weak deps on, matching the
# setup the installer was tested with.
RUN dnf5 install -y \
      virt-manager \
      virt-install \
      virt-viewer \
      libvirt-daemon-kvm \
      libvirt-daemon-config-network \
      qemu-kvm \
      edk2-ovmf \
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
RUN cat /tmp/build/1password-groups >> /usr/lib/group \
    && test "$(getent group onepassword | cut -d: -f3)" = 950 \
    && test "$(getent group onepassword-mcp | cut -d: -f3)" = 951

RUN dnf5 --setopt=install_weak_deps=False install -y 1password \
    && dnf5 clean all

# IosevkaTerm Nerd Font Mono: pinned release, verified checksum.
RUN set -eu; \
    archive=/tmp/IosevkaTerm.tar.xz; \
    fontdir=/usr/share/fonts/iosevka-term-nerd-font; \
    curl --fail --location --show-error --silent --output "$archive" \
      "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONTS_VERSION}/IosevkaTerm.tar.xz"; \
    echo "${NERD_FONTS_SHA256}  ${archive}" | sha256sum --check; \
    mkdir -p "$fontdir"; \
    tar --no-same-owner -xJf "$archive" -C "$fontdir" \
      IosevkaTermNerdFontMono-Regular.ttf \
      IosevkaTermNerdFontMono-Bold.ttf \
      IosevkaTermNerdFontMono-Italic.ttf \
      IosevkaTermNerdFontMono-BoldItalic.ttf; \
    chmod 0644 "$fontdir"/*.ttf; \
    fc-cache -f "$fontdir"; \
    rm -f "$archive"

# System configuration. Also restores 1password.repo, which its RPM rewrites.
COPY files/ /
COPY cosign.pub /etc/pki/containers/fedora-bootc-niri-noctalia.pub

RUN test "$(stat -c '%g:%a' /opt/1Password/1Password-BrowserSupport)" = 950:2755 \
    && test "$(stat -c '%g:%a' /opt/1Password/1password-mcp)" = 951:2755 \
    && grep -qx 'gpgcheck=1' /etc/yum.repos.d/1password.repo \
    && grep -qx 'repo_gpgcheck=1' /etc/yum.repos.d/1password.repo \
    && /tmp/build/check-repo-gpgcheck.sh \
    && yq -e '.default[0].type == "reject"' /etc/containers/policy.json > /dev/null

# niri-session still calls import-environment without names; systemd 262 only
# warns. Recheck if the session loses its environment after a systemd update.
RUN niri validate --config /etc/niri/config.kdl

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
      virtstoraged.socket

# Laptop: no inbound SSH. Start sshd manually when needed.
RUN systemctl disable sshd.service \
    && firewall-offline-cmd --remove-service=ssh \
    && echo "Firewall zone $(firewall-offline-cmd --get-default-zone) allows: $(firewall-offline-cmd --list-services)"

# Remove build helpers, caches, and repo metadata; keep service state in /var/lib.
# A random seed must never ship: every install would start from the same one.
# /run and /tmp are runtime-only: tmpfiles recreates their contents at boot.
# Podman mounts .containerenv, secrets and run/systemd/resolve during builds.
RUN find /run /tmp -mindepth 1 -maxdepth 1 \
      ! -name .containerenv ! -name secrets ! -name systemd -exec rm -rf {} + \
    && find /run/systemd -mindepth 1 -maxdepth 1 ! -name resolve -exec rm -rf {} + \
    && rm -rf \
      /var/cache/ldconfig \
      /var/cache/libX11 \
      /var/cache/libdnf5 \
      /var/cache/swcatalog \
      /var/lib/dnf/repos \
    && rm -f /var/log/dnf5.log* \
          /var/lib/systemd/random-seed \
          /var/lib/systemd/catalog/database

RUN bootc container lint
