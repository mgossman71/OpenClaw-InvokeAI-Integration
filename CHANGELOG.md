# Changelog

All notable changes to the OpenClaw-InvokeAI-Integration project will be documented in this file.

## [Unreleased]

### Added
- Comprehensive model comparison guide (SDXL vs FLUX vs SD 1.5)
- Step-by-step workflow for all model types
- Detailed troubleshooting section with specific error messages
- Model selection guide with use cases
- Cross-references to related skills and repositories
- FLUX sub-model requirements documentation
- SD 1.5 graph structure reference
- Prompt engineering guidelines by model type

## [1.0.0] - 2026-04-27

### Added
- Initial comprehensive README with:
  - Quick start guide with cURL examples
  - Server setup reference
  - Available models documentation
  - Graph structure reference for SDXL and FLUX
  - API authentication notes
  - Text-to-image generation workflow
  - Common issues and troubleshooting
- LEARNINGS.md with critical discoveries:
  - Node dictionary structure (not array)
  - Model key requirements
  - FLUX graph differences from SDXL
  - Text rendering limitations
  - Anatomy specificity requirements
  - Sub-model key discovery
  - HTML response troubleshooting
- Example files:
  - sdxl-request.json - Working SDXL graph
  - flux-request.json - Working FLUX graph with sub-models
  - invokeai_helper.py - Python helper script

### Changed
- Updated README from ~200 lines to 831 lines
- Expanded graph structure section with complete examples
- Added critical warnings about model type compatibility

### Fixed
- Corrected FLUX graph to include all required sub-models
- Fixed node structure documentation (dict vs array)
- Added edge validation examples

## Known Issues
- FLUX text rendering is still placeholder/gibberish (inherent limitation)
- Sub-model keys are installation-specific and may vary
- Some anatomy prompts require extreme specificity

## Future Improvements
- [ ] Add SD 1.5 example JSON file
- [ ] Create graph validation script
- [ ] Add more prompt engineering examples
- [ ] Include performance benchmarks
- [ ] Add Docker deployment guide
- [ ] Create video tutorial links

---

**Maintainer**: Mark Gossman  
**Project**: https://github.com/mgossman71/OpenClaw-InvokeAI-Integration
