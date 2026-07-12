
---
name: deploy
description: Deploy MoonBit applications to various platforms. Handles first-time setup and re-deploys idempotently. Trigger on: "deploy", "deploy to &lt;platform&gt;", "&lt;platform&gt; deploy", "发布", "部署", "上线".
disable-model-invocation: false
user_invocable: true
category: development
allowed_tools:
  - Terminal
  - FileReader
  - WebFetch
---

# Deploy MoonBit App

Deploy the current MoonBit project to various platforms. Works for both first-time deploys and re-deploys.

## Prerequisites Check

Before starting, verify that you're in a MoonBit project:

```bash
ls moon.mod
```

If not found, let the user know and offer to help create a project first.

---

## Common Deployment Targets

### Option 1: Deploy to GitHub Releases (Recommended for CLI tools)

**Step 1 — Build for multiple targets**

MoonBit can build for:
- `native` (Windows, macOS, Linux)
- `wasm-gc` (Web)
- `wasm` (Node.js, Deno)

```bash
moon build --target native --release cmd
```

**Step 2 — Check if git repo exists**

```bash
git status
```

If not initialized:
```bash
git init
git add .
git commit -m "Initial commit"
```

**Step 3 — Create a GitHub release**

Ask user if they want to create a GitHub release. If yes:
1. Guide them to create a repo on GitHub
2. Add the remote
3. Push the code
4. Create a release and upload the binary

**Step 4 — Package the binary**

On Windows:
```bash
# Zip the .exe file
powershell -Command "Compress-Archive -Path _build/native/release/build/cmd/cmd.exe -DestinationPath my-tool-v1.0.0-windows-x64.zip"
```

On macOS/Linux:
```bash
# Create a tar.gz
tar -czf my-tool-v1.0.0-linux-x64.tar.gz -C _build/native/release/build/cmd/ .
```

---

### Option 2: Deploy as NPM Package (WASM)

**Step 1 — Build for wasm**

```bash
moon build --target wasm-gc --release cmd
# or
moon build --target wasm --release cmd
```

**Step 2 — Create package.json**

```json
{
  "name": "&lt;package-name&gt;",
  "version": "1.0.0",
  "description": "&lt;description&gt;",
  "main": "index.js",
  "type": "module",
  "files": ["dist/"],
  "bin": {
    "&lt;command-name&gt;": "./dist/cli.js"
  }
}
```

**Step 3 — Publish**

```bash
npm publish --access public
```

---

### Option 3: Deploy Web App to Vercel/Netlify

**Step 1 — Build for Web (WASM)**

```bash
moon build --target wasm-gc --release cmd
```

**Step 2 — Create HTML entry point**

Create `index.html`:
```html
&lt;!DOCTYPE html&gt;
&lt;html&gt;
&lt;head&gt;
  &lt;meta charset="utf-8"&gt;
  &lt;title&gt;My MoonBit App&lt;/title&gt;
&lt;/head&gt;
&lt;body&gt;
  &lt;script type="module"&gt;
    // Load and initialize your WASM module here
  &lt;/script&gt;
&lt;/body&gt;
&lt;/html&gt;
```

**Step 3 — Deploy**

For Vercel:
```bash
# Install Vercel CLI if needed
npm i -g vercel
# Deploy
vercel --prod
```

For Netlify:
```bash
# Install Netlify CLI if needed
npm i -g netlify-cli
# Deploy
netlify deploy --prod
```

---

### Option 4: Deploy Docker Container

**Step 1 — Create Dockerfile**

```dockerfile
FROM debian:bookworm-slim

# Copy the built binary
COPY _build/native/release/build/cmd/cmd /usr/local/bin/my-app

# Run it
ENTRYPOINT ["/usr/local/bin/my-app"]
```

**.dockerignore**:
```
node_modules
_build
.git
.gitignore
*.md
!README.md
```

**Step 2 — Build and push**

```bash
# Build
docker build -t &lt;username&gt;/&lt;app-name&gt;:v1.0.0 .

# Push to registry (Docker Hub, GHCR, etc.)
docker push &lt;username&gt;/&lt;app-name&gt;:v1.0.0
```

---

## Step-by-Step Interactive Flow

1. **Ask the user which target platform**:
   - GitHub Releases (CLI tool)
   - NPM Package (WASM library)
   - Vercel/Netlify (Web app)
   - Docker Container
   - Other (custom)

2. **Check prerequisites based on the choice**

3. **Build the project**

4. **Package if needed**

5. **Deploy**

6. **Verify deployment**

---

## Output Format

On success:
```
✅ Deployment complete!
🌐 Live URL: &lt;url&gt; (if applicable)
📦 Package: &lt;package-name&gt;
📋 Next steps: &lt;what to do next&gt;
```

On failure:
```
❌ Deployment failed: &lt;error message&gt;

🔧 Troubleshooting steps:
1. &lt;step 1&gt;
2. &lt;step 2&gt;
3. &lt;step 3&gt;
```
