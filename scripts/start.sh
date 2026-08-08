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
# (HF_HOME / PIP_CACHE_DIR are exported in lib.sh, before provisioning runs.)
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"

PY="python3"
[[ -x "$VENV_DIR/bin/python" ]] && PY="$VENV_DIR/bin/python"

EXTRA_ARGS=()
if [[ -n "${COMFY_EXTRA_ARGS// /}" ]]; then
  read -r -a EXTRA_ARGS <<< "$COMFY_EXTRA_ARGS"
fi

# --- torch / CUDA preflight -------------------------------------------------
# A torch wheel built against a newer CUDA than the host driver dies with
# "The NVIDIA driver on your system is too old (found version …)", which blames
# the driver for what is actually a wheel mismatch. Catch it here, while the
# message can still be acted on, instead of at the first sampler run.
if TORCH_INFO="$("$PY" -c 'import torch; print("torch", torch.__version__, "cuda", torch.version.cuda); assert torch.cuda.is_available()' 2>&1)"; then
  dim "$(printf '%s' "$TORCH_INFO" | head -1) — CUDA available"
else
  warn "torch cannot use this GPU:"
  printf '%s\n' "$TORCH_INFO" | tail -3 | sed 's/^/       /' >&2
  DRIVER_CUDA="$(driver_cuda_version)"
  FIX_INDEX="${TORCH_INDEX_URL:-}"
  [[ -z "$FIX_INDEX" ]] && FIX_INDEX="$(torch_index_for_driver "$DRIVER_CUDA")"

  if [[ "${AUTO_FIX_TORCH:-1}" == "1" && -n "$FIX_INDEX" && -w "$VENV_DIR" ]]; then
    warn "driver supports CUDA ${DRIVER_CUDA:-unknown} — reinstalling torch from $FIX_INDEX"
    warn "(a few minutes; bake it in properly by rebuilding with --build-arg TORCH_INDEX_URL=$FIX_INDEX)"
    "$PY" -m pip install --quiet --force-reinstall \
      torch torchvision torchaudio --index-url "$FIX_INDEX" \
      || die "torch reinstall failed — rebuild the image with TORCH_INDEX_URL=$FIX_INDEX"
    "$PY" -c 'import torch; assert torch.cuda.is_available()' \
      || die "torch still cannot see the GPU after reinstall"
    ok "torch repaired for CUDA ${DRIVER_CUDA}"
  else
    die "driver supports CUDA ${DRIVER_CUDA:-unknown}; rebuild the image with --build-arg TORCH_INDEX_URL=${FIX_INDEX:-<matching wheel index>}"
  fi
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
