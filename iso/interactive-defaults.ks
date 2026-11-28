# Offline: install the payload embedded in the ISO (verified by `just iso`).
# The installed system then takes updates from the registry.
bootc --source-imgref containers-storage:ghcr.io/bobby-welch/fedora-bootc-niri-noctalia:45 --target-imgref ghcr.io/bobby-welch/fedora-bootc-niri-noctalia:45

# Keep the image's firewall; Anaconda's default re-opens SSH.
firewall --use-system-defaults

# Anaconda writes accounts, hostname and the home directory with generic
# SELinux labels, and restorecon is a silent no-op in its chroot, so label
# them with setfiles and the policy's file contexts.
# Anaconda's fstab line for / can't be remounted under composefs
# (systemd-remount-fs fails); the kernel command line already mounts root.
# Without a / line, bootc's fstab generator rewrites fstab at every boot
# (so mount warns that systemd's copy is stale) unless it finds its stamp.
%post --erroronfail
set -eux
sed -i -E '/^[^#[:space:]]+[[:space:]]+\/[[:space:]]/d' /etc/fstab
echo '# Updated by bootc-fstab-edit.service: / removed by the installer, root comes from the kernel command line' >> /etc/fstab
setfiles -F /etc/selinux/targeted/contexts/files/file_contexts /etc /var/home /var/roothome
ls -dZ /etc/passwd /var/home/*
cat /etc/fstab
%end
