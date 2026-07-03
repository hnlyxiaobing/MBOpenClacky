---
name: personal_website
description: "Generate and deploy a personal website"
version: "1.0.0"
user_invocable: true
category: development
allowed_tools: [Terminal, Write, FileReader, WebFetch]
argument_hint: "[--template minimal|blog|portfolio] [--deploy vercel|github-pages]"
---

# Personal Website

## Purpose

Generate a static personal website from a chosen template, preview it locally, configure a deployment target, publish the site, and verify it is live.

## Instructions

1. **Select a Template**: Ask the user to choose or parse from arguments:
   - `minimal` — single-page resume/about site (HTML + CSS only)
   - `blog` — multi-page site with a post listing, Markdown-based articles
   - `portfolio` — gallery-style layout showcasing projects with images

2. **Gather Content**: Prompt for:
   - Name / title
   - Short bio or description
   - Links (GitHub, LinkedIn, email, etc.)
   - For blog: initial post title and content
   - For portfolio: 2-3 project entries (name, description, link)

3. **Generate Static Files**: Create the site directory structure:
   ```
   <site-name>/
     index.html
     css/
       style.css
     js/
       main.js
     assets/
       (images if portfolio)
   ```
   - Write semantic HTML5 with responsive CSS
   - Include a mobile-friendly navigation bar
   - Add subtle animations and modern styling

4. **Local Preview**: Start a simple HTTP server for preview:
   - Run `python -m http.server 8080` or `npx serve` in the site directory
   - Report the local URL for the user to open

5. **Configure Deployment**: Based on `--deploy` flag or user choice:
   - **Vercel**: verify `vercel` CLI is installed, run `vercel` in the site directory
   - **GitHub Pages**: ensure a git repo exists, configure `gh-pages` branch, run deployment

6. **Publish**: Execute the deployment command and wait for completion.

7. **Verify Live**: Fetch the deployed URL and check for a 200 response to confirm the site is live.

## Output Format

- Generated file list with descriptions
- Local preview URL
- Deployment status (success/failure)
- Live site URL
- Post-deployment verification result
