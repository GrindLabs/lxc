#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2011-2026 GrindLabs
# Author: Alexandre "Todi" Ferreira <alexandresgf@gmail.com>
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/grindlabs/lxc

APP="vLLM-OpenVINO"
var_tags="${var_tags:-ai}"
var_cpu="${var_cpu:-6}"
var_ram="${var_ram:-16384}"
var_disk="${var_disk:-64}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-22.04}"
var_gpu="${var_gpu:-yes}"
PIP_EXTRA_INDEX_URL="${PIP_EXTRA_INDEX_URL:-https://download.pytorch.org/whl/cpu}"

header_info "$APP"
variables
color
catch_errors

function install_vllm_openvino() {
  msg_info "Updating system packages"
  pct exec "${CTID}" -- bash -c "apt-get update -y"
  pct exec "${CTID}" -- bash -c "apt-get install -y python3-pip python3-venv gnupg git wget curl ca-certificates build-essential"

  msg_info "Installing vLLM OpenVINO dependencies"
  pct exec "${CTID}" -- bash -c "wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg"
  pct exec "${CTID}" -- bash -c '. /etc/os-release; \
    if [[ ! " jammy " =~ " ${VERSION_CODENAME} " ]]; then \
      echo "Ubuntu version ${VERSION_CODENAME} not supported"; \
    else \
      wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | \
      gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg; \
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu ${VERSION_CODENAME}/lts/2350 unified" | \
      tee /etc/apt/sources.list.d/intel-gpu-${VERSION_CODENAME}.list; \
      apt-get update; \
    fi'
  pct exec "${CTID}" -- bash -c "if ! apt-get install -y \
    linux-headers-\$(uname -r) \
    linux-modules-extra-\$(uname -r) \
    flex bison \
    intel-fw-gpu intel-i915-dkms xpu-smi; then \
      echo \"Skipping kernel header modules (not available for \$(uname -r)).\"; \
    fi"
  pct exec "${CTID}" -- bash -c "apt-get install -y \
    intel-opencl-icd intel-level-zero-gpu level-zero \
    intel-media-va-driver-non-free libmfxgen1 libvpl2 \
    libegl-mesa0 libegl1-mesa libegl1-mesa-dev libgbm1 libgl1-mesa-dev libgl1-mesa-dri \
    libglapi-mesa libgles2-mesa-dev libglx-mesa0 libigdgmm12 libxatracker2 mesa-va-drivers \
    mesa-vdpau-drivers mesa-vulkan-drivers va-driver-all vainfo hwinfo clinfo"
  pct exec "${CTID}" -- bash -c "apt-get install -y \
    libigc-dev intel-igc-cm libigdfcl-dev libigfxcmrt-dev level-zero-dev"
  pct exec "${CTID}" -- bash -c "apt-get install -y ocl-icd-libopencl1"
  pct exec "${CTID}" -- bash -c "mkdir -p /tmp/neo && cd /tmp/neo && \
    wget https://github.com/intel/intel-graphics-compiler/releases/download/v2.27.10/intel-igc-core-2_2.27.10+20617_amd64.deb && \
    wget https://github.com/intel/intel-graphics-compiler/releases/download/v2.27.10/intel-igc-opencl-2_2.27.10+20617_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/intel-ocloc-dbgsym_26.01.36711.4-0_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/intel-ocloc_26.01.36711.4-0_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/intel-opencl-icd-dbgsym_26.01.36711.4-0_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/intel-opencl-icd_26.01.36711.4-0_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/libigdgmm12_22.9.0_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/libze-intel-gpu1-dbgsym_26.01.36711.4-0_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/libze-intel-gpu1_26.01.36711.4-0_amd64.deb && \
    dpkg -i *.deb"
  pct exec "${CTID}" -- bash -c "apt-get install -y \
    intel-igc-core intel-igc-opencl intel-ocloc intel-opencl-icd libigdgmm12 libze-intel-gpu1"
  msg_ok "Installed vLLM OpenVINO dependencies"

  msg_info "Installing vLLM OpenVINO"
  pct exec "${CTID}" -- bash -c "python3 -m venv /opt/vllm-venv"
  pct exec "${CTID}" -- bash -c "/opt/vllm-venv/bin/python -m pip install --upgrade pip"
  pct exec "${CTID}" -- bash -c "rm -rf /opt/vllm-openvino && git clone https://github.com/vllm-project/vllm-openvino.git /opt/vllm-openvino"
  pct exec "${CTID}" -- bash -c "cd /opt/vllm-openvino && \
    VLLM_TARGET_DEVICE=\"empty\" PIP_EXTRA_INDEX_URL=\"${PIP_EXTRA_INDEX_URL}\" /opt/vllm-venv/bin/python -m pip install -v ."
  pct exec "${CTID}" -- bash -c "/opt/vllm-venv/bin/python -m pip uninstall -y triton"
  msg_ok "Installed vLLM OpenVINO"

  msg_info "Configuring vLLM OpenVINO"
  pct exec "${CTID}" -- bash -c "cat <<'EOF' >/etc/profile.d/vllm-openvino.sh
export VLLM_OPENVINO_DEVICE=GPU
export VLLM_OPENVINO_ENABLE_QUANTIZED_WEIGHTS=ON
export VLLM_USE_V1=1
export VLLM_OPENVINO_KVCACHE_SPACE=8
export VLLM_OPENVINO_KV_CACHE_PRECISION=i8
export VLLM_TARGET_DEVICE=openvino
export PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL}
export VLLM_VENV=/opt/vllm-venv
export PATH=\$VLLM_VENV/bin:\$PATH
EOF"
  pct exec "${CTID}" -- bash -c "chmod 644 /etc/profile.d/vllm-openvino.sh"
  msg_ok "Configured vLLM OpenVINO"

  msg_info "Running GPU benchmark"
  pct exec "${CTID}" -- bash -c "git clone https://github.com/vllm-project/vllm.git /tmp/vllm && cd /tmp/vllm \
    VLLM_OPENVINO_DEVICE=GPU VLLM_OPENVINO_KV_CACHE_PRECISION=i8 VLLM_OPENVINO_ENABLE_QUANTIZED_WEIGHTS=ON && \
    /opt/vllm-openvino/bin/python benchmarks/benchmark_throughput.py --model meta-llama/Llama-2-7b-chat-hf --dataset benchmarks/ShareGPT_V3_unfiltered_cleaned_split.json"
  msg_ok "Ran GPU benchmark"

  msg_info "Enabling root console autologin"
  pct exec "${CTID}" -- bash -c "passwd -d root >/dev/null 2>&1 || true"
  pct exec "${CTID}" -- bash -c "mkdir -p /etc/systemd/system/getty@tty1.service.d"
  pct exec "${CTID}" -- bash -c "cat <<'EOF' >/etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF"
  pct exec "${CTID}" -- bash -c "systemctl daemon-reload && systemctl restart getty@tty1"
  msg_ok "Root console autologin enabled"

  msg_ok "Installed vLLM OpenVINO"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! pct exec "${CTID}" -- test -d /opt/vllm-openvino; then
    msg_error "No vLLM OpenVINO installation found!"
    exit
  fi

  msg_info "Updating system packages"
  pct exec "${CTID}" -- bash -c "apt-get update -y"
  pct exec "${CTID}" -- bash -c "apt-get install -y python3-pip python3-venv gnupg git wget curl ca-certificates build-essential"

  msg_info "Updating vLLM OpenVINO dependencies"
  pct exec "${CTID}" -- bash -c "wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg"
  pct exec "${CTID}" -- bash -c '. /etc/os-release; \
    if [[ ! " jammy " =~ " ${VERSION_CODENAME} " ]]; then \
      echo "Ubuntu version ${VERSION_CODENAME} not supported"; \
    else \
      wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | \
      gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg; \
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu ${VERSION_CODENAME}/lts/2350 unified" | \
      tee /etc/apt/sources.list.d/intel-gpu-${VERSION_CODENAME}.list; \
      apt-get update; \
    fi'
  pct exec "${CTID}" -- bash -c "if ! apt-get install -y \
    linux-headers-\$(uname -r) \
    linux-modules-extra-\$(uname -r) \
    flex bison \
    intel-fw-gpu intel-i915-dkms xpu-smi; then \
      echo \"Skipping kernel header modules (not available for \$(uname -r)).\"; \
    fi"
  pct exec "${CTID}" -- bash -c "apt-get install -y \
    intel-opencl-icd intel-level-zero-gpu level-zero \
    intel-media-va-driver-non-free libmfxgen1 libvpl2 \
    libegl-mesa0 libegl1-mesa libegl1-mesa-dev libgbm1 libgl1-mesa-dev libgl1-mesa-dri \
    libglapi-mesa libgles2-mesa-dev libglx-mesa0 libigdgmm12 libxatracker2 mesa-va-drivers \
    mesa-vdpau-drivers mesa-vulkan-drivers va-driver-all vainfo hwinfo clinfo"
  pct exec "${CTID}" -- bash -c "apt-get install -y \
    libigc-dev intel-igc-cm libigdfcl-dev libigfxcmrt-dev level-zero-dev"
  pct exec "${CTID}" -- bash -c "apt-get install -y ocl-icd-libopencl1"
  pct exec "${CTID}" -- bash -c "mkdir -p /tmp/neo && cd /tmp/neo && \
    wget https://github.com/intel/intel-graphics-compiler/releases/download/v2.27.10/intel-igc-core-2_2.27.10+20617_amd64.deb && \
    wget https://github.com/intel/intel-graphics-compiler/releases/download/v2.27.10/intel-igc-opencl-2_2.27.10+20617_amd64.deb && \
    # NOTE: not working 404 status code
    # wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/intel-ocloc-dbgsym_26.01.36711.4-0_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/intel-ocloc_26.01.36711.4-0_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/intel-opencl-icd-dbgsym_26.01.36711.4-0_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/intel-opencl-icd_26.01.36711.4-0_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/libigdgmm12_22.9.0_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/libze-intel-gpu1-dbgsym_26.01.36711.4-0_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/26.01.36711.4/libze-intel-gpu1_26.01.36711.4-0_amd64.deb && \
    dpkg -i *.deb"
  pct exec "${CTID}" -- bash -c "apt-get install -y \
    intel-igc-core intel-igc-opencl intel-ocloc intel-opencl-icd libigdgmm12 libze-intel-gpu1"
  msg_ok "Updated vLLM OpenVINO dependencies"

  msg_info "Updating vLLM OpenVINO"
  if ! pct exec "${CTID}" -- test -x /opt/vllm-venv/bin/python; then
    pct exec "${CTID}" -- bash -c "python3 -m venv /opt/vllm-venv"
  fi
  pct exec "${CTID}" -- bash -c "/opt/vllm-venv/bin/python -m pip install --upgrade pip"
  pct exec "${CTID}" -- bash -c "cd /opt/vllm-openvino && git pull --ff-only"
  pct exec "${CTID}" -- bash -c "VLLM_TARGET_DEVICE=\"empty\" PIP_EXTRA_INDEX_URL=\"${PIP_EXTRA_INDEX_URL}\" /opt/vllm-venv/bin/python -m pip install -v ."
  pct exec "${CTID}" -- bash -c "/opt/vllm-venv/bin/python -m pip uninstall -y triton"
  msg_ok "Updated vLLM OpenVINO"
  exit
}

start
build_container
description
install_vllm_openvino

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
CONTAINER_IP=$(pct exec "${CTID}" -- bash -c "hostname -I | awk '{print \$1}'")
if [[ -n "${CONTAINER_IP}" ]]; then
  echo -e "${INFO}${YW} Container IP: ${CONTAINER_IP}${CL}"
else
  echo -e "${INFO}${YW} Container IP: unavailable${CL}"
fi
