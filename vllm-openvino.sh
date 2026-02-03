#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func || \
  curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/refs/heads/main/misc/build.func || \
  curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func || \
  curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVE/raw/branch/main/misc/build.func || \
  curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main/misc/build.func)

APP="vLLM-OpenVINO"
var_tags="${var_tags:-ai}"
var_cpu="${var_cpu:-6}"
var_ram="${var_ram:-16384}"
var_disk="${var_disk:-64}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_gpu="${var_gpu:-yes}"
PIP_EXTRA_INDEX_URL="${PIP_EXTRA_INDEX_URL:-https://download.pytorch.org/whl/cpu}"

header_info "$APP"
variables
color
catch_errors

function install_vllm_openvino() {
  msg_info "Installing system dependencies"
  pct exec "${CTID}" -- bash -c "apt-get update -y"
  pct exec "${CTID}" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-full python3-venv build-essential git curl ca-certificates"
  msg_ok "Installed system dependencies"

  if [[ "${var_gpu}" == "yes" ]]; then
    msg_info "Ensuring Debian repo components for GPU packages"
    pct exec "${CTID}" -- bash -c "set -e; \
      NEED_UPDATE=0; \
      if [[ -f /etc/apt/sources.list.d/vllm-openvino.list ]]; then \
        rm -f /etc/apt/sources.list.d/vllm-openvino.list; \
        NEED_UPDATE=1; \
      fi; \
      if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then \
        if ! grep -q '^Components: main contrib non-free non-free-firmware' /etc/apt/sources.list.d/debian.sources; then \
          sed -i 's/^Components:.*/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources; \
          NEED_UPDATE=1; \
        fi; \
      elif [[ -f /etc/apt/sources.list ]]; then \
        if ! grep -q ' non-free-firmware' /etc/apt/sources.list; then \
          sed -i 's/ main$/ main contrib non-free non-free-firmware/' /etc/apt/sources.list; \
          NEED_UPDATE=1; \
        fi; \
      fi; \
      if [[ \"\${NEED_UPDATE}\" -eq 1 ]]; then apt-get update -y; fi"
    msg_ok "Ensured Debian repo components"

    msg_info "Installing Intel GPU runtime dependencies"
    pct exec "${CTID}" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y \
      ocl-icd-libopencl1"
    pct exec "${CTID}" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y \
      intel-opencl-icd libze1 libze-intel-gpu1" || \
      msg_warn "Intel GPU packages not found in APT. Skipping optional GPU runtime packages."
    pct exec "${CTID}" -- bash -c "getent group render >/dev/null || groupadd -r render"
    pct exec "${CTID}" -- bash -c "getent group video >/dev/null || groupadd -r video"
    pct exec "${CTID}" -- bash -c "usermod -aG render,video root"
    msg_ok "Installed Intel GPU runtime dependencies"
  fi

  msg_info "Installing vLLM with OpenVINO backend"
  pct exec "${CTID}" -- bash -c "python3 -m venv /opt/vllm-venv"
  pct exec "${CTID}" -- bash -c "/opt/vllm-venv/bin/python -m pip install --upgrade pip"
  pct exec "${CTID}" -- bash -c "rm -rf /opt/vllm && git clone https://github.com/vllm-project/vllm.git /opt/vllm"
  pct exec "${CTID}" -- bash -c "cd /opt/vllm && \
    PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL}; \
    if [[ -f requirements-build.txt ]]; then \
      /opt/vllm-venv/bin/python -m pip install -r requirements-build.txt --extra-index-url ${PIP_EXTRA_INDEX_URL}; \
    else \
      /opt/vllm-venv/bin/python -m pip install -r requirements/build.txt --extra-index-url ${PIP_EXTRA_INDEX_URL}; \
    fi"
  pct exec "${CTID}" -- bash -c "cd /opt/vllm && \
    PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL} \
    VLLM_TARGET_DEVICE=openvino \
    /opt/vllm-venv/bin/python -m pip install -v ."
  pct exec "${CTID}" -- bash -c "cd /opt/vllm && git rev-parse HEAD >/opt/vllm_version.txt"
  msg_ok "Installed vLLM with OpenVINO backend"

  msg_info "Configuring OpenVINO runtime environment"
  pct exec "${CTID}" -- bash -c "cat <<'EOF' >/etc/profile.d/vllm-openvino.sh
export VLLM_OPENVINO_DEVICE=GPU
export VLLM_OPENVINO_KVCACHE_SPACE=8
export VLLM_OPENVINO_ENABLE_QUANTIZED_WEIGHTS=ON
EOF"
  pct exec "${CTID}" -- bash -c "chmod 644 /etc/profile.d/vllm-openvino.sh"
  msg_ok "Configured OpenVINO runtime environment"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! pct exec "${CTID}" -- test -d /opt/vllm; then
    msg_error "No vLLM installation found!"
    exit
  fi

  CURRENT="$(pct exec "${CTID}" -- bash -c "cat /opt/vllm_version.txt 2>/dev/null || true")"
  LATEST="$(pct exec "${CTID}" -- bash -c "cd /opt/vllm && git fetch -q origin main && git rev-parse origin/main")"

  if [[ -z "${CURRENT}" || "${CURRENT}" != "${LATEST}" ]]; then
    msg_info "Updating vLLM to latest main"
    pct exec "${CTID}" -- bash -c "cd /opt/vllm && git reset --hard origin/main"
    pct exec "${CTID}" -- bash -c "cd /opt/vllm && \
      PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL}; \
      if [[ -f requirements-build.txt ]]; then \
        /opt/vllm-venv/bin/python -m pip install -r requirements-build.txt --extra-index-url ${PIP_EXTRA_INDEX_URL}; \
      else \
        /opt/vllm-venv/bin/python -m pip install -r requirements/build.txt --extra-index-url ${PIP_EXTRA_INDEX_URL}; \
      fi"
    pct exec "${CTID}" -- bash -c "cd /opt/vllm && \
      PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL} \
      VLLM_TARGET_DEVICE=openvino \
      /opt/vllm-venv/bin/python -m pip install -v ."
    pct exec "${CTID}" -- bash -c "cd /opt/vllm && git rev-parse HEAD >/opt/vllm_version.txt"
    msg_ok "Updated vLLM to ${LATEST}"
  else
    msg_ok "No update required. vLLM is already at ${CURRENT}"
  fi
  exit
}

start
build_container
description
install_vllm_openvino

IP="$(pct exec "${CTID}" -- bash -c "hostname -I | awk '{print \$1}'")"
msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Container IP:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}${IP}${CL}"
echo -e "${INFO}${YW} Example vLLM OpenVINO launch:${CL}"
echo -e "${TAB}source /etc/profile.d/vllm-openvino.sh${CL}"
echo -e "${TAB}vllm serve --model meta-llama/Llama-2-7b-chat-hf --enable-prefix-caching --enable-chunked-prefill${CL}"