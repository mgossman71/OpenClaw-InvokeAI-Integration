#!/usr/bin/env python3
"""Validate InvokeAI graph structure before submission.

Usage:
    python3 validate_graph.py flux-request.json
    python3 validate_graph.py sdxl-request.json
    python3 validate_graph.py sd15-request.json

Returns 0 if valid, 1 if errors found.
"""

import json
import sys
from pathlib import Path


def load_json(filepath):
    """Load and return JSON file."""
    with open(filepath, 'r') as f:
        return json.load(f)


def validate_graph_structure(data):
    """Validate the overall graph structure."""
    errors = []
    
    # Check batch wrapper
    if "batch" not in data:
        errors.append("ERROR: Missing 'batch' wrapper")
        return errors
    
    batch = data["batch"]
    
    if "graph" not in batch:
        errors.append("ERROR: Missing 'graph' in batch")
        return errors
    
    if "runs" not in batch:
        errors.append("WARNING: Missing 'runs' in batch (defaults to 1)")
    
    graph = batch["graph"]
    
    # Check graph has id
    if "id" not in graph:
        errors.append("WARNING: Missing graph 'id'")
    
    # Check nodes exist
    if "nodes" not in graph:
        errors.append("ERROR: Missing 'nodes' in graph")
        return errors
    
    if not isinstance(graph["nodes"], dict):
        errors.append("ERROR: 'nodes' must be a dictionary (keyed by node name)")
        return errors
    
    # Check edges exist
    if "edges" not in graph:
        errors.append("ERROR: Missing 'edges' in graph")
        return errors
    
    return errors


def validate_nodes(nodes):
    """Validate node structure."""
    errors = []
    
    for node_key, node in nodes.items():
        # Check node has type
        if "type" not in node:
            errors.append(f"ERROR: Node '{node_key}' missing 'type' field")
        
        # Check node has id
        if "id" not in node:
            errors.append(f"ERROR: Node '{node_key}' missing 'id' field")
        elif node["id"] != node_key:
            errors.append(f"ERROR: Node '{node_key}' id ('{node['id']}') doesn't match key")
        
        # Check for known node types
        known_types = [
            "sdxl_model_loader", "sdxl_compel_prompt",
            "flux_model_loader", "flux_text_encoder", "flux_denoise", "flux_vae_decode",
            "main_model_loader", "compel",
            "noise", "denoise_latents", "l2i", "save_image"
        ]
        if node.get("type") and node["type"] not in known_types:
            errors.append(f"WARNING: Unknown node type '{node['type']}' in '{node_key}'")
    
    return errors


def validate_edges(edges, nodes):
    """Validate edge structure and connectivity."""
    errors = []
    
    # Required field mappings by node type
    required_fields = {
        "sdxl_model_loader": ["unet", "clip", "clip2", "vae"],
        "flux_model_loader": ["transformer", "clip", "t5_encoder", "vae"],
        "main_model_loader": ["unet", "clip", "vae"],
        "sdxl_compel_prompt": ["clip", "clip2", "conditioning"],
        "compel": ["clip", "conditioning"],
        "flux_text_encoder": ["clip", "t5_encoder", "conditioning"],
        "noise": ["noise"],
        "denoise_latents": ["unet", "positive_conditioning", "negative_conditioning", "noise", "latents"],
        "flux_denoise": ["transformer", "positive_text_conditioning", "latents"],
        "l2i": ["latents", "vae", "image"],
        "flux_vae_decode": ["latents", "vae", "image"],
        "save_image": ["image"]
    }
    
    for i, edge in enumerate(edges):
        edge_num = i + 1
        
        # Check source
        if "source" not in edge:
            errors.append(f"ERROR: Edge {edge_num} missing 'source'")
            continue
        
        source = edge["source"]
        if "node_id" not in source or "field" not in source:
            errors.append(f"ERROR: Edge {edge_num} source missing 'node_id' or 'field'")
            continue
        
        src_node = source["node_id"]
        src_field = source["field"]
        
        if src_node not in nodes:
            errors.append(f"ERROR: Edge {edge_num} references unknown source node '{src_node}'")
            continue
        
        # Check destination
        if "destination" not in edge:
            errors.append(f"ERROR: Edge {edge_num} missing 'destination'")
            continue
        
        dest = edge["destination"]
        if "node_id" not in dest or "field" not in dest:
            errors.append(f"ERROR: Edge {edge_num} destination missing 'node_id' or 'field'")
            continue
        
        dest_node = dest["node_id"]
        dest_field = dest["field"]
        
        if dest_node not in nodes:
            errors.append(f"ERROR: Edge {edge_num} references unknown destination node '{dest_node}'")
            continue
        
        # Check field validity
        dest_type = nodes[dest_node].get("type", "")
        if dest_type in required_fields:
            if dest_field not in required_fields[dest_type]:
                valid = ", ".join(required_fields[dest_type])
                errors.append(f"WARNING: Edge {edge_num} to '{dest_node}' uses field '{dest_field}', expected one of: {valid}")
    
    # Check all non-loader, non-noise nodes have at least one incoming edge
    for node_key, node in nodes.items():
        node_type = node.get("type", "")
        if node_type.endswith("_loader") or node_type == "noise":
            continue
        
        has_incoming = any(
            edge["destination"]["node_id"] == node_key 
            for edge in edges 
            if "destination" in edge and "node_id" in edge["destination"]
        )
        
        if not has_incoming:
            errors.append(f"ERROR: Node '{node_key}' has no incoming edges (disconnected)")
    
    return errors


def validate_model_specific(nodes):
    """Validate model-specific requirements."""
    errors = []
    
    # Detect model type from loader
    model_type = None
    for node in nodes.values():
        if node.get("type") == "flux_model_loader":
            model_type = "flux"
            break
        elif node.get("type") == "sdxl_model_loader":
            model_type = "sdxl"
            break
        elif node.get("type") == "main_model_loader":
            model_type = "sd15"
            break
    
    if not model_type:
        errors.append("ERROR: No model loader found (sdxl_model_loader, flux_model_loader, or main_model_loader)")
        return errors
    
    # FLUX-specific checks
    if model_type == "flux":
        loader = next((n for n in nodes.values() if n.get("type") == "flux_model_loader"), None)
        if loader:
            for submodel in ["t5_encoder_model", "clip_embed_model", "vae_model"]:
                if submodel not in loader:
                    errors.append(f"ERROR: FLUX loader missing '{submodel}' (required for FLUX)")
        
        # Check for noise node (FLUX shouldn't have one)
        has_noise = any(n.get("type") == "noise" for n in nodes.values())
        if has_noise:
            errors.append("WARNING: FLUX graph has 'noise' node (FLUX doesn't use separate noise node)")
        
        # Check for negative prompt (FLUX shouldn't have one)
        has_negative = any(n.get("type") == "sdxl_compel_prompt" and "negative" in n.get("id", "") for n in nodes.values())
        if has_negative:
            errors.append("WARNING: FLUX graph has negative prompt (FLUX doesn't support negative prompts)")
    
    # SDXL-specific checks
    elif model_type == "sdxl":
        # Check for noise node
        has_noise = any(n.get("type") == "noise" for n in nodes.values())
        if not has_noise:
            errors.append("ERROR: SDXL graph missing 'noise' node (required for SDXL)")
        
        # Check for positive prompt
        has_positive = any(n.get("type") == "sdxl_compel_prompt" for n in nodes.values())
        if not has_positive:
            errors.append("ERROR: SDXL graph missing 'sdxl_compel_prompt' node")
    
    # SD 1.5-specific checks
    elif model_type == "sd15":
        # Check for noise node
        has_noise = any(n.get("type") == "noise" for n in nodes.values())
        if not has_noise:
            errors.append("ERROR: SD 1.5 graph missing 'noise' node (required)")
        
        # Check for compel node
        has_compel = any(n.get("type") == "compel" for n in nodes.values())
        if not has_compel:
            errors.append("ERROR: SD 1.5 graph missing 'compel' node")
    
    return errors


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 validate_graph.py <graph_file.json>")
        sys.exit(1)
    
    filepath = Path(sys.argv[1])
    
    if not filepath.exists():
        print(f"ERROR: File '{filepath}' not found")
        sys.exit(1)
    
    print(f"Validating {filepath}...")
    print("=" * 60)
    
    try:
        data = load_json(filepath)
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON: {e}")
        sys.exit(1)
    
    # Run validations
    all_errors = []
    
    print("\n1. Checking graph structure...")
    errors = validate_graph_structure(data)
    all_errors.extend(errors)
    print(f"   {'✓' if not errors else '✗'} Structure {'valid' if not errors else 'has errors'}")
    
    if "graph" in data.get("batch", {}):
        graph = data["batch"]["graph"]
        nodes = graph.get("nodes", {})
        edges = graph.get("edges", [])
        
        print("\n2. Checking nodes...")
        errors = validate_nodes(nodes)
        all_errors.extend(errors)
        print(f"   {'✓' if not errors else '✗'} Nodes {'valid' if not errors else 'has errors'}")
        
        print("\n3. Checking edges...")
        errors = validate_edges(edges, nodes)
        all_errors.extend(errors)
        print(f"   {'✓' if not errors else '✗'} Edges {'valid' if not errors else 'has errors'}")
        
        print("\n4. Checking model-specific requirements...")
        errors = validate_model_specific(nodes)
        all_errors.extend(errors)
        print(f"   {'✓' if not errors else '✗'} Model {'valid' if not errors else 'has errors'}")
    
    # Print all errors
    if all_errors:
        print("\n" + "=" * 60)
        print("ERRORS/WARNINGS:")
        print("=" * 60)
        for error in all_errors:
            print(f"  • {error}")
        print(f"\nTotal: {len(all_errors)} issues")
        sys.exit(1)
    else:
        print("\n" + "=" * 60)
        print("✅ ALL CHECKS PASSED - Graph is valid!")
        print("=" * 60)
        sys.exit(0)


if __name__ == "__main__":
    main()
