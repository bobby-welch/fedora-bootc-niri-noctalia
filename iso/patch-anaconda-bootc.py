#!/usr/bin/env python3
"""Let Anaconda's bootc source install a local image without a network.

Anaconda's bootc source always says it needs a network, so the installer
shows a "We'll need network access" screen and blocks Begin Installation
on a machine with no network device, although this ISO installs from
local container storage. The ostreecontainer source already requires a
network only for registry images; this gives bootc the same rule.

Fails the build if the upstream code changes or the patched source doesn't
behave as expected, including for this ISO's kickstart. Drop it once
Anaconda fixes this upstream.
"""
import glob
import py_compile
import re
import sys

PATTERN = "/usr/lib*/python3*/site-packages/pyanaconda/modules/payloads/source/bootc/bootc.py"
KICKSTART = "/usr/share/anaconda/interactive-defaults.ks"

OLD = '''    def network_required(self):
        """Does the source require a network?

        :return: True or False
        """
        return True
'''

NEW = '''    def network_required(self):
        """Does the source require a network?

        :return: True or False
        """
        # Patched by fedora-bootc-niri-noctalia (iso/patch-anaconda-bootc.py):
        # only registry images need a network; no transport means a registry.
        local = ("containers-storage:", "oci:", "oci-archive:", "dir:")
        return not self.configuration.sourceImgRef.startswith(local)
'''


def fail(message):
    sys.exit(f"patch-anaconda-bootc: {message}")


def patch():
    paths = glob.glob(PATTERN)
    if len(paths) != 1:
        fail(f"expected one bootc.py, found {paths}")
    path = paths[0]

    with open(path, encoding="utf-8") as f:
        text = f.read()
    if text.count(OLD) != 1:
        fail(f"{path} changed upstream; review the patch")
    with open(path, "w", encoding="utf-8") as f:
        f.write(text.replace(OLD, NEW))

    # Refresh the bytecode Fedora ships (.pyc and .opt-1.pyc)
    for level in (0, 1):
        py_compile.compile(path, optimize=level, doraise=True)
    print(f"patch-anaconda-bootc: patched {path}")


def needs_network(ref):
    """Ask the patched module, as Anaconda would."""
    from pyanaconda.modules.common.structures.bootc import BootcConfigurationData
    from pyanaconda.modules.payloads.source.bootc.bootc import BootcSourceModule

    data = BootcConfigurationData()
    data.sourceImgRef = ref
    source = BootcSourceModule()
    source.set_configuration(data)
    return source.network_required


def self_test():
    with open(KICKSTART, encoding="utf-8") as f:
        match = re.search(r"^bootc\s.*--source-imgref[ =](\S+)", f.read(), re.M)
    if not match:
        fail(f"no bootc --source-imgref in {KICKSTART}")

    cases = {
        match.group(1): False,  # this ISO's embedded image
        "oci:/run/install/image": False,
        "registry:quay.io/fedora/fedora-bootc:45": True,
        "quay.io/fedora/fedora-bootc:45": True,
    }
    for ref, expected in cases.items():
        actual = needs_network(ref)
        if actual is not expected:
            fail(f"network_required for {ref!r} is {actual}, expected {expected}")
    print(f"patch-anaconda-bootc: self-test passed ({len(cases)} cases)")


if __name__ == "__main__":
    patch()
    self_test()
