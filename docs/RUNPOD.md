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
| Pod template | **any RunPod PyTorch template** — e.g. `runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04`. Prefer the newest offered. |
| Container disk | 20 GB is enough (see below) |
| HTTP ports | `8188` |
| TCP ports | `22` |

#### Which pod template?

Any RunPod **PyTorch** template works, and the version barely matters: bootstrap
builds its own virtualenv on the volume and installs a current torch into it, so
the image's torch is never used. All the template has to supply is Ubuntu,
Python 3.10+, `git` and the CUDA userspace — every RunPod PyTorch image has all
four. A plain CUDA template works too; bootstrap installs `git` and
`python3-venv` if they are missing.

Prefer a newer template when the list offers one, purely so the CUDA userspace
is better matched to the driver. Do not pick a bare Ubuntu image with no CUDA.

**Container disk can stay at the 20 GB default.** ComfyUI, the venv, the model
and every cache (pip, Hugging Face) are placed under `/workspace`, on the network
volume. Nothing large is written to container disk.

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

#### Port 8188 is not in the Connect tab

Expect this if you deployed straight from a stock RunPod template — those expose
`8888` for Jupyter and nothing else, and the proxy only routes ports declared in
the pod config. ComfyUI running is not enough.

Either **⋮ → Edit Pod → HTTP ports → add `8188`** (the pod restarts; do it before
the download, not after), or skip the exposed port entirely and tunnel over the
SSH connection you already have:

```bash
ssh root@<POD_IP> -p <PORT> -i ~/.ssh/id_ed25519 -L 8188:localhost:8188
```

Run `./bootstrap.sh` inside that session and open `http://localhost:8188`
locally. Nothing needs to be exposed, and the tunnel lives as long as the SSH
session does.

### 4b. Confirm the volume is actually mounted

Before kicking off a 28 GB download, make sure it is landing on the network
volume and not on container disk:

```bash
df -h /workspace
```

A ~100 GB filesystem means you are good. If you see the small container disk, or
no `/workspace` at all, the pod has no network volume attached — redeploy with
one, or you will re-download the checkpoint every session.

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

## Route B — your own RunPod template

A pod from this template comes up with ComfyUI already serving on 8188. No
terminal, no clone, no port fiddling.

### 1. Get an image built

Pushing to `main` triggers [`.github/workflows/build.yml`](../.github/workflows/build.yml),
which builds on GitHub's amd64 runners and publishes to:

```
ghcr.io/<your-github-user>/qwen-template:latest
```

Build it by hand from the **Actions** tab → *build image* → **Run workflow**.
Roughly 15–25 minutes for the first run; later runs hit the layer cache.

> **Build in CI, not on an Apple Silicon Mac.** `make build` works, but
> `--platform linux/amd64` runs the torch install through qemu emulation and
> takes the better part of an hour. The Makefile target is there for Linux hosts
> and for debugging.

### 2. Make the package public — one time

GHCR packages default to **private**, and RunPod cannot pull a private image
without registry credentials. After the first successful build:

**GitHub repo → Packages → `qwen-template` → Package settings → Change visibility
→ Public.**

(Prefer to keep it private? Leave it, and use **Select registry authentication**
in the RunPod template with a GitHub personal access token that has
`read:packages`.)

### 3. Create the template

**Templates → New Template**:

| Field | Value |
|---|---|
| Template name | `qwen-comfyui` |
| Template type | **Pods** |
| Compute type | **NVIDIA · GPU** |
| Public template | off |
| Container image | `ghcr.io/<your-github-user>/qwen-template:latest` |
| Start command | **leave empty** — the image already starts ComfyUI |
| Container disk | **20 GB** (5 GB is too small: ComfyUI-Manager's pip installs land in the image's writable layer) |
| Persistent storage mount path | `/workspace` |
| Volume disk | 100 GB — ignored when you attach a network volume at deploy, so it is just a safe fallback |

**Networking configuration:**

| Type | Label | Port |
|---|---|---|
| HTTP Ports | `ComfyUI` | `8188` |
| TCP Ports | `SSH` | `22` |

Getting 8188 in here is the whole point — a stock template exposes only 8888 for
Jupyter, which is why the port never showed up in the Connect tab.

**Environment variables** (all optional, full list in [`.env.example`](../.env.example)):

| Name | Value |
|---|---|
| `MODELS` | `v23-sfw` — which checkpoint to pull on first boot |
| `HF_TOKEN` | your read-only token, for a faster download |

### 4. Deploy

**Pods → Deploy**, pick a 48 GB GPU, select this template, and attach your
**100 GB network volume**. The container provisions onto the volume and launches
ComfyUI by itself; watch progress under the pod's **Logs** tab.

Every later pod from this template reuses the volume, so it skips the download
and is ready in under a minute.

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
