
---
name: personal-website
description: |
  Generate a beautiful personal homepage (linktree-style) and publish it online for the user.
  Reads user info from ~/.mbopenclacky/agents/USER.md and AI info from ~/.mbopenclacky/agents/SOUL.md.
  Trigger on: "profile card", "homepage", "personal page", "generate my card", "make my card",
  "publish my card", "生成名片", "做名片", "我的名片", "个人主页", "发布主页",
  "delete my card", "删除名片", "删除主页".
user_invocable: true
category: development
allowed_tools:
  - Terminal
  - FileReader
  - Write
---

# Profile Homepage Skill

Generate a beautiful personal homepage and publish it.

---

## Step 1 — Read user info

Read `~/.mbopenclacky/agents/USER.md` and `~/.mbopenclacky/agents/SOUL.md`.

Extract everything you can find:
- `name` — display name (fallback: "Friend")
- `occupation` — job title or role (fallback: "")
- `bio` — short personal description (fallback: "")
- `links` — **all** social/contact links found, preserve their labels. Common ones to look for:
  GitHub, Twitter/X, LinkedIn, Website, Blog, Email, Instagram, YouTube, Telegram, WeChat, etc.
  Each link: `{ label, url, type }` where type helps pick an icon emoji.
- `ai_name` — AI assistant name from SOUL.md (fallback: "Assistant")

---

## Step 2 — Handle delete request

If the user asked to **delete** their homepage:
- Ask for confirmation first
- If confirmed, delete the files (if we created them)
- Tell the user their homepage has been removed. Stop here.

---

## Step 3 — Design & generate the HTML

Write a **complete, self-contained** HTML file to `/tmp/profile-card.html` or `./index.html` in the current directory.

### You have full creative freedom on:
- Layout, typography, spacing, color palette
- Background (solid / gradient / subtle pattern / animated)
- Link button style (pill / card / underline / ghost / anything)
- Avatar treatment (large initial letter with color, emoji, geometric shape — no real image needed)
- Animations (subtle hover effects, entrance fade, etc.)
- Overall vibe — make it feel like a real personal brand page, not a template

### Hard constraints (must follow):
- **Single HTML file, zero external resources** — no CDN, no Google Fonts URLs, no `<img src="http...">`.
  Use system fonts: `'Helvetica Neue', Arial, 'PingFang SC', 'Hiragino Sans GB', sans-serif`
- **Mobile-first, responsive** — `<meta name="viewport">` required, works on phone screens
- **Valid HTML5**
- **All links open in `_blank`** with `rel="noopener noreferrer"`
- **Badge** somewhere subtle: "Made with MBOpenClacky" — small, not intrusive
- Page `<title>`: `{name}'s Homepage` or similar

### Link icons (use emoji prefix in button text):
| Type     | Emoji |
|----------|-------|
| github   | 🐙 |
| twitter/x | 🐦 |
| linkedin | 💼 |
| website/blog | 🌐 |
| email    | 📧 |
| instagram | 📸 |
| youtube  | ▶️ |
| telegram | ✈️ |
| default  | 🔗 |

---

## Template Structure

Here's a starting point (customize and make it beautiful):

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{name}'s Homepage</title>
  <style>
    /* Your beautiful CSS here */
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Helvetica Neue', Arial, 'PingFang SC', 'Hiragino Sans GB', sans-serif;
      min-height: 100vh;
      /* Nice background */
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 2rem;
    }
    .card {
      background: white;
      border-radius: 1.5rem;
      padding: 2.5rem;
      max-width: 420px;
      width: 100%;
      box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
    }
    /* More styles... */
  </style>
</head>
<body>
  <div class="card">
    <div class="avatar">{name.charAt(0)}</div>
    <h1>{name}</h1>
    <p class="bio">{bio}</p>
    <div class="links">
      {each link as a button}
    </div>
    <footer class="badge">Made with MBOpenClacky</footer>
  </div>
</body>
</html>
```

---

## Step 4 — Publish Options

Ask the user how they want to publish:

1. **GitHub Pages** (free, recommended)
2. **Vercel** (free, easy)
3. **Netlify** (free, easy)
4. **Local only** — just save the file, don't publish
5. **Other** — user has their own hosting

### Option A: GitHub Pages

1. Create a repo (or use existing)
2. Commit the `index.html`
3. Push to GitHub
4. Enable Pages in repo settings

### Option B: Vercel

If `vercel` CLI is available:
```bash
# Create a project and deploy
vercel --prod
```

### Option C: Netlify

If `netlify` CLI is available:
```bash
# Deploy
netlify deploy --prod
```

---

## Step 5 — Done

Tell the user their homepage is live. Share the URL. Be warm and natural.

Example (adapt tone to personality):
> Your homepage is live 🌟
> → https://&lt;username&gt;.github.io/&lt;repo&gt;/
>
> It's got all your links in one place. Share it anywhere!
