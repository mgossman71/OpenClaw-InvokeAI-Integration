# InvokeAI Skill - Professional Image Generation

## Overview

This skill provides professional-grade image generation using InvokeAI's graph-based API. It supports model selection, prompt templates, and full parameter control.

**Base URL**: `http://10.0.0.144:9090`  
**API Reference**: `http://10.0.0.144:9090/docs`  
**MCP Reference**: https://github.com/coinstax/invokeai-mcp-server

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

---

## Graph Structure

InvokeAI uses a node-based graph. Here's the standard text-to-image graph:

### Nodes (dict keyed by node name)
```json
{
  "model_loader": {
    "type": "sdxl_model_loader",  // or "main_model_loader" for SD1.5
    "id": "model_loader",
    "model": {"key": "...", "hash": "...", "name": "...", "base": "sdxl", "type": "main"}
  },
  "positive_prompt": {
    "type": "sdxl_compel_prompt",  // or "compel" for SD1.5
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
    "id": "latents_to_image"
  },
  "save_image": {
    "type": "save_image",
    "id": "save_image",
    "is_intermediate": false
  }
}
```

### Edges (array of connections)
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

### Batch Request
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

```bash
#!/bin/bash
# InvokeAI Image Generation Helper
# Usage: ./generate.sh --prompt "text" --model "model_key" --output path.png

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
        "latents_to_image": {"type": "l2i", "id": "latents_to_image"},
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
- Use negative prompts to exclude unwanted elements
- SDXL benefits from the `style` field matching the prompt

### Common Issues
- **"Node not found in graph"**: Ensure nodes dict keys match edge references
- **HTML responses**: API endpoints may return HTML if path is wrong; use exact paths from OpenAPI spec
- **Timeout**: Increase timeout for high step counts or large images
- **No models available**: Check `/api/v2/models/` - models may need to be downloaded

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
