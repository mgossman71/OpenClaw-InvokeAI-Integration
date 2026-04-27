# InvokeAI API Reference

## Base URL
```
http://YOUR_INVOKE_SERVER:9090
```

## Authentication
Most endpoints do not require authentication in default setups. If authentication is enabled, use:
- API key header: `X-API-Key: your-api-key`
- Or session-based authentication

## Core Endpoints

### Queue Management

#### Enqueue Batch Generation
```http
POST /api/v1/queue/{queue_id}/enqueue_batch
Content-Type: application/json
```

Request body:
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

Response:
```json
{
  "batch": {
    "batch_id": "uuid-string",
    "created_at": "2026-04-27T21:51:00Z",
    "priority": 0,
    "origin": "api",
    "destination": "gallery",
    "session_id": "...",
    "graph": {...}
  }
}
```

#### Check Batch Status
```http
GET /api/v1/queue/{queue_id}/b/{batch_id}/status
```

Response:
```json
{
  "batch_id": "uuid-string",
  "in_progress": 0,
  "completed": 1,
  "failed": 0,
  "total": 1,
  "pending": 0
}
```

### Models

#### List All Models
```http
GET /api/v2/models/?limit=200&offset=0
```

**Important**: The `limit` parameter is required to get results. Without it, the API returns 0 models.

Response:
```json
{
  "models": [
    {
      "key": "uuid-string",
      "hash": "blake3:...",
      "path": "...",
      "file_size": 6693456272,
      "name": "FLUX.1 schnell (quantized)",
      "source": "...",
      "source_type": "hf_repo_id",
      "format": "bnb_quantized_nf4b",
      "base": "flux",
      "type": "main",
      "variant": "schnell"
    }
  ],
  "offset": 0,
  "limit": 200
}
```

#### Get Model by Key
```http
GET /api/v2/models/i/{model_key}
```

Response includes all model metadata needed for graph construction:
```json
{
  "key": "...",
  "hash": "...",
  "name": "...",
  "base": "...",
  "type": "...",
  "format": "...",
  "description": "..."
}
```

#### Empty Model Cache
```http
POST /api/v2/models/empty_model_cache
```

Frees VRAM by unloading cached models.

### Images

#### List Generated Images
```http
GET /api/v1/images/?is_intermediate=false&limit=10
```

Response:
```json
{
  "items": [
    {
      "image_name": "image-name-string.png",
      "image_origin": "gallery",
      "created_at": "2026-04-27T21:51:00Z",
      "width": 1024,
      "height": 1536,
      "board_id": null,
      "is_intermediate": false
    }
  ],
  "offset": 0,
  "limit": 10
}
```

#### Download Image (Full Resolution)
```http
GET /api/v1/images/i/{image_name}/full
```

Returns binary PNG data.

#### Download Image (Thumbnail)
```http
GET /api/v1/images/i/{image_name}/thumbnail
```

### System

#### Health Check
```http
GET /api/v1/app/version
```

#### OpenAPI Spec
```http
GET /openapi.json
```

Returns the complete OpenAPI specification for all endpoints.

## Graph Structure

### Node Types by Model Architecture

#### SDXL Nodes
- `sdxl_model_loader` - Loads SDXL model (outputs: unet, clip, clip2, vae)
- `sdxl_compel_prompt` - Prompt encoding (outputs: conditioning)
- `noise` - Generates noise (outputs: noise)
- `denoise_latents` - Denoising process (outputs: latents)
- `l2i` - Latents to image (outputs: image)
- `save_image` - Saves to gallery

#### FLUX Nodes
- `flux_model_loader` - Loads FLUX model + sub-models (outputs: transformer, clip, t5_encoder, vae, max_seq_len)
- `flux_text_encoder` - Text encoding for FLUX (outputs: conditioning)
- `flux_denoise` - FLUX denoising (outputs: latents)
- `flux_vae_decode` - Decodes latents to image (outputs: image)

### Edge Structure
```json
{
  "source": {
    "node_id": "source_node_id",
    "field": "output_field_name"
  },
  "destination": {
    "node_id": "dest_node_id", 
    "field": "input_field_name"
  }
}
```

### Model Identifier Format
```json
{
  "key": "model-uuid",
  "hash": "blake3:hash-string",
  "name": "Human-readable name",
  "base": "flux|sdxl|sd-1",
  "type": "main|vae|clip_embed|t5_encoder"
}
```

## HTTP Status Codes

- `200` - Success
- `201` - Created (batch enqueued)
- `400` - Bad Request (invalid graph structure)
- `422` - Validation Error (missing required fields)
- `404` - Not Found (model, image, or endpoint doesn't exist)
- `500` - Internal Server Error (model loading failure)
