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

## Step-by-Step Workflow

### For Any Model Type

#### Step 1: Determine Model Type
```bash
# Get model info
curl -s http://10.0.0.144:9090/api/v2/models/i/{model_key} | jq '.base'
```
- `"sdxl"` → Use **SDXL Graph**
- `"flux"` → Use **FLUX Graph**
- `"sd-1"` → Use **SD 1.5 Graph**

#### Step 2: Get Required Sub-Models (FLUX only)
```bash
# List all models to find sub-model keys
curl -s "http://10.0.0.144:9090/api/v2/models/?limit=200" | jq '.items[] | {key, name, base, type}'
```

#### Step 3: Build the Request File
```bash
# Choose the appropriate template:
# - SDXL: examples/sdxl-request.json
# - FLUX: examples/flux-request.json
# - SD 1.5: Modify SDXL template with compel instead of sdxl_compel_prompt
```

#### Step 4: Submit the Job
```bash
cat > /tmp/request.json << 'EOF'
{ "batch": { "graph": { ... }, "runs": 1, "data": null } }
EOF

curl -s -X POST http://10.0.0.144:9090/api/v1/queue/default/enqueue_batch \
  -H "Content-Type: application/json" \
  -d @/tmp/request.json | jq
```

#### Step 5: Poll for Completion
```bash
# Use batch_id from Step 4 response
curl -s http://10.0.0.144:9090/api/v1/queue/default/b/{batch_id}/status | jq
```

#### Step 6: Retrieve Image
```bash
# List completed images
curl -s "http://10.0.0.144:9090/api/v1/images/?is_intermediate=false&limit=1" | jq

# Download specific image
curl -s "http://10.0.0.144:9090/api/v1/images/i/{image_name}/full" -o output.png
```

---

## Quick Start

### Generate an Image (cURL - SDXL Example)

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
          "model": {"key": "a95230a4-0304-451b-9e85-1e112bee1f14", "hash": "...", "name": "Juggernaut XL v9", "base": "sdxl", "type": "main"}
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
          "seed": -1,
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

**Note**: For FLUX, use the FLUX graph structure from the section above. The workflow is identical, only the graph nodes/edges differ.

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
| `a95230a4-0304-451b-9e85-1e112bee1f14` | SDXL | 6.46 GB | Photorealistic, portraits, wildlife | High detail |
| `4279ed9f-ee14-44b6-a43a-3413b1edfd5a` | FLUX.1 dev (quantized) | FLUX | 6.24 GB | General purpose, high quality | Best prompt adherence |
| `3bc65a62-1410-476e-bc44-2c23d6fb278a` | FLUX.1 schnell | FLUX | 6.23 GB | Fast iterations | 4-step generation |
| `c9465203-d02e-4f7b-b54e-31680f0bcc04` | FLUX.1 Krea dev (quantized) | FLUX | 6.46 GB | Creative, artistic | Artistic styles |
| `f1e16898-132d-4233-9551-304e8f445f94` | FLUX.1 Kontext dev (quantized) | FLUX | 6.46 GB | Contextual understanding | Complex scenes |

### Get Model Details
```bash
curl -s "http://10.0.0.144:9090/api/v2/models/i/{model_key}" | jq
```

---

## Understanding Model Types

InvokeAI supports multiple model architectures, each requiring **completely different graph structures**. This is the most common source of errors.

### Quick Decision Guide

| If you want... | Use Model | Graph Type | Key Difference |
|----------------|-----------|------------|----------------|
| Photorealistic portraits, wildlife | SDXL | SDXL Graph | Has negative prompts, cfg_scale |
| Best prompt adherence, general use | FLUX | FLUX Graph | No negative prompts, uses guidance |
| Fast iterations, simple compositions | SD 1.5 | SD 1.5 Graph | Smaller, simpler structure |

---

### SDXL (Stable Diffusion XL)

**When to use**: Photorealistic images, portraits, wildlife photography, detailed scenes

**Required Nodes**:
- `sdxl_model_loader` - Loads the SDXL model
- `sdxl_compel_prompt` (×2) - Positive and negative prompts
- `noise` - Generates random noise (contains seed, width, height)
- `denoise_latents` - The denoising process (uses cfg_scale)
- `l2i` - Converts latents to image
- `save_image` - Saves the output

**Key Parameters**:
- `cfg_scale`: 7.5-12 (controls prompt adherence)
- `steps`: 30-50
- `scheduler`: euler, dpmpp_2m_sde_k

**Why it's different**: SDXL has two text encoders (clip and clip2), supports negative prompts, and uses the traditional cfg_scale approach.

**Common Mistake**: Forgetting the `noise` node. SDXL requires explicit noise generation.

---

### FLUX (Black Forest Labs)

**When to use**: General purpose, highest quality, best prompt adherence, complex scenes

**Required Nodes**:
- `flux_model_loader` - Loads FLUX + 3 sub-models
- `flux_text_encoder` - Encodes the prompt (uses t5_encoder + clip)
- `flux_denoise` - Denoising (contains seed, width, height, guidance)
- `flux_vae_decode` - Decodes latents to image
- `save_image` - Saves the output

**Key Parameters**:
- `guidance`: 3.5-5.0 (replaces cfg_scale)
- `num_steps`: 20-30 (FLUX converges faster)
- `cfg_scale`: Always 1.0 (ignored, but required)

**Required Sub-Models** (must be loaded in flux_model_loader):
- `t5_encoder_model` - Text encoder (e.g., "t5_bnb_int8_quantized_encoder")
- `clip_embed_model` - CLIP embedder (e.g., "clip-vit-large-patch14")
- `vae_model` - VAE decoder (e.g., "FLUX.1-schnell_ae")

**Why it's different**: 
- No `noise` node (seed/width/height are in `flux_denoise`)
- No negative prompts (FLUX doesn't use them)
- No `cfg_scale` (uses `guidance` instead)
- Requires 3 additional sub-models
- Uses `transformer` field instead of `unet`

**Critical Warning**: If you forget the sub-models, FLUX will fail silently or produce garbage output.

---

### SD 1.5 (Stable Diffusion 1.5)

**When to use**: Quick iterations, simpler compositions, lower memory usage

**Required Nodes**:
- `main_model_loader` - Loads the SD 1.5 model
- `compel` (×2) - Positive and negative prompts
- `noise` - Generates random noise
- `denoise_latents` - The denoising process
- `l2i` - Converts latents to image
- `save_image` - Saves the output

**Key Parameters**:
- `cfg_scale`: 7.5-12
- `steps`: 20-40
- `width/height`: 512×512 (default), up to 768×768

**Why it's different**: Similar to SDXL but uses `compel` instead of `sdxl_compel_prompt`, and only has one CLIP encoder.

---

### ⚠️ CRITICAL: Graph Structure Must Match Model Type

**Using the wrong graph structure is the #1 failure mode.**

| Model Type | Wrong Graph | Result |
|------------|-------------|--------|
| FLUX | SDXL graph | "Node not found" or silent failure |
| SDXL | FLUX graph | "Field 'unet' not found" |
| SD 1.5 | SDXL graph | "Field 'clip2' not found" |

**Always check the model's `base` field** from `/api/v2/models/i/{model_key}` to determine which graph to use:
- `"base": "sdxl"` → Use SDXL graph
- `"base": "flux"` → Use FLUX graph
- `"base": "sd-1"` → Use SD 1.5 graph

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

### Request Structure (All Models)

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

### ⚠️ Critical Rules

1. **Nodes are a dictionary** keyed by node name, NOT an array
2. **Node `id` must match** the dictionary key exactly
3. **Edges reference nodes** by their `id` field, not the key
4. **All edges must connect** existing nodes and valid fields
5. **Graph structure must match** the model type (SDXL/FLUX/SD1.5)
6. **Model keys must be exact** from `/api/v2/models/` endpoint

---

---

## Graph Structure Reference

### SDXL Graph

#### Nodes
```json
{
  "model_loader": {
    "type": "sdxl_model_loader",
    "id": "model_loader",
    "model": {"key": "a95230a4-0304-451b-9e85-1e112bee1f14", "hash": "...", "name": "Juggernaut XL v9", "base": "sdxl", "type": "main"}
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
    "seed": -1,
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
    "model": {"key": "4279ed9f-ee14-44b6-a43a-3413b1edfd5a", "hash": "...", "name": "FLUX.1 dev", "base": "flux", "type": "main"},
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
    "seed": -1,
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
    "seed": -1,
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

## Model Comparison & Selection Guide

### Detailed Comparison

| Feature | SDXL | FLUX | SD 1.5 |
|---------|------|------|--------|
| **Best Use Case** | Photorealism, portraits | General purpose, quality | Quick iterations |
| **Node Loader** | `sdxl_model_loader` | `flux_model_loader` | `main_model_loader` |
| **Prompt Node** | `sdxl_compel_prompt` | `flux_text_encoder` | `compel` |
| **Denoise Node** | `denoise_latents` | `flux_denoise` | `denoise_latents` |
| **Image Decode** | `l2i` | `flux_vae_decode` | `l2i` |
| **Negative Prompts** | ✅ Yes | ❌ No | ✅ Yes |
| **Sub-models Required** | None | 3 (t5, clip, vae) | None |
| **Noise Node** | ✅ Yes | ❌ No (in denoise) | ✅ Yes |
| **Guidance Parameter** | N/A (uses cfg_scale) | ✅ Yes (3.5-5.0) | N/A (uses cfg_scale) |
| **cfg_scale** | 7.5-12 | 1.0 (ignored) | 7.5-12 |
| **Steps** | 30-50 | 20-30 | 20-40 |
| **Memory Usage** | High | Very High | Medium |
| **Speed** | Medium | Slower | Fast |
| **Text Rendering** | ❌ No | ❌ No | ❌ No |
| **Anatomy Accuracy** | Good | Better | Good |

---

### When to Use Which Model

**Choose SDXL when**:
- You need photorealistic portraits
- You want negative prompts to control exclusions
- You're doing wildlife/nature photography style
- You need the `style` field for artistic control

**Choose FLUX when**:
- You want best overall quality
- You need good prompt adherence
- You're doing complex scenes with multiple subjects
- You have enough VRAM (FLUX needs more memory)

**Choose SD 1.5 when**:
- You need quick iterations for testing
- You have limited VRAM
- You're doing simpler compositions
- You're fine-tuning or training LoRAs

---

### Cross-Reference: Related Skills & Tools

| Need | Use This | Repository |
|------|----------|------------|
| Readable text infographics | `pro-infographic` skill | (Separate skill) |
| Simple prompt-based generation | Stable Diffusion API | http://10.0.0.155:7860 |
| InvokeAI graph-based generation | This README | You're here! |
| FLUX prompt examples | `flux-prompt-examples` | https://github.com/mgossman71/flux-prompt-examples |
| Server installation | Proxmox LXC guide | https://github.com/mgossman71/InvokeAI-on-Proxmox-LXC-with-RTX-5070Ti |

---

## Prompt Engineering

### Best Practices by Model

**SDXL**:
- Be specific: "golden hour lighting" not just "nice lighting"
- Use the `style` field to match the prompt
- Include negative prompts for quality: "blurry, deformed, ugly, low quality"
- Good for: "portrait photography, 85mm lens, f/1.8, shallow depth of field"

**FLUX**:
- Be extremely specific about anatomy and features
- Describe spatial relationships: "subject on left, background on right"
- Use natural language: "a majestic sperm whale with massive square block-shaped head"
- No negative prompts - describe what you want, not what you don't want
- Good for: complex scenes, multiple subjects, precise compositions

**SD 1.5**:
- Simpler prompts work well
- Use negative prompts for quality control
- Good for: quick tests, simpler compositions

### Parameter Guidelines

| Parameter | SDXL | FLUX | SD 1.5 | Notes |
|-----------|------|------|--------|-------|
| Steps | 30-50 | 20-30 | 20-40 | FLUX converges faster |
| CFG Scale | 7.5-12 | 1.0 | 7.5-12 | FLAX uses guidance |
| Guidance | N/A | 3.5-5.0 | N/A | FLUX-specific |
| Scheduler | euler, dpmpp_2m_sde_k | euler | euler | |
| Width | 1024 | 1024 | 512 | Multiple of 64 |
| Height | 768-1536 | 768-1536 | 512-768 | Multiple of 64 |
| **Seed** | **-1** | **-1** | **-1** | **-1 = random (recommended)** |

### Seed Behavior

| Seed Value | Result | Use Case |
|------------|--------|----------|
| `-1` | **Random** — unique image every time | ✅ **Default for exploration** |
| Fixed number (e.g., `42`, `777`) | **Reproducible** — same prompt + seed = same image | A/B testing, comparisons, replicating a good result |

**Best Practice:** Always use `seed: -1` for default generation. Only fix the seed when you need to reproduce or iterate on a specific result.

---

---

## Common Issues & Troubleshooting

### "Node not found in graph"
**Cause**: Node dictionary keys don't match edge references, or node `id` doesn't match the key.
**Fix**: 
1. Ensure node `id` matches the dictionary key exactly
2. Check edge `node_id` references match the keys
3. Verify all nodes referenced in edges exist in the nodes dict

**Example**:
```json
// WRONG - id doesn't match key
{"nodes": {"loader": {"id": "model_loader", ...}}}

// CORRECT - id matches key
{"nodes": {"model_loader": {"id": "model_loader", ...}}}
```

---

### "Field 'unet' not found" (or 'transformer', 'clip', etc.)
**Cause**: Using wrong graph type for the model.
**Fix**: 
1. Check model base: `curl http://SERVER:9090/api/v2/models/i/{model_key}`
2. Use matching graph:
   - `"base": "sdxl"` → SDXL graph (uses `unet`)
   - `"base": "flux"` → FLUX graph (uses `transformer`)
   - `"base": "sd-1"` → SD 1.5 graph (uses `unet`)

---

### FLUX produces blank/garbage output
**Cause**: Missing sub-models in flux_model_loader.
**Fix**: Include ALL 3 sub-models:
```json
"model_loader": {
  "type": "flux_model_loader",
  "model": {"key": "4279ed9f-ee14-44b6-a43a-3413b1edfd5a", "base": "flux", "type": "main"},
  "t5_encoder_model": {"key": "...", "type": "t5_encoder"},
  "clip_embed_model": {"key": "...", "type": "clip_embed"},
  "vae_model": {"key": "...", "type": "vae"}
}
```
Get sub-model keys from: `curl http://SERVER:9090/api/v2/models/?model_type=main`

---

### HTML responses instead of JSON
**Cause**: Wrong API endpoint or missing Content-Type header.
**Fix**: 
1. Use exact paths from OpenAPI spec at `/openapi.json`
2. Always include `-H "Content-Type: application/json"`
3. Use `-d @file.json` not `-d "{...}"` (avoids shell escaping issues)

---

### Timeout errors
**Cause**: Request takes longer than client timeout.
**Fix**: 
1. Increase curl timeout: `curl --max-time 300 ...`
2. Reduce steps for testing (FLUX: 20 steps, SDXL: 25 steps)
3. Use smaller resolution for testing (512×512)
4. Check server logs: `journalctl -u invokeai -f`

---

### "Model not found"
**Cause**: Model key doesn't exist or model not downloaded.
**Fix**: 
1. List available models: `curl http://SERVER:9090/api/v2/models/`
2. Check model key matches exactly (case-sensitive)
3. Download model via InvokeAI web UI if missing
4. Use exact key from API response, not display name

---

### Text renders as gibberish
**Cause**: Diffusion models fundamentally cannot render real text.
**Fix**: 
- **Understand**: This is normal behavior, not a bug
- **For infographics**: Use external API models (DALL-E 3, Ideogram) that support text
- **Workaround**: Generate text-free base image, add text with image editor (Photoshop, GIMP)
- **Never**: Try to get diffusion models to render readable text - it's mathematically impossible

---

### Wrong anatomy or subject
**Cause**: Prompt too generic, model confusion.
**Fix**: 
1. Use extreme specificity: "massive square block-shaped head" not just "big head"
2. Describe distinctive features: "wrinkled dark gray skin", "triangular tail flukes"
3. Include context: "underwater photography", "size comparison with diver"
4. For FLUX: Describe spatial relationships explicitly
5. Use negative prompts (SDXL/SD1.5): "blue whale, humpback whale, orca"

---

### High memory usage / OOM errors
**Cause**: Model too large for available VRAM.
**Fix**: 
1. Use quantized models (bnb_nf4, gguf) - check model name for "quantized"
2. Reduce resolution (1024×1024 uses less memory than 2048×2048)
3. Close other GPU applications
4. Enable CPU offloading in invokeai.yaml
5. For FLUX: Use `3bc65a62-1410-476e-bc44-2c23d6fb278a` (FLUX.1 schnell, faster, slightly less quality)

---

### Slow generation
**Cause**: High step count, large resolution, or CPU fallback.
**Fix**: 
1. Reduce steps: FLUX 20-25, SDXL 25-30
2. Check GPU is being used (not CPU): `nvidia-smi` during generation
3. Use schnell models for quick iterations
4. Enable xformers or flash attention if available

---

### "Invalid graph structure"
**Cause**: Missing required edges or disconnected nodes.
**Fix**: 
1. Every node (except model_loader) must have an incoming edge
2. Every field referenced in edges must exist in the node type
3. Follow the exact edge patterns in the examples above
4. Use the SDXL edges for SDXL, FLUX edges for FLUX (they're different!)

---

### Authentication errors
**Cause**: InvokeAI configured for multi-user mode.
**Fix**: 
1. Check invokeai.yaml: `multiuser: false` for no auth
2. If multiuser is enabled, provide API token in header
3. Default single-user mode requires no authentication

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

## Lessons Learned the Hard Way

This section documents the painful discoveries from hours of trial and error. Read this BEFORE you start debugging.

### The "Nodes Are a Dictionary" Trap
**What we tried:** Array of nodes `[{"type": "..."}, {"type": "..."}]`  
**What happened:** Silent failures, node not found errors  
**The fix:** Nodes must be a dictionary keyed by name: `{"model_loader": {"type": "..."}, "prompt": {"type": "..."}}`  
**Where it's documented:** [Graph Structure Reference](#graph-structure-reference)

### The "Wrong Graph for Model" Trap
**What we tried:** Using SDXL graph with FLUX model  
**What happened:** "Node not found in graph" or "Field 'unet' not found"  
**The fix:** Check model base type first (`sdxl`, `flux`, or `sd-1`), then use matching graph  
**Where it's documented:** [Understanding Model Types](#understanding-model-types)

### The "Missing FLUX Sub-Models" Trap
**What we tried:** FLUX graph without t5_encoder_model, clip_embed_model, vae_model  
**What happened:** Blank white image or completely garbled output (no error message!)  
**The fix:** Must include ALL 3 sub-models in flux_model_loader node  
**Where it's documented:** [FLUX Graph](#flux-graph)

### The "Batch Wrapper" Trap
**What we tried:** Sending graph directly without batch wrapper  
**What happened:** API rejected the request  
**The fix:** Must wrap in `{"batch": {"graph": graph, "runs": 1, "data": null}}`  
**Where it's documented:** [Request Structure](#request-structure-all-models)

### The "Model Key Exact Match" Trap
**What we tried:** Using display name or partial key  
**What happened:** "Model not found" errors  
**The fix:** Must use exact key from `/api/v2/models/` endpoint  
**Where it's documented:** [Available Models](#available-models)

### The "Text Is Always Gibberish" Reality
**What we tried:** Asking for text in images (infographic text, signs, labels)  
**What happened:** Text-like patterns that aren't readable  
**The fix:** Use external APIs (DALL-E 3, Ideogram) for real text, or generate text-free base and add text later  
**Where it's documented:** [Text Rendering Limitations](#text-rendering-limitations)

### The "HTML Instead of JSON" Trap
**What we tried:** Wrong API endpoint  
**What happened:** Got HTML response instead of JSON  
**The fix:** Use `/api/v1/queue/default/enqueue_batch` not `/api/v1/queue`  
**Where it's documented:** [Common Issues](#common-issues--troubleshooting)

---

## License

This integration guide is provided as-is for the OpenClaw community.

## Contributing

To add learnings or corrections:
1. Fork this repository
2. Add your findings
3. Submit a pull request

For questions about InvokeAI itself, refer to the official InvokeAI documentation and GitHub issues.
