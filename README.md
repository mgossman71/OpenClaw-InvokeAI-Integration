# OpenClaw InvokeAI Integration

Complete integration guide for connecting OpenClaw agents to an InvokeAI image generation server.

**Server**: `http://10.0.0.144:9090`  
**API Docs**: `http://10.0.0.144:9090/docs`  
**OpenAPI Spec**: `http://10.0.0.144:9090/openapi.json`

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Server Setup](#server-setup)
3. [Available Models](#available-models)
4. [Understanding Model Types](#understanding-model-types)
5. [API Authentication](#api-authentication)
6. [Text-to-Image Generation](#text-to-image-generation)
7. [Graph Structure Reference](#graph-structure-reference)
   - [SDXL Graph](#sdxl-graph)
   - [FLUX Graph](#flux-graph)
   - [SD 1.5 Graph](#sd-15-graph)
8. [Prompt Engineering](#prompt-engineering)
9. [Common Issues & Troubleshooting](#common-issues--troubleshooting)
10. [References & Resources](#references--resources)

---

## Quick Start

### Generate an Image (cURL)

```bash
# 1. Create a request file
cat > /tmp/request.json << 'EOF'
{
  "batch": {
    "graph": {
      "id": "test_graph",
      "nodes": {
        "model_loader": {
          "type": "sdxl_model_loader",
          "id": "model_loader",
          "model": {"key": "juggernaut-xl-v9", "hash": "...", "name": "Juggernaut XL v9", "base": "sdxl", "type": "main"}
        },
        "positive_prompt": {
          "type": "sdxl_compel_prompt",
          "id": "positive_prompt",
          "prompt": "a majestic eagle in flight, wildlife photography, dramatic lighting",
          "style": "a majestic eagle in flight, wildlife photography, dramatic lighting"
        },
        "noise": {
          "type": "noise",
          "id": "noise",
          "seed": 42,
          "width": 1024,
          "height": 768,
          "use_cpu": false
        },
        "denoise": {
          "type": "denoise_latents",
          "id": "denoise",
          "steps": 30,
          "cfg_scale": 7.5,
          "scheduler": "euler",
          "denoising_start": 0,
          "denoising_end": 1
        },
        "latents_to_image": {
          "type": "l2i",
          "id": "latents_to_image"
        },
        "save_image": {
          "type": "save_image",
          "id": "save_image",
          "is_intermediate": false
        }
      },
      "edges": [
        {"source": {"node_id": "model_loader", "field": "unet"}, "destination": {"node_id": "denoise", "field": "unet"}},
        {"source": {"node_id": "model_loader", "field": "clip"}, "destination": {"node_id": "positive_prompt", "field": "clip"}},
        {"source": {"node_id": "positive_prompt", "field": "conditioning"}, "destination": {"node_id": "denoise", "field": "positive_conditioning"}},
        {"source": {"node_id": "noise", "field": "noise"}, "destination": {"node_id": "denoise", "field": "noise"}},
        {"source": {"node_id": "denoise", "field": "latents"}, "destination": {"node_id": "latents_to_image", "field": "latents"}},
        {"source": {"node_id": "model_loader", "field": "vae"}, "destination": {"node_id": "latents_to_image", "field": "vae"}},
        {"source": {"node_id": "latents_to_image", "field": "image"}, "destination": {"node_id": "save_image", "field": "image"}}
      ]
    },
    "runs": 1,
    "data": null
  }
}
EOF

# 2. Enqueue the generation
curl -s -X POST http://10.0.0.144:9090/api/v1/queue/default/enqueue_batch \
  -H "Content-Type: application/json" \
  -d @/tmp/request.json | jq

# 3. Check status (replace {batch_id} with the ID from step 2)
curl -s http://10.0.0.144:9090/api/v1/queue/default/b/{batch_id}/status | jq

# 4. List images
curl -s "http://10.0.0.144:9090/api/v1/images/?is_intermediate=false&limit=1" | jq

# 5. Download image (replace {image_name} with the name from step 4)
curl -s "http://10.0.0.144:9090/api/v1/images/i/{image_name}/full" -o output.png
```

---

## Server Setup

For installing InvokeAI on Proxmox LXC with NVIDIA GPU, see:  
[InvokeAI-on-Proxmox-LXC-with-RTX-5070Ti](https://github.com/mgossman71/InvokeAI-on-Proxmox-LXC-with-RTX-5070Ti)

Key configuration in `invokeai.yaml`:
```yaml
schema_version: 4.0.2
host: 0.0.0.0
port: 9090
```

---

## Available Models

### List All Models
```bash
curl -s "http://10.0.0.144:9090/api/v2/models/?model_type=main" | jq
```

### Model Types

| Model | Base | Size | Best For | Key Feature |
|-------|------|------|----------|-------------|
| `juggernaut-xl-v9` | SDXL | 6.46 GB | Photorealistic, portraits, wildlife | High detail |
| `flux-1-dev` | FLUX | 6.24 GB | General purpose, high quality | Best prompt adherence |
| `flux-1-schnell` | FLUX | 6.23 GB | Fast iterations | 4-step generation |
| `flux-1-krea-dev` | FLUX | 6.46 GB | Creative, artistic | Artistic styles |
| `flux-1-kontext-dev` | FLUX | 6.46 GB | Contextual understanding | Complex scenes |

### Get Model Details
```bash
curl -s "http://10.0.0.144:9090/api/v2/models/i/{model_key}" | jq
```

---

## Understanding Model Types

InvokeAI supports multiple model architectures, each requiring different graph structures:

### SDXL (Stable Diffusion XL)
- **Node types**: `sdxl_model_loader`, `sdxl_compel_prompt`, `denoise_latents`, `l2i`
- **Features**: Negative prompts, style field, cfg_scale parameter
- **Best for**: Photorealistic images, portraits, detailed scenes

### FLUX (Black Forest Labs)
- **Node types**: `flux_model_loader`, `flux_text_encoder`, `flux_denoise`, `flux_vae_decode`
- **Features**: No negative prompts, `guidance` parameter instead of cfg_scale
- **Best for**: General purpose, high quality, good prompt adherence
- **Note**: Requires additional sub-models (t5_encoder, clip_embed)

### SD 1.5 (Stable Diffusion 1.5)
- **Node types**: `main_model_loader`, `compel`, `denoise_latents`, `l2i`
- **Features**: Smaller memory footprint, faster generation
- **Best for**: Quick iterations, simpler compositions

**Critical**: The graph structure MUST match the model type. Using SDXL nodes with a FLUX model will fail.

---

## API Authentication

In single-user mode (default), no authentication is required. The server accepts all requests.

For multi-user mode, authentication would be configured in `invokeai.yaml`.

---

## Text-to-Image Generation

### The Graph Concept

InvokeAI uses a node-based graph where:
- **Nodes** are processing units (model loading, prompt encoding, denoising, etc.)
- **Edges** connect nodes, specifying data flow
- **Graph** = nodes + edges
- **Batch** wraps the graph for the queue API

### Request Structure

```json
{
  "batch": {
    "graph": {
      "id": "unique_graph_id",
      "nodes": { "node_name": { ... }, ... },
      "edges": [ { "source": {...}, "destination": {...} }, ... ]
    },
    "runs": 1,
    "data": null
  }
}
```

### Important Notes
- Nodes are a **dictionary** (keyed by node name), not an array
- Edges reference nodes by their `id` field
- Node `id` must match the key in the nodes dictionary
- All edges must connect existing nodes and fields

---

## Graph Structure Reference

### SDXL Graph

#### Nodes
```json
{
  "model_loader": {
    "type": "sdxl_model_loader",
    "id": "model_loader",
    "model": {"key": "juggernaut-xl-v9", "hash": "...", "name": "Juggernaut XL v9", "base": "sdxl", "type": "main"}
  },
  "positive_prompt": {
    "type": "sdxl_compel_prompt",
    "id": "positive_prompt",
    "prompt": "your prompt here",
    "style": "your prompt here"
  },
  "negative_prompt": {
    "type": "sdxl_compel_prompt",
    "id": "negative_prompt",
    "prompt": "blurry, deformed, ugly, low quality",
    "style": ""
  },
  "noise": {
    "type": "noise",
    "id": "noise",
    "seed": 42,
    "width": 1024,
    "height": 768,
    "use_cpu": false
  },
  "denoise": {
    "type": "denoise_latents",
    "id": "denoise",
    "steps": 30,
    "cfg_scale": 7.5,
    "scheduler": "euler",
    "denoising_start": 0,
    "denoising_end": 1
  },
  "latents_to_image": {
    "type": "l2i",
    "id": "latents_to_image"
  },
  "save_image": {
    "type": "save_image",
    "id": "save_image",
    "is_intermediate": false
  }
}
```

#### Edges
```json
[
  {"source": {"node_id": "model_loader", "field": "unet"}, "destination": {"node_id": "denoise", "field": "unet"}},
  {"source": {"node_id": "model_loader", "field": "clip"}, "destination": {"node_id": "positive_prompt", "field": "clip"}},
  {"source": {"node_id": "model_loader", "field": "clip"}, "destination": {"node_id": "negative_prompt", "field": "clip"}},
  {"source": {"node_id": "model_loader", "field": "clip2"}, "destination": {"node_id": "positive_prompt", "field": "clip2"}},
  {"source": {"node_id": "model_loader", "field": "clip2"}, "destination": {"node_id": "negative_prompt", "field": "clip2"}},
  {"source": {"node_id": "positive_prompt", "field": "conditioning"}, "destination": {"node_id": "denoise", "field": "positive_conditioning"}},
  {"source": {"node_id": "negative_prompt", "field": "conditioning"}, "destination": {"node_id": "denoise", "field": "negative_conditioning"}},
  {"source": {"node_id": "noise", "field": "noise"}, "destination": {"node_id": "denoise", "field": "noise"}},
  {"source": {"node_id": "denoise", "field": "latents"}, "destination": {"node_id": "latents_to_image", "field": "latents"}},
  {"source": {"node_id": "model_loader", "field": "vae"}, "destination": {"node_id": "latents_to_image", "field": "vae"}},
  {"source": {"node_id": "latents_to_image", "field": "image"}, "destination": {"node_id": "save_image", "field": "image"}}
]
```

---

### FLUX Graph

#### Key Differences from SDXL
- No `noise` node (seed/width/height are in `flux_denoise`)
- No `negative_prompt` node (FLUX doesn't use negative prompts)
- No `cfg_scale` parameter (use `guidance` instead, typically 3.5)
- Uses `flux_model_loader` with additional sub-models
- Uses `flux_text_encoder` instead of `sdxl_compel_prompt`
- Uses `flux_vae_decode` instead of `l2i`

#### Nodes
```json
{
  "model_loader": {
    "type": "flux_model_loader",
    "id": "model_loader",
    "model": {"key": "flux-1-dev", "hash": "...", "name": "FLUX.1 dev", "base": "flux", "type": "main"},
    "t5_encoder_model": {"key": "36d7f5c9-03a7-46fa-9f0a-90be4e05d155", "hash": "...", "name": "t5_bnb_int8_quantized_encoder", "base": "any", "type": "t5_encoder"},
    "clip_embed_model": {"key": "0c55e4d1-7042-4e65-b65d-1e500e802865", "hash": "...", "name": "clip-vit-large-patch14", "base": "any", "type": "clip_embed"},
    "vae_model": {"key": "151393bc-1b21-42fe-b147-ecaceb35d278", "hash": "...", "name": "FLUX.1-schnell_ae", "base": "flux", "type": "vae"}
  },
  "prompt": {
    "type": "flux_text_encoder",
    "id": "prompt",
    "prompt": "your prompt here",
    "t5_max_seq_len": 512
  },
  "denoise": {
    "type": "flux_denoise",
    "id": "denoise",
    "num_steps": 25,
    "cfg_scale": 1.0,
    "scheduler": "euler",
    "width": 1024,
    "height": 1536,
    "seed": 42,
    "guidance": 3.5
  },
  "vae_decode": {
    "type": "flux_vae_decode",
    "id": "vae_decode"
  },
  "save_image": {
    "type": "save_image",
    "id": "save_image",
    "is_intermediate": false
  }
}
```

#### Edges
```json
[
  {"source": {"node_id": "model_loader", "field": "transformer"}, "destination": {"node_id": "denoise", "field": "transformer"}},
  {"source": {"node_id": "model_loader", "field": "clip"}, "destination": {"node_id": "prompt", "field": "clip"}},
  {"source": {"node_id": "model_loader", "field": "t5_encoder"}, "destination": {"node_id": "prompt", "field": "t5_encoder"}},
  {"source": {"node_id": "prompt", "field": "conditioning"}, "destination": {"node_id": "denoise", "field": "positive_text_conditioning"}},
  {"source": {"node_id": "denoise", "field": "latents"}, "destination": {"node_id": "vae_decode", "field": "latents"}},
  {"source": {"node_id": "model_loader", "field": "vae"}, "destination": {"node_id": "vae_decode", "field": "vae"}},
  {"source": {"node_id": "vae_decode", "field": "image"}, "destination": {"node_id": "save_image", "field": "image"}}
]
```

---

### SD 1.5 Graph

#### Nodes
```json
{
  "model_loader": {
    "type": "main_model_loader",
    "id": "model_loader",
    "model": {"key": "model_key_here", "hash": "...", "name": "Model Name", "base": "sd-1", "type": "main"}
  },
  "positive_prompt": {
    "type": "compel",
    "id": "positive_prompt",
    "prompt": "your prompt here"
  },
  "negative_prompt": {
    "type": "compel",
    "id": "negative_prompt",
    "prompt": "blurry, deformed, ugly, low quality"
  },
  "noise": {
    "type": "noise",
    "id": "noise",
    "seed": 42,
    "width": 512,
    "height": 512,
    "use_cpu": false
  },
  "denoise": {
    "type": "denoise_latents",
    "id": "denoise",
    "steps": 30,
    "cfg_scale": 7.5,
    "scheduler": "euler",
    "denoising_start": 0,
    "denoising_end": 1
  },
  "latents_to_image": {
    "type": "l2i",
    "id": "latents_to_image"
  },
  "save_image": {
    "type": "save_image",
    "id": "save_image",
    "is_intermediate": false
  }
}
```

#### Edges
```json
[
  {"source": {"node_id": "model_loader", "field": "unet"}, "destination": {"node_id": "denoise", "field": "unet"}},
  {"source": {"node_id": "model_loader", "field": "clip"}, "destination": {"node_id": "positive_prompt", "field": "clip"}},
  {"source": {"node_id": "model_loader", "field": "clip"}, "destination": {"node_id": "negative_prompt", "field": "clip"}},
  {"source": {"node_id": "positive_prompt", "field": "conditioning"}, "destination": {"node_id": "denoise", "field": "positive_conditioning"}},
  {"source": {"node_id": "negative_prompt", "field": "conditioning"}, "destination": {"node_id": "denoise", "field": "negative_conditioning"}},
  {"source": {"node_id": "noise", "field": "noise"}, "destination": {"node_id": "denoise", "field": "noise"}},
  {"source": {"node_id": "denoise", "field": "latents"}, "destination": {"node_id": "latents_to_image", "field": "latents"}},
  {"source": {"node_id": "model_loader", "field": "vae"}, "destination": {"node_id": "latents_to_image", "field": "vae"}},
  {"source": {"node_id": "latents_to_image", "field": "image"}, "destination": {"node_id": "save_image", "field": "image"}}
]
```

---

## Prompt Engineering

### Best Practices
- Be specific: "golden hour lighting" not just "nice lighting"
- Include style keywords: "wildlife photography", "portrait photography", "digital art"
- For FLUX: Be very specific about anatomy and features
- SDXL benefits from the `style` field matching the prompt

### Parameter Guidelines

| Parameter | SDXL | FLUX | Notes |
|-----------|------|------|-------|
| Steps | 30-50 | 20-30 | FLUX converges faster |
| CFG Scale | 7.5-12 | N/A | FLUX uses `guidance` |
| Guidance | N/A | 3.5-5.0 | FLUX-specific |
| Scheduler | euler, dpmpp_2m_sde_k | euler | |
| Width | 1024 | 1024 | Multiple of 64 |
| Height | 768-1536 | 768-1536 | Multiple of 64 |

---

## Common Issues & Troubleshooting

### "Node not found in graph"
- Ensure node dictionary keys match edge references
- Verify node `id` fields match the dictionary keys

### HTML responses instead of JSON
- API endpoints return HTML if the path is wrong
- Use exact paths from OpenAPI spec at `/openapi.json`

### Timeout errors
- Increase timeout for high step counts or large images
- FLUX models may take longer due to larger architecture

### No models available
- Check `/api/v2/models/` endpoint
- Models may need to be downloaded through the InvokeAI web UI first

### Text renders as gibberish
- **Diffusion models (FLUX, SDXL) cannot render real readable text**
- They generate text-like patterns that look plausible but are nonsense
- For infographics with real text, use external API models (DALL-E 3, Ideogram)
- Alternative: Generate text-free base image, add text with image editor

### Wrong anatomy (e.g., blue whale instead of sperm whale)
- Use extreme specificity in prompts
- Describe distinctive features: "massive square block-shaped head", "wrinkled skin", "triangular tail flukes"
- Consider generating isolated subject first, then compositing

---

## References & Resources

### Official InvokeAI Resources
- [InvokeAI GitHub](https://github.com/invoke-ai/InvokeAI)
- [InvokeAI Documentation](https://invoke-ai.github.io/InvokeAI/)
- [InvokeAI Support](https://support.invoke.ai/)

### API & Swagger
- OpenAPI Spec: `http://YOUR_SERVER:9090/openapi.json`
- Swagger UI: `http://YOUR_SERVER:9090/docs`
- [GitHub Issues (API problems)](https://github.com/invoke-ai/InvokeAI/issues)

### MCP Server Reference
- [coinstax/invokeai-mcp-server](https://github.com/coinstax/invokeai-mcp-server) - Reference implementation for MCP integration

### Related Repositories
- [InvokeAI-on-Proxmox-LXC-with-RTX-5070Ti](https://github.com/mgossman71/InvokeAI-on-Proxmox-LXC-with-RTX-5070Ti) - Server installation guide

### Model Documentation
- [FLUX.1 Documentation](https://blackforestlabs.ai/)
- [Stable Diffusion XL](https://stability.ai/stable-diffusion)

---

## License

This integration guide is provided as-is for the OpenClaw community.

## Contributing

To add learnings or corrections:
1. Fork this repository
2. Add your findings
3. Submit a pull request

For questions about InvokeAI itself, refer to the official InvokeAI documentation and GitHub issues.
