---
name: media-gen
description: Generate images, diagrams, and media content using AI tools
version: "1.0.0"
user_invocable: true
category: utility
allowed_tools: [Terminal, Write, WebFetch]
---

# Media Generator

## Purpose
Generate images, diagrams, charts, and other media content using available AI generation tools and diagramming libraries.

## Instructions
1. Understand the user's visual requirement (type, style, content)
2. Select appropriate generation method:
   - Mermaid diagrams for flowcharts, sequences, class diagrams
   - SVG for simple vector graphics
   - External AI API for complex images
   - ASCII art for terminal-friendly output
3. Generate the content with appropriate parameters
4. Save to the designated output location
5. Provide a preview description or file path

## Output Format
- Generated file path (relative to project root)
- Brief description of what was created
- Rendering instructions if applicable
- Suggestions for refinement if needed
