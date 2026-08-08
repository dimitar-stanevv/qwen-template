#!/usr/bin/env bash
# Install the fixed TextEncodeQwenImageEditPlus node.
#
# PATCH_MODE=shadow    (default) drop a custom node that overrides the core one.
#                      Survives ComfyUI updates, touches no core file.
# PATCH_MODE=overwrite replace comfy_extras/nodes_qwen.py, the model author's
#                      documented method. Note this also removes
#                      EmptyQwenImageLayeredLatentImage, which the author's file
#                      does not define.
# PATCH_MODE=none      leave ComfyUI alone (you keep the zoom/crop quirk).
#
# Pass --revert to undo everything and restore stock behaviour.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NODE_SRC="$REPO_DIR/custom_nodes/qwen_edit_target_latent"
NODE_DST="$COMFY_DATA/custom_nodes/qwen_edit_target_latent"
CORE_FILE="$COMFY_SRC/comfy_extras/nodes_qwen.py"
CORE_BACKUP="$COMFY_SRC/comfy_extras/nodes_qwen.py.qwen-template-orig"

restore_core() {
  if [[ -f "$CORE_BACKUP" ]]; then
    cp "$CORE_BACKUP" "$CORE_FILE"
    rm -f "$CORE_BACKUP"
    log "restored stock comfy_extras/nodes_qwen.py"
  fi
}

if [[ "${1:-}" == "--revert" ]]; then
  step "Reverting encoder-node patch"
  rm -rf "$NODE_DST"
  restore_core
  ok "stock TextEncodeQwenImageEditPlus is back"
  exit 0
fi

step "Encoder-node patch (mode: $PATCH_MODE)"

case "$PATCH_MODE" in
  shadow)
    restore_core   # in case a previous run used overwrite mode
    rm -rf "$NODE_DST"
    mkdir -p "$(dirname "$NODE_DST")"
    cp -r "$NODE_SRC" "$NODE_DST"
    vpython -m py_compile "$NODE_DST/__init__.py" \
      || die "patched node failed to compile — refusing to leave it in place"
    dim "custom node installed at $NODE_DST"
    ;;

  overwrite)
    rm -rf "$NODE_DST"
    [[ -f "$CORE_FILE" ]] || die "$CORE_FILE not found"
    if [[ ! -f "$CORE_BACKUP" ]]; then
      cp "$CORE_FILE" "$CORE_BACKUP"
      dim "backed up stock node to $(basename "$CORE_BACKUP")"
    fi
    if grep -q "EmptyQwenImageLayeredLatentImage" "$CORE_BACKUP" 2>/dev/null; then
      warn "the author's file does not define EmptyQwenImageLayeredLatentImage;"
      warn "overwrite mode removes that node. Use PATCH_MODE=shadow to keep it."
    fi
    cp "$REPO_DIR/patches/nodes_qwen.v2.py" "$CORE_FILE"
    vpython -m py_compile "$CORE_FILE" || { restore_core; die "patched core file failed to compile — reverted"; }
    dim "overwrote $CORE_FILE"
    ;;

  none)
    rm -rf "$NODE_DST"
    restore_core
    dim "skipped — stock encoder node in use"
    ;;

  *)
    die "PATCH_MODE must be shadow, overwrite or none (got '$PATCH_MODE')"
    ;;
esac

ok "encoder node handled"
