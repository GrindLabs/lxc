# Grindlabs LXC

This project contributes LXC helper scripts for quick setup on ProxmoxVE. The goal is to make it easy to bootstrap common containers with a single command.

## Quick start

Run on a ProxmoxVE host:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/ollama.sh)"
```

Mirroring that example for this repo's `vllm-openvino.sh`:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/grindlabs/lxc/main/vllm-openvino.sh)"
```
