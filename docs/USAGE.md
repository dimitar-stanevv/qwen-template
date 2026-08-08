# Using it

## Settings

| | Value |
|---|---|
| Steps | **4–8** (4 is usually enough; 8 for detail) |
| CFG | **1.0** — not negotiable, the Lightning LoRAs are baked in |
| Denoise | **1.0** — see below |
| Sampler / scheduler (v20–v23) | `euler_ancestral` / `beta` |
| Sampler / scheduler (v19) | `er_sde` / `beta` |
| Negative prompt | **empty** — at CFG 1.0 it does nothing |

The bundled workflows already have all of this set for whichever version you
downloaded.

### Why denoise stays at 1.0

This is the thing that trips up everyone coming from SDXL img2img or Fooocus.
Your input photo is **not** fed in as a noised latent. It is VAE-encoded and
attached to the conditioning by the `TextEncodeQwenImageEditPlus` node, and the
sampler starts from pure noise. Lowering denoise does not "preserve more of the
original" — it just gives the sampler less room to work and degrades the result.

## Prompting

Write an **instruction**, not a caption.

| Don't | Do |
|---|---|
| `a street with one person` | `Remove the person on the left. Keep everything else identical.` |
| `woman in a red jacket` | `Change her jacket to red leather. Keep the face, pose and background unchanged.` |
| `golden hour photo` | `Relight the scene as golden hour, warm low sun from the right. Keep the composition.` |

Things that reliably help:

- **Say what to preserve.** "Keep the background, lighting and composition
  identical" measurably reduces drift in the parts you did not ask about.
- **`Professional digital photography`** — the model card's own tip for cutting
  the plastic-skin look. Works.
- **One change at a time.** Two unrelated edits in one prompt is how you get one
  of them ignored. Chain runs instead.
- **Reference multiple images by number.** With more than one `LoadImage` wired,
  the encoder labels them `Picture 1`, `Picture 2` … so you can write
  `Put the woman from Picture 1 into the hallway from Picture 2.`

## Output size and the target_latent input

`EmptyLatentImage` ("Final Image Size") does two jobs in these workflows: it sets
the output resolution *and* feeds `target_latent` on the encoder node, which is
what makes reference images get encoded at the sampling resolution.

**Match your input photo's aspect ratio.** A 16:9 photo edited into a 1:1 latent
gets cropped, and it will look like the model invented a crop. Set the latent to
the same aspect, roughly 1 megapixel:

| Aspect | Size |
|---|---|
| 1:1 | 1024×1024 (or 1328×1328, Qwen's native square) |
| 3:2 | 1216×832 |
| 16:9 | 1344×768 |
| 2:3 | 832×1216 |

## Comparing to inpainting

You have not lost inpainting — you have swapped mask-painting for instructions.
The trade:

- **Better**: no mask to paint, edits that need global consistency (relighting,
  perspective, "make her look left") just work, and multi-image composition is a
  first-class feature.
- **Worse**: nothing is pixel-locked. The whole frame is re-encoded, so grain,
  fine text and background detail shift slightly even where you asked for no
  change.

When you need untouched pixels, run the edit, then composite the result over the
original through a mask in your editor of choice. You get the instruction-driven
edit *and* an intact background.

## Swapping checkpoints

```bash
./scripts/download_models.sh v19-sfw
```

Then pick it in the `Load Checkpoint` node — and **restart ComfyUI first**. A new
file appears in the Model Library immediately but the loader dropdown stays empty
until `/object_info` is rebuilt; the Refresh button is not enough.

Remember to move the sampler to `er_sde/beta` when you switch to v19.
