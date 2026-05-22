#!/usr/bin/env python3
"""Mooncakes.io package search tool.

Wraps the mooncakes.io public API to provide local search, filter, and
detail retrieval for MoonBit packages.

API endpoints:
  GET https://mooncakes.io/api/v0/modules          - list all modules
  GET https://mooncakes.io/api/v0/modules/{a}/{n}  - module detail

Usage:
  python3 mooncakes_search.py search <query> [options]
  python3 mooncakes_search.py info   <author/name> [options]
  python3 mooncakes_search.py list   [options]
  python3 mooncakes_search.py batch  <q1> <q2> ... [options]
"""

import argparse
import json
import os
import re
import sys
import tempfile
import time
import urllib.request
import urllib.error

API_BASE = "https://mooncakes.io/api/v0"
CACHE_FILENAME = "mooncakes_modules_cache.json"
CACHE_TTL_SECONDS = 1800  # 30 minutes


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def _fetch_json(url, timeout=30):
    """Fetch JSON from a URL. Returns parsed object or raises SystemExit."""
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.URLError as e:
        print(f"Error: network request failed for {url}: {e}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: failed to parse JSON from {url}: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: unexpected error fetching {url}: {e}", file=sys.stderr)
        sys.exit(1)


def _cache_path():
    """Return the cache file path in the system temp directory."""
    return os.path.join(tempfile.gettempdir(), CACHE_FILENAME)


def _load_cache(no_cache=False):
    """Load the module list from cache or API."""
    cache_file = _cache_path()
    if not no_cache and os.path.exists(cache_file):
        try:
            mtime = os.path.getmtime(cache_file)
            if time.time() - mtime < CACHE_TTL_SECONDS:
                with open(cache_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                if isinstance(data, list) and len(data) > 0:
                    return data
        except (json.JSONDecodeError, OSError):
            pass  # fall through to fetch

    data = _fetch_json(f"{API_BASE}/modules")
    if not isinstance(data, list):
        print("Error: API returned unexpected format (expected array)", file=sys.stderr)
        sys.exit(1)

    try:
        with open(cache_file, "w", encoding="utf-8") as f:
            json.dump(data, f)
    except OSError:
        pass  # caching is best-effort

    return data


# ---------------------------------------------------------------------------
# Matching algorithms
# ---------------------------------------------------------------------------

def _exact_match(query, text):
    """Case-insensitive exact substring match."""
    return query.lower() in text.lower()


def _fuzzy_match(query, text):
    """Tokenized fuzzy match.

    Splits the query into tokens (by whitespace and /-). A match occurs
    when ANY query token is a substring of the text (case-insensitive).
    This OR-semantics ensures broad discovery; ranking by _score() will
    push the most relevant results (where multiple tokens match) to the top.
    """
    q_tokens = [qt for qt in re.split(r"[\s/]+", query.lower()) if qt]
    if not q_tokens:
        return False
    text_lower = text.lower()
    return any(qt in text_lower for qt in q_tokens)


def _regex_match(query, text):
    """Full regex pattern match."""
    try:
        return bool(re.search(query, text, re.IGNORECASE))
    except re.error as e:
        print(f"Error: invalid regex pattern '{query}': {e}", file=sys.stderr)
        sys.exit(1)


_MATCHERS = {
    "exact": _exact_match,
    "fuzzy": _fuzzy_match,
    "regex": _regex_match,
}


# ---------------------------------------------------------------------------
# Field accessors
# ---------------------------------------------------------------------------

def _get_fields(module, field):
    """Return a list of strings to match against for the given field."""
    if field == "name":
        return [module.get("name", "")]
    elif field == "keywords":
        return module.get("keywords", [])
    elif field == "description":
        return [module.get("description", "")]
    elif field == "license":
        return [module.get("license", "")]
    elif field == "repository":
        return [module.get("repository", "")]
    elif field == "all":
        return (
            [module.get("name", "")]
            + module.get("keywords", [])
            + [module.get("description", "")]
            + [module.get("license", "")]
            + [module.get("repository", "")]
        )
    else:
        print(f"Error: unknown field '{field}'", file=sys.stderr)
        sys.exit(1)


def _matches(module, query, field, mode):
    """Check if a module matches the query on the given field/mode."""
    match_fn = _MATCHERS.get(mode)
    if match_fn is None:
        print(f"Error: unknown mode '{mode}'", file=sys.stderr)
        sys.exit(1)
    return any(match_fn(query, text) for text in _get_fields(module, field))


# ---------------------------------------------------------------------------
# Scoring (for result ranking)
# ---------------------------------------------------------------------------

def _score(module, query):
    """Compute a relevance score (higher = more relevant).

    Name exact match:  +100
    Name prefix match: +80
    Name contains:     +50
    Keyword exact:     +60
    Keyword contains:  +30
    Description:       +10 per query token matched
    Multi-token bonus: +20 per additional query token matched in name/keywords
    """
    q_lower = query.lower()
    name = module.get("name", "").lower()
    q_tokens = [qt for qt in re.split(r"[\s/]+", q_lower) if qt]
    score = 0

    # Name scoring
    if name == q_lower:
        score += 100
    elif name.startswith(q_lower):
        score += 80
    elif q_lower in name:
        score += 50
    else:
        # Check how many query tokens match in the name
        name_matches = sum(1 for qt in q_tokens if qt in name)
        if name_matches > 0:
            score += 20 * name_matches
            if name_matches > 1:
                score += 20 * (name_matches - 1)  # multi-token bonus

    # Keyword scoring
    kw_list = module.get("keywords", [])
    kw_text = " ".join(kw_list).lower()
    kw_matches = sum(1 for qt in q_tokens if qt in kw_text)
    for kw in kw_list:
        kw_lower = kw.lower()
        if kw_lower == q_lower:
            score += 60
        elif q_lower in kw_lower:
            score += 30
        else:
            for qt in q_tokens:
                if qt in kw_lower:
                    score += 15
    if kw_matches > 1:
        score += 20 * (kw_matches - 1)  # multi-token bonus

    # Description scoring
    desc = module.get("description", "").lower()
    desc_matches = sum(1 for qt in q_tokens if qt in desc)
    score += 10 * desc_matches
    if desc_matches > 1:
        score += 5 * (desc_matches - 1)

    return score


# ---------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------

def _format_search_results(results, query, json_output=False):
    """Format search results for display."""
    if json_output:
        return json.dumps(results, indent=2, ensure_ascii=False)

    if not results:
        return f"No packages found matching '{query}'."

    lines = [f"Found {len(results)} package(s) matching '{query}':\n"]
    lines.append(f"  {'#':>3}  {'Name':<30} {'Version':<10} {'License':<14} Description")
    lines.append(f"  {'---':>3}  {'-'*30} {'-'*10} {'-'*14} {'-'*20}")

    for i, mod in enumerate(results, 1):
        name = mod.get("name", "?")[:30]
        ver = mod.get("version", "?")[:10]
        lic = mod.get("license", "?")[:14]
        desc = mod.get("description", "")[:60]
        lines.append(f"  {i:>3}  {name:<30} {ver:<10} {lic:<14} {desc}")

    return "\n".join(lines)


def _format_detail(data, json_output=False):
    """Format package detail for display."""
    if json_output:
        return json.dumps(data, indent=2, ensure_ascii=False)

    meta = data.get("metadata", {})
    lines = []
    lines.append(f"Package: {data.get('module', '?')}")
    lines.append(f"  Version:     {meta.get('version', '?')} (latest)")
    lines.append(f"  License:     {meta.get('license', '?')}")
    lines.append(f"  Repository:  {meta.get('repository', '?')}")
    lines.append(f"  Target:      {meta.get('preferred-target', '?')}")
    lines.append(f"  Build:       {data.get('build_status', '?')}")
    lines.append(f"  Description: {meta.get('description', '?')}")

    keywords = meta.get("keywords", [])
    lines.append(f"  Keywords:    {', '.join(keywords) if keywords else '(none)'}")

    deps = meta.get("deps", {})
    if deps:
        lines.append("  Dependencies:")
        for dep_name, dep_ver in deps.items():
            lines.append(f"    {dep_name}: {dep_ver}")
    else:
        lines.append("  Dependencies: (none declared)")

    versions = data.get("versions", [])
    ver_list = [v["version"] for v in versions if not v.get("yanked")]
    if ver_list:
        preview = ", ".join(ver_list[:10])
        suffix = f", ... ({len(ver_list)} total)" if len(ver_list) > 10 else ""
        lines.append(f"  Versions:    {preview}{suffix}")

    created = meta.get("created_at", "")
    if created:
        lines.append(f"  Created:     {created[:10]}")

    return "\n".join(lines)


def _format_list_results(results, json_output=False):
    """Format list/filter results for display."""
    if json_output:
        return json.dumps(results, indent=2, ensure_ascii=False)

    if not results:
        return "No packages match the filter criteria."

    lines = [f"Found {len(results)} package(s):\n"]
    lines.append(f"  {'#':>3}  {'Name':<30} {'Version':<10} {'License':<14} Description")
    lines.append(f"  {'---':>3}  {'-'*30} {'-'*10} {'-'*14} {'-'*20}")

    for i, mod in enumerate(results, 1):
        name = mod.get("name", "?")[:30]
        ver = mod.get("version", "?")[:10]
        lic = mod.get("license", "?")[:14]
        desc = mod.get("description", "")[:60]
        lines.append(f"  {i:>3}  {name:<30} {ver:<10} {lic:<14} {desc}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Command implementations
# ---------------------------------------------------------------------------

def cmd_search(args):
    """Search packages by query."""
    modules = _load_cache(no_cache=args.no_cache)
    query = args.query
    field = args.field
    mode = args.mode
    limit = args.limit

    matched = []
    for mod in modules:
        if _matches(mod, query, field, mode):
            scored = dict(mod)
            scored["_score"] = _score(mod, query)
            matched.append(scored)

    matched.sort(key=lambda m: m.get("_score", 0), reverse=True)
    matched = matched[:limit]

    for m in matched:
        m.pop("_score", None)

    print(_format_search_results(matched, query, json_output=args.json))


def cmd_info(args):
    """Get detailed info about a package."""
    full_name = args.package
    parts = full_name.split("/")
    if len(parts) != 2:
        print(f"Error: package name must be in 'author/name' format, got '{full_name}'", file=sys.stderr)
        sys.exit(1)

    author, name = parts
    data = _fetch_json(f"{API_BASE}/modules/{author}/{name}")
    print(_format_detail(data, json_output=args.json))


def cmd_list(args):
    """List packages with optional filters."""
    modules = _load_cache(no_cache=args.no_cache)

    if args.keyword:
        kw_lower = args.keyword.lower()
        modules = [m for m in modules if any(kw_lower == k.lower() for k in m.get("keywords", []))]

    if args.license:
        lic_lower = args.license.lower()
        modules = [m for m in modules if m.get("license", "").lower() == lic_lower]

    if args.author:
        auth_lower = args.author.lower()
        modules = [m for m in modules if m.get("name", "").split("/")[0].lower() == auth_lower]

    modules = modules[:args.limit]
    print(_format_list_results(modules, json_output=args.json))


def cmd_batch(args):
    """Search multiple queries and deduplicate."""
    modules = _load_cache(no_cache=args.no_cache)
    field = args.field
    mode = args.mode
    limit = args.limit

    seen_names = set()
    matched = []

    for query in args.queries:
        for mod in modules:
            name = mod.get("name", "")
            if name in seen_names:
                continue
            if _matches(mod, query, field, mode):
                scored = dict(mod)
                scored["_score"] = _score(mod, query)
                matched.append(scored)
                seen_names.add(name)

    matched.sort(key=lambda m: m.get("_score", 0), reverse=True)
    matched = matched[:limit]

    for m in matched:
        m.pop("_score", None)

    queries_str = ", ".join(args.queries)
    if args.json:
        print(json.dumps(matched, indent=2, ensure_ascii=False))
    else:
        print(_format_search_results(matched, queries_str))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        prog="mooncakes_search",
        description="Search and explore MoonBit packages on mooncakes.io",
    )
    parser.add_argument("--no-cache", action="store_true", help="Force fresh API fetch, ignore cache")
    sub = parser.add_subparsers(dest="command", required=True)

    # --- search ---
    p_search = sub.add_parser("search", help="Search packages by query")
    p_search.add_argument("query", help="Search term or pattern")
    p_search.add_argument(
        "--field",
        choices=["name", "keywords", "description", "license", "repository", "all"],
        default="all",
        help="Field(s) to search (default: all)",
    )
    p_search.add_argument(
        "--mode",
        choices=["exact", "fuzzy", "regex"],
        default="fuzzy",
        help="Match mode (default: fuzzy)",
    )
    p_search.add_argument("--limit", type=int, default=20, help="Max results (default: 20)")
    p_search.add_argument("--json", action="store_true", help="Output raw JSON")

    # --- info ---
    p_info = sub.add_parser("info", help="Get detailed package info")
    p_info.add_argument("package", help="Full package name (author/name)")
    p_info.add_argument("--json", action="store_true", help="Output raw JSON")

    # --- list ---
    p_list = sub.add_parser("list", help="List packages with optional filters")
    p_list.add_argument("--keyword", help="Filter by keyword tag")
    p_list.add_argument("--license", help="Filter by license type")
    p_list.add_argument("--author", help="Filter by author/namespace")
    p_list.add_argument("--limit", type=int, default=50, help="Max results (default: 50)")
    p_list.add_argument("--json", action="store_true", help="Output raw JSON")

    # --- batch ---
    p_batch = sub.add_parser("batch", help="Search multiple queries and deduplicate")
    p_batch.add_argument("queries", nargs="+", help="Multiple search terms")
    p_batch.add_argument(
        "--field",
        choices=["name", "keywords", "description", "license", "repository", "all"],
        default="all",
        help="Field(s) to search (default: all)",
    )
    p_batch.add_argument(
        "--mode",
        choices=["exact", "fuzzy", "regex"],
        default="fuzzy",
        help="Match mode (default: fuzzy)",
    )
    p_batch.add_argument("--limit", type=int, default=30, help="Max results (default: 30)")
    p_batch.add_argument("--json", action="store_true", help="Output raw JSON")

    args = parser.parse_args()

    dispatch = {
        "search": cmd_search,
        "info": cmd_info,
        "list": cmd_list,
        "batch": cmd_batch,
    }
    dispatch[args.command](args)


if __name__ == "__main__":
    main()
