#!/usr/bin/env bash
# Shared config + helpers. Sourced by every script in this folder.
# shellcheck shell=bash

set -euo pipefail

# ---------------------------------------------------------------- logging ---
if [[ -t 1 ]]; then
  _C_RESET=$'\033[0m'; _C_BLUE=$'\033[1;34m'; _C_YEL=$'\033[1;33m'
  _C_RED=$'\033[1;31m'; _C_GRN=$'\033[1;32m'; _C_DIM=$'\033[2m'
else
  _C_RESET=''; _C_BLUE=''; _C_YEL=''; _C_RED=''; _C_GRN=''; _C_DIM=''
fi

log()  { printf '%s[qwen]%s %s\n' "$_C_BLUE" "$_C_RESET" "$*"; }
ok()   { printf '%s[qwen]%s %s\n' "$_C_GRN"  "$_C_RESET" "$*"; }
dim()  { printf '%s       %s%s\n' "$_C_DIM"  "$*" "$_C_RESET"; }
warn() { printf '%s[qwen] WARN%s %s\n' "$_C_YEL" "$_C_RESET" "$*" >&2; }
die()  { printf '%s[qwen] ERROR%s %s\n' "$_C_RED" "$_C_RESET" "$*" >&2; exit 1; }

step() { printf '\n%s==>%s %s\n' "$_C_BLUE" "$_C_RESET" "$*"; }

# ------------------------------------------------------------- repo paths ---
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_DIR

# --------------------------------------------------------------- settings ---
# COMFY_SRC   where the ComfyUI *code* lives.
# COMFY_DATA  where models / outputs / workflows / custom_nodes live. On RunPod
#             this must sit on the network volume so it survives pod restarts.
# They are the same directory in the bootstrap flow, and different in the
# Docker flow (code baked into the image, data on the volume).
COMFY_SRC="${COMFY_SRC:-/workspace/ComfyUI}"
COMFY_DATA="${COMFY_DATA:-$COMFY_SRC}"
VENV_DIR="${VENV_DIR:-$COMFY_SRC/venv}"

COMFYUI_REPO="${COMFYUI_REPO:-https://github.com/comfyanonymous/ComfyUI.git}"
COMFYUI_REF="${COMFYUI_REF:-master}"

# Leave empty to use the default PyPI torch wheels (CUDA-enabled on Linux).
# Override for a specific CUDA build, e.g.
#   TORCH_INDEX_URL=https://download.pytorch.org/whl/cu128
TORCH_INDEX_URL="${TORCH_INDEX_URL:-}"

HF_REPO="${HF_REPO:-Phr00t/Qwen-Image-Edit-Rapid-AIO}"
# Comma-separated keys from the table in scripts/download_models.sh.
MODELS="${MODELS:-v23-sfw}"

# shadow    register a fixed node that overrides the core one (default, safest)
# overwrite replace ComfyUI's comfy_extras/nodes_qwen.py (the author's method)
# none      leave the encoder node alone
PATCH_MODE="${PATCH_MODE:-shadow}"

INSTALL_MANAGER="${INSTALL_MANAGER:-1}"
COMFY_PORT="${COMFY_PORT:-8188}"
COMFY_EXTRA_ARGS="${COMFY_EXTRA_ARGS:-}"

export COMFY_SRC COMFY_DATA VENV_DIR COMFYUI_REPO COMFYUI_REF TORCH_INDEX_URL
export HF_REPO MODELS PATCH_MODE INSTALL_MANAGER COMFY_PORT COMFY_EXTRA_ARGS

# Keep every cache on the network volume. RunPod's container disk is small and
# defaults to ~20 GB — a torch wheel plus pip's cache will fill it and the
# install dies halfway with "no space left on device".
export HF_HOME="${HF_HOME:-$COMFY_DATA/.cache/huggingface}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-$COMFY_DATA/.cache/pip}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$COMFY_DATA/.cache}"

# ---------------------------------------------------------------- helpers ---
# Python from the venv when it exists, otherwise the system one.
vpython() {
  if [[ -x "$VENV_DIR/bin/python" ]]; then
    "$VENV_DIR/bin/python" "$@"
  else
    python3 "$@"
  fi
}

vpip() { vpython -m pip "$@"; }

have() { command -v "$1" >/dev/null 2>&1; }

# Highest CUDA version this host's driver supports, e.g. "12.8". Empty if no GPU.
driver_cuda_version() {
  nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: *\([0-9]*\.[0-9]*\).*/\1/p' | head -1
}

# Pick a torch wheel index the driver can actually run.
#
# PyPI's default torch tracks the newest CUDA, so on a host whose driver is even
# slightly behind you get "The NVIDIA driver on your system is too old (found
# version 12080)" — which blames the driver for what is really a wheel mismatch.
# Echoes an empty string when the driver is new enough for the PyPI default.
torch_index_for_driver() {
  local v="${1:-}" major minor
  [[ -z "$v" ]] && { echo ""; return; }
  major="${v%%.*}"; minor="${v##*.}"
  if   (( major >= 13 )); then echo ""
  elif (( major == 12 && minor >= 8 )); then echo "https://download.pytorch.org/whl/cu128"
  elif (( major == 12 && minor >= 6 )); then echo "https://download.pytorch.org/whl/cu126"
  elif (( major == 12 )); then echo "https://download.pytorch.org/whl/cu124"
  else echo ""; fi
}

require_linux_gpu() {
  if ! have nvidia-smi; then
    warn "nvidia-smi not found — is this a GPU pod? ComfyUI will fall back to CPU and be unusably slow."
    return
  fi
  local name mem
  name="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
  mem="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)"
  dim "GPU: ${name} (${mem} MiB)"
  if [[ "$mem" -lt 40000 ]]; then
    warn "${mem} MiB VRAM. The AIO checkpoint is ~28.4 GB; under ~40 GB ComfyUI will"
    warn "offload the text encoder every run. It works, but expect slow generations."
    warn "48 GB (L40S / RTX 6000 Ada / A40) is the comfortable floor."
  fi
}
