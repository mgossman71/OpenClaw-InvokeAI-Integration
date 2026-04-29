# Troubleshooting Guide

## Error Response Examples

### 404 Not Found (Wrong Model Key)
```json
{
  "detail": "Model 'flux.1-dev' not found"
}
```
**Cause**: Using display name instead of UUID  
**Fix**: Query `/api/v2/models/` to get actual UUID keys

### 400 Bad Request (Invalid Graph Structure)
```json
{
  "detail": "Node 'vae_decode' referenced in edge but not found in graph.nodes"
}
```
**Cause**: Typo in node ID or missing node definition  
**Fix**: Verify all `node_id` references in edges match keys in `nodes` dict

### Empty Batch (Silent Failure)
```json
{
  "batch": {
    "batch_id": "abc123",
    "status": "completed",
    "completed": 1,
    "failed": 0
  }
}
// But no images were created!
```
**Cause**: Missing FLUX sub-models (most common), incorrect node types, or missing edges  
**Fix**: 
1. Verify all 4 FLUX sub-models loaded (t5_encoder, clip_embed, vae, main transformer)
2. Check node types match model architecture (flux_* for FLUX, sdxl_* for SDXL)
3. Verify all required edges are present
4. Check InvokeAI server console for stack traces

---

## Common Issues

### "Unknown model" or "Model not found"
**Cause**: Using display name (e.g., `flux.1-dev`) instead of UUID  
**Fix**: Model keys are UUIDs, not friendly names
```bash
# Get actual UUID keys
curl -s "http://10.0.0.144:9090/api/v2/models/?model_type=main&limit=200" | jq '.models[] | {key, name}'
```
Use the `key` field (UUID), not the `name` field (display name)

### "Node not found in graph"
**Cause**: Node ID in edges doesn't match node key in nodes dict  
**Fix**: Ensure `node_id` in edges matches the key in the `nodes` dictionary

### "transformer does not exist in node model_loader"
**Cause**: Using `main_model_loader` or `sdxl_model_loader` for FLUX  
**Fix**: FLUX requires `flux_model_loader` which outputs `transformer`, not `unet`

### "conditioning type mismatch" or "Cannot connect compel to flux_denoise"
**Cause**: Using `compel` or `sdxl_compel_prompt` with FLUX  
**Fix**: FLUX uses `flux_text_encoder` node, not `compel`

### "Unknown model" errors
**Cause**: Model key doesn't exist or API path is wrong  
**Fix**: 
```bash
# List all models to verify keys
curl -s "http://YOUR_SERVER:9090/api/v2/models/?limit=200&offset=0" | jq '.models[].key'
```

### API returns 0 models
**Cause**: Missing `limit` parameter in v2 models endpoint  
**Fix**: Always include `?limit=200&offset=0`

### HTML response instead of JSON
**Cause**: Wrong API path or method  
**Fix**: Check the exact endpoint path in the OpenAPI spec at `/openapi.json`

### FLUX generation fails silently (execution error with no details)
**Cause**: Missing sub-models in `flux_model_loader`  
**Fix**: FLUX requires 4 models:
1. Main transformer (`model`)
2. T5 encoder (`t5_encoder_model`)
3. CLIP embed (`clip_embed_model`)
4. VAE (`vae_model`)

Example fix:
```python
"model_loader": {
    "type": "flux_model_loader",
    "id": "model_loader",
    "model": {"key": "5b266dd7-...", "hash": "...", "name": "FLUX.1 schnell", "base": "flux", "type": "main"},
    "t5_encoder_model": {"key": "36d7f5c9-...", "hash": "...", "name": "t5_bnb_int8_quantized_encoder", "base": "any", "type": "t5_encoder"},
    "clip_embed_model": {"key": "0c55e4d1-...", "hash": "...", "name": "clip-vit-large-patch14", "base": "any", "type": "clip_embed"},
    "vae_model": {"key": "151393bc-...", "hash": "...", "name": "FLUX.1-schnell_ae", "base": "flux", "type": "vae"}
}
```

### "no such table: main.models_old"
**Cause**: Using old v1 model relationship API which is deprecated  
**Fix**: Use v2 API endpoints instead

### Batch shows "completed" but no image appears
**Cause**: Image might be marked as intermediate  
**Fix**: Check with `is_intermediate=true` parameter, or ensure `save_image` node has `is_intermediate: false`

### Timeout errors
**Cause**: Generation taking longer than HTTP timeout  
**Fix**: 
- Increase timeout in API client
- Reduce steps for faster generation
- Use FLUX schnell for quick iterations

### Out of memory errors
**Cause**: Model too large for available VRAM  
**Fix**:
- Use quantized models (bnb_nf4, gguf)
- Reduce image dimensions
- Clear model cache: `POST /api/v2/models/empty_model_cache`
- Generate smaller images and upscale

## FLUX-Specific Issues

### "flux_denoise" doesn't have "vae" field
**Correct**: `flux_denoise` doesn't take VAE input. VAE goes to `flux_vae_decode` only.

### What is "t5_max_seq_len"?
- For FLUX schnell: `256`
- For FLUX dev: `512`
- Set on `flux_text_encoder` node

### No negative prompts in FLUX
FLUX doesn't use negative prompting in the same way as SDXL. The official workflow has no negative prompt node.

### "guidance" vs "cfg_scale"
- FLUX uses `guidance` parameter (typically 3.5-4.5)
- SDXL uses `cfg_scale` parameter (typically 7-8)
- These are different parameters for different architectures

## SDXL-Specific Issues

### "clip2 does not exist"
**Cause**: Using `main_model_loader` instead of `sdxl_model_loader`  
**Fix**: SDXL requires `sdxl_model_loader` which outputs `clip2` for the secondary text encoder

### Style field in prompts
SDXL benefits from the `style` field matching the main prompt content.

## Debugging Steps

1. **Check server health**: `GET /api/v1/app/version`
2. **List models**: `GET /api/v2/models/?limit=200&offset=0`
3. **Verify model info**: `GET /api/v2/models/i/{key}`
4. **Test simple graph**: Start with minimal nodes
5. **Check OpenAPI spec**: `GET /openapi.json` for exact field names
6. **Review queue status**: `GET /api/v1/queue/default/list_all` - shows failed batches with errors
7. **Check server console logs** - stack traces appear here for silent failures

## Race Conditions & Image Retrieval

### Problem: Getting wrong/cached images
**Symptom**: Downloaded image doesn't match your prompt, or is from a previous batch  
**Cause**: Using `limit=1` without timestamp filtering  
**Fix**: Record batch start time and filter by `created_at > start_time`

```python
# BEFORE enqueueing
start_time = datetime.datetime.now()

# AFTER batch completion (+ 5 second buffer)
images = api_get("/api/v1/images/?is_intermediate=false&limit=50")
our_image = None
for item in images.get("items", []):
    created = datetime.datetime.fromisoformat(item['created_at'].replace("Z", "+00:00"))
    if created.replace(tzinfo=None) > start_time:
        our_image = item
        break
```

See [Pattern 3: Time-Based Image Retrieval](../README.md#pattern-3-time-based-image-retrieval-prevent-race-conditions) in README.md.

### Problem: Duplicate images created
**Symptom**: Two image files for each generation  
**Cause**: Missing `is_intermediate: true` on VAE decode node  
**Fix**: Set `is_intermediate: true` on `flux_vae_decode` or `l2i` node, only `save_image` should have `is_intermediate: false`

### Problem: Concurrent generations colliding
**Symptom**: Multiple batches running simultaneously, unpredictable results  
**Cause**: No locking mechanism  
**Fix**: Implement file-based lock (see [Pattern 7](../README.md#pattern-7-lock-file-mechanism-prevent-concurrent-generations))

## Getting Help

- InvokeAI GitHub: https://github.com/invoke-ai/InvokeAI
- OpenAPI docs: `http://YOUR_SERVER:9090/docs`
- OpenAPI spec: `http://YOUR_SERVER:9090/openapi.json`
