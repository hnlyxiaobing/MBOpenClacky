---
name: moonbit-package-search
description: Search and explore MoonBit packages on mooncakes.io. Use when the user needs to find MoonBit packages by name, keyword, description, license, or repository; check package availability; compare alternatives; get detailed package metadata (dependencies, versions, build status); or answer "does MoonBit have a package for X?" questions. Also use when planning dependencies, evaluating C FFI alternatives, or researching the MoonBit ecosystem.
---

# MoonBit Package Search

Search and explore the mooncakes.io package registry directly from the
development environment. This skill wraps the mooncakes.io public API to
provide fast, structured package discovery without leaving the terminal.

## When to use

- User asks "is there a MoonBit package for X?"
- User needs to find packages by keyword, name, license, or description
- User wants detailed info about a specific package (deps, versions, build status)
- User is comparing alternative packages for a feature
- User is evaluating C FFI alternatives or researching the ecosystem
- Any task that involves MoonBit dependency selection

## API reference

The mooncakes.io registry exposes two public endpoints:

### List all modules

```
GET https://mooncakes.io/api/v0/modules
```

Returns a JSON array. Each element:

```json
{
  "name": "author/package",
  "version": "0.1.0",
  "license": "MIT",
  "repository": "https://github.com/...",
  "keywords": ["tag1", "tag2"],
  "description": "Short description of the package",
  "is_new": false,
  "created_at": "2025-07-28T12:41:23.304188"
}
```

### Get module detail

```
GET https://mooncakes.io/api/v0/modules/{author}/{name}
```

Returns a JSON object:

```json
{
  "module": "author/package",
  "metadata": {
    "name": "author/package",
    "version": "0.10.0",
    "deps": { "moonbitlang/x": "0.4.41" },
    "readme": "README.md",
    "repository": "https://github.com/...",
    "license": "Apache-2.0",
    "keywords": ["http", "server"],
    "description": "Package description",
    "preferred-target": "native",
    "checksum": "...",
    "created_at": "2026-04-25T10:49:07.422266+00:00"
  },
  "latest_version": "0.10.0",
  "build_status": "success",
  "versions": [
    { "version": "0.10.0", "yanked": false },
    { "version": "0.9.0", "yanked": false }
  ]
}
```

## Core search script

The search logic lives in `scripts/mooncakes_search.py`.

### Usage

```
python3 scripts/mooncakes_search.py <command> [options]
```

### Commands

#### `search` - Search packages by query

```
python3 scripts/mooncakes_search.py search <query> [--field name|keywords|description|license|repository|all] [--mode exact|fuzzy|regex] [--limit N] [--json]
```

- `query` (required): Search term or pattern
- `--field`: Which field(s) to search. Default: `all`
- `--mode`: Match mode. Default: `fuzzy`
  - `exact`: Case-insensitive exact substring match
  - `fuzzy`: Tokenized fuzzy match (splits query and target into tokens, matches if all query tokens appear in any target token's substring)
  - `regex`: Full regex pattern match
- `--limit N`: Maximum results. Default: `20`
- `--json`: Output raw JSON instead of formatted table

#### `info` - Get detailed package info

```
python3 scripts/mooncakes_search.py info <author>/<name> [--json]
```

- `author/name` (required): Full package identifier (e.g. `moonbitlang/async`)
- `--json`: Output raw JSON instead of formatted text

#### `list` - List all packages (with optional filters)

```
python3 scripts/mooncakes_search.py list [--keyword KW] [--license LIC] [--author AUTHOR] [--limit N] [--json]
```

- `--keyword KW`: Filter by keyword tag
- `--license LIC`: Filter by license type
- `--author AUTHOR`: Filter by author/namespace prefix
- `--limit N`: Maximum results. Default: `50`
- `--json`: Output raw JSON

#### `batch` - Search multiple queries at once

```
python3 scripts/mooncakes_search.py batch <query1> <query2> ... [--field F] [--mode M] [--limit N] [--json]
```

Runs the same search across multiple query terms and deduplicates results.

### Caching

The full module list is cached locally for 30 minutes under the system temp
directory (`mooncakes_modules_cache.json`). Subsequent searches within the
cache window reuse the cached data instead of hitting the API again. Use
`--no-cache` to force a fresh fetch.

## Workflow

### Finding packages for a feature

1. **Broad search first**: Use `search` with `--field all --mode fuzzy` to
   discover candidates.

   ```
   python3 scripts/mooncakes_search.py search "http server"
   ```

2. **Narrow down**: Use `--field` to target specific fields.

   ```
   python3 scripts/mooncakes_search.py search "http" --field keywords --mode exact
   python3 scripts/mooncakes_search.py search "web framework" --field description
   ```

3. **Get details**: Use `info` on promising candidates.

   ```
   python3 scripts/mooncakes_search.py info bobzhang/crescent
   ```

4. **Compare**: Run `info` on multiple candidates and compare deps, versions,
   build status, and preferred-target.

### Answering "does MoonBit have X?"

1. Search with the feature keyword:

   ```
   python3 scripts/mooncakes_search.py search "encryption" --field keywords
   python3 scripts/mooncakes_search.py search "aes" --field name
   ```

2. If no results, broaden the search:

   ```
   python3 scripts/mooncakes_search.py search "crypto cipher encrypt" --mode fuzzy
   ```

3. Check details of closest matches to confirm capability.

### Evaluating C FFI alternatives

1. Search for the technology area:

   ```
   python3 scripts/mooncakes_search.py search "sqlite" --field all
   ```

2. Get details to see if the package wraps C FFI internally or is pure MoonBit:

   ```
   python3 scripts/mooncakes_search.py info colmugx/sqlite3
   ```

3. The `metadata.preferred-target` field is a strong indicator:
   - `"native"` often (but not always) means C FFI is involved
   - `"js"` or `"wasm"` targets imply pure MoonBit or JS/WASM FFI

## Output format

### Search results (default)

```
Found 5 packages matching 'http server':

  #  Name                    Version  License      Description
  1  bobzhang/crescent       0.10.0   Apache-2.0   Crescent: A web framework for MoonBit.
  2  moonbitlang/async       0.19.1   Apache-2.0   Asynchronous programming library for MoonBit
  3  f4ah6o/sse              0.3.0    MIT          Server-Sent Events (SSE) library
  ...
```

### Package detail (default)

```
Package: moonbitlang/async
  Version:     0.19.1 (latest)
  License:     Apache-2.0
  Repository:  https://github.com/moonbitlang/async
  Target:      native
  Build:       success
  Description: Asynchronous programming library for MoonBit
  Keywords:    (none)
  Dependencies:
    moonbitlang/core (implicit)
  Versions:    0.19.1, 0.19.0, 0.18.1, ... (58 total)
```

## Error handling

- **Network failure**: The script exits with code 1 and prints an error message.
  The agent should inform the user and suggest retrying or checking connectivity.
- **Empty results**: The script exits with code 0 and prints "No packages found".
  The agent should suggest broadening the search or trying different fields.
- **Invalid package name**: The `info` command exits with code 1 if the package
  does not exist. The agent should suggest using `search` to find the correct name.
- **API changes**: If the API response structure changes, the script will print
  a parse error. The agent should inform the user and suggest checking the
  mooncakes.io website directly.

## Performance notes

- The full module list is ~1219 entries and ~400KB JSON. Fetching takes 2-5
  seconds on a typical connection. Caching avoids repeated fetches.
- Fuzzy search over 1200+ entries completes in under 100ms locally.
- Detail API calls take 1-3 seconds per package.
