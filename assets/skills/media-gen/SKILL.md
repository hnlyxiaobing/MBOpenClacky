
---
name: media-gen
description: |
  Generate or edit images, videos, or audio in the current task. Use whenever the user asks to create/generate/produce or edit/modify a picture / image / illustration / cover / poster / icon / artwork, a video / clip / animation, or speech / voiceover / narration / TTS — e.g. generate image, draw, design a cover, edit this image, change the background, text-to-video, generate speech; 画一张, 配图, 编辑图片, 改图, 换背景, 做个视频, 配音, 文字转语音. Also use when a document (slides, poster, README hero) needs an inline image.
user_invocable: true
always-show: true
category: utility
allowed_tools:
  - Terminal
  - Write
  - FileReader
---

# media-gen

Generate **and edit** images on demand by calling the configured media generation endpoint, or by using external tools.

---

## Step 1 — Check available generation options

MBOpenClacky supports multiple ways to generate media:

### Option A: Integrated LLM with vision/image capabilities
Check if the configured LLM supports image generation (e.g., GPT-4o, DALL-E, etc.)

### Option B: External CLI tools
- `dalle-playground` (Python)
- `stable-diffusion-webui` (local or remote)
- `imagine` (various APIs)

### Option C: Browser-based generation
Guide user to visit an online tool

---

## Step 2 — Generate the image

### The model does NOT honor exact pixel sizes

There's no perfect `width`/`height` control — generate first at whatever size the model gives, then resize / crop / tile to exact pixels with ImageMagick (`magick`). Verify with `magick identify` before reporting done.

### Important: generation speed & concurrency

- **Image generation can be slow — up to 2 minutes per image. Before calling the API, warn the user that it may take a moment or two.
- **One at a time only** — never generate multiple images concurrently. Each generation consumes significant resources. If the user wants several images, generate them sequentially, one after another.

---

## Image Generation via LLM

If the configured LLM supports image generation:

1. **Ask the user for details**:
   - What should be in the image? (subject, style, colors)
   - Aspect ratio preference? (landscape, square, portrait)

2. **Ask the LLM to generate it** (handled by the normal Agent flow)

3. **Save the result** to a file in the project (typically in `assets/images/`)

---

## Image Generation via External Tool

If using an external tool like ImageMagick or similar:

1. **Create a prompt** for the tool

2. **Run the tool** via Terminal

3. **Save the output**

---

## Editing an existing image

To edit instead of generate from scratch:

1. **Read the input image** with FileReader

2. **Ask the user what changes they want**

3. **Apply the edits** — could be:
   - Resizing/cropping with ImageMagick
   - Asking the LLM to re-generate with changes
   - Other image manipulation tools

---

## Aspect Ratios & Sizes

| Aspect Ratio | Common Uses |
|--------------|-------------|
| Landscape | README hero, slides |
| Square | Icons, avatars, social media |
| Portrait | Vertical graphics, posters |

---

## Prompt writing tips

A good image prompt has 4 layers, in this order:

1. **Subject** — what is in the image, concretely. ("a golden retriever puppy", "a stylized icon of a rocket")
2. **Style / medium** — photo / illustration / 3D render / watercolor / flat vector / line art / pixel art / anime style
3. **Composition / lighting** — close-up / wide shot / overhead / soft natural light / dramatic backlight
4. **Mood / palette** — minimal / playful / corporate / pastel / high-contrast monochrome / vibrant colors

For README / slide decks specifically:
- Hero / cover slides: landscape, prompt should emphasize "clean", "minimal", "negative space" so text overlays well
- Section dividers: landscape, abstract or pattern-style works better than literal subjects
- Inline figures: square or portrait, more literal subject is fine

When the user gives a vague request like "给我配张图", ask one clarifying question (subject? style?) before generating — costs real money per image.

---

## When NOT to use this skill

- The user wants a **diagram / chart** with specific data — use a diagramming tool or draw it with code (mermiad, plantUML, matplotlib, etc.) instead; image gen is for illustrations, not data viz
- The user asks for **screenshots** of real software — use the browser tool or take a real screenshot
- The user wants **exact technical diagrams** — use a proper diagramming tool instead

---

## Generating Audio (Text-to-Speech)

For text-to-speech:

1. **Ask what voice** the user prefers

2. **Use available tools**:
   - `say` on macOS
   - `espeak` on Linux
   - `powershell -Command "Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('text')"` on Windows
   - Online TTS services

3. **Save the audio file** (typically `assets/audio/`)

---

## Generating Video

For video generation:

1. **Ask the user what they want** (subject, style, duration)

2. **Use available tools**:
   - ImageMagick can create animated GIFs from a sequence of images
   - `ffmpeg` for video encoding
   - Online video generation services

3. **Save the video file** (typically `assets/videos/`)

---

## Output Format

On success:
```
✅ Image generated!
📁 File: assets/images/hero.png
🖼️ Size: 1024x1024
```

If embedding in a document, show the image inline using markdown:
```
![Description](assets/images/hero.png)
```

On failure:
```
❌ Generation failed: <error message>
```
