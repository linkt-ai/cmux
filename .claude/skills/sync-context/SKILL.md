---
name: sync-context
description: Pull Linear ticket and GitHub PR context for current branch
disable-model-invocation: false
---

Gather context from Linear and GitHub for the current branch.

## Branch Parsing

Extract Linear ticket ID from branch name using pattern `oss-(\d+)` (case-insensitive).
Reconstruct as `OSS-N` (e.g., branch `jack/oss-4-git-graph` → ticket `OSS-4`).

Only `OSS-*` tickets are supported. If the branch doesn't match, skip Linear lookup gracefully and note "No Linear ticket detected for this branch."

Current branch: !`git branch --show-current`

## Data Sources

### Linear
- Ticket description, title, status, assignee, labels
- Use `mcp__linear__get_issue` with `OSS-N` identifier

### GitHub
- Check `manaflow-ai/cmux` for PRs matching the current branch
- Also check `linkt-ai/cmux` (user's fork) for PRs
- Use `mcp__github__list_pull_requests` and `mcp__github__get_pull_request`

## Workflow

1. Parse ticket ID from branch name (regex: `oss-(\d+)`, case-insensitive)
2. If ticket ID found, fetch Linear ticket via `mcp__linear__get_issue`
3. Search for GitHub PRs on both `manaflow-ai/cmux` and `linkt-ai/cmux`
4. Write combined context to `workspace/context.md`
5. Display inline summary

## Output

### File: `workspace/context.md`

```markdown
# Context: [TICKET-ID]

## Linear Ticket
**Title**: [title]
**Status**: [status]
**Description**: [description]

## GitHub PR
**Title**: [PR title]
**URL**: [PR url]
**Description**: [PR description]
**Comments**: [summary of discussion]

---
*Synced: [timestamp]*
```

If no Linear ticket is detected, still write the file with GitHub PR info (if any) and note the branch name.

### Inline Summary

Provide 3-5 bullet summary of:
- What the ticket/PR is about
- Key requirements
- Current status
- Any blockers or concerns mentioned
