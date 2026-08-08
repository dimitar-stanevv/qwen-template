# Troubleshooting

## The checkpoint is missing from the `Load Checkpoint` dropdown

Restart ComfyUI. A newly downloaded model shows up in the Model Library right
away, but the loader dropdown is populated from `/object_info`, which is cached
until the server restarts. The Refresh button does not rebuild it.

```bash
# on the pod
pkill -f "main.py" ; cd /workspace/qwen-template && ./bootstrap.sh
```

## The output is zoomed in, cropped oddly, or has a mirrored edge

This is the stock encoder node, not the model. Check the patch actually applied:

```bash
grep -c "qwen-template patch" "$COMFY_SRC/comfy_extras/nodes_qwen.py"
```

`1` means it is in place. In the ComfyUI log you should see:

```
[qwen-template] TextEncodeQwenImageEditPlus redefined (4 image inputs + target_latent scaling)
```

If the node is present but you still get drift, confirm `EmptyLatentImage` is
wired into the encoder's **`target_latent`** input, and that the latent's aspect
ratio matches your input photo.

If the log instead shows an import error for `comfy_api.latest`, your ComfyUI is
too old:

```bash
cd /workspace/ComfyUI && git pull && cd /workspace/qwen-template && ./bootstrap.sh
```

## `TextEncodeQwenImageEditPlus` has only 3 image inputs

The patch did not apply — see above. The stock node has `image1..image3` and no
`target_latent`; the patched one has `image1..image4` plus `target_latent`.

## `TypeError: execute() got an unexpected keyword argument 'target_latent'`

The workflow has the patched node's inputs but ComfyUI registered the *stock*
class. Templates from before 2026-08-09 shipped the fix as a custom node, which
ComfyUI refuses to register over a built-in id — it imports, logs a reassuring
"patched" message, and is skipped.

Update and re-apply:

```bash
cd /opt/qwen-template 2>/dev/null || cd /workspace/qwen-template
git pull && bash scripts/install_qwen_node.sh && echo "restart ComfyUI now"
```

In the saved workflow JSON the tell is that `image4` and `target_latent` have no
`localized_name` field while the other inputs do — the frontend resolved the core
schema and kept your extra slots as unrecognised leftovers.

## CUDA out of memory

The checkpoint is 28.4 GB, so a 24 GB card cannot hold it and the text encoder at
once. In order of what to try:

```bash
COMFY_EXTRA_ARGS=--lowvram ./bootstrap.sh      # text encoder to CPU
COMFY_EXTRA_ARGS="--lowvram --cache-none"      # also free node outputs eagerly
COMFY_EXTRA_ARGS="--lowvram --fast-disk"       # NVMe-backed offload
```

Also drop the latent to 1024×1024 or below. If it is still tight, the real fix is
a 48 GB GPU.

## The download stopped or the file looks truncated

Re-run it. `download_models.py` compares the local size against the Hub's
metadata, deletes a short file and resumes:

```bash
cd /workspace/qwen-template && ./scripts/download_models.sh
```

If it dies with a disk-space error, your network volume is too small — 28.4 GB
per checkpoint plus ~15 GB for ComfyUI and the venv. Grow it to 100 GB.

## `no space left on device`

Check what is eating the volume:

```bash
du -sh /workspace/ComfyUI/* | sort -h
```

Usual suspects: a second checkpoint you forgot about, `output/`, and
`.cache/huggingface`. The staging folder
`/workspace/ComfyUI/models/checkpoints/.hf-staging` should be empty — delete it
if a download was interrupted hard.

## Results look plastic / airbrushed

Add `Professional digital photography` to the prompt (the model card's own tip).
If it persists, try v19 or v22 — the author retuned the skin/realism LoRA mix
almost every release, and which one looks right is subject-dependent.

## Faces change identity across edits

Use **`v19-sfw`**. The author's own note is that v19 is the most consistent for
edits, and v23 the best at following instructions. Fetch both and switch:

```bash
./scripts/download_models.sh v19-sfw
```

Also state it in the prompt — "keep her face identical" is not implied.

## There is no port 8188 in the pod's Connect tab

The stock RunPod templates expose `8888` (Jupyter) and nothing else, and the
proxy only routes ports declared in the pod config — ComfyUI listening on 8188 does
not make the port appear.

Fix it permanently with **⋮ → Edit Pod → HTTP ports → add `8188`** (the pod
restarts), or avoid exposing anything and tunnel over SSH:

```bash
ssh root@<POD_IP> -p <PORT> -i ~/.ssh/id_ed25519 -L 8188:localhost:8188
```

then open `http://localhost:8188` on your own machine.

## ComfyUI starts but the RunPod proxy URL 502s

The server binds after model scanning, which takes a moment on a 28 GB file.
Watch the log; you want `To see the GUI go to: http://0.0.0.0:8188`. Also confirm
`8188` is listed under **HTTP Ports** on the pod, not TCP.

## Everything is slow even on a big GPU

Check you are not on CPU:

```bash
nvidia-smi                     # is the GPU there at all
grep -i "device:" /workspace/comfy.log | head
```

ComfyUI prints the device it picked at startup. If it says CPU, torch was
installed without CUDA support — reinstall pinned to a CUDA build:

```bash
TORCH_INDEX_URL=https://download.pytorch.org/whl/cu128 ./bootstrap.sh
```

## Undo the encoder patch entirely

```bash
./scripts/install_qwen_node.sh --revert
```

Restores stock behaviour, including `comfy_extras/nodes_qwen.py` if you had used
`PATCH_MODE=overwrite`.
