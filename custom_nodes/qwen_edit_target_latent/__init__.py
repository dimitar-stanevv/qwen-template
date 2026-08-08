"""
Patched TextEncodeQwenImageEditPlus for Qwen-Image-Edit-Rapid-AIO.

WHY THIS EXISTS
---------------
ComfyUI's stock `TextEncodeQwenImageEditPlus` rescales reference images to a
fixed budget before VAE-encoding them. When your output size differs from the
reference size you get unexplained zoom, off-centre crops and mirrored edges.
Phr00t (the model author) publishes a fixed version of the node; this package
is that fix, repackaged as a custom node.

WHY A CUSTOM NODE INSTEAD OF OVERWRITING comfy_extras/nodes_qwen.py
------------------------------------------------------------------
The author's instructions say to overwrite ComfyUI's own `nodes_qwen.py`.
That works, but it has two costs: a `git pull` in ComfyUI silently reverts it,
and the author's file defines fewer nodes than current upstream — overwriting
therefore DELETES `EmptyQwenImageLayeredLatentImage` from your install.

ComfyUI registers custom nodes AFTER built-ins and the registry is a plain dict
(last writer wins), so registering the same `node_id` here shadows the core node
without touching a single core file. Uninstall = delete this folder.

WHAT CHANGED vs THE CORE NODE
-----------------------------
* 4 image inputs instead of 3.
* New optional `target_latent` input. Wire your EmptyLatentImage into it and
  reference images are scaled to the sampling resolution, which is what stops
  the zoom/crop drift. With nothing wired, no scaling is applied.
* A more instruction-oriented system prompt for the VL encoder.

If your ComfyUI is too old to expose `comfy_api.latest`, this module logs a
warning and declines to load — you fall back to the stock node, which still
works, just with the scaling quirk.
"""

import logging

_LOG = logging.getLogger(__name__)

try:
    import math

    import comfy.utils
    import node_helpers
    from comfy_api.latest import ComfyExtension, io
    from typing_extensions import override
except ImportError as exc:  # pragma: no cover - depends on host ComfyUI version
    raise ImportError(
        "qwen_edit_target_latent needs a ComfyUI new enough to provide "
        f"comfy_api.latest ({exc}). Update ComfyUI or delete this custom node "
        "folder; the stock TextEncodeQwenImageEditPlus will be used instead."
    ) from exc


# Mirrors Phr00t's nodes_qwen.v2.py, kept byte-compatible in behaviour.
LLAMA_TEMPLATE = (
    "<|im_start|>system\nDescribe key details of the input image (including any "
    "objects, characters, poses, facial features, clothing, setting, textures and "
    "style), then explain how the user's text instruction should alter, modify or "
    "recreate the image. Generate a new image that meets the user's requirements, "
    "which can vary from a small change to a completely new image using inputs as "
    "a guide.<|im_end|>\n<|im_start|>user\n{}<|im_end|>\n<|im_start|>assistant\n"
)

# The Qwen2.5-VL tower sees every reference at this budget regardless of output size.
VL_PIXEL_BUDGET = 384 * 384


class TextEncodeQwenImageEditPlus(io.ComfyNode):
    @classmethod
    def define_schema(cls):
        return io.Schema(
            node_id="TextEncodeQwenImageEditPlus",
            display_name="TextEncodeQwenImageEditPlus (target_latent patch)",
            category="advanced/conditioning",
            inputs=[
                io.Clip.Input("clip"),
                io.String.Input("prompt", multiline=True, dynamic_prompts=True),
                io.Vae.Input("vae", optional=True),
                io.Image.Input("image1", optional=True),
                io.Image.Input("image2", optional=True),
                io.Image.Input("image3", optional=True),
                io.Image.Input("image4", optional=True),
                io.Latent.Input("target_latent", optional=True),
            ],
            outputs=[io.Conditioning.Output()],
        )

    @classmethod
    def execute(
        cls,
        clip,
        prompt,
        vae=None,
        image1=None,
        image2=None,
        image3=None,
        image4=None,
        target_latent=None,
    ) -> io.NodeOutput:
        ref_latents = []
        images_vl = []
        image_prompt = ""

        for i, image in enumerate([image1, image2, image3, image4]):
            if image is None:
                continue

            samples = image.movedim(-1, 1)

            # Downscale a copy to the VL tower's budget for the text encoder.
            scale_by = math.sqrt(VL_PIXEL_BUDGET / (samples.shape[3] * samples.shape[2]))
            vl = comfy.utils.common_upscale(
                samples,
                round(samples.shape[3] * scale_by),
                round(samples.shape[2] * scale_by),
                "lanczos",
                "center",
            )
            images_vl.append(vl.movedim(1, -1))

            if vae is not None:
                if target_latent is not None:
                    # THE FIX: encode the reference at the sampling resolution so the
                    # latent geometry lines up and the result does not drift/zoom.
                    twidth = target_latent["samples"].shape[-1] * 8
                    theight = target_latent["samples"].shape[-2] * 8
                    s = comfy.utils.common_upscale(samples, twidth, theight, "lanczos", "center")
                else:
                    s = samples
                ref_latents.append(vae.encode(s.movedim(1, -1)[:, :, :, :3]))

            image_prompt += "Picture {}: <|vision_start|><|image_pad|><|vision_end|>".format(i + 1)

        tokens = clip.tokenize(
            image_prompt + prompt, images=images_vl, llama_template=LLAMA_TEMPLATE
        )
        conditioning = clip.encode_from_tokens_scheduled(tokens)

        if ref_latents:
            conditioning = node_helpers.conditioning_set_values(
                conditioning, {"reference_latents": ref_latents}, append=True
            )
        return io.NodeOutput(conditioning)


class QwenEditTargetLatentExtension(ComfyExtension):
    @override
    async def get_node_list(self) -> list[type[io.ComfyNode]]:
        _LOG.info(
            "[qwen-template] TextEncodeQwenImageEditPlus patched "
            "(4 image inputs + target_latent scaling)"
        )
        return [TextEncodeQwenImageEditPlus]


async def comfy_entrypoint() -> QwenEditTargetLatentExtension:
    return QwenEditTargetLatentExtension()
