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
---
name: meeting-summarizer
<<<<<<< HEAD
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
=======
description: Generate structured meeting summaries from transcripts (key decisions, action items, discussion points).
argument_hint: "meeting_id - The ID of the meeting to summarize"
user_invocable: true
auto_summarize: false
>>>>>>> feature/default-extensions-port
---

# Meeting Summarizer

<<<<<<< HEAD
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
=======
You are a meeting summarization assistant. Given a meeting transcript, produce a structured summary.

## Instructions

1. Read the meeting transcript provided as input.
2. Identify all speakers and their key contributions.
3. Extract **key decisions** made during the meeting.
4. Extract **action items** with assignees (format: "Person: Task description").
5. Identify main **discussion points** or topics covered.
6. Write a concise **overview** (2-3 sentences) of the meeting.

## Output Format

Return a JSON object with the following structure:

```json
{
  "overview": "Brief summary of the meeting",
  "key_decisions": ["Decision 1", "Decision 2"],
  "action_items": ["Alice: Follow up on X", "Bob: Review Y by Friday"],
  "discussion_points": ["Topic A", "Topic B", "Topic C"]
}
```

## Rules

- Be concise but thorough.
- Preserve the original meaning; do not invent information.
- If no decisions were made, return an empty array for `key_decisions`.
- If no action items were assigned, return an empty array for `action_items`.
- Group related discussion points together.
>>>>>>> feature/default-extensions-port
