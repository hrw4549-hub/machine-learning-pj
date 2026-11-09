#!/usr/bin/env bash
# Optional workaround only for hosts where the whole Windows drive fails to mount.
set -Eeuo pipefail
if [[ "$EUID" != 0 ]]; then echo 'Run this script as root.'; exit 1; fi
windows_path="${1:?Pass the Windows project folder, e.g. D:\\machine learning}"
mount_dir="${2:-/mnt/project}"
mkdir -p "$mount_dir"
if ! mountpoint -q "$mount_dir"; then
  mount -t drvfs "$windows_path" "$mount_dir"
fi
escaped_source="$(printf '%s' "$windows_path" | sed 's/\\/\\134/g; s/ /\\040/g')"
escaped_target="$(printf '%s' "$mount_dir" | sed 's/ /\\040/g')"
if ! grep -Fq "$escaped_source $escaped_target drvfs " /etc/fstab; then
  cp -a /etc/fstab /etc/fstab.pj7-backup
  printf '\n%s %s drvfs defaults,nofail 0 0\n' "$escaped_source" "$escaped_target" >> /etc/fstab
fi
test -d "$mount_dir/pj7-environment"
echo "Project mount configured at $mount_dir."
