# InvokeAI Model Reference

## Model Discovery

List all available models on your InvokeAI server:

```bash
curl -s "http://YOUR_INVOKE_SERVER:9090/api/v2/models/?limit=200&offset=0" | jq '.models[] | {key, name, base, type, format}'
```

## Model Types

InvokeAI organizes models by `type`:
- `main` - Primary diffusion models (SDXL, FLUX transformers)
- `vae` - Variational Autoencoders for image encoding/decoding
- `clip_embed` - CLIP text encoders
- `t5_encoder` - T5 text encoders (used by FLUX)
- `controlnet` - ControlNet models
- `control_lora` - ControlNet LoRA models
- `ip_adapter` - IP Adapter models
- `flux_redux` - FLUX Redux models

## Base Model Architectures

The `base` field indicates the model architecture:
- `sdxl` - Stable Diffusion XL
- `flux` - FLUX.1 models
- `any` - Architecture-agnostic (CLIP, T5 encoders)
- `sd-1` - Stable Diffusion 1.5
- `sd-3` - Stable Diffusion 3

## Common Model Formats

- `diffusers` - HuggingFace Diffusers format
- `checkpoint` - Single-file checkpoint (.safetensors, .ckpt)
- `bnb_quantized_nf4b` - BitsAndBytes NF4 quantized
- `bnb_quantized_int8b` - BitsAndBytes INT8 quantized
- `gguf_quantized` - GGUF quantized format

## FLUX Model Requirements

FLUX models require **4 separate model components**:

### 1. Main Transformer (type: main, base: flux)
| Model | Key | Format | Notes |
|-------|-----|--------|-------|
| FLUX.1 schnell | `5b266dd7-8f77-4416-bdb6-767f07c31acd` | bnb_quantized_nf4b | Fast, 4 steps |
| FLUX.1 dev | `4279ed9f-ee14-44b6-a43a-3413b1edfd5a` | bnb_quantized_nf4b | Quality, 20-50 steps |
| FLUX.1 Krea dev | `c9465203-d02e-4f7b-b54e-31680f0bcc04` | gguf_quantized | Creative |
| FLUX.1 Kontext dev | `f1e16898-132d-4233-9551-304e8f445f94` | gguf_quantized | Contextual |

### 2. T5 Encoder (type: t5_encoder, base: any)
| Model | Key | Format | Used With |
|-------|-----|--------|-----------|
| t5_bnb_int8_quantized_encoder | `36d7f5c9-03a7-46fa-9f0a-90be4e05d155` | bnb_quantized_int8b | All FLUX models |

### 3. CLIP Embed (type: clip_embed, base: any)
| Model | Key | Format | Used With |
|-------|-----|--------|-----------|
| clip-vit-large-patch14 | `0c55e4d1-7042-4e65-b65d-1e500e802865` | diffusers | All FLUX models |

### 4. VAE (type: vae, base: flux)
| Model | Key | Format | Used With |
|-------|-----|--------|-----------|
| FLUX.1-schnell_ae | `151393bc-1b21-42fe-b147-ecaceb35d278` | checkpoint | FLUX schnell |

## SDXL Models

SDXL models only require a single model specification:

### Main Models (type: main, base: sdxl)
| Model | Key | Format | Best For |
|-------|-----|--------|----------|
| Juggernaut XL v9 | `a2510f8f-c49d-4d37-b2b1-1d4400a26d43` | diffusers | Photorealistic |

## Model Selection Strategy

### For Speed (Fast Iterations)
- **FLUX.1 schnell** - 4 steps, good quality
- Use `num_steps: 4`, `guidance: 4.0`

### For Quality (Final Renders)
- **FLUX.1 dev** - 20-50 steps, highest quality
- Use `num_steps: 25-40`, `guidance: 3.5-4.5`

### For Photorealism
- **Juggernaut XL v9** - Optimized for realistic images
- Use `steps: 30-40`, `cfg_scale: 7-8`

### For Creative/Artistic
- **FLUX.1 Krea dev** - Artistic interpretation
- Use `num_steps: 20-30`

## Important Notes

### Quantized Models
- Quantized models (bnb_nf4, gguf) require all sub-models to be explicitly specified
- The UI auto-populates sub-models, but the API does not
- Always check which sub-models are needed for your main model

### Model Size
- FLUX models: ~6GB transformer + ~250MB T5 + ~250MB CLIP + ~300MB VAE
- Total memory: ~7GB for quantized FLUX
- SDXL models: ~6-7GB single file

### Model Loading
- Models are loaded on first use and cached
- Subsequent generations with the same model are faster
- Use `POST /api/v2/models/empty_model_cache` to free VRAM
