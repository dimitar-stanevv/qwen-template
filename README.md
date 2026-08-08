# qwen-template

RunPod + ComfyUI template for **[Phr00t/Qwen-Image-Edit-Rapid-AIO](https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO)** — instruction-driven image editing ("remove the person on the left", "change the jacket to red leather", "relight as golden hour") at 4–8 steps.

Boot a pod, wait for the download, open ComfyUI, and the workflows are already in the sidebar pointing at the right checkpoint with the right sampler.

---

## What the model is

An all-in-one merge of **Qwen-Image-Edit-2511**: the DiT, the VAE and the Qwen2.5-VL text encoder plus Lightning acceleration LoRAs, baked into one FP8 `.safetensors`. That is what "AIO" buys you — a plain `Load Checkpoint` node instead of the usual separate UNET / CLIP / VAE loader trio.

Two things surprise people arriving from SDXL inpainting:

- **There is no mask.** You give up to 4 reference images plus an instruction, and the model regenerates the frame. Nothing is pixel-locked — the whole image round-trips through the VAE, so untouched regions drift slightly. If you need bit-exact preservation, composite the result back over the original afterwards.
- **Denoise stays at 1.0.** The input photo enters through the *text encoder* node as conditioning, not through the latent. Do not reach for the denoise slider.

---

## Quick start — existing pod (no Docker build)

Deploy any RunPod GPU pod with a PyTorch or CUDA image, **attach a network volume of at least 100 GB**, then:

```bash
git clone https://github.com/dimitar-stanevv/qwen-template.git /workspace/qwen-template && cd /workspace/qwen-template && ./bootstrap.sh
```

That installs ComfyUI, downloads the checkpoint, patches the encoder node, installs the workflows and starts the server. Expose HTTP port **8188** and open `https://<POD_ID>-8188.proxy.runpod.net`.

Re-running `./bootstrap.sh` after a restart skips everything already done and starts in seconds.

## Quick start — your own template image

```bash
make build IMAGE=youruser/qwen-comfyui
make push  IMAGE=youruser/qwen-comfyui
```

Then create a RunPod template with that image, HTTP port `8188`, TCP port `22`, a **100 GB network volume mounted at `/workspace`**, and whatever environment variables you want from [`.env.example`](.env.example). The image is a few GB; the 28.4 GB checkpoint is deliberately *not* baked in — it lands on the volume on first boot and is reused by every later pod.

---

## Pod sizing

The checkpoint is **28.43 GB** of FP8 weights, and all three components (DiT + VL text encoder + VAE) live in that one file.

| VRAM | Verdict |
|---|---|
| 24 GB (4090, L4) | Works, but ComfyUI pages the text encoder in and out every run. Add `COMFY_EXTRA_ARGS=--lowvram`. |
| **48 GB (L40S, RTX 6000 Ada, A40)** | **The comfortable floor — recommended.** |
| 80 GB (A100, H100) | Headroom for several versions resident at once. |

Disk: 100 GB network volume is the sweet spot — 28.4 GB per checkpoint, ~15 GB for ComfyUI and the Python environment, the rest for outputs and a second model version.

---

## Configuration

Everything is environment variables — set them in the RunPod pod/template config, or in a local `.env`. Full list with comments in [`.env.example`](.env.example).

| Variable | Default | What it does |
|---|---|---|
| `MODELS` | `v23-sfw` | Comma-separated checkpoints to fetch. `./scripts/download_models.sh --list` shows all keys. |
| `HF_TOKEN` | — | Optional. The repo is public so downloads work without it, but a token gets you higher rate limits and Xet-accelerated transfer — worth setting for a 28 GB pull. A read-only token is enough. |
| `PATCH_MODE` | `shadow` | How to fix the encoder node. See below. |
| `COMFY_EXTRA_ARGS` | — | Extra `main.py` flags, e.g. `--lowvram`. |
| `COMFY_DATA` | `/workspace/ComfyUI` | Models / outputs / workflows. Must be on the volume. |
| `FORCE_WORKFLOWS` | `0` | Re-copy bundled workflows on boot, discarding your edits. |
| `SKIP_PROVISION` | `0` | Skip all setup checks and launch immediately. |

### Which checkpoint

The author stopped at v23 ("this project has peaked"). Their own guidance:

| Key | Why |
|---|---|
| `v23-sfw` | Best **prompt adherence**. The default. |
| `v19-sfw` | Best **edit consistency** — subjects keep their identity. |

Both, if you want to A/B: `MODELS=v23-sfw,v19-sfw` (57 GB total). `*-nsfw` variants exist for each version; the model card explains the split.

The workflows are auto-retargeted at whichever version you fetched, including that version's recommended sampler (`euler_ancestral/beta` for v20–v23, `er_sde/beta` for v19).

### The encoder-node patch

ComfyUI's stock `TextEncodeQwenImageEditPlus` rescales reference images badly — you get unexplained zoom, off-centre crops and mirrored edges. This is the single biggest source of "the model is bad" complaints, and it is not the model.

The author publishes a fixed node and tells you to overwrite `comfy_extras/nodes_qwen.py` with it. This template defaults to something safer:

- **`shadow` (default)** — ships the fix as a custom node registering the same `node_id`. ComfyUI loads custom nodes *after* built-ins and the registry is last-writer-wins, so it overrides the core node without touching a core file. Survives ComfyUI updates; uninstall by deleting the folder. Workflows stay compatible with everyone else's.
- **`overwrite`** — the author's literal method, with an automatic backup. Note it also *removes* `EmptyQwenImageLayeredLatentImage`, which the author's file does not define.
- **`none`** — stock node, quirk included.

Either fixed path adds a 4th image input and the `target_latent` input that does the actual fixing: wire your `EmptyLatentImage` in and references get encoded at the sampling resolution.

Revert at any time with `./scripts/install_qwen_node.sh --revert`.

---

## Layout

```
bootstrap.sh                  one-shot setup for an existing pod
Dockerfile                    build your own RunPod template image
Makefile                      build / push / run / check
scripts/
  start.sh                    entrypoint: provision, then exec ComfyUI
  provision.sh                idempotent setup, runs on every boot
  install_comfyui.sh          ComfyUI source + venv + torch
  download_models.py|sh       resumable, size-verified checkpoint fetch
  install_qwen_node.sh        the encoder-node fix (shadow/overwrite/none)
  install_workflows.py        copy + retarget workflows into the sidebar
custom_nodes/
  qwen_edit_target_latent/    the patched TextEncodeQwenImageEditPlus
patches/nodes_qwen.v2.py      the author's original file, for overwrite mode
workflows/
  01-qwen-image-edit.json     image editing, 2 inputs wired, target_latent set
  02-qwen-text-to-image.json  same checkpoint, no input images
  qwen-rapid-aio.upstream.json  the author's reference graph, untouched
docs/                         RunPod setup, prompting, troubleshooting
```

## Docs

- [docs/RUNPOD.md](docs/RUNPOD.md) — pod creation click-by-click, volume reuse, costs
- [docs/USAGE.md](docs/USAGE.md) — prompting, settings, getting images in and out
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — the failure modes you will actually hit

## Credits

Model by [Phr00t](https://huggingface.co/Phr00t); base model [Qwen-Image-Edit-2511](https://huggingface.co/Qwen/Qwen-Image-Edit-2511) (Apache-2.0). The patched encoder node is Phr00t's fix, repackaged.
