# mooncakes.io API Reference

## Endpoints

### List All Modules

```
GET https://mooncakes.io/api/v0/modules
```

**Response**: JSON array of module summary objects.

**Fields per module**:

| Field | Type | Description |
|-------|------|-------------|
| name | string | Full module name in `author/package` format |
| version | string | Latest version string |
| license | string | SPDX license identifier (e.g. "Apache-2.0", "MIT") |
| repository | string | Source code repository URL |
| keywords | string[] | Array of keyword tags |
| description | string | Short description of the package |
| is_new | boolean | Whether the package was recently added |
| created_at | string | ISO 8601 timestamp of initial creation |

**Example**:
```json
{
  "name": "bobzhang/crescent",
  "version": "0.10.0",
  "license": "Apache-2.0",
  "repository": "https://github.com/bobzhang/crescent",
  "keywords": ["http", "server", "web", "framework", "async", "ai-friendly"],
  "description": "Crescent: A web framework for MoonBit.",
  "is_new": false,
  "created_at": "2026-04-25T10:49:07.422266"
}
```

**Size**: ~1219 entries, ~400KB JSON payload.

---

### Get Module Detail

```
GET https://mooncakes.io/api/v0/modules/{author}/{name}
```

**Parameters**:
- `{author}`: The author/namespace from the module name (e.g. `moonbitlang`)
- `{name}`: The package name (e.g. `async`)

**Response**: JSON object with full metadata.

**Top-level fields**:

| Field | Type | Description |
|-------|------|-------------|
| module | string | Full module name |
| metadata | object | Detailed metadata (see below) |
| latest_version | string | Latest version string |
| build_status | string | Build status: "success", "failure", etc. |
| versions | object[] | Array of all published versions |

**Metadata fields**:

| Field | Type | Description |
|-------|------|-------------|
| name | string | Full module name |
| version | string | Version this metadata describes |
| deps | object | Map of dependency name → version constraint |
| readme | string | README filename |
| repository | string | Source code repository URL |
| license | string | SPDX license identifier |
| keywords | string[] | Array of keyword tags |
| description | string | Short description |
| preferred-target | string | Target platform: "native", "js", "wasm", etc. |
| checksum | string | Package integrity checksum |
| created_at | string | ISO 8601 timestamp |

**Version object fields**:

| Field | Type | Description |
|-------|------|-------------|
| version | string | Version string |
| yanked | boolean | Whether this version was yanked |

**Example**:
```json
{
  "module": "moonbitlang/async",
  "metadata": {
    "name": "moonbitlang/async",
    "version": "0.19.1",
    "deps": {},
    "readme": "README.md",
    "repository": "https://github.com/moonbitlang/async",
    "license": "Apache-2.0",
    "keywords": [],
    "description": "Asynchronous programming library for MoonBit",
    "preferred-target": "native",
    "checksum": "a7e6793c...",
    "created_at": "2026-05-18T03:50:57.836703+00:00"
  },
  "latest_version": "0.19.1",
  "build_status": "success",
  "versions": [
    {"version": "0.19.1", "yanked": false},
    {"version": "0.19.0", "yanked": false}
  ]
}
```

## Rate limiting

No documented rate limits observed. The API is public and appears to be
unauthenticated. Use reasonable request patterns: cache the module list,
avoid rapid-fire detail requests.

## Error responses

- Non-existent module: Returns HTTP 404 with an error JSON body.
- Server errors: Returns HTTP 5xx.
