# InvokeAI Skill - Professional Image Generation

## Overview

This skill provides professional-grade image generation using InvokeAI's graph-based API. It supports model selection, prompt templates, and full parameter control.

**Base URL**: `http://10.0.0.144:9090`  
**API Reference**: `http://10.0.0.144:9090/docs`  
**MCP Reference**: https://github.com/coinstax/invokeai-mcp-server

## Related Skills
- **pro-infographic**: For infographics WITH readable text (uses external API models)
- **stable-diffusion**: Alternative local SD server at `http://10.0.0.155:7860`

---

## Quick Start

### Generate an Image (Default Settings)
```bash
cd /root/.openclaw/workspace/skills/invoke-ai
./generate.sh "a majestic eagle in flight, wildlife photography, dramatic lighting" eagle.png
```

### Generate with Custom Settings
```bash
./generate.sh \
  --prompt "cyberpunk cityscape at night, neon lights, rain, reflective streets, 8k" \
  --model "FLUX.1-dev" \
  --steps 40 \
  --cfg 7.5 \
  --width 1024 \
  --height 768 \
  --sampler "euler" \
  --output /root/.openclaw/workspace/cyberpunk_city.png
```

---

## Configuration

### Server Settings
```json
{
  "invokeai_url": "http://10.0.0.144:9090",
  "queue_id": "default",
  "timeout_seconds": 300,
  "poll_interval_seconds": 2
}
```

### Available Models (as of 2026-04-27)
| Model | Base | Size | Best For |
|-------|------|------|----------|
| `Juggernaut XL v9` | SDXL | 6.46 GB | Photorealistic, portraits, wildlife |
| `FLUX.1-dev` | FLUX | 6.24 GB | General purpose, high quality |
| `FLUX.1-schnell` | FLUX | 6.23 GB | Fast generation (4 steps) |
| `FLUX.1 Krea dev` | FLUX | 6.46 GB | Creative, artistic |
| `FLUX.1 Kontext dev` | FLUX | 6.46 GB | Contextual understanding |

**List Models**: `curl -s "http://10.0.0.144:9090/api/v2/models/?model_type=main" | jq`

## Model Capabilities Matrix
| Capability | SDXL (Juggernaut) | FLUX.1-dev | Notes |
|------------|---------------------|------------|-------|
| Photorealism | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Both excellent |
| Text rendering | ⭐⭐ (gibberish) | ⭐⭐ (gibberish) | **Diffusion models cannot render real text** |
| Prompt adherence | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | FLUX slightly better |
| Speed | ⭐⭐⭐⭐ | ⭐⭐⭐ | Schnell = very fast |
| Anatomical accuracy | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | Still can fail (e.g., sperm whale vs blue whale) |

## ⚠️ CRITICAL: Text Rendering Limitations

**Diffusion models (FLUX, SDXL, Stable Diffusion) CANNOT reliably render real readable text.**

They learn visual patterns of what text *looks like* but do not understand language. Results:
- Words that look plausible but are gibberish ("SERM WHALE" instead of "SPERM WHALE")
- Lorem ipsum-style placeholder text
- Numbers that look like stats but are nonsensical ("7.73 dB" instead of "230 dB")

### When to Use Which Approach
| Goal | Use | Skill |
|------|-----|-------|
| Text-free illustrations, backgrounds | InvokeAI (FLUX/SDXL) | This skill |
| Text-free infographics, assets | InvokeAI (FLUX/SDXL) | This skill |
| Infographics WITH readable text | `image_generate` (DALL-E 3, Ideogram) | `pro-infographic` skill |
| Professional posters with real data | External API models | `pro-infographic` skill |

### Workarounds for Text in InvokeAI Images
1. **Generate text-free base image** (e.g., "infographic with empty white boxes, no text")
2. **Add text separately** using image editors (GIMP, Canva, Photoshop, or Python PIL)
3. **Or use `pro-infographic` skill** with `image_generate` tool for models that CAN render text

See `/root/.openclaw/workspace/skills/pro-infographic/SKILL.md` for full infographic workflow with readable text.

---

## Prompt Templates

### Photorealistic Portrait
```
{subject}, professional portrait photography, studio lighting, sharp focus, 
8k, highly detailed, skin texture, natural expression
Negative: cartoon, painting, drawing, anime, blurry, deformed, plastic skin
```

### Wildlife Photography
```
{subject} in natural habitat, wildlife photography, telephoto lens, 
dramatic lighting, sharp focus, detailed feathers/fur, 8k
Negative: cartoon, painting, drawing, human, blurry, deformed
```

### Landscape
```
{scene}, landscape photography, golden hour, dramatic sky, 
highly detailed, 8k, wide angle
Negative: cartoon, painting, drawing, people, blurry, distorted
```

### Cyberpunk/Sci-Fi
```
{scene}, cyberpunk, neon lights, futuristic, highly detailed, 
8k, dramatic lighting, reflective surfaces
Negative: cartoon, painting, drawing, blurry, deformed, low quality
```

### Fantasy Art
```
{subject}, fantasy art, digital painting, dramatic lighting, 
intricate details, magical atmosphere, 8k
Negative: photo, realistic, blurry, deformed, low quality
```

### Product Photography
```
{product}, professional product photography, studio lighting, 
clean background, sharp focus, commercial quality, 8k
Negative: cartoon, painting, drawing, people, cluttered background
```

---

## Tunable Parameters

### Core Parameters
| Parameter | Type | Default | Range | Description |
|-----------|------|---------|-------|-------------|
| `prompt` | string | (required) | - | Main text prompt |
| `negative_prompt` | string | "" | - | What to avoid |
| `model` | string | "Juggernaut XL v9" | - | Model key from /api/v2/models/ |
| `seed` | int | -1 (random) | 0-2³² | -1 for random |
| `width` | int | 1024 | 512-2048 | Image width (multiple of 64) |
| `height` | int | 768 | 512-2048 | Image height (multiple of 64) |

### Generation Parameters
| Parameter | Type | Default | Range | Description |
|-----------|------|---------|-------|-------------|
| `steps` | int | 30 | 1-150 | Diffusion steps (more = better quality) |
| `cfg_scale` | float | 7.5 | 1-20 | Prompt adherence (higher = stricter) |
| `scheduler` | string | "euler" | - | Sampler: euler, dpmpp_2m_sde_k, lcm, heun |
| `denoising_start` | float | 0 | 0-1 | When to start denoising (for img2img) |
| `denoising_end` | float | 1 | 0-1 | When to stop denoising |

### Advanced Parameters
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `use_cpu` | bool | false | Use CPU for noise generation (slower) |
| `is_intermediate` | bool | false | Save as intermediate (for workflows) |
| `board` | string | "" | Board name for organization |

### Seed Behavior
| Seed Value | Result | Use Case |
|------------|--------|----------|
| `-1` or omitted | **Random** — unique image every time | Default for exploration and variation |
| Fixed number (e.g., `42`, `777`) | **Reproducible** — same prompt + seed = same image | A/B testing, comparisons, replicating a good result |

**Best Practice:** Use `seed: -1` for default generation. Only fix the seed when you want to reproduce or iterate on a specific result.

---

## Graph Structure

InvokeAI uses a node-based graph. The graph structure differs between SDXL and FLUX models.

### SDXL Graph (Standard)

#### Nodes (dict keyed by node name)
```json
{
  "model_loader": {
    "type": "sdxl_model_loader",
    "id": "model_loader",
    "model": {"key": "...", "hash": "...", "name": "...", "base": "sdxl", "type": "main"}
  },
  "positive_prompt": {
    "type": "sdxl_compel_prompt",
    "id": "positive_prompt",
    "prompt": "your prompt here",
    "style": "optional style"
  },
  "negative_prompt": {
    "type": "sdxl_compel_prompt",
    "id": "negative_prompt",
    "prompt": "negative prompt",
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
    "id": "latents_to_image",
    "is_intermediate": true
  },
  "save_image": {
    "type": "save_image",
    "id": "save_image",
    "is_intermediate": false
  }
}
```

#### SDXL Edges
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

### FLUX Graph (Different Structure)

**Key differences from SDXL:**
- Uses `flux_model_loader` instead of `sdxl_model_loader`
- Uses `flux_text_encoder` instead of `sdxl_compel_prompt`
- No `noise` node — seed/width/height are in `flux_denoise`
- No `negative_prompt` node — FLUX doesn't use negative prompts
- Uses `flux_vae_decode` instead of `l2i`
- No `cfg_scale` parameter (use `guidance` instead)
- Requires `t5_encoder_model` and `clip_embed_model` in model loader

#### FLUX Nodes
```json
{
  "model_loader": {
    "type": "flux_model_loader",
    "id": "model_loader",
    "model": {"key": "4279ed9f-ee14-44b6-a43a-3413b1edfd5a", "hash": "blake3:8e532c2cb80971c1fc56074e63adcfcaba7b2e1c7c79afda98a459aafd4f4b87", "name": "FLUX.1 dev (quantized)", "base": "flux", "type": "main"},
    "t5_encoder_model": {"key": "a0be381d-353a-4720-b28c-0cc63d2d9f0d", "hash": "blake3:12f3f5d4856e684c627c0b5c403ace83a8e8baaf0fa6518cd230b5ec1c519107", "name": "t5_base_encoder", "base": "any", "type": "t5_encoder"},
    "clip_embed_model": {"key": "0c55e4d1-7042-4e65-b65d-1e500e802865", "hash": "blake3:17c19f0ef941c3b7609a9c94a659ca5364de0be364a91d4179f0e39ba17c3b70", "name": "clip-vit-large-patch14", "base": "any", "type": "clip_embed"},
    "vae_model": {"key": "151393bc-1b21-42fe-b147-ecaceb35d278", "hash": "blake3:ce21cb76364aa6e2421311cf4a4b5eb052a76c4f1cd207b50703d8978198a068", "name": "FLUX.1-schnell_ae", "base": "flux", "type": "vae"}
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
    "seed": 2847561923,
    "guidance": 3.5
  },
  "vae_decode": {
    "type": "flux_vae_decode",
    "id": "vae_decode",
    "is_intermediate": true
  },
  "save_image": {
    "type": "save_image",
    "id": "save_image",
    "is_intermediate": false
  }
}
```

#### FLUX Edges
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

### Batch Request (Same for both)
```json
{
  "batch": {
    "graph": {
      "id": "unique_graph_id",
      "nodes": {...},
      "edges": [...]
    },
    "runs": 1,
    "data": null
  }
}
```

---

## API Endpoints

### List Models
```bash
curl -s "http://10.0.0.144:9090/api/v2/models/?model_type=main" | jq
```

### Get Model Info
```bash
curl -s "http://10.0.0.144:9090/api/v2/models/i/{model_key}" | jq
```

### Enqueue Generation
```bash
curl -s -X POST "http://10.0.0.144:9090/api/v1/queue/default/enqueue_batch" \
  -H "Content-Type: application/json" \
  -d @request.json | jq
```

### Check Status
```bash
curl -s "http://10.0.0.144:9090/api/v1/queue/default/b/{batch_id}/status" | jq
```

### List Images
```bash
curl -s "http://10.0.0.144:9090/api/v1/images/?is_intermediate=false&limit=10" | jq
```

### Download Image
```bash
curl -s "http://10.0.0.144:9090/api/v1/images/i/{image_name}/full" -o output.png
```

---

## Helper Script: generate.sh

**⚠️ IMPORTANT: This helper script supports SDXL models only.** It does NOT support FLUX models because FLUX requires a completely different graph structure (different node types, no noise node, no negative prompt, etc.).

For FLUX generation, use the Python API examples in the "Graph Structure" section below, or modify the script to detect FLUX models and build the appropriate graph.

```bash
#!/bin/bash
# InvokeAI Image Generation Helper (SDXL ONLY)
# Usage: ./generate.sh --prompt "text" --model "model_key" --output path.png
# NOTE: For FLUX models, use the Python API directly

set -e

INVOKEAI_URL="http://10.0.0.144:9090"
QUEUE_ID="default"

# Defaults
PROMPT=""
NEGATIVE_PROMPT="blurry, deformed, ugly, cartoon, painting, drawing, low quality, distorted"
MODEL_KEY=""
STEPS=30
CFG_SCALE=7.5
SCHEDULER="euler"
WIDTH=1024
HEIGHT=768
SEED=-1
OUTPUT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --prompt) PROMPT="$2"; shift 2 ;;
    --negative) NEGATIVE_PROMPT="$2"; shift 2 ;;
    --model) MODEL_KEY="$2"; shift 2 ;;
    --steps) STEPS="$2"; shift 2 ;;
    --cfg) CFG_SCALE="$2"; shift 2 ;;
    --sampler) SCHEDULER="$2"; shift 2 ;;
    --width) WIDTH="$2"; shift 2 ;;
    --height) HEIGHT="$2"; shift 2 ;;
    --seed) SEED="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "$PROMPT" ]; then
  echo "Error: --prompt is required"
  exit 1
fi

if [ -z "$MODEL_KEY" ]; then
  # Default to Jernaut XL v9
  MODEL_KEY="juggernaut-xl-v9"
fi

# Generate random seed if not provided
if [ "$SEED" = "-1" ]; then
  SEED=$RANDOM
fi

echo "Generating image..."
echo "  Model: $MODEL_KEY"
echo "  Prompt: $PROMPT"
echo "  Size: ${WIDTH}x${HEIGHT}"
echo "  Steps: $STEPS, CFG: $CFG_SCALE, Scheduler: $SCHEDULER"
echo "  Seed: $SEED"

# Create Python script for graph generation
python3 << PYEOF
import json, random, urllib.request, urllib.error, time, sys

INVOKEAI_URL = "$INVOKEAI_URL"
QUEUE_ID = "$QUEUE_ID"

def api_get(path):
    req = urllib.request.Request(f"{INVOKEAI_URL}{path}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())

def api_post(path, data):
    req = urllib.request.Request(f"{INVOKEAI_URL}{path}", 
                                  data=json.dumps(data).encode(),
                                  headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())

def api_get_binary(path):
    req = urllib.request.Request(f"{INVOKEAI_URL}{path}")
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()

# Get model info
try:
    model_info = api_get(f"/api/v2/models/i/$MODEL_KEY")
except Exception as e:
    print(f"Error fetching model info: {e}")
    sys.exit(1)

print(f"Using model: {model_info.get('name', 'unknown')}")

is_sdxl = model_info.get("base") == "sdxl"
model_type = "sdxl_model_loader" if is_sdxl else "main_model_loader"
prompt_type = "sdxl_compel_prompt" if is_sdxl else "compel"

# Build graph
graph = {
    "id": f"gen_{random.randint(1000,9999)}",
    "nodes": {
        "model_loader": {
            "type": model_type,
            "id": "model_loader",
            "model": {"key": model_info["key"], "hash": model_info["hash"], "name": model_info["name"], "base": model_info["base"], "type": model_info["type"]}
        },
        "positive_prompt": {"type": prompt_type, "id": "positive_prompt", "prompt": """$PROMPT""", "style": "$PROMPT" if is_sdxl else ""},
        "negative_prompt": {"type": prompt_type, "id": "negative_prompt", "prompt": """$NEGATIVE_PROMPT""", "style": ""},
        "noise": {"type": "noise", "id": "noise", "seed": $SEED, "width": $WIDTH, "height": $HEIGHT, "use_cpu": False},
        "denoise": {"type": "denoise_latents", "id": "denoise", "steps": $STEPS, "cfg_scale": $CFG_SCALE, "scheduler": "$SCHEDULER", "denoising_start": 0, "denoising_end": 1},
        "latents_to_image": {"type": "l2i", "id": "latents_to_image", "is_intermediate": True},
        "save_image": {"type": "save_image", "id": "save_image", "is_intermediate": False}
    },
    "edges": [
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
}

# Enqueue
batch = {"batch": {"graph": graph, "runs": 1, "data": None}}
result = api_post("/api/v1/queue/default/enqueue_batch", batch)
batch_id = result.get("batch", {}).get("batch_id", "")

if not batch_id:
    print(f"Error: {result}")
    sys.exit(1)

print(f"Batch: {batch_id}")
print("Generating...")

# Wait for completion
for i in range(90):
    time.sleep(2)
    status = api_get(f"/api/v1/queue/default/b/{batch_id}/status")
    if status.get("completed", 0) > 0:
        print("✓ Complete!")
        break
    if status.get("failed", 0) > 0:
        print(f"Failed: {status}")
        sys.exit(1)
    if i % 10 == 0:
        print(f"  ...{i*2}s")

# Get image
images = api_get("/api/v1/images/?is_intermediate=false&limit=1")
if images.get("items"):
    image_name = images["items"][0]["image_name"]
    print(f"Image: {image_name}")
    img_data = api_get_binary(f"/api/v1/images/i/{image_name}/full")
    output_path = "$OUTPUT" if "$OUTPUT" else f"/root/.openclaw/workspace/gen_{batch_id[:8]}.png"
    with open(output_path, "wb") as f:
        f.write(img_data)
    print(f"✓ Saved to {output_path}")
else:
    print("No image found")
    sys.exit(1)
PYEOF

echo "Done!"
```

---

## Best Practices

### Model Selection
- **SDXL models** (Juggernaut XL): Best for photorealistic images, portraits, wildlife
- **FLUX.1-dev**: Best all-rounder, high quality, good prompt adherence
- **FLUX.1-schnell**: Fast (4 steps), good for iterations and testing

### Parameter Tuning
- **Steps**: 25-35 for quality, 4-8 for schnell, 50+ for maximum detail
- **CFG Scale**: 7-8 for natural, 10-12 for strict prompt adherence, 15+ for artistic
- **Scheduler**: 
  - `euler` - Fast, standard quality
  - `dpmpp_2m_sde_k` - Higher quality, slower
  - `lcm` - Optimized for few steps (LCM models)
  - `heun` - 2nd order, best quality, 2x slower

### Prompt Engineering
- Be specific: "golden hour lighting" not just "nice lighting"
- Include style keywords: "wildlife photography", "portrait photography", "digital art"
- Use negative prompts to exclude unwanted elements (SDXL only)
- For FLUX: Be very specific about anatomy and features
- SDXL benefits from the `style` field matching the prompt

### For Text-Free Infographic Bases (InvokeAI)
If you need a clean base image for later text addition:
- Prompt: "infographic with empty white boxes, no text, blank areas for text"
- Generate at high resolution (1024x1536)
- Add text later with image editing tools (GIMP, Canva, Python PIL)
- Or use `pro-infographic` skill for models that CAN render text

### Common Issues
- **"Node not found in graph"**: Ensure nodes dict keys match edge references
- **HTML responses**: API endpoints may return HTML if path is wrong; use exact paths from OpenAPI spec
- **Timeout**: Increase timeout for high step counts or large images
- **No models available**: Check `/api/v2/models/` - models may need to be downloaded
- **Text is gibberish**: See "Text Rendering Limitations" section above. Diffusion models cannot render real text. Use `pro-infographic` skill for readable text.
- **Wrong anatomy** (e.g., blue whale instead of sperm whale): Use extreme specificity in prompts ("massive square block-shaped head", "wrinkled skin", "triangular tail"). Consider generating isolated subject first, then compositing.
- **CUDA OutOfMemoryError / OOM**: The full FLUX.1 schnell model is ~33GB and may not fit in VRAM. **Use the quantized model instead**:
  - Full: `3bc65a62-1410-476e-bc44-2c23d6fb278a` (~33GB) — may OOM on 16GB VRAM
  - **Quantized: `5b266dd7-8f77-4416-bdb6-767f07c31acd` (~12GB)** — recommended for limited VRAM
  - Also consider reducing resolution (512×512 instead of 1024×768) to save memory
  - Check queue status with `curl -s "http://10.0.0.144:9090/api/v1/queue/default/list_all"` to see error details
- **Seed collision (quantized FLUX)**: Some quantized FLUX models may produce identical images with different seeds. **Always verify uniqueness**:
  - Generate images with truly random seeds using Python: `seed = random.randint(1000000000, 2000000000)`
  - Verify with MD5: `md5sum image1.png image2.png`
  - If hashes match, the seeds collided — generate new seeds in a different range
- **`seed: -1` is NOT random for FLUX**: InvokeAI's FLUX implementation treats `seed: -1` as a fixed seed. **Always use explicit random seeds**:
  ```python
  import random
  seed = random.randint(1000000000, 2147483647)
  ```
  Then pass the explicit seed in the `flux_denoise` node
- **Seed Collision (Quantized FLUX)**: Quantized FLUX models can produce **identical images** from different seeds. This is a known bug in some quantized implementations.
  - **Symptom**: Same image generated for completely different prompts
  - **Detection**: Compare MD5 hashes of consecutive images
  - **Workaround**: Use widely spaced seeds (1M+ apart) or regenerate with a new random seed
  - **Note**: The `generate.sh` script now detects collisions and warns you
- **JSON creation failures with heredocs**: Shell heredocs don't reliably expand variables for complex JSON. **Always use Python to create JSON**:
  ```python
  import json
  data = {"batch": {"graph": {...}}, "runs": 1}
  with open('request.json', 'w') as f:
      json.dump(data, f)
  ```

## Cross-Reference: When to Use Which Skill

| Use Case | Use This Skill | Tool |
|----------|----------------|------|
| General images, illustrations, backgrounds | invoke-ai | `exec` with curl/Python |
| Wildlife, portraits, product shots | invoke-ai | `exec` with curl/Python |
| Text-free infographic bases | invoke-ai | `exec` with curl/Python |
| Infographics WITH readable text | pro-infographic | `image_generate` |
| Museum posters, field guides | pro-infographic | `image_generate` |
| Instagram posts with text | pro-infographic | `image_generate` |

See `/root/.openclaw/workspace/skills/pro-infographic/SKILL.md` for the complete text-capable infographic workflow.

---

## Testing

### Quick Test
```bash
./generate.sh --prompt "test image, simple composition" --output test.png
```

### Model Test
```bash
# List available models
curl -s "http://10.0.0.144:9090/api/v2/models/?model_type=main" | jq '.models[] | {key, name, base}'
```

### Full Quality Test
```bash
./generate.sh \
  --prompt "professional product photography, luxury watch on velvet, studio lighting, sharp focus, 8k" \
  --model "Juggernaut XL v9" \
  --steps 40 \
  --cfg 7.5 \
  --width 1024 \
  --height 1024 \
  --output product_test.png
```

---

## Credits

- **API Discovery**: InvokeAI OpenAPI spec at `/openapi.json`
- **Reference Implementation**: https://github.com/coinstax/invokeai-mcp-server
- **Documentation**: http://10.0.0.144:9090/docs
