# Running this on RunPod

Two routes. Route A needs no build infrastructure and is the fastest way to a
working pod. Route B gives faster cold starts and a reproducible template.

---

## Route A — bootstrap an existing pod

### 1. Create a network volume first

**Storage → Network Volumes → New**. Pick a datacenter that actually has the GPU
you want, and size it **100 GB**.

Why a network volume and not container disk: the checkpoint is 28.4 GB. Container
disk is wiped when the pod is destroyed, so you would re-download every session.
A network volume keeps the model, your outputs and your edited workflows.

> Already have a ComfyUI volume with models under `/workspace/ComfyUI/models/`?
> Attach that one — this template writes to exactly that layout and will not
> disturb models already there.

### 2. Deploy a pod

**Pods → Deploy**, then:

| Setting | Value |
|---|---|
| GPU | L40S / RTX 6000 Ada / A40 (48 GB). See sizing in the README. |
| Network volume | the one you just made, mounted at `/workspace` |
| Template | any RunPod PyTorch or CUDA template |
| HTTP ports | `8188` |
| TCP ports | `22` |

### 3. Bootstrap

Open the pod's web terminal (or SSH in) and run:

```bash
git clone https://github.com/dimitar-stanevv/qwen-template.git /workspace/qwen-template && cd /workspace/qwen-template && ./bootstrap.sh
```

First run installs ComfyUI, pulls the 28.4 GB checkpoint and starts the server.
Expect roughly 10–20 minutes, nearly all of it the download.

### 4. Open ComfyUI

Click **Connect → HTTP Service [Port 8188]**, or go straight to:

```
https://<POD_ID>-8188.proxy.runpod.net
```

The workflows are in the sidebar under **Workflows**. Open
`01-qwen-image-edit` and press **Run**.

### 5. Later sessions

```bash
cd /workspace/qwen-template && ./bootstrap.sh
```

Everything is already on the volume, so this starts in seconds. Add
`SKIP_PROVISION=1` to skip even the checks.

To keep it running after you close the terminal:

```bash
cd /workspace/qwen-template && nohup ./bootstrap.sh > /workspace/comfy.log 2>&1 &
```

---

## Route B — your own template image

```bash
make build push IMAGE=youruser/qwen-comfyui
```

Then **Templates → New Template**:

| Field | Value |
|---|---|
| Container Image | `youruser/qwen-comfyui:latest` |
| Container Disk | 20 GB |
| Volume Mount Path | `/workspace` |
| HTTP Ports | `8188` |
| TCP Ports | `22` |
| Environment Variables | anything from [`.env.example`](../.env.example) |

Deploy a pod from that template with a 100 GB network volume attached. The
container starts, provisions onto the volume and launches ComfyUI on its own —
no terminal needed.

`MODELS` is the variable worth setting at template level: it decides which
checkpoint gets pulled on first boot.

---

## Cost notes

- The pod bills while it **runs**; the network volume bills while it **exists**,
  running or not. Check RunPod's current per-GPU and per-GB rates — they move.
- **Stop the pod, do not terminate it**, between sessions if you want the
  container disk too. Terminating is fine here: everything that matters lives on
  the volume, and re-bootstrapping takes seconds.
- The first download is the only expensive-in-time step. Keeping the volume means
  never paying it again.
- Generating is fast — 4–8 steps at CFG 1.0 — so most of your spend is idle pod
  time. Stop the pod when you step away.

## Getting files in and out

- **In**: drag onto the `LoadImage` node in the ComfyUI web UI. That uploads to
  `/workspace/ComfyUI/input/`.
- **Out**: right-click the output image → Save, or pull a batch over SSH:
  ```bash
  scp -P <PORT> -i ~/.ssh/id_ed25519 -r root@<POD_IP>:/workspace/ComfyUI/output ./
  ```
- Bulk uploads go the same way, into `/workspace/ComfyUI/input/`.
