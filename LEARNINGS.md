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

### 10. Seed for Reproducibility

Always set a seed if you want reproducible results:
- SDXL: `"seed": 42` in the `noise` node
- FLUX: `"seed": 42` in the `flux_denoise` node

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
