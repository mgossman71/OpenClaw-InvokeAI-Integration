# Working Examples

## Example 1: FLUX Schnell Generation (Fast)

```python
import json, random, urllib.request

INVOKEAI_URL = "http://YOUR_SERVER:9090"

def api_post(path, data):
    req = urllib.request.Request(
        f"{INVOKEAI_URL}{path}",
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())

def api_get(path):
    req = urllib.request.Request(f"{INVOKEAI_URL}{path}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())

# Model keys (get from your server)
FLUX_TRANSFORMER = "5b266dd7-8f77-4416-bdb6-767f07c31acd"
T5_ENCODER = "36d7f5c9-03a7-46fa-9f0a-90be4e05d155"
CLIP_EMBED = "0c55e4d1-7042-4e65-b65d-1e500e802865"
FLUX_VAE = "151393bc-1b21-42fe-b147-ecaceb35d278"

def get_model_obj(key):
    info = api_get(f"/api/v2/models/i/{key}")
    return {"key": info["key"], "hash": info["hash"], "name": info["name"], "base": info["base"], "type": info["type"]}

# Build graph
graph = {
    "id": f"flux_{random.randint(1000,9999)}",
    "nodes": {
        "model_loader": {
            "type": "flux_model_loader",
            "id": "model_loader",
            "model": get_model_obj(FLUX_TRANSFORMER),
            "t5_encoder_model": get_model_obj(T5_ENCODER),
            "clip_embed_model": get_model_obj(CLIP_EMBED),
            "vae_model": get_model_obj(FLUX_VAE)
        },
        "prompt": {
            "type": "flux_text_encoder",
            "id": "prompt",
            "prompt": "a beautiful sunset over mountains, highly detailed",
            "t5_max_seq_len": 256
        },
        "denoise": {
            "type": "flux_denoise",
            "id": "denoise",
            "num_steps": 4,
            "cfg_scale": 1.0,
            "scheduler": "euler",
            "width": 1024,
            "height": 1024,
            "seed": -1,
            "guidance": 4.0
        },
        "vae_decode": {
            "type": "flux_vae_decode",
            "id": "vae_decode"
        }
    },
    "edges": [
        {"source": {"node_id": "model_loader", "field": "transformer"}, "destination": {"node_id": "denoise", "field": "transformer"}},
        {"source": {"node_id": "model_loader", "field": "clip"}, "destination": {"node_id": "prompt", "field": "clip"}},
        {"source": {"node_id": "model_loader", "field": "t5_encoder"}, "destination": {"node_id": "prompt", "field": "t5_encoder"}},
        {"source": {"node_id": "prompt", "field": "conditioning"}, "destination": {"node_id": "denoise", "field": "positive_text_conditioning"}},
        {"source": {"node_id": "denoise", "field": "latents"}, "destination": {"node_id": "vae_decode", "field": "latents"}},
        {"source": {"node_id": "model_loader", "field": "vae"}, "destination": {"node_id": "vae_decode", "field": "vae"}}
    ]
}

# Enqueue
result = api_post("/api/v1/queue/default/enqueue_batch", {"batch": {"graph": graph, "runs": 1, "data": None}})
batch_id = result["batch"]["batch_id"]
print(f"Queued: {batch_id}")
```

## Example 2: SDXL Generation

```python
# SDXL only needs one model
JUGGERNAUT_XL = "a2510f8f-c49d-4d37-b2b1-1d4400a26d43"

model_info = get_model_obj(JUGGERNAUT_XL)

graph = {
    "id": f"sdxl_{random.randint(1000,9999)}",
    "nodes": {
        "model_loader": {
            "type": "sdxl_model_loader",
            "id": "model_loader",
            "model": model_info
        },
        "positive_prompt": {
            "type": "sdxl_compel_prompt",
            "id": "positive_prompt",
            "prompt": "professional portrait, studio lighting, 8k",
            "style": "professional portrait photography"
        },
        "negative_prompt": {
            "type": "sdxl_compel_prompt",
            "id": "negative_prompt",
            "prompt": "blurry, deformed, ugly, cartoon",
            "style": ""
        },
        "noise": {
            "type": "noise",
            "id": "noise",
            "seed": -1,
            "width": 1024,
            "height": 768,
            "use_cpu": False
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
            "is_intermediate": False
        }
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
```

## Example 3: Complete Python Script with Polling

```python
#!/usr/bin/env python3
"""Complete InvokeAI generation script with FLUX support."""

import json, random, time, sys
import urllib.request, urllib.error

INVOKEAI_URL = "http://YOUR_SERVER:9090"
QUEUE_ID = "default"

# Model keys - UPDATE THESE for your server
MODELS = {
    "flux_schnell": {
        "transformer": "5b266dd7-8f77-4416-bdb6-767f07c31acd",
        "t5_encoder": "36d7f5c9-03a7-46fa-9f0a-90be4e05d155",
        "clip_embed": "0c55e4d1-7042-4e65-b65d-1e500e802865",
        "vae": "151393bc-1b21-42fe-b147-ecaceb35d278"
    },
    "juggernaut_xl": {
        "main": "a2510f8f-c49d-4d37-b2b1-1d4400a26d43"
    }
}

def api_get(path):
    req = urllib.request.Request(f"{INVOKEAI_URL}{path}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())

def api_post(path, data):
    req = urllib.request.Request(
        f"{INVOKEAI_URL}{path}",
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())

def api_get_binary(path):
    req = urllib.request.Request(f"{INVOKEAI_URL}{path}")
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()

def get_model_obj(key):
    info = api_get(f"/api/v2/models/i/{key}")
    return {
        "key": info["key"],
        "hash": info["hash"],
        "name": info["name"],
        "base": info["base"],
        "type": info["type"]
    }

def generate_flux(prompt, width=1024, height=1024, steps=4, output="output.png"):
    """Generate image using FLUX.1 schnell."""
    m = MODELS["flux_schnell"]
    
    graph = {
        "id": f"flux_{random.randint(1000,9999)}",
        "nodes": {
            "model_loader": {
                "type": "flux_model_loader",
                "id": "model_loader",
                "model": get_model_obj(m["transformer"]),
                "t5_encoder_model": get_model_obj(m["t5_encoder"]),
                "clip_embed_model": get_model_obj(m["clip_embed"]),
                "vae_model": get_model_obj(m["vae"])
            },
            "prompt": {
                "type": "flux_text_encoder",
                "id": "prompt",
                "prompt": prompt,
                "t5_max_seq_len": 256
            },
            "denoise": {
                "type": "flux_denoise",
                "id": "denoise",
                "num_steps": steps,
                "cfg_scale": 1.0,
                "scheduler": "euler",
                "width": width,
                "height": height,
                "seed": -1,
                "guidance": 4.0
            },
            "vae_decode": {
                "type": "flux_vae_decode",
                "id": "vae_decode"
            }
        },
        "edges": [
            {"source": {"node_id": "model_loader", "field": "transformer"}, "destination": {"node_id": "denoise", "field": "transformer"}},
            {"source": {"node_id": "model_loader", "field": "clip"}, "destination": {"node_id": "prompt", "field": "clip"}},
            {"source": {"node_id": "model_loader", "field": "t5_encoder"}, "destination": {"node_id": "prompt", "field": "t5_encoder"}},
            {"source": {"node_id": "prompt", "field": "conditioning"}, "destination": {"node_id": "denoise", "field": "positive_text_conditioning"}},
            {"source": {"node_id": "denoise", "field": "latents"}, "destination": {"node_id": "vae_decode", "field": "latents"}},
            {"source": {"node_id": "model_loader", "field": "vae"}, "destination": {"node_id": "vae_decode", "field": "vae"}}
        ]
    }
    
    # Enqueue
    result = api_post(f"/api/v1/queue/{QUEUE_ID}/enqueue_batch", 
                      {"batch": {"graph": graph, "runs": 1, "data": None}})
    batch_id = result["batch"]["batch_id"]
    print(f"Queued: {batch_id}")
    
    # Poll for completion
    for i in range(60):
        time.sleep(2)
        status = api_get(f"/api/v1/queue/{QUEUE_ID}/b/{batch_id}/status")
        if status.get("completed", 0) > 0:
            print("✓ Complete!")
            break
        if status.get("failed", 0) > 0:
            print(f"✗ Failed: {status}")
            sys.exit(1)
        if i % 5 == 0:
            print(f"  ...{i*2}s")
    
    # Download latest image
    images = api_get("/api/v1/images/?is_intermediate=false&limit=1")
    if images.get("items"):
        image_name = images["items"][0]["image_name"]
        img_data = api_get_binary(f"/api/v1/images/i/{image_name}/full")
        with open(output, "wb") as f:
            f.write(img_data)
        print(f"✓ Saved to {output}")
    else:
        print("✗ No image found")

if __name__ == "__main__":
    generate_flux("a majestic eagle in flight, wildlife photography")
```

## Example 4: Bash One-Liner for Quick Testing

```bash
# Test if server is up
curl -s "http://YOUR_SERVER:9090/api/v1/app/version" | jq

# List all models
curl -s "http://YOUR_SERVER:9090/api/v2/models/?limit=200&offset=0" | jq '.models[] | {key, name, base, type}'

# Get specific model info
curl -s "http://YOUR_SERVER:9090/api/v2/models/i/5b266dd7-8f77-4416-bdb6-767f07c31acd" | jq
```
