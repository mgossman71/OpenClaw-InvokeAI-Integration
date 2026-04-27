# OpenClaw-InvokeAI-Integration

Complete integration guide and skill for connecting OpenClaw to an InvokeAI image generation server.

## What This Is

A production-ready skill that allows any OpenClaw instance to:
- Generate images using InvokeAI's graph-based API
- Support both SDXL and FLUX model architectures
- Select models, control parameters, and manage outputs
- Handle quantized models (bnb_nf4, gguf) correctly

## Quick Start

1. **Copy the skill** to your OpenClaw workspace:
   ```bash
   cp -r skills/invoke-ai ~/.openclaw/workspace/skills/
   ```

2. **Configure your InvokeAI server URL** in `skills/invoke-ai/SKILL.md`

3. **List available models**:
   ```bash
   curl -s "http://YOUR_INVOKE_SERVER:9090/api/v2/models/?limit=200&offset=0" | jq
   ```

4. **Generate an image**:
   ```bash
   cd ~/.openclaw/workspace/skills/invoke-ai
   ./generate.sh --prompt "your prompt here" --output result.png
   ```

## Key Learning from This Integration

**The critical discovery**: FLUX quantized models are split into 4 separate components that must ALL be explicitly specified in the `flux_model_loader` node:

1. **Main transformer** (the quantized model itself)
2. **T5 encoder** (text encoding)
3. **CLIP embed** (CLIP text encoding)  
4. **VAE** (image decoding)

The UI workflow editor auto-populates these, but the API requires them all to be passed explicitly.

## Architecture

```
OpenClaw Agent <-> InvokeAI API (http://host:9090)
                  <-> Queue System
                  <-> Model Manager
                  <-> Graph Execution Engine
```

## Documentation

- [SKILL.md](skills/invoke-ai/SKILL.md) - Full skill documentation
- [MODELS.md](docs/MODELS.md) - Model reference and keys
- [API-REFERENCE.md](docs/API-REFERENCE.md) - Complete API documentation
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [EXAMPLES.md](docs/EXAMPLES.md) - Working code examples

## Requirements

- InvokeAI server (local or remote) with API enabled
- Python 3.8+ with urllib, json modules
- jq (optional, for pretty-printing API responses)

## License

MIT - Free to use, modify, and distribute.

## Credits

Based on real-world integration work with InvokeAI v5.x, tested with:
- FLUX.1 schnell (bnb_quantized_nf4b)
- FLUX.1 dev (bnb_quantized_nf4b)
- Juggernaut XL v9 (SDXL)

## References and Resources

### Official InvokeAI Resources
- **InvokeAI GitHub**: https://github.com/invoke-ai/InvokeAI
- **InvokeAI Documentation**: https://invoke-ai.github.io/InvokeAI/
- **InvokeAI Support Portal**: https://support.invoke.ai

### API and Development Resources
- **OpenAPI Specification**: Available at `http://YOUR_INVOKE_SERVER:9090/openapi.json` on your local server
- **Swagger UI**: `http://YOUR_INVOKE_SERVER:9090/docs`
- **API GitHub Issues**: https://github.com/invoke-ai/InvokeAI/issues (search for API-related issues)

### Model-Specific Resources
- **FLUX Models on InvokeAI**: https://support.invoke.ai/support/solutions/articles/151000199277-using-flux-models-on-invoke
- **Hugging Face FLUX Models**: https://huggingface.co/black-forest-labs
- **InvokeAI Model Manager Docs**: https://invoke-ai.github.io/InvokeAI/features/model_manager/

### Community and Support
- **InvokeAI Discord**: https://discord.gg/invokeai
- **Reddit r/InvokeAI**: https://www.reddit.com/r/InvokeAI/
- **MCP Server Reference**: https://github.com/coinstax/invokeai-mcp-server (used as reference for graph structure)

### Articles and Tutorials
- **FLUX img2img Guide**: https://stable-diffusion-art.com/flux-img2img-inpainting/
- **InvokeAI Installation**: https://invoke-ai.github.io/InvokeAI/installation/quick_start/
