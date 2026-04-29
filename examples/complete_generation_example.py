#!/usr/bin/env python3
"""
Complete InvokeAI Image Generation Example

This example demonstrates ALL critical implementation patterns:
1. Dynamic model key resolution (UUIDs, not display names)
2. FLUX sub-model discovery
3. Time-based image retrieval (prevent race conditions)
4. Proper is_intermediate flag usage
5. Explicit seed generation
6. Error handling and debugging
7. Lock file mechanism

Usage:
    python3 complete_generation_example.py "your prompt here" output.png
"""

import json
import urllib.request
import urllib.error
import datetime
import time
import random
import os
import fcntl
import sys

# Configuration
INVOKEAI_URL = "http://10.0.0.144:9090"
LOCK_FILE = "/tmp/invokeai_generation.lock"


# ============================================================================
# Pattern 1: Dynamic Model Key Resolution
# ============================================================================

def get_model_uuid(friendly_name):
    """
    Resolve friendly model name to UUID.
    
    CRITICAL: API model keys are UUIDs, not display names like 'flux.1-dev'
    """
    req = urllib.request.Request(
        f"{INVOKEAI_URL}/api/v2/models/?model_type=main&limit=200"
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            models = json.loads(resp.read().decode())['models']
            for model in models:
                if friendly_name.lower() in model['name'].lower():
                    print(f"✓ Resolved '{friendly_name}' → {model['key']}")
                    return model['key']
    except Exception as e:
        raise RuntimeError(f"Failed to query models: {e}")
    
    raise ValueError(
        f"Model '{friendly_name}' not found. "
        f"Available: {[m['name'] for m in models]}"
    )


# ============================================================================
# Pattern 2: FLUX Sub-Model Discovery
# ============================================================================

def discover_flux_submodels(main_model_key):
    """
    Discover required sub-models for FLUX dynamically.
    
    CRITICAL: FLUX requires 4 components:
    - Main transformer
    - t5_encoder (text encoding)
    - clip_embed (CLIP vision encoder)
    - vae (variational autoencoder for decoding)
    
    Don't hardcode these - discover them from the API!
    """
    req = urllib.request.Request(
        f"{INVOKEAI_URL}/api/v2/models/?model_type=any&limit=500"
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            all_models = json.loads(resp.read().decode())['models']
    except Exception as e:
        raise RuntimeError(f"Failed to query sub-models: {e}")
    
    # Find required sub-models
    submodels = {}
    for model in all_models:
        if model['type'] == 't5_encoder' and model['base'] == 'any':
            submodels['t5_encoder'] = model['key']
        elif model['type'] == 'clip_embed' and model['base'] == 'any':
            submodels['clip_embed'] = model['key']
        elif model['type'] == 'vae' and model['base'] == 'flux':
            submodels['vae'] = model['key']
    
    # Verify we found all required sub-models
    required = ['t5_encoder', 'clip_embed', 'vae']
    missing = [r for r in required if r not in submodels]
    if missing:
        raise RuntimeError(f"Missing FLUX sub-models: {missing}")
    
    print(f"✓ Discovered FLUX sub-models:")
    print(f"  - t5_encoder: {submodels['t5_encoder']}")
    print(f"  - clip_embed: {submodels['clip_embed']}")
    print(f"  - vae: {submodels['vae']}")
    
    return submodels


# ============================================================================
# Pattern 3: Time-Based Image Retrieval
# ============================================================================

def retrieve_image_by_timestamp(start_time, timeout_seconds=300):
    """
    Retrieve image created after start_time.
    
    CRITICAL: Don't use limit=1 alone - it may return cached images.
    Filter by creation timestamp to get YOUR image.
    """
    poll_interval = 2
    max_attempts = int(timeout_seconds / poll_interval)
    
    print(f"⏳ Waiting for image (started at {start_time})...")
    
    for attempt in range(max_attempts):
        try:
            req = urllib.request.Request(
                f"{INVOKEAI_URL}/api/v1/images/?is_intermediate=false&limit=50"
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                images = json.loads(resp.read().decode())
            
            # Filter by creation time
            for item in images.get('items', []):
                created_str = item.get('created_at', '')
                try:
                    created = datetime.datetime.fromisoformat(
                        created_str.replace("Z", "+00:00")
                    ).replace(tzinfo=None)
                    
                    if created > start_time:
                        print(f"✓ Found image: {item['image_name']} (created: {created})")
                        return item
                        
                except Exception as e:
                    print(f"Warning: Failed to parse timestamp: {e}")
                    continue
            
            # No matching image yet - keep polling
            if attempt % 10 == 0:
                print(f"  ... still waiting (attempt {attempt + 1}/{max_attempts})")
            time.sleep(poll_interval)
            
        except urllib.error.URLError as e:
            print(f"Warning: API error: {e}")
            time.sleep(poll_interval)
    
    raise RuntimeError(
        f"No image found within {timeout_seconds}s. "
        f"Check queue status: {INVOKEAI_URL}/api/v1/queue/default/list_all"
    )


# ============================================================================
# Pattern 4 & 5: Build FLUX Graph with Correct Flags
# ============================================================================

def build_flux_graph(prompt, model_key, submodels, width=1024, height=1024, 
                     steps=25, guidance=7.5):
    """
    Build FLUX graph with:
    - is_intermediate: true on vae_decode (Pattern 4)
    - Explicit random seed (Pattern 5)
    """
    # Pattern 5: Generate explicit random seed (FLUX doesn't support seed: -1)
    seed = random.randint(1000000000, 2147483647)
    print(f"✓ Using seed: {seed}")
    
    graph = {
        "batch": {
            "graph": {
                "nodes": {
                    "model_loader": {
                        "type": "flux_model_loader",
                        "id": "model_loader",
                        "model": {"key": model_key, "base": "flux", "type": "main"},
                        "t5_encoder_model": {
                            "key": submodels['t5_encoder'],
                            "base": "any",
                            "type": "t5_encoder"
                        },
                        "clip_embed_model": {
                            "key": submodels['clip_embed'],
                            "base": "any",
                            "type": "clip_embed"
                        },
                        "vae_model": {
                            "key": submodels['vae'],
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
                        "seed": seed,
                        "guidance": guidance
                    },
                    # Pattern 4: CRITICAL - prevent duplicate images
                    "vae_decode": {
                        "type": "flux_vae_decode",
                        "id": "vae_decode",
                        "is_intermediate": True  # ← Prevents duplicate saves!
                    },
                    "save_image": {
                        "type": "save_image",
                        "id": "save_image",
                        "is_intermediate": False
                    }
                },
                "edges": [
                    {"source": {"node_id": "model_loader", "field": "transformer"}, 
                     "destination": {"node_id": "denoise", "field": "transformer"}},
                    {"source": {"node_id": "model_loader", "field": "clip"}, 
                     "destination": {"node_id": "prompt", "field": "clip"}},
                    {"source": {"node_id": "model_loader", "field": "t5_encoder"}, 
                     "destination": {"node_id": "prompt", "field": "t5_encoder"}},
                    {"source": {"node_id": "prompt", "field": "conditioning"}, 
                     "destination": {"node_id": "denoise", "field": "positive_text_conditioning"}},
                    {"source": {"node_id": "denoise", "field": "latents"}, 
                     "destination": {"node_id": "vae_decode", "field": "latents"}},
                    {"source": {"node_id": "model_loader", "field": "vae"}, 
                     "destination": {"node_id": "vae_decode", "field": "vae"}},
                    {"source": {"node_id": "vae_decode", "field": "image"}, 
                     "destination": {"node_id": "save_image", "field": "image"}}
                ]
            },
            "runs": 1,
            "data": []
        }
    }
    
    return graph


# ============================================================================
# API Helper Functions
# ============================================================================

def api_post(path, data):
    """POST JSON to API"""
    req = urllib.request.Request(
        f"{INVOKEAI_URL}{path}",
        data=json.dumps(data).encode(),
        headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        print(f"❌ HTTP {e.code}: {error_body}")
        raise RuntimeError(f"API error {e.code}: {error_body}")


def api_get(path):
    """GET JSON from API"""
    req = urllib.request.Request(f"{INVOKEAI_URL}{path}")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        print(f"❌ HTTP {e.code}: {error_body}")
        raise RuntimeError(f"API error {e.code}: {error_body}")


def api_get_binary(path):
    """GET binary data (image) from API"""
    req = urllib.request.Request(f"{INVOKEAI_URL}{path}")
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


# ============================================================================
# Pattern 6: Error Handling & Debugging
# ============================================================================

def check_queue_status():
    """Check queue for failed batches"""
    try:
        status = api_get("/api/v1/queue/default/list_all")
        print("\n📊 Queue Status:")
        print(json.dumps(status, indent=2))
    except Exception as e:
        print(f"Warning: Could not check queue status: {e}")


# ============================================================================
# Pattern 7: Lock File Mechanism
# ============================================================================

def acquire_lock():
    """Prevent concurrent generations"""
    lock_fd = open(LOCK_FILE, 'w')
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return lock_fd
    except IOError:
        raise RuntimeError(
            "Another generation is in progress. "
            f"Remove {LOCK_FILE} if stuck."
        )


def release_lock(lock_fd):
    """Release lock file"""
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    lock_fd.close()
    if os.path.exists(LOCK_FILE):
        os.remove(LOCK_FILE)


# ============================================================================
# Main Generation Function
# ============================================================================

def generate_image(prompt, output_path, model_name="FLUX.1 dev", 
                   width=1024, height=1024, steps=25, guidance=7.5):
    """
    Generate image using InvokeAI with all best practices.
    """
    print(f"\n🎨 Generating image: '{prompt}'")
    print(f"📐 Size: {width}x{height}, Steps: {steps}, Guidance: {guidance}")
    print()
    
    # Pattern 7: Acquire lock
    lock = acquire_lock()
    
    try:
        # Pattern 1: Resolve model key
        model_key = get_model_uuid(model_name)
        
        # Pattern 2: Discover FLUX sub-models
        submodels = discover_flux_submodels(model_key)
        
        # Build graph with Patterns 4 & 5
        graph = build_flux_graph(
            prompt=prompt,
            model_key=model_key,
            submodels=submodels,
            width=width,
            height=height,
            steps=steps,
            guidance=guidance
        )
        
        # Pattern 3: Record start time BEFORE enqueue
        start_time = datetime.datetime.now()
        print(f"⏰ Batch started at: {start_time}")
        
        # Enqueue batch
        print("\n📤 Enqueueing batch...")
        result = api_post("/api/v1/queue/default/enqueue_batch", graph)
        batch_id = result["batch"]["batch_id"]
        print(f"✓ Batch ID: {batch_id}")
        
        # Poll for completion
        print("\n⏳ Processing...")
        for attempt in range(150):
            time.sleep(2)
            status = api_get(f"/api/v1/queue/default/b/{batch_id}/status")
            
            if status.get("completed", 0) > 0:
                print("✓ Batch completed!")
                break
            if status.get("failed", 0) > 0:
                print("❌ Batch failed!")
                check_queue_status()
                raise RuntimeError("Batch failed - check queue status")
            
            if attempt % 10 == 0:
                print(f"  ... still processing ({attempt * 2}s)")
        else:
            raise RuntimeError("Timeout waiting for batch completion")
        
        # Pattern 3: Add buffer for indexing
        print("\n⏳ Waiting for image indexing...")
        time.sleep(5)
        
        # Pattern 3: Retrieve image by timestamp
        our_image = retrieve_image_by_timestamp(start_time)
        
        # Download image
        print(f"\n⬇️  Downloading image...")
        img_data = api_get_binary(
            f"/api/v1/images/i/{our_image['image_name']}/full"
        )
        
        with open(output_path, "wb") as f:
            f.write(img_data)
        
        print(f"\n✅ Success! Saved to: {output_path}")
        print(f"📊 Image info:")
        print(f"   - Name: {our_image['image_name']}")
        print(f"   - Created: {our_image['created_at']}")
        print(f"   - Size: {len(img_data)} bytes")
        
        return output_path
        
    finally:
        # Pattern 7: Release lock
        release_lock(lock)


# ============================================================================
# CLI Entry Point
# ============================================================================

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 complete_generation_example.py \"prompt\" output.png")
        print("\nExample:")
        print('  python3 complete_generation_example.py "cute robot assistant" robot.png')
        sys.exit(1)
    
    prompt = sys.argv[1]
    output_path = sys.argv[2]
    
    try:
        generate_image(prompt, output_path)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        sys.exit(1)
