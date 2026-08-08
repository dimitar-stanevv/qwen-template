#!/usr/bin/env bash
# Container / pod entrypoint: provision, then hand the process over to ComfyUI.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# RunPod convention: if the pod was launched with an SSH key, wire it up.
if [[ -n "${PUBLIC_KEY:-}" ]] && [[ -d /etc/ssh ]]; then
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  grep -qxF "$PUBLIC_KEY" /root/.ssh/authorized_keys 2>/dev/null \
    || echo "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  ssh-keygen -A >/dev/null 2>&1 || true
  service ssh start >/dev/null 2>&1 || /usr/sbin/sshd 2>/dev/null || true
fi

if [[ "${SKIP_PROVISION:-0}" != "1" ]]; then
  bash "$REPO_DIR/scripts/provision.sh"
fi

# Helps a lot on a 28 GB checkpoint that gets paged between CPU and GPU.
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"
export HF_HOME="${HF_HOME:-$COMFY_DATA/.cache/huggingface}"

PY="python3"
[[ -x "$VENV_DIR/bin/python" ]] && PY="$VENV_DIR/bin/python"

EXTRA_ARGS=()
if [[ -n "${COMFY_EXTRA_ARGS// /}" ]]; then
  read -r -a EXTRA_ARGS <<< "$COMFY_EXTRA_ARGS"
fi

printf '\n'
ok "starting ComfyUI on port $COMFY_PORT"
if [[ -n "${RUNPOD_POD_ID:-}" ]]; then
  dim "open  https://${RUNPOD_POD_ID}-${COMFY_PORT}.proxy.runpod.net"
else
  dim "open  http://localhost:${COMFY_PORT}"
fi
printf '\n'

cd "$COMFY_SRC"
exec "$PY" main.py \
  --listen 0.0.0.0 \
  --port "$COMFY_PORT" \
  --base-directory "$COMFY_DATA" \
  --disable-auto-launch \
  "${EXTRA_ARGS[@]}"
