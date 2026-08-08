# Qwen-Image-Edit-Rapid-AIO on ComfyUI — RunPod template image.
#
# The image carries ComfyUI + its Python environment (slow to install, identical
# on every pod). It deliberately does NOT carry the 28.4 GB checkpoint — that is
# pulled onto the network volume on first boot, so the image stays small and the
# model survives pod restarts.

ARG CUDA_IMAGE=nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04
FROM ${CUDA_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    COMFY_SRC=/opt/ComfyUI \
    COMFY_DATA=/workspace/ComfyUI \
    VENV_DIR=/opt/venv \
    SKIP_COMFY_INSTALL=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv python3-dev \
        git curl wget ca-certificates \
        openssh-server \
        libgl1 libglib2.0-0 \
        tini \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd

WORKDIR /opt/qwen-template

# Scripts first so the expensive ComfyUI layer is not invalidated by doc edits.
COPY scripts/ ./scripts/

ARG COMFYUI_REF=master
ARG TORCH_INDEX_URL=""
RUN COMFYUI_REF="${COMFYUI_REF}" TORCH_INDEX_URL="${TORCH_INDEX_URL}" \
    bash ./scripts/install_comfyui.sh

COPY . .

EXPOSE 8188 22

# tini reaps the ComfyUI child cleanly when RunPod stops the pod.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash", "/opt/qwen-template/scripts/start.sh"]
