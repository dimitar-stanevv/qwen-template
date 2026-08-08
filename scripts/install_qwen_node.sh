#!/usr/bin/env bash
# Install the fixed TextEncodeQwenImageEditPlus node.
#
# PATCH_MODE=append    (default) append a redefinition to ComfyUI's own
#                      comfy_extras/nodes_qwen.py. Python's later definition
#                      wins, and QwenExtension.get_node_list() resolves the name
#                      at call time — so the patched class is registered while
#                      every other node in that file survives.
# PATCH_MODE=overwrite replace the file with the model author's version. Also
#                      works, but drops EmptyQwenImageLayeredLatentImage, which
#                      the author's file does not define.
# PATCH_MODE=none      leave ComfyUI alone (you keep the zoom/crop quirk).
#
# NOT an option: shipping this from custom_nodes. ComfyUI's
# init_external_custom_nodes() passes the set of built-in node ids as `ignore`,
# so a custom node cannot override a core node id — it imports, logs, and is
# then silently skipped. An earlier version of this template did exactly that
# and looked like it was working.
#
# Pass --revert to restore stock behaviour.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CORE_FILE="$COMFY_SRC/comfy_extras/nodes_qwen.py"
CORE_BACKUP="$COMFY_SRC/comfy_extras/nodes_qwen.py.qwen-template-orig"
APPEND_FILE="$REPO_DIR/patches/qwen_edit_plus_append.py"
MARKER="─── qwen-template patch ───"

# Left behind by templates <= 2026-08-08, which tried the custom_nodes route.
STALE_NODE_DIR="$COMFY_DATA/custom_nodes/qwen_edit_target_latent"

restore_core() {
  if [[ -f "$CORE_BACKUP" ]]; then
    cp "$CORE_BACKUP" "$CORE_FILE"
    rm -f "$CORE_BACKUP"
    log "restored stock comfy_extras/nodes_qwen.py"
  fi
}

if [[ -d "$STALE_NODE_DIR" ]]; then
  warn "removing the old custom-node patch (it never actually registered)"
  rm -rf "$STALE_NODE_DIR"
fi

if [[ "${1:-}" == "--revert" ]]; then
  step "Reverting encoder-node patch"
  restore_core
  ok "stock TextEncodeQwenImageEditPlus is back"
  exit 0
fi

step "Encoder-node patch (mode: $PATCH_MODE)"
[[ -f "$CORE_FILE" ]] || die "$CORE_FILE not found — is COMFY_SRC ($COMFY_SRC) right?"

case "$PATCH_MODE" in
  append)
    if grep -q "$MARKER" "$CORE_FILE"; then
      # Already patched. Start from the pristine copy so we never stack patches.
      [[ -f "$CORE_BACKUP" ]] || die "patched file with no backup — restore ComfyUI's nodes_qwen.py by hand"
      cp "$CORE_BACKUP" "$CORE_FILE"
    else
      # Pristine (possibly a newer ComfyUI): refresh the backup.
      cp "$CORE_FILE" "$CORE_BACKUP"
    fi

    cat "$APPEND_FILE" >> "$CORE_FILE"

    vpython -m py_compile "$CORE_FILE" \
      || { restore_core; die "patched file failed to compile — reverted"; }

    # Prove the redefinition is the one that wins, rather than trusting Python.
    vpython - "$CORE_FILE" <<'PY' || { restore_core; die "patch did not take effect — reverted"; }
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
classes = [n for n in tree.body if isinstance(n, ast.ClassDef)]
plus = [c for c in classes if c.name == "TextEncodeQwenImageEditPlus"]
assert len(plus) == 2, f"expected 2 definitions, found {len(plus)}"
execs = [f for f in plus[-1].body if isinstance(f, ast.FunctionDef) and f.name == "execute"]
assert execs, "last definition has no execute()"
args = {a.arg for a in execs[0].args.args} | {a.arg for a in execs[0].args.kwonlyargs}
assert "target_latent" in args, "last definition lacks target_latent"
assert "image4" in args, "last definition lacks image4"
names = {c.name for c in classes}
assert "EmptyQwenImageLayeredLatentImage" in names, "core node was lost"
print("       verified: patched class is last, core nodes intact")
PY
    dim "appended to $CORE_FILE"
    ;;

  overwrite)
    if [[ ! -f "$CORE_BACKUP" ]]; then
      cp "$CORE_FILE" "$CORE_BACKUP"
      dim "backed up stock node to $(basename "$CORE_BACKUP")"
    fi
    if grep -q "EmptyQwenImageLayeredLatentImage" "$CORE_BACKUP" 2>/dev/null; then
      warn "the author's file does not define EmptyQwenImageLayeredLatentImage;"
      warn "overwrite mode removes that node. PATCH_MODE=append keeps it."
    fi
    cp "$REPO_DIR/patches/nodes_qwen.v2.py" "$CORE_FILE"
    vpython -m py_compile "$CORE_FILE" \
      || { restore_core; die "patched file failed to compile — reverted"; }
    dim "overwrote $CORE_FILE"
    ;;

  none)
    restore_core
    dim "skipped — stock encoder node in use"
    ;;

  *)
    die "PATCH_MODE must be append, overwrite or none (got '$PATCH_MODE')"
    ;;
esac

ok "encoder node handled"
