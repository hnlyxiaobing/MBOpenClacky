---
name: meeting-summarizer
description: |
  Summarize a completed meeting from its transcript. Produces a structured summary with key decisions, action items, and discussion highlights. Triggered automatically when a meeting ends.
  Trigger on: "meeting summary", "summarize meeting", "会议总结", "会议纪要".
disable-model-invocation: false
user_invocable: true
category: utility
allowed_tools:
  - FileReader
  - Write
  - Terminal
---

# Meeting Summarizer

A skill for summarizing completed meetings from their transcripts into structured summaries.

## Workflow

1. **Retrieve the meeting**: Read the meeting record from `~/.mbopenclacky/meetings.json` or accept a pasted transcript.
2. **Analyze the transcript**: Identify key discussion topics, decisions, and action items.
3. **Generate structured summary**: Produce a summary with the following sections:
   - **Meeting Overview**: Title, date, participants
   - **Key Decisions**: Decisions made during the meeting
   - **Action Items**: Tasks with assignees and deadlines
   - **Discussion Highlights**: Important points discussed
   - **Open Questions**: Unresolved items requiring follow-up
4. **Save the summary**: Update the meeting record via the REST API (`PUT /api/meetings/:id`) or write directly to the meetings file.

## API Integration

Meetings are managed through the REST API:

```
GET    /api/meetings           - List all meetings
POST   /api/meetings           - Create a new meeting
GET    /api/meetings/:id       - Get meeting details
PUT    /api/meetings/:id       - Update meeting (save summary)
DELETE /api/meetings/:id       - Delete meeting
POST   /api/meetings/:id/summarize - Trigger summarization
```

## Summary Format

```markdown
## Meeting: [Title]
**Date**: [Date]
**Participants**: [Names]

### Key Decisions
1. [Decision 1]
2. [Decision 2]

### Action Items
- [ ] [Task] — @[Assignee] (due: [Date])
- [ ] [Task] — @[Assignee]

### Discussion Highlights
- [Topic 1]: [Summary]
- [Topic 2]: [Summary]

### Open Questions
- [Question 1]
- [Question 2]
```

## Notes

- If the transcript is very long, focus on the most impactful decisions and action items.
- Always include assignees for action items when identifiable from the transcript.
- Use Chinese if the meeting transcript is in Chinese; otherwise use English.
