

# ─── qwen-template patch ─── appended, do not edit ───────────────────────────
#
# Redefines TextEncodeQwenImageEditPlus *after* the original definition above.
# QwenExtension.get_node_list() resolves these names as module globals when it
# is called (after the whole module has executed), so the class below is the one
# that gets registered — while every other node in this file, including
# EmptyQwenImageLayeredLatentImage, survives untouched. Replacing the file
# wholesale (the model author's instructions) would delete those.
#
# This is appended rather than shadowed from custom_nodes because ComfyUI's
# init_external_custom_nodes() passes the set of built-in node ids as `ignore`,
# so a custom node CANNOT override a core node id. It loads, logs, and is
# then skipped.
#
# Applied by scripts/install_qwen_node.sh; revert with --revert.

import logging as _qt_logging
import math as _qt_math


class TextEncodeQwenImageEditPlus(io.ComfyNode):  # noqa: F811
    """Qwen image-edit conditioning with 4 image slots and target-size scaling.

    The stock node encodes reference images at a fixed pixel budget regardless
    of the sampling resolution, which shows up as unexplained zoom, off-centre
    crops and mirrored edges. Feeding the sampling latent into `target_latent`
    makes references encode at the resolution actually being sampled.
    """

    # The Qwen2.5-VL tower sees every reference at this budget, independent of
    # output size — this part matches upstream.
    VL_PIXEL_BUDGET = 384 * 384

    LLAMA_TEMPLATE = (
        "<|im_start|>system\nDescribe key details of the input image (including any "
        "objects, characters, poses, facial features, clothing, setting, textures and "
        "style), then explain how the user's text instruction should alter, modify or "
        "recreate the image. Generate a new image that meets the user's requirements, "
        "which can vary from a small change to a completely new image using inputs as "
        "a guide.<|im_end|>\n<|im_start|>user\n{}<|im_end|>\n<|im_start|>assistant\n"
    )

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

            scale_by = _qt_math.sqrt(
                cls.VL_PIXEL_BUDGET / (samples.shape[3] * samples.shape[2])
            )
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
                    # The fix: encode references at the sampling resolution.
                    twidth = target_latent["samples"].shape[-1] * 8
                    theight = target_latent["samples"].shape[-2] * 8
                    s = comfy.utils.common_upscale(
                        samples, twidth, theight, "lanczos", "center"
                    )
                else:
                    s = samples
                ref_latents.append(vae.encode(s.movedim(1, -1)[:, :, :, :3]))

            image_prompt += "Picture {}: <|vision_start|><|image_pad|><|vision_end|>".format(i + 1)

        tokens = clip.tokenize(
            image_prompt + prompt, images=images_vl, llama_template=cls.LLAMA_TEMPLATE
        )
        conditioning = clip.encode_from_tokens_scheduled(tokens)

        if ref_latents:
            conditioning = node_helpers.conditioning_set_values(
                conditioning, {"reference_latents": ref_latents}, append=True
            )
        return io.NodeOutput(conditioning)


_qt_logging.getLogger(__name__).info(
    "[qwen-template] TextEncodeQwenImageEditPlus redefined "
    "(4 image inputs + target_latent scaling)"
)
