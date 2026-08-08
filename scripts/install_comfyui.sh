#!/usr/bin/env bash
# Install (or update) ComfyUI + its Python environment.
# Idempotent: safe to run on every pod start.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

step "ComfyUI code — $COMFY_SRC"

if [[ -d "$COMFY_SRC/.git" ]]; then
  # Deliberately NOT updating by default: a silent `git pull` on every pod start
  # is a great way to arrive one morning at a ComfyUI that no longer runs.
  if [[ "${UPDATE_COMFYUI:-0}" == "1" ]]; then
    log "UPDATE_COMFYUI=1 — fetching $COMFYUI_REF"
    git -C "$COMFY_SRC" fetch --depth 1 origin "$COMFYUI_REF"
    git -C "$COMFY_SRC" checkout -q FETCH_HEAD
  else
    dim "already cloned at $(git -C "$COMFY_SRC" rev-parse --short HEAD) (UPDATE_COMFYUI=1 to update)"
  fi
elif [[ -f "$COMFY_SRC/main.py" ]]; then
  dim "found a non-git ComfyUI install, leaving it alone"
else
  log "cloning ComfyUI ($COMFYUI_REF)"
  mkdir -p "$(dirname "$COMFY_SRC")"
  if ! git clone --depth 1 --branch "$COMFYUI_REF" "$COMFYUI_REPO" "$COMFY_SRC" 2>/dev/null; then
    # COMFYUI_REF was probably a commit SHA, which --branch will not take.
    git clone "$COMFYUI_REPO" "$COMFY_SRC"
    git -C "$COMFY_SRC" checkout -q "$COMFYUI_REF"
  fi
fi
[[ -f "$COMFY_SRC/main.py" ]] || die "no main.py in $COMFY_SRC — ComfyUI install looks broken"

step "Python environment — $VENV_DIR"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  log "creating venv"
  python3 -m venv "$VENV_DIR"
fi
vpip install --quiet --upgrade pip wheel

if ! vpython -c "import torch" 2>/dev/null; then
  log "installing torch (this is the slow part, ~5 min)"
  if [[ -n "$TORCH_INDEX_URL" ]]; then
    vpip install torch torchvision torchaudio --index-url "$TORCH_INDEX_URL"
  else
    vpip install torch torchvision torchaudio
  fi
else
  dim "torch $(vpython -c 'import torch;print(torch.__version__)') already present"
fi

log "installing ComfyUI requirements"
vpip install --quiet -r "$COMFY_SRC/requirements.txt"

log "installing download helpers"
vpip install --quiet "huggingface_hub[hf_transfer,hf_xet]"

ok "ComfyUI code + Python environment ready"
