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
  # Auto-detect available models - prefer FLUX quantized
  echo "Auto-detecting models..."
  MODEL_KEY=$(python3 << 'PYEOF'
import urllib.request, json

try:
    req = urllib.request.Request("http://10.0.0.144:9090/api/v2/models/")
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode())
        
    # Prefer FLUX quantized models (faster, less VRAM)
    for m in data:
        if m.get("base") == "flux" and "quantized" in m.get("name", "").lower():
            print(m["key"])
            exit()
    
    # Fallback to any FLUX model
    for m in data:
        if m.get("base") == "flux":
            print(m["key"])
            exit()
    
    # Fallback to SDXL
    for m in data:
        if m.get("base") == "sdxl":
            print(m["key"])
            exit()
    
    # Last resort - any main model
    for m in data:
        if m.get("type") == "main":
            print(m["key"])
            exit()
            
except Exception as e:
    print("")
PYEOF
)
  
  if [ -z "$MODEL_KEY" ]; then
    echo "Error: Could not auto-detect models. Is InvokeAI running at http://10.0.0.144:9090?"
    exit 1
  fi
  
  echo "Auto-selected model: $MODEL_KEY"
fi

# Generate random seed if not provided
# NOTE: FLUX models do NOT support seed:-1 (random). Always use explicit seeds.
# ALSO: Quantized FLUX models have SEED COLLISION - different seeds may produce identical images!
if [ "$SEED" = "-1" ]; then
  SEED=$(python3 -c "import random; print(random.randint(1000000, 2147483647))")
  echo "Generated random seed: $SEED"
fi

# Track previous image hashes to detect collisions (for FLUX quantized)
PREV_HASH_FILE="/tmp/invoke_prev_hash.txt"
PREV_PROMPT_FILE="/tmp/invoke_prev_prompt.txt"

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

base = model_info.get("base", "")
is_sdxl = base == "sdxl"
is_flux = base == "flux"

if is_flux:
    # FLUX requires completely different graph structure
    # Fetch sub-models
    try:
        models_list = api_get("/api/v2/models/")
        t5_encoder = None
        clip_embed = None
        vae_model = None
        
        for m in models_list:
            m_type = m.get("type", "").lower()
            m_base = m.get("base", "").lower()
            
            if m_type == "t5_encoder":
                t5_encoder = m
            elif m_type == "clip_embed":
                clip_embed = m
            elif m_type == "vae" and m_base == "flux":
                vae_model = m
        
        if not t5_encoder or not clip_embed or not vae_model:
            print("Error: FLUX requires t5_encoder, clip_embed, and vae models. Please install them.")
            sys.exit(1)
            
    except Exception as e:
        print(f"Error fetching sub-models: {e}")
        sys.exit(1)
    
    # Build FLUX graph
    graph = {
        "id": f"gen_{random.randint(1000,9999)}",
        "nodes": {
            "model_loader": {
                "type": "flux_model_loader",
                "id": "model_loader",
                "model": {"key": model_info["key"], "hash": model_info["hash"], "name": model_info["name"], "base": model_info["base"], "type": model_info["type"]},
                "t5_encoder_model": {"key": t5_encoder["key"], "hash": t5_encoder["hash"], "name": t5_encoder["name"], "base": t5_encoder["base"], "type": t5_encoder["type"]},
                "clip_embed_model": {"key": clip_embed["key"], "hash": clip_embed["hash"], "name": clip_embed["name"], "base": clip_embed["base"], "type": clip_embed["type"]},
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
                "seed": $SEED,
                "guidance": 3.5
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
    # SDXL or SD 1.5 graph
    model_type = "sdxl_model_loader" if is_sdxl else "main_model_loader"
    prompt_type = "sdxl_compel_prompt" if is_sdxl else "compel"
    
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
    
    # Check for seed collision (FLUX quantized bug)
    import hashlib
    current_hash = hashlib.md5(img_data).hexdigest()
    
    # Check against previous hash
    prev_hash = ""
    prev_prompt = ""
    try:
        with open("/tmp/invoke_prev_hash.txt", "r") as f:
            prev_hash = f.read().strip()
        with open("/tmp/invoke_prev_prompt.txt", "r") as f:
            prev_prompt = f.read().strip()
    except:
        pass
    
    if current_hash == prev_hash and "$PROMPT" != prev_prompt:
        print(f"⚠️ WARNING: Seed collision detected! Same image generated for different prompt.")
        print(f"  Prompt was: {prev_prompt}")
        print(f"  Now: {'$PROMPT'}")
        print(f"  MD5: {current_hash}")
        print(f"  → Try again with a different seed")
        
        # Save the collided image anyway but warn
        output_path = "$OUTPUT" if "$OUTPUT" else f"/root/.openclaw/workspace/gen_{batch_id[:8]}.png"
        with open(output_path, "wb") as f:
            f.write(img_data)
        print(f"✓ Saved to {output_path} (COLLISION WARNING)")
    else:
        # Save hash and prompt for next comparison
        with open("/tmp/invoke_prev_hash.txt", "w") as f:
            f.write(current_hash)
        with open("/tmp/invoke_prev_prompt.txt", "w") as f:
            f.write("$PROMPT")
        
        output_path = "$OUTPUT" if "$OUTPUT" else f"/root/.openclaw/workspace/gen_{batch_id[:8]}.png"
        with open(output_path, "wb") as f:
            f.write(img_data)
        print(f"✓ Saved to {output_path}")
else:
    print("No image found")
    sys.exit(1)
PYEOF

echo "Done!"
