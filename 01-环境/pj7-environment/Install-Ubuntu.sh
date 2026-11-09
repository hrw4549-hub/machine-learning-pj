#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PJ7_HOME:-$HOME/pj7}"
CONDA_DIR="${PJ7_CONDA_HOME:-$HOME/.local/share/pj7-miniforge}"
ENV_DIR="$PROJECT_DIR/.conda"
ACT_COMMIT='742c753c0d4a5d87076c8f69e5628c79a8cc5488'
mkdir -p "$PROJECT_DIR" "$SCRIPT_DIR/logs"
exec > >(tee -a "$SCRIPT_DIR/logs/ubuntu-install.log") 2>&1
trap 'echo "FAILED at line $LINENO. Correct the error and rerun this script."' ERR
if [[ "$(uname -m)" != "x86_64" ]]; then echo 'This installer targets Ubuntu x86_64.'; exit 1; fi
if [[ "$EUID" == 0 ]]; then
  echo 'Run as a regular Ubuntu user with sudo access, not root.'; exit 1
fi
if [[ "${PJ7_SKIP_SYSTEM_PACKAGES:-0}" != 1 ]]; then
  sudo bash "$SCRIPT_DIR/Install-SystemPackages.sh"
fi

if [[ ! -x "$CONDA_DIR/bin/conda" ]]; then
  installer="$PROJECT_DIR/Miniforge3-25.3.1-0-Linux-x86_64.sh"
  cached_installer="$SCRIPT_DIR/downloads/Miniforge3-25.3.1-0-Linux-x86_64.sh"
  if [[ -f "$cached_installer" ]]; then
    cp "$cached_installer" "$installer"
  else
    curl --fail --location --retry 3 --output "$installer" \
      'https://github.com/conda-forge/miniforge/releases/download/25.3.1-0/Miniforge3-Linux-x86_64.sh'
  fi
  echo "376b160ed8130820db0ab0f3826ac1fc85923647f75c1b8231166e3d559ab768  $installer" | sha256sum --check
  bash "$installer" -b -p "$CONDA_DIR"
fi
if [[ ! -x "$ENV_DIR/bin/python" ]]; then
  "$CONDA_DIR/bin/conda" create --yes --prefix "$ENV_DIR" --override-channels -c conda-forge python=3.10 pip
fi
source "$CONDA_DIR/etc/profile.d/conda.sh"
conda activate "$ENV_DIR"
python -m pip install 'pip==25.0.1' 'setuptools==75.8.0' 'wheel==0.45.1'
python -m pip install 'torch==2.5.1' 'torchvision==0.20.1' --index-url https://download.pytorch.org/whl/cu121
if [[ -f "$SCRIPT_DIR/requirements-linux.lock.txt" ]]; then
  python -m pip install -r "$SCRIPT_DIR/requirements-linux.lock.txt"
else
  python -m pip install -r "$SCRIPT_DIR/requirements.txt"
fi
mkdir -p "$PROJECT_DIR/src" "$PROJECT_DIR/data" "$PROJECT_DIR/runs"
if [[ ! -d "$PROJECT_DIR/src/act/.git" ]]; then
  if [[ -f "$SCRIPT_DIR/act-source.bundle" ]]; then
    echo "7ad1d1ec064842c64bcad00738b50bef746d9534833619b8c98720b36b5c0a38  $SCRIPT_DIR/act-source.bundle" | sha256sum --check
    git clone "$SCRIPT_DIR/act-source.bundle" "$PROJECT_DIR/src/act"
    git -C "$PROJECT_DIR/src/act" remote set-url origin https://github.com/tonyzhaozh/act.git
  else
    git -c http.connectTimeout=20 -c http.lowSpeedLimit=100 -c http.lowSpeedTime=60 clone https://github.com/tonyzhaozh/act.git "$PROJECT_DIR/src/act"
  fi
  git -C "$PROJECT_DIR/src/act" checkout --detach "$ACT_COMMIT"
fi
if [[ "$(git -C "$PROJECT_DIR/src/act" rev-parse HEAD)" != "$ACT_COMMIT" ]]; then
  echo "Existing ACT source differs from the baseline commit $ACT_COMMIT; leaving it untouched."
  exit 1
fi
python -m pip install --no-deps --no-build-isolation -e "$PROJECT_DIR/src/act/detr"
python -m pip check
python -m pip freeze > "$SCRIPT_DIR/logs/requirements-resolved.txt"
git -C "$PROJECT_DIR/src/act" rev-parse HEAD > "$SCRIPT_DIR/logs/act-commit.txt"
conda list --explicit > "$SCRIPT_DIR/logs/conda-explicit.txt"
cat > "$PROJECT_DIR/activate.sh" <<EOF
source "$CONDA_DIR/etc/profile.d/conda.sh"
conda activate "$ENV_DIR"
export PYTHONPATH="$PROJECT_DIR/src/act:\${PYTHONPATH:-}"
EOF
echo "Installed. Activate with: source \"$PROJECT_DIR/activate.sh\""
echo 'Now run verify_environment.py. Installation alone does not confirm rendering or ACT Lift integration.'
