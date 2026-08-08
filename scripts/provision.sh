#!/usr/bin/env bash
# Bring a pod from empty to ready-to-generate. Idempotent — this runs on every
# start, and everything it does is skipped if already done.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

START_TS=$SECONDS

printf '\n%s┌─ Qwen-Image-Edit-Rapid-AIO — provisioning ─┐%s\n' "$_C_BLUE" "$_C_RESET"
dim "code      $COMFY_SRC"
dim "data      $COMFY_DATA"
dim "models    $MODELS"
dim "patch     $PATCH_MODE"

require_linux_gpu

if [[ "${SKIP_COMFY_INSTALL:-0}" != "1" ]]; then
  bash "$REPO_DIR/scripts/install_comfyui.sh"
else
  dim "SKIP_COMFY_INSTALL=1 — using the ComfyUI baked into this image"
fi

step "Data directories — $COMFY_DATA"
mkdir -p \
  "$COMFY_DATA/models/checkpoints" \
  "$COMFY_DATA/models/loras" \
  "$COMFY_DATA/custom_nodes" \
  "$COMFY_DATA/input" \
  "$COMFY_DATA/output" \
  "$COMFY_DATA/user/default/workflows"
dim "ok"

if [[ "$INSTALL_MANAGER" == "1" ]]; then
  step "ComfyUI-Manager"
  MANAGER_DIR="$COMFY_DATA/custom_nodes/ComfyUI-Manager"
  if [[ -d "$MANAGER_DIR/.git" ]]; then
    dim "already installed"
  else
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git "$MANAGER_DIR" \
      || warn "ComfyUI-Manager clone failed — continuing without it"
  fi
  if [[ -f "$MANAGER_DIR/requirements.txt" ]]; then
    vpip install --quiet -r "$MANAGER_DIR/requirements.txt" || warn "Manager requirements failed"
  fi
fi

step "Checkpoints — $COMFY_DATA/models/checkpoints"
IFS=',' read -r -a MODEL_LIST <<< "$MODELS"
[[ ${#MODEL_LIST[@]} -gt 0 && -n "${MODEL_LIST[0]}" ]] \
  || die "MODELS is empty — set it to at least one key (see ./scripts/download_models.sh --list)"
vpython "$REPO_DIR/scripts/download_models.py" \
  "$COMFY_DATA/models/checkpoints" "${MODEL_LIST[@]}"

bash "$REPO_DIR/scripts/install_qwen_node.sh"

step "Workflows"
FORCE_FLAG=""
[[ "${FORCE_WORKFLOWS:-0}" == "1" ]] && FORCE_FLAG="--force"
vpython "$REPO_DIR/scripts/install_workflows.py" \
  "$REPO_DIR/workflows" \
  "$COMFY_DATA/user/default/workflows" \
  "${MODEL_LIST[0]}" $FORCE_FLAG

printf '\n'
ok "provisioning finished in $((SECONDS - START_TS))s"
