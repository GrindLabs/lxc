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

function msg_info_nl() {
  echo -e "\n"
  msg_info "$1"
  echo -e "\n"
}

function pct_exec_silent() {
  pct exec "${CTID}" -- bash -c "$1" >/dev/null
}

function pct_exec_silent_raw() {
  pct exec "${CTID}" -- "$@" >/dev/null
}

function install_vllm_openvino() {
  msg_info_nl "Installing system dependencies"
  pct_exec_silent "apt-get update -y"
  pct_exec_silent "DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-full python3-venv build-essential git curl ca-certificates"
  msg_ok "Installed system dependencies"

  if [[ "${var_gpu}" == "yes" ]]; then
    msg_info_nl "Ensuring Debian repo components for GPU packages"
    pct_exec_silent "CODENAME=\$(. /etc/os-release; echo \"\${VERSION_CODENAME}\"); \
      if [[ -n \"\${CODENAME}\" ]]; then \
        cat <<EOF >/etc/apt/sources.list.d/vllm-openvino.list
deb http://deb.debian.org/debian \${CODENAME} main contrib non-free non-free-firmware
deb http://deb.debian.org/debian \${CODENAME}-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security \${CODENAME}-security main contrib non-free non-free-firmware
EOF
      fi"
    pct_exec_silent "apt-get update -y"
    msg_ok "Ensured Debian repo components"

    msg_info_nl "Installing Intel GPU runtime dependencies"
    pct_exec_silent "DEBIAN_FRONTEND=noninteractive apt-get install -y \
      ocl-icd-libopencl1"
    pct_exec_silent "DEBIAN_FRONTEND=noninteractive apt-get install -y \
      intel-opencl-icd libze1 libze-intel-gpu1" || \
      msg_warn "Intel GPU packages not found in APT. Skipping optional GPU runtime packages."
    pct_exec_silent "getent group render >/dev/null || groupadd -r render"
    pct_exec_silent "getent group video >/dev/null || groupadd -r video"
    pct_exec_silent "usermod -aG render,video root"
    msg_ok "Installed Intel GPU runtime dependencies"
  fi

  msg_info_nl "Installing vLLM with OpenVINO backend"
  pct_exec_silent "python3 -m venv /opt/vllm-venv"
  pct_exec_silent "/opt/vllm-venv/bin/python -m pip install --upgrade pip"
  pct_exec_silent "rm -rf /opt/vllm && git clone https://github.com/vllm-project/vllm.git /opt/vllm"
  pct_exec_silent "cd /opt/vllm && \
    PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL}; \
    if [[ -f requirements-build.txt ]]; then \
      /opt/vllm-venv/bin/python -m pip install -r requirements-build.txt --extra-index-url ${PIP_EXTRA_INDEX_URL}; \
    else \
      /opt/vllm-venv/bin/python -m pip install -r requirements/build.txt --extra-index-url ${PIP_EXTRA_INDEX_URL}; \
    fi"
  pct_exec_silent "cd /opt/vllm && \
    PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL} \
    VLLM_TARGET_DEVICE=openvino \
    /opt/vllm-venv/bin/python -m pip install -v ."
  pct_exec_silent "cd /opt/vllm && git rev-parse HEAD >/opt/vllm_version.txt"
  msg_ok "Installed vLLM with OpenVINO backend"

  msg_info_nl "Configuring OpenVINO runtime environment"
  pct_exec_silent "cat <<'EOF' >/etc/profile.d/vllm-openvino.sh
export VLLM_OPENVINO_DEVICE=GPU
export VLLM_OPENVINO_KVCACHE_SPACE=8
export VLLM_OPENVINO_ENABLE_QUANTIZED_WEIGHTS=ON
EOF"
  pct_exec_silent "chmod 644 /etc/profile.d/vllm-openvino.sh"
  msg_ok "Configured OpenVINO runtime environment"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! pct_exec_silent_raw test -d /opt/vllm; then
    msg_error "No vLLM installation found!"
    exit
  fi

  CURRENT="$(pct exec "${CTID}" -- bash -c "cat /opt/vllm_version.txt 2>/dev/null || true")"
  LATEST="$(pct exec "${CTID}" -- bash -c "cd /opt/vllm && git fetch -q origin main && git rev-parse origin/main")"

  if [[ -z "${CURRENT}" || "${CURRENT}" != "${LATEST}" ]]; then
    msg_info_nl "Updating vLLM to latest main"
    pct_exec_silent "cd /opt/vllm && git reset --hard origin/main"
    pct_exec_silent "cd /opt/vllm && \
      PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL}; \
      if [[ -f requirements-build.txt ]]; then \
        /opt/vllm-venv/bin/python -m pip install -r requirements-build.txt --extra-index-url ${PIP_EXTRA_INDEX_URL}; \
      else \
        /opt/vllm-venv/bin/python -m pip install -r requirements/build.txt --extra-index-url ${PIP_EXTRA_INDEX_URL}; \
      fi"
    pct_exec_silent "cd /opt/vllm && \
      PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL} \
      VLLM_TARGET_DEVICE=openvino \
      /opt/vllm-venv/bin/python -m pip install -v ."
    pct_exec_silent "cd /opt/vllm && git rev-parse HEAD >/opt/vllm_version.txt"
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