image := "fedora-bootc-niri-noctalia"

# Build the image into root's container storage.
build:
    sudo podman build --pull=newer -t localhost/{{image}}:dev .

# Re-run bootc's checks against the built image.
lint: build
    sudo podman run --rm localhost/{{image}}:dev bootc container lint

# Poke around inside the image.
shell: build
    sudo podman run --rm -it localhost/{{image}}:dev bash

# Package names in the image, one per line, sorted.
# Build output goes to stderr so stdout is only the list.
packages:
    {{just_executable()}} build >&2
    sudo podman run --rm localhost/{{image}}:dev rpm -qa --qf '%{NAME}\n' | LC_ALL=C sort -u

# Boot this machine into the locally built image (switch back to the
# registry image afterwards with `just switch-registry OWNER`).
switch-local: build
    sudo bootc switch --transport containers-storage localhost/{{image}}:dev

switch-registry owner:
    sudo bootc switch --enforce-container-sigpolicy ghcr.io/{{owner}}/{{image}}:45

# Output: iso/output/bootc-fedora-45-bootc-generic-iso-x86_64/
# Installer ISO with the signed :45 image embedded (offline install).
iso:
    #!/usr/bin/env bash
    set -euo pipefail
    repo=ghcr.io/bobby-welch/{{image}}
    # Copy by digest, accepting only our signature: the same containers/image
    # check bootc applies on the installed system, so no cosign needed.
    # Signatures are checked, then not stored: stored ones break the ISO copy.
    digest=$(skopeo inspect --format '{{{{.Digest}}' "docker://$repo:45")
    policy=$(mktemp); trap 'rm -f "$policy"' EXIT
    printf '{"default":[{"type":"reject"}],"transports":{"docker":{"%s":[{"type":"sigstoreSigned","keyPath":"%s","signedIdentity":{"type":"matchRepository"}}]}}}\n' \
      "$repo" "$PWD/cosign.pub" > "$policy"
    sudo skopeo --policy "$policy" --registries.d files/etc/containers/registries.d \
      copy --quiet --remove-signatures "docker://$repo@$digest" "containers-storage:$repo:45"
    echo "payload $digest $(sudo podman run --rm "$repo:45" rpm -q kernel)"
    sudo podman build --pull=newer -t localhost/{{image}}-installer:dev iso/
    # image-builder from Fedora's signed RPM, on the same pinned base.
    # unconfined_t: the host has no osbuild-selinux policy.
    # The osbuild store needs a volume: it gets relabeled, and overlayfs refuses.
    base=$(sed -n 's/^FROM //p' Containerfile)
    mkdir -p iso/output
    sudo podman run --rm --privileged --security-opt label=type:unconfined_t \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      -v image-builder-store:/var/cache/image-builder/store \
      -v "$PWD/iso/output:/output" -w /output \
      -e INSTALLER=localhost/{{image}}-installer:dev -e PAYLOAD="$repo:45" \
      "$base" bash -c 'dnf5 -yq install image-builder > /dev/null \
        && image-builder build --bootc-ref "$INSTALLER" \
             --bootc-installer-payload-ref "$PAYLOAD" \
             --bootc-default-fs ext4 bootc-generic-iso'
    sudo chown -R "$(id -u):$(id -g)" iso/output
    find iso/output -name '*.iso' -exec ls -lh {} +
