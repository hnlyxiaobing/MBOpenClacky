---
name: recall-memory
description: Recall and search through previously saved memories
version: "1.0.0"
user_invocable: true
category: memory
allowed_tools: [MemoryTool]
---

# Recall Memory

## Purpose
Search through and recall previously saved memories by keyword, category, or topic.

## Instructions
1. Understand what the user is trying to recall
2. Search memories by relevant keywords or phrases
3. Filter results by category if the user specified one
4. Present matching memories with full context
5. If no exact matches found:
   - Try broader search terms
   - Suggest related categories to explore
   - Offer to list all memories in a category

## Output Format
- List of matching memories with keys, values, and categories
- Relevance indicator for each match
- "No matches found" with alternative search suggestions if empty
- Total count of results
