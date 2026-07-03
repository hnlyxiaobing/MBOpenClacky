---
name: deploy
description: Deploy applications to cloud platforms and hosting services
version: "1.0.0"
user_invocable: true
category: development
allowed_tools: [Terminal, FileReader, WebFetch]
---

# Deploy

## Purpose
Deploy applications to cloud platforms (Vercel, Netlify, Docker, cloud VMs, etc.) with proper configuration and verification.

## Instructions
1. Identify the project type and determine target platform
2. Check prerequisites:
   - Required CLI tools installed
   - Authentication/credentials configured
   - Build dependencies available
3. Build the project if needed (run build commands)
4. Execute the deployment command for the target platform
5. Wait for deployment to complete
6. Verify deployment succeeded (check URL, health endpoint)
7. Report results with access URL

## Output Format
- Deployment status (success/failure)
- Live URL if successful
- Build and deploy logs summary
- Any warnings or issues encountered
- Rollback instructions if needed
