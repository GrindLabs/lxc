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

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    # Setup environment variables
    export VLLM_OPENVINO_DEVICE=GPU
    export VLLM_OPENVINO_ENABLE_QUANTIZED_WEIGHTS=ON
    export VLLM_USE_V1=1
    export VLLM_OPENVINO_KVCACHE_SPACE=8
    export VLLM_OPENVINO_KV_CACHE_PRECISION=i8
    export VLLM_TARGET_DEVICE=openvino
    export PIP_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cpu"

    # Update and install base dependencies
    apt-get update -y
    apt-get install -y python3 git curl ca-certificates build-essential ocl-icd-libopencl1 intel-opencl-icd intel-level-zero-gpu level-zero

    # Update pip
    pip install --upgrade pip

    # Change to app directory
    cd /opt

    # Clone openvino repository
    git clone https://github.com/vllm-project/vllm-openvino.git
    cd vllm-openvino

    # Install vLLM OpenVINO
    python -m pip install -v .

    # After installation it is necessary to remove triton lib
    # Reference: https://github.com/vllm-project/vllm-openvino?tab=readme-ov-file#build-wheel-from-source
    # pip uninstall -y triton
}

start
build_container
description
update_script

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Container IP:${CL}"