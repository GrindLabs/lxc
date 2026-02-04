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
var_version="${var_version:-24.04}"
var_gpu="${var_gpu:-yes}"
PIP_EXTRA_INDEX_URL="${PIP_EXTRA_INDEX_URL:-https://download.pytorch.org/whl/cpu}"

header_info "$APP"
variables
color
catch_errors

function install_vllm_openvino() {
  msg_info "Installing vLLM OpenVINO"
  pct exec "${CTID}" -- bash -c "apt-get update -y"
  pct exec "${CTID}" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-venv git curl ca-certificates build-essential"
  pct exec "${CTID}" -- bash -c "GPU_PKGS=\"\"; \
    for P in ocl-icd-libopencl1 intel-opencl-icd libze1 libze-intel-gpu1 intel-compute-runtime; do \
      if apt-cache show \"\${P}\" >/dev/null 2>&1; then GPU_PKGS=\"\${GPU_PKGS} \${P}\"; fi; \
    done; \
    if [[ -n \"\${GPU_PKGS}\" ]]; then \
      DEBIAN_FRONTEND=noninteractive apt-get install -y \${GPU_PKGS}; \
    else \
      msg_warn \"No Intel GPU runtime packages available in APT.\"; \
    fi"
  pct exec "${CTID}" -- bash -c "python3 -m venv /opt/vllm-venv"
  pct exec "${CTID}" -- bash -c "/opt/vllm-venv/bin/python -m pip install --upgrade pip"
  pct exec "${CTID}" -- bash -c "rm -rf /opt/vllm-openvino && git clone https://github.com/vllm-project/vllm-openvino.git /opt/vllm-openvino"
  pct exec "${CTID}" -- bash -c "cd /opt/vllm-openvino && \
    PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL} \
    VLLM_TARGET_DEVICE=openvino \
    /opt/vllm-venv/bin/python -m pip install -v ."
  pct exec "${CTID}" -- bash -c "cat <<'EOF' >/etc/profile.d/vllm-openvino.sh
export VLLM_OPENVINO_DEVICE=GPU
export VLLM_OPENVINO_ENABLE_QUANTIZED_WEIGHTS=ON
export VLLM_USE_V1=1
export VLLM_OPENVINO_KVCACHE_SPACE=8
export VLLM_OPENVINO_KV_CACHE_PRECISION=i8
export VLLM_TARGET_DEVICE=openvino
export PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL}
EOF"
  pct exec "${CTID}" -- bash -c "chmod 644 /etc/profile.d/vllm-openvino.sh"
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

  msg_info "Updating vLLM OpenVINO"
  pct exec "${CTID}" -- bash -c "apt-get update -y"
  pct exec "${CTID}" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-venv git curl ca-certificates build-essential"
  pct exec "${CTID}" -- bash -c "GPU_PKGS=\"\"; \
    for P in ocl-icd-libopencl1 intel-opencl-icd libze1 libze-intel-gpu1 intel-compute-runtime; do \
      if apt-cache show \"\${P}\" >/dev/null 2>&1; then GPU_PKGS=\"\${GPU_PKGS} \${P}\"; fi; \
    done; \
    if [[ -n \"\${GPU_PKGS}\" ]]; then \
      DEBIAN_FRONTEND=noninteractive apt-get install -y \${GPU_PKGS}; \
    else \
      msg_warn \"No Intel GPU runtime packages available in APT.\"; \
    fi"
  pct exec "${CTID}" -- bash -c "/opt/vllm-venv/bin/python -m pip install --upgrade pip"
  pct exec "${CTID}" -- bash -c "cd /opt/vllm-openvino && git pull --ff-only"
  pct exec "${CTID}" -- bash -c "cd /opt/vllm-openvino && \
    PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL} \
    VLLM_TARGET_DEVICE=openvino \
    /opt/vllm-venv/bin/python -m pip install -v ."
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
