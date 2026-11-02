#!/usr/bin/bash
# Make niri-session import the full login environment into the systemd user
# manager. Fails the build if upstream changes the line, so the patch gets
# reviewed (and dropped once upstream no longer needs it).
set -euo pipefail

file=${1:-/usr/bin/niri-session}
original='    systemctl --user import-environment'
replacement=$(cat <<'LINE'
    systemctl --user import-environment $(printenv | cut -d'=' -f1 | tr '\n' ' ')
LINE
)

count=$(grep -cxF -- "$original" "$file" || true)
if [[ "$count" != 1 ]]; then
    echo "niri-session changed upstream; review the compatibility patch" >&2
    exit 1
fi

ORIG="$original" REPL="$replacement" awk '
    $0 == ENVIRON["ORIG"] { print ENVIRON["REPL"]; next }
    { print }
' "$file" > "$file.new"
cat "$file.new" > "$file"   # keep the original mode and ownership
rm -f "$file.new"

grep -qxF -- "$replacement" "$file"
bash -n "$file"
echo "Applied niri-session environment-import patch"
