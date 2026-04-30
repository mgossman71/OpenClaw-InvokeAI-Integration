# Image-to-Image (img2img) Guide for InvokeAI

## Overview

Image-to-image editing allows you to transform an existing image using a text prompt while preserving some aspects of the original. The key parameter is **strength**, which controls how much the AI changes vs. preserves.

**Primary Use Case:** Background replacement while preserving foreground subjects.

---

## Quick Start

### Basic img2img Command

```bash
cd /root/.openclaw/workspace/skills/invoke-ai-img2img
./img2img.sh \
  "/path/to/input.jpg" \
  "boy standing with red Honda dirt bike on forest trail, tall pine trees, dappled sunlight" \
  0.55 \
  "/root/.openclaw/workspace/output.png"
```

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image_path` | Path to source image | Required |
| `prompt` | Description of desired output | Required |
| `strength` | Transformation intensity (0.35-0.80) | 0.55 |
| `output` | Output file path | `/root/.openclaw/workspace/output.png` |

---

## Strength Guidelines

The `strength` parameter is the most critical setting for img2img. It determines the balance between preservation and transformation.

### Strength Reference Table

| Strength | Denoising Range | Result | Best For |
|----------|-----------------|--------|----------|
| **0.35-0.45** | 0.65→1.0 to 0.55→1.0 | Minimal changes, high preservation | Subtle adjustments, color correction |
| **0.50-0.60** | 0.50→1.0 to 0.40→1.0 | **Balanced** - background changes, subjects preserved | **Background replacement** |
| **0.65-0.75** | 0.35→1.0 to 0.25→1.0 | Full transformation, some subject distortion | Complete scene reimagining |
| **0.80+** | 0.20→1.0+ | Creative reinterpretation | Artistic variations, not preservation |

### Recommended Strength by Goal

#### Goal: Change Background Only, Preserve Subjects
```
Strength: 0.50-0.60
Prompt: "(subjects:1.3), new background description, lighting, atmosphere"
Negative: "old background, indoor, walls, ceiling, unwanted objects"
```
**Trade-off:** Background change may be subtle; some old elements may remain.

#### Goal: Complete Scene Transformation
```
Strength: 0.65-0.75
Prompt: VERY detailed description of ALL elements (subjects + background)
Negative: "old scene elements, blurry, distorted"
```
**Trade-off:** Subjects will be reconstructed (may have artifacts/differences).

#### Goal: Zero Distortion (Best Quality)
```
Method: Use InvokeAI Unified Canvas web UI
1. Upload image to http://10.0.0.144:9090
2. Go to Unified Canvas
3. Paint mask over background only (protect subjects)
4. Inpaint with background prompt
5. Generate
```
**Result:** Perfect subject preservation, clean background replacement.

---

## Technical Requirements

### 1. Graph Structure (SDXL)

The img2img graph requires specific node types and connections:

```
┌─────────────────┐
│ model_loader    │──unet──┐
│ (sdxl_model_)   │──clip──┼──► positive_prompt
│                 │──clip2─┼──► negative_prompt
│                 │──vae───┼──► image_to_latents
└─────────────────┘        │
                           │
┌─────────────────┐        │
│ image_to_latents│──latents────► denoise
│ (i2l)           │        │
└─────────────────┘        │
                           │
┌─────────────────┐        │
│ noise           │──noise──────► denoise
│ (must match img │        │
│  dimensions!)   │        │
└─────────────────┘        │
                           │
┌─────────────────┐        │
│ positive_prompt │──conditioning─► denoise
└─────────────────┘        │
                           │
┌─────────────────┐        │
│ negative_prompt │──conditioning─► denoise
└─────────────────┘        │
                           │
                    ┌──────▼──────┐
                    │   denoise   │
                    │ (denoise_   │
                    │  latents)   │
                    └──────┬──────┘
                           │ latents
                           ▼
                    ┌──────────────┐
                    │latents_to_   │
                    │image (l2i)   │
                    └──────┬───────┘
                           │ image
                           ▼
                    ┌──────────────┐
                    │ save_image   │
                    └──────────────┘
```

### 2. Critical Connections

**MUST HAVE** these edges or the batch will fail:

```json
// VAE to image_to_latents (COMMONLY MISSED!)
{
  "source": {"node_id": "model_loader", "field": "vae"},
  "destination": {"node_id": "image_to_latents", "field": "vae"}
}

// Image latents to denoise (the img2img connection)
{
  "source": {"node_id": "image_to_latents", "field": "latents"},
  "destination": {"node_id": "denoise", "field": "latents"}
}

// Noise to denoise
{
  "source": {"node_id": "noise", "field": "noise"},
  "destination": {"node_id": "denoise", "field": "noise"}
}
```

### 3. Noise Node Dimensions

**CRITICAL:** The `noise` node's `width` and `height` must exactly match the uploaded image dimensions.

**Wrong:**
```json
"noise": {"width": 512, "height": 512}  // Hardcoded!
```

**Right:**
```python
# Get from upload response
image_name, width, height = upload_image(path)
# Use in noise node
"noise": {"width": width, "height": height}
```

**Error if wrong:**
```
Incompatible 'noise' and 'latents' shapes: 
latents.shape=torch.Size([1, 4, 120, 160]) 
noise.shape=torch.Size([1, 4, 64, 64])
```

### 4. Image Upload Endpoint

```
POST /api/v1/images/upload?image_category=user&is_intermediate=false
Content-Type: multipart/form-data

Response:
{
  "image_name": "uuid.png",
  "width": 1280,
  "height": 960
}
```

**Note:** Endpoint is `/upload` (singular), not `/uploads`.

---

## Complete Working Example

### Python Implementation

```python
import json
import urllib.request
import datetime
import time
import random
import os

INVOKEAI_URL = "http://10.0.0.144:9090"

def upload_image(image_path):
    """Upload image and return image_name, width, height."""
    boundary = f"----WebKitFormBoundary{random.randint(10**9, 10**10-1)}"
    with open(image_path, 'rb') as f:
        file_data = f.read()
    filename = os.path.basename(image_path)
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        f"Content-Type: image/jpeg\r\n\r\n"
    ).encode('utf-8') + file_data + f"\r\n--{boundary}--\r\n".encode('utf-8')
    
    url = f"{INVOKEAI_URL}/api/v1/images/upload?image_category=user&is_intermediate=false"
    req = urllib.request.Request(url, data=body, 
                                  headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        result = json.loads(resp.read().decode())
        return result['image_name'], result['width'], result['height']

def create_img2img_graph(image_name, prompt, negative_prompt, strength, 
                          model_key, steps, cfg_scale, scheduler, seed, width, height):
    """Create SDXL img2img graph."""
    if seed is None:
        seed = random.randint(0, 2**32 - 1)
    
    denoising_start = 1.0 - strength
    
    nodes = {
        "image_to_latents": {
            "type": "i2l",
            "id": "image_to_latents",
            "image": {"image_name": image_name}
        },
        "model_loader": {
            "type": "sdxl_model_loader",
            "id": "model_loader",
            "model": {
                "key": model_key,
                "hash": "blake3:...",  # Get from API
                "name": "Juggernaut XL v9",
                "base": "sdxl",
                "type": "main"
            }
        },
        "positive_prompt": {
            "type": "sdxl_compel_prompt",
            "id": "positive_prompt",
            "prompt": prompt,
            "style": prompt
        },
        "negative_prompt": {
            "type": "sdxl_compel_prompt",
            "id": "negative_prompt",
            "prompt": negative_prompt,
            "style": ""
        },
        "noise": {
            "type": "noise",
            "id": "noise",
            "seed": seed,
            "width": width,    # MUST MATCH IMAGE
            "height": height,  # MUST MATCH IMAGE
            "use_cpu": False
        },
        "denoise": {
            "type": "denoise_latents",
            "id": "denoise",
            "steps": steps,
            "cfg_scale": cfg_scale,
            "scheduler": scheduler,
            "denoising_start": denoising_start,
            "denoising_end": 1.0
        },
        "latents_to_image": {"type": "l2i", "id": "latents_to_image"},
        "save_image": {
            "type": "save_image",
            "id": "save_image",
            "is_intermediate": False
        }
    }
    
    edges = [
        # Model loader connections
        {"source": {"node_id": "model_loader", "field": "unet"}, 
         "destination": {"node_id": "denoise", "field": "unet"}},
        {"source": {"node_id": "model_loader", "field": "clip"}, 
         "destination": {"node_id": "positive_prompt", "field": "clip"}},
        {"source": {"node_id": "model_loader", "field": "clip"}, 
         "destination": {"node_id": "negative_prompt", "field": "clip"}},
        {"source": {"node_id": "model_loader", "field": "clip2"}, 
         "destination": {"node_id": "positive_prompt", "field": "clip2"}},
        {"source": {"node_id": "model_loader", "field": "clip2"}, 
         "destination": {"node_id": "negative_prompt", "field": "clip2"}},
        
        # CRITICAL: VAE to image_to_latents
        {"source": {"node_id": "model_loader", "field": "vae"}, 
         "destination": {"node_id": "image_to_latents", "field": "vae"}},
        
        # Image to latents → denoise
        {"source": {"node_id": "image_to_latents", "field": "latents"}, 
         "destination": {"node_id": "denoise", "field": "latents"}},
        
        # Prompts to denoise
        {"source": {"node_id": "positive_prompt", "field": "conditioning"}, 
         "destination": {"node_id": "denoise", "field": "positive_conditioning"}},
        {"source": {"node_id": "negative_prompt", "field": "conditioning"}, 
         "destination": {"node_id": "denoise", "field": "negative_conditioning"}},
        
        # Noise to denoise
        {"source": {"node_id": "noise", "field": "noise"}, 
         "destination": {"node_id": "denoise", "field": "noise"}},
        
        # Denoise to latents_to_image
        {"source": {"node_id": "denoise", "field": "latents"}, 
         "destination": {"node_id": "latents_to_image", "field": "latents"}},
        
        # VAE to latents_to_image
        {"source": {"node_id": "model_loader", "field": "vae"}, 
         "destination": {"node_id": "latents_to_image", "field": "vae"}},
        
        # Final image to save
        {"source": {"node_id": "latents_to_image", "field": "image"}, 
         "destination": {"node_id": "save_image", "field": "image"}}
    ]
    
    return {"nodes": nodes, "edges": edges}

# Usage
image_name, width, height = upload_image("/path/to/input.jpg")

graph = create_img2img_graph(
    image_name=image_name,
    prompt="(boy with red Honda dirt bike:1.3), forest trail, tall pine trees, dappled sunlight",
    negative_prompt="garage, indoor, walls, ceiling, car, distorted, deformed",
    strength=0.55,  # Balanced
    model_key="a95230a4-0304-451b-9e85-1e112bee1f14",  # Juggernaut XL v9
    steps=35,
    cfg_scale=7.0,
    scheduler="euler",
    seed=None,
    width=width,
    height=height
)

# Enqueue and poll (see examples/flux-request.json for pattern)
```

---

## Prompt Engineering

### Weighted Emphasis Syntax

```
(word)          = 1.1x emphasis
((word))        = 1.21x emphasis
(((word)))      = 1.33x emphasis
(word:1.3)      = 1.3x emphasis (explicit)
(word:0.8)      = 0.8x emphasis (reduced)
```

### Background Replacement Template

```
Positive Prompt:
"(subject description:1.3), (second subject:1.2), 
new background setting, lighting conditions, atmosphere,
style keywords, quality modifiers"

Negative Prompt:
"old background elements, indoor, walls, ceiling, 
unwanted objects, distorted, deformed, blurry, low quality"
```

### Example: Garage → Woods

```
Positive:
"(boy standing between two red Honda CRF dirt bikes:1.3), 
forest trail background, tall pine trees, dappled sunlight 
filtering through canopy, natural dirt path with tire tracks, 
ferns and undergrowth, outdoor motocross adventure, 
professional photography, golden hour lighting, photorealistic"

Negative:
"garage, indoor, warehouse, car, corvette, sports car, 
building, walls, ceiling, concrete floor, tools, shelves, 
enclosed space, artificial lighting, distorted, deformed"
```

---

## Common Errors & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `Node i2l missing connections for field vae` | Missing VAE edge | Add `model_loader.vae` → `image_to_latents.vae` edge |
| `Incompatible 'noise' and 'latents' shapes` | Noise dimensions wrong | Get width/height from upload response |
| `HTTP 405 Method Not Allowed` | Wrong endpoint | Use `/api/v1/images/upload` (singular) |
| Subjects distorted | Strength too high | Lower to 0.45-0.55 |
| Background unchanged | Strength too low | Raise to 0.60-0.70 |
| Empty/dark output | Missing model info | Query API for full model details (hash, name, base, type) |
| `HTTP 422 Unprocessable Entity` | Invalid graph structure | Check node types match model base (sdxl_*) |

---

## Model Compatibility

| Model Base | Model Loader Type | Prompt Node | Supports Negative |
|------------|-------------------|-------------|-------------------|
| SDXL | `sdxl_model_loader` | `sdxl_compel_prompt` | ✅ Yes |
| FLUX | `flux_model_loader` | `flux_text_encoder` | ❌ No |
| SD 1.5 | `main_model_loader` | `compel_prompt` | ✅ Yes |

**Recommended for img2img:** SDXL models (Juggernaut XL v9) - best balance of quality and prompt control.

---

## Session Test Results

**Date:** 2026-04-30
**Task:** Transform garage photo (boy + 2 dirt bikes) to woods trail

| File | Strength | Result |
|------|----------|--------|
| `garage_to_woods_final.png` | 0.75 | Lost the person entirely |
| `garage_to_woods_person_preserved.png` | 0.45 | Person preserved, garage still visible |
| `boy_bikes_woods_trail.png` | 0.38 | Garage barely changed |
| `boy_bikes_woods_v2.png` | 0.68 | Woods background, distorted subjects |
| `boy_bikes_woods_balanced.png` | 0.55 | **Best compromise** |

**Conclusion:** Strength 0.50-0.60 is the sweet spot for background replacement with subject preservation.

---

## Related Documents

- [README.md](../README.md) - Main integration guide
- [LEARNINGS.md](../LEARNINGS.md) - Critical discoveries
- [examples/sdxl-img2img-request.json](../examples/sdxl-img2img-request.json) - Complete graph example
- [InvokeAI Unified Canvas](http://10.0.0.144:9090) - Web UI for manual inpainting

---

## References

- InvokeAI Official Docs: https://invoke-ai.github.io/InvokeAI/
- MCP Server Reference: https://github.com/coinstax/invokeai-mcp-server
- OpenClaw InvokeAI Skill: `/root/.openclaw/workspace/skills/invoke-ai-img2img/SKILL.md`
