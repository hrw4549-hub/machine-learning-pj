#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$EUID" != 0 ]]; then echo 'Run with sudo bash Install-SystemPackages.sh'; exit 1; fi
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=3 update
apt-get -o Acquire::Retries=3 install -y git curl ca-certificates build-essential pkg-config \
  libgl1 libegl1 libglfw3 libosmesa6 libglew-dev libglib2.0-0 ffmpeg tmux
