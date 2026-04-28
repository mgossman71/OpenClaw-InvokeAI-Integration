#!/bin/bash
# InvokeAI Image Generation Helper - Supports both SDXL and FLUX
# Usage: ./generate.sh --prompt "text" --model "FLUX.1-dev" --output path.png

set -e

INVOKEAI_URL="http://10.0.0.144:9090"
QUEUE_ID="default"

# Defaults
PROMPT=""
NEGATIVE_PROMPT="blurry, deformed, ugly, cartoon, painting, drawing, low quality, distorted"
MODEL_KEY=""
MODEL_NAME=""
STEPS=30
CFG_SCALE=7.5
GUIDANCE=3.5
SCHEDULER="euler"
WIDTH=1024
HEIGHT=1024
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
    --guidance) GUIDANCE="$2"; shift 2 ;;
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
  MODEL_KEY="juggernaut-xl-v9"
  MODEL_NAME="Juggernaut XL v9"
fi

echo "Generating image..."
echo "  Model: ${MODEL_NAME:-$MODEL_KEY}"
echo "  Prompt: $PROMPT"
echo "  Size: ${WIDTH}x${HEIGHT}"
echo "  Steps: $STEPS, CFG: $CFG_SCALE, Guidance: $GUIDANCE, Scheduler: $SCHEDULER"
echo "  Seed: $SEED"

# Create Python script for graph generation
python3 << PYEOF
import json, random, urllib.request, urllib.error, time, sys

INVOKEAI_URL = "$INVOKEAI_URL"

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

model_base = model_info.get("base", "")
model_name = model_info.get("name", "")

# Detect if this is a FLUX model
is_flux = model_base == "flux"

if is_flux:
    # Fetch FLUX sub-models dynamically
    all_models = api_get("/api/v2/models/")
    
    t5_model = None
    clip_model = None
    vae_model = None
    
    for m in all_models.get("models", []):
        if m.get("type") == "t5_encoder":
            t5_model = m
        elif m.get("type") == "clip_embed":
            clip_model = m
        elif m.get("type") == "vae" and "flux" in m.get("name", "").lower():
            vae_model = m
    
    if not t5_model or not clip_model or not vae_model:
        print("Error: Could not find required FLUX sub-models (T5, CLIP, VAE)")
        print(f"  T5: {t5_model}")
        print(f"  CLIP: {clip_model}")
        print(f"  VAE: {vae_model}")
        sys.exit(1)
    
    print(f"  T5 encoder: {t5_model['name']}")
    print(f"  CLIP: {clip_model['name']}")
    print(f"  VAE: {vae_model['name']}")
    
    # Build FLUX graph
    graph = {
        "id": f"gen_{random.randint(1000,9999)}",
        "nodes": {
            "model_loader": {
                "type": "flux_model_loader",
                "id": "model_loader",
                "model": {"key": model_info["key"], "hash": model_info["hash"], "name": model_info["name"], "base": model_info["base"], "type": model_info["type"]},
                "t5_encoder_model": {"key": t5_model["key"], "hash": t5_model["hash"], "name": t5_model["name"], "base": t5_model["base"], "type": t5_model["type"]},
                "clip_embed_model": {"key": clip_model["key"], "hash": clip_model["hash"], "name": clip_model["name"], "base": clip_model["base"], "type": clip_model["type"]},
                "vae_model": {"key": vae_model["key"], "hash": vae_model["hash"], "name": vae_model["name"], "base": vae_model["base"], "type": vae_model["type"]}
            },
            "prompt": {
                "type": "flux_text_encoder",
                "id": "prompt",
                "prompt": """$PROMPT""",
                "t5_max_seq_len": 512
            },
            "denoise": {
                "type": "flux_denoise",
                "id": "denoise",
                "num_steps": $STEPS,
                "cfg_scale": 1.0,
                "scheduler": "$SCHEDULER",
                "width": $WIDTH,
                "height": $HEIGHT,
                "seed": $SEED if $SEED != -1 else random.randint(1000000000, 2147483647),
                "guidance": $GUIDANCE
            },
            "vae_decode": {
                "type": "flux_vae_decode",
                "id": "vae_decode"
            },
            "save_image": {
                "type": "save_image",
                "id": "save_image",
                "is_intermediate": False
            }
        },
        "edges": [
            {"source": {"node_id": "model_loader", "field": "transformer"}, "destination": {"node_id": "denoise", "field": "transformer"}},
            {"source": {"node_id": "model_loader", "field": "clip"}, "destination": {"node_id": "prompt", "field": "clip"}},
            {"source": {"node_id": "model_loader", "field": "t5_encoder"}, "destination": {"node_id": "prompt", "field": "t5_encoder"}},
            {"source": {"node_id": "prompt", "field": "conditioning"}, "destination": {"node_id": "denoise", "field": "positive_text_conditioning"}},
            {"source": {"node_id": "denoise", "field": "latents"}, "destination": {"node_id": "vae_decode", "field": "latents"}},
            {"source": {"node_id": "model_loader", "field": "vae"}, "destination": {"node_id": "vae_decode", "field": "vae"}},
            {"source": {"node_id": "vae_decode", "field": "image"}, "destination": {"node_id": "save_image", "field": "image"}}
        ]
    }
else:
    # Build SDXL graph
    graph = {
        "id": f"gen_{random.randint(1000,9999)}",
        "nodes": {
            "model_loader": {
                "type": "sdxl_model_loader",
                "id": "model_loader",
                "model": {"key": model_info["key"], "hash": model_info["hash"], "name": model_info["name"], "base": model_info["base"], "type": model_info["type"]}
            },
            "positive_prompt": {
                "type": "sdxl_compel_prompt",
                "id": "positive_prompt",
                "prompt": """$PROMPT""",
                "style": """$PROMPT"""
            },
            "negative_prompt": {
                "type": "sdxl_compel_prompt",
                "id": "negative_prompt",
                "prompt": """$NEGATIVE_PROMPT""",
                "style": ""
            },
            "noise": {
                "type": "noise",
                "id": "noise",
                "seed": $SEED if $SEED != -1 else random.randint(0, 2147483647),
                "width": $WIDTH,
                "height": $HEIGHT,
                "use_cpu": False
            },
            "denoise": {
                "type": "denoise_latents",
                "id": "denoise",
                "steps": $STEPS,
                "cfg_scale": $CFG_SCALE,
                "scheduler": "$SCHEDULER",
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
for i in range(120):
    time.sleep(2)
    status = api_get(f"/api/v1/queue/default/b/{batch_id}/status")
    if status.get("completed", 0) > 0:
        print("Complete!")
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
    print(f"Saved to {output_path}")
else:
    print("No image found")
    sys.exit(1)
PYEOF

echo "Done!"
