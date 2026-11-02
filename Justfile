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

# Package names in the image (for diffing against ublue-os/base-main).
packages: build
    sudo podman run --rm localhost/{{image}}:dev rpm -qa --qf '%{NAME}\n' | sort

# Boot this machine into the locally built image (switch back to the
# registry image afterwards with `just switch-registry OWNER`).
switch-local: build
    sudo bootc switch --transport containers-storage localhost/{{image}}:dev

switch-registry owner:
    sudo bootc switch --enforce-container-sigpolicy ghcr.io/{{owner}}/{{image}}:44
