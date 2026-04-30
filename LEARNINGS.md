# OpenClaw InvokeAI Integration - Learnings & Gotchas

This document captures real-world learnings from integrating OpenClaw with InvokeAI.

## Critical Discoveries

### 1. Node Structure is a Dictionary, Not Array

**Wrong:**
```json
{
  "nodes": [
    {"type": "model_loader", "id": "model_loader"},
    {"type": "prompt", "id": "positive_prompt"}
  ]
}
```

**Right:**
```json
{
  "nodes": {
    "model_loader": {"type": "model_loader", "id": "model_loader"},
    "positive_prompt": {"type": "prompt", "id": "positive_prompt"}
  }
}
```

### 2. Model Keys Must Be Exact

The model key must match exactly what's returned by `/api/v2/models/`. No guessing.

```bash
curl -s "http://10.0.0.144:9090/api/v2/models/?model_type=main" | jq '.models[] | {key, name, base}'
```

### 3. FLUX Graph is Completely Different from SDXL

| Feature | SDXL | FLUX |
|---------|------|------|
| Model loader | `sdxl_model_loader` | `flux_model_loader` |
| Prompt | `sdxl_compel_prompt` | `flux_text_encoder` |
| Negative prompt | Yes | No |
| Noise node | Yes | No (in denoise) |
| Denoise | `denoise_latents` | `flux_denoise` |
| Decode | `l2i` | `flux_vae_decode` |
| CFG scale | 7.5 | N/A |
| Guidance | N/A | 3.5 |
| Sub-models | None | t5_encoder, clip_embed, vae |

### 4. Text Rendering Limitation

**Diffusion models cannot render real readable text.**

They generate text-like patterns that look plausible but are gibberish:
- "SERM WHALE" instead of "SPERM WHALE"
- "7.73 dB" instead of "230 dB"
- Lorem ipsum-style placeholder text

**Solutions:**
1. Generate text-free base image, add text with image editor
2. Use external API models (DALL-E 3, Ideogram) for text-heavy infographics
3. Accept text as decorative only

### 5. Anatomy Accuracy Requires Extreme Specificity

Generic prompts produce generic results:
- "sperm whale" → often looks like blue whale
- "sperm whale with massive square block-shaped head, wrinkled dark gray skin, small pectoral fins, triangular tail flukes" → much better

### 6. Sub-Model Keys for FLUX

The t5_encoder, clip_embed, and vae model keys are specific to the InvokeAI installation. Fetch them dynamically:

```bash
curl -s "http://10.0.0.144:9090/api/v2/models/?model_type=t5_encoder" | jq
curl -s "http://10.0.0.144:9090/api/v2/models/?model_type=clip_embed" | jq
curl -s "http://10.0.0.144:9090/api/v2/models/?model_type=vae" | jq
```

### 7. HTML Responses Mean Wrong Endpoint

If you get HTML instead of JSON, the API path is wrong. Check the OpenAPI spec:
```bash
curl -s http://10.0.0.144:9090/openapi.json | jq '.paths | keys'
```

### 8. Image Retrieval

After generation, images are listed at:
```bash
curl -s "http://10.0.0.144:9090/api/v1/images/?is_intermediate=false&limit=1" | jq
```

Then downloaded by name:
```bash
curl -s "http://10.0.0.144:9090/api/v1/images/i/{image_name}/full" -o output.png
```

### 9. No Authentication in Single-User Mode

When InvokeAI runs with multiuser disabled, no API key is needed. Just make requests.

### 10. Seed for Reproducibility vs Variation

**Default: Random seeds (`-1`) for variety**

| Seed Value | Result | Use Case |
|------------|--------|----------|
| `-1` | **Random** — unique image every time | ✅ **Default for exploration** |
| Fixed number (e.g., `42`, `777`) | **Reproducible** — same prompt + seed = same image | A/B testing, comparisons, replicating a good result |

**Where to set the seed:**
- **SDXL**: `"seed": -1` in the `noise` node
- **FLUX**: `"seed": -1` in the `flux_denoise` node
- **SD 1.5**: `"seed": -1` in the `noise` node

**Best Practice:** Always use `seed: -1` for default generation. Only fix the seed when you need to reproduce or iterate on a specific result.

## Testing Checklist

- [ ] Server responds at `http://10.0.0.144:9090`
- [ ] Models are listed at `/api/v2/models/`
- [ ] Graph validates before enqueue
- [ ] Batch completes without errors
- [ ] Image is retrievable after generation
- [ ] Output matches expected dimensions
- [ ] Output quality is acceptable

## Performance Notes

- FLUX models are larger (6.2-6.5 GB) and slower than SDXL
- FLUX-schnell is optimized for 4 steps (very fast)
- SDXL with 30 steps is a good balance of quality/speed
- GPU memory usage: ~8-12 GB for most models

## References

- [InvokeAI MCP Server](https://github.com/coinstax/invokeai-mcp-server) - Reference implementation
- [InvokeAI GitHub](https://github.com/invoke-ai/InvokeAI)
- [InvokeAI Documentation](https://invoke-ai.github.io/InvokeAI/)

---

## Image-to-Image (img2img) Learnings

**Date Added:** 2026-04-30
**Test Case:** Transform garage photo (boy + 2 dirt bikes) to woods trail background

### 11. Strength Parameter is Critical

The `strength` parameter (via `denoising_start = 1.0 - strength`) controls everything:

| Strength | Result | Lesson |
|----------|--------|--------|
| 0.38-0.45 | Background doesn't fully change, garage still visible | Too conservative |
| 0.50-0.60 | **Sweet spot** - background changes, subjects mostly preserved | ✅ Recommended |
| 0.68-0.75 | Background fully changes but subjects get distorted/reconstructed | Too aggressive |

**Test Results:**
- `0.75` - Lost the person entirely
- `0.45` - Person preserved but garage still visible
- `0.38` - Garage barely changed
- `0.68` - Woods background but distorted subjects
- `0.55` - Best compromise

### 12. VAE Connection to image_to_latents is Mandatory

The `i2l` (image_to_latents) node **must** have a VAE input from the model loader.

**Missing edge causes:**
```
Node i2l missing connections for field vae
```

**Required edge:**
```json
{
  "source": {"node_id": "model_loader", "field": "vae"},
  "destination": {"node_id": "image_to_latents", "field": "vae"}
}
```

### 13. Noise Dimensions Must Match Image Exactly

The `noise` node's `width` and `height` must match the uploaded image dimensions.

**Error if wrong:**
```
Incompatible 'noise' and 'latents' shapes: 
latents.shape=torch.Size([1, 4, 120, 160]) 
noise.shape=torch.Size([1, 4, 64, 64])
```

**Solution:** Get width/height from upload response, pass to noise node:
```python
image_name, width, height = upload_image(path)
# Use in noise node:
"noise": {"width": width, "height": height}
```

### 14. Image Upload Endpoint Details

**Endpoint:** `/api/v1/images/upload` (singular, not `/uploads`)

**Query params required:**
```
?image_category=user&is_intermediate=false
```

**Request:** multipart/form-data with `file` field

**Response:**
```json
{
  "image_name": "uuid.png",
  "width": 1280,
  "height": 960
}
```

### 15. Prompt Weighting Helps Subject Preservation

Use weighted emphasis to prioritize subjects:
```
(boy with red Honda dirt bike:1.3)  # 30% more emphasis
((forest background))               # ~21% more emphasis
```

**Template:**
```
Positive: "(subjects:1.3), new background description, lighting, atmosphere"
Negative: "old background elements, indoor, walls, ceiling, unwanted objects"
```

### 16. The Fundamental Trade-off

**You cannot perfectly preserve subjects while completely changing the background with img2img alone.**

| Approach | Pros | Cons |
|----------|------|------|
| Low strength (0.35-0.50) | Subjects preserved perfectly | Background change is subtle |
| High strength (0.65-0.75) | Background fully transforms | Subjects get distorted |
| **Inpainting (Unified Canvas)** | Perfect preservation + clean background | Requires manual masking |

**For zero-distortion background replacement:** Use InvokeAI's Unified Canvas web UI with inpainting/masking.

### 17. Complete Working Graph Structure

See `docs/IMG2IMG.md` and `examples/sdxl-img2img-request.json` for the complete working graph with all required nodes and edges.

**Key nodes for SDXL img2img:**
- `image_to_latents` (i2l) - converts input image to latents
- `sdxl_model_loader` - loads the model
- `sdxl_compel_prompt` (x2) - positive and negative prompts
- `noise` - must match image dimensions
- `denoise_latents` - the transformation (uses denoising_start/end)
- `l2i` - latents to image
- `save_image` - final output

**Critical edges:**
- `model_loader.vae` → `image_to_latents.vae` (commonly missed!)
- `image_to_latents.latents` → `denoise.latents` (the img2img connection)
- `noise.noise` → `denoise.noise`
