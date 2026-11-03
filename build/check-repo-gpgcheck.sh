#!/usr/bin/bash
# Fails the build if any repo section doesn't verify package signatures,
# including repos that packages or COPRs add later.
set -euo pipefail
awk '
  function check() { if (section != "" && !ok) bad = bad "\n  " file " " section }
  /^\[/ { check(); section = $0; file = FILENAME; ok = 0; next }
  /^[[:space:]]*(pkg_)?gpgcheck[[:space:]]*=[[:space:]]*(1|[Tt]rue|[Yy]es)[[:space:]]*$/ { ok = 1 }
  END { check(); if (bad != "") { print "Repos without gpgcheck=1:" bad > "/dev/stderr"; exit 1 } }
' /etc/yum.repos.d/*.repo
