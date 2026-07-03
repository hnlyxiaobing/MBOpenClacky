---
name: mcp-manager
description: Manage MCP server connections, install and configure servers
version: "1.0.0"
user_invocable: true
category: management
allowed_tools: [Terminal, FileReader, Write]
---

# MCP Manager

## Purpose
Install, configure, and manage MCP (Model Context Protocol) server connections for extending agent capabilities.

## Instructions
1. List currently configured MCP servers from project configuration
2. For installation:
   - Verify prerequisites (runtime, network access)
   - Install the MCP server package
   - Add server configuration to the project config file
   - Test the connection
3. For removal:
   - Stop the running server process
   - Remove from configuration
   - Clean up any local artifacts
4. For status check:
   - Ping each configured server
   - Report health and available tools count

## Output Format
- Server name, status (connected/disconnected), available tools count
- For installation: step-by-step progress with success/failure indicators
- For removal: confirmation of cleanup steps
