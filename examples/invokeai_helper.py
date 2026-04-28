#!/usr/bin/env python3
"""
OpenClaw InvokeAI Integration - Python Helper

This script demonstrates how to generate images using InvokeAI's graph-based API
from Python. Supports both SDXL and FLUX models.

Usage:
    python invokeai_helper.py --prompt "a majestic eagle" --model juggernaut-xl-v9
    python invokeai_helper.py --prompt "a sperm whale" --model flux-1-dev --width 1024 --height 1536
"""

import json
import urllib.request
import urllib.error
import time
import sys
import argparse

INVOKEAI_URL = "http://10.0.0.144:9090"
QUEUE_ID = "default"


def api_get(path):
    """Make a GET request to the InvokeAI API."""
    req = urllib.request.Request(f"{INVOKEAI_URL}{path}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def api_post(path, data):
    """Make a POST request to the InvokeAI API."""
    req = urllib.request.Request(
        f"{INVOKEAI_URL}{path}",
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def api_get_binary(path):
    """Download binary data from the InvokeAI API."""
    req = urllib.request.Request(f"{INVOKEAI_URL}{path}")
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def get_model_info(model_key):
    """Fetch model information from the API."""
    try:
        return api_get(f"/api/v2/models/i/{model_key}")
    except Exception as e:
        print(f"Error fetching model info: {e}")
        sys.exit(1)


def build_sdxl_graph(model_info, prompt, negative_prompt, width, height, steps, cfg_scale, seed):
    """Build an SDXL graph structure."""
    return {
        "id": f"sdxl_{int(time.time())}",
        "nodes": {
            "model_loader": {
                "type": "sdxl_model_loader",
                "id": "model_loader",
                "model": {
                    "key": model_info["key"],
                    "hash": model_info.get("hash", ""),
                    "name": model_info["name"],
                    "base": model_info["base"],
                    "type": model_info["type"]
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
                "seed": -1,
                "width": width,
                "height": height,
                "use_cpu": False
            },
            "denoise": {
                "type": "denoise_latents",
                "id": "denoise",
                "steps": steps,
                "cfg_scale": cfg_scale,
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


def build_flux_graph(model_info, prompt, width, height, steps, guidance, seed):
    """Build a FLUX graph structure."""
    # Get sub-model keys - these should be available on the server
    # In practice, fetch these from /api/v2/models/ endpoint
    t5_key = "36d7f5c9-03a7-46fa-9f0a-90be4e05d155"
    clip_key = "0c55e4d1-7042-4e65-b65d-1e500e802865"
    vae_key = "151393bc-1b21-42fe-b147-ecaceb35d278"
    
    return {
        "id": f"flux_{int(time.time())}",
        "nodes": {
            "model_loader": {
                "type": "flux_model_loader",
                "id": "model_loader",
                "model": {
                    "key": model_info["key"],
                    "hash": model_info.get("hash", ""),
                    "name": model_info["name"],
                    "base": model_info["base"],
                    "type": model_info["type"]
                },
                "t5_encoder_model": {
                    "key": t5_key,
                    "hash": "",
                    "name": "t5_bnb_int8_quantized_encoder",
                    "base": "any",
                    "type": "t5_encoder"
                },
                "clip_embed_model": {
                    "key": clip_key,
                    "hash": "",
                    "name": "clip-vit-large-patch14",
                    "base": "any",
                    "type": "clip_embed"
                },
                "vae_model": {
                    "key": vae_key,
                    "hash": "",
                    "name": "FLUX.1-schnell_ae",
                    "base": "flux",
                    "type": "vae"
                }
            },
            "prompt": {
                "type": "flux_text_encoder",
                "id": "prompt",
                "prompt": prompt,
                "t5_max_seq_len": 512
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
                "guidance": guidance
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


def generate_image(prompt, model_key, width=1024, height=768, steps=30, cfg_scale=7.5, guidance=3.5, seed=-1, output_path=None):
    """Generate an image using the specified model."""
    
    # Get model info
    print(f"Fetching model info for: {model_key}")
    model_info = get_model_info(model_key)
    print(f"Using model: {model_info.get('name', 'unknown')} (base: {model_info.get('base', 'unknown')})")
    
    # Determine model type and build appropriate graph
    base = model_info.get("base", "").lower()
    
    if "flux" in base:
        print("Building FLUX graph...")
        graph = build_flux_graph(model_info, prompt, width, height, steps, guidance, seed)
    elif "sdxl" in base:
        print("Building SDXL graph...")
        negative_prompt = "blurry, deformed, ugly, cartoon, painting, drawing, low quality, distorted"
        graph = build_sdxl_graph(model_info, prompt, negative_prompt, width, height, steps, cfg_scale, seed)
    else:
        print(f"Unknown model base: {base}. Attempting SDXL graph.")
        negative_prompt = "blurry, deformed, ugly, cartoon, painting, drawing, low quality, distorted"
        graph = build_sdxl_graph(model_info, prompt, negative_prompt, width, height, steps, cfg_scale, seed)
    
    # Create batch request
    batch = {"batch": {"graph": graph, "runs": 1, "data": None}}
    
    # Enqueue
    print("Enqueuing generation...")
    result = api_post("/api/v1/queue/default/enqueue_batch", batch)
    batch_id = result.get("batch", {}).get("batch_id", "")
    
    if not batch_id:
        print(f"Error: {result}")
        sys.exit(1)
    
    print(f"Batch ID: {batch_id}")
    print("Generating", end="")
    
    # Wait for completion
    for i in range(90):
        time.sleep(2)
        status = api_get(f"/api/v1/queue/default/b/{batch_id}/status")
        if status.get("completed", 0) > 0:
            print(" ✓ Complete!")
            break
        if status.get("failed", 0) > 0:
            print(f"\nFailed: {status}")
            sys.exit(1)
        if i % 5 == 0:
            print(".", end="", flush=True)
    
    # Get image
    print("Retrieving image...")
    images = api_get("/api/v1/images/?is_intermediate=false&limit=1")
    if images.get("items"):
        image_name = images["items"][0]["image_name"]
        print(f"Image: {image_name}")
        img_data = api_get_binary(f"/api/v1/images/i/{image_name}/full")
        
        if not output_path:
            output_path = f"/tmp/invokeai_{batch_id[:8]}.png"
        
        with open(output_path, "wb") as f:
            f.write(img_data)
        print(f"✓ Saved to {output_path}")
        return output_path
    else:
        print("No image found")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Generate images using InvokeAI")
    parser.add_argument("--prompt", required=True, help="Text prompt for generation")
    parser.add_argument("--model", default="juggernaut-xl-v9", help="Model key to use")
    parser.add_argument("--width", type=int, default=1024, help="Image width")
    parser.add_argument("--height", type=int, default=768, help="Image height")
    parser.add_argument("--steps", type=int, default=30, help="Number of steps")
    parser.add_argument("--cfg", type=float, default=7.5, help="CFG scale (SDXL only)")
    parser.add_argument("--guidance", type=float, default=3.5, help="Guidance scale (FLUX only)")
    parser.add_argument("--seed", type=int, default=-1, help="Random seed (-1 for random)")
    parser.add_argument("--output", help="Output file path")
    
    args = parser.parse_args()
    
    # Generate random seed if not provided
    seed = args.seed if args.seed != -1 else int(time.time()) % 2**32
    
    generate_image(
        prompt=args.prompt,
        model_key=args.model,
        width=args.width,
        height=args.height,
        steps=args.steps,
        cfg_scale=args.cfg,
        guidance=args.guidance,
        seed=seed,
        output_path=args.output
    )


if __name__ == "__main__":
    main()
