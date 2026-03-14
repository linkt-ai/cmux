---
name: session-notes
description: Capture session decisions, changes, and next steps
disable-model-invocation: false
---

Capture notes for this session.

## Trigger

Claude may suggest running this when context usage is high.

## Content (Compact Format)

### Decisions
- Key choices made and rationale

### Files Modified
- List of changed files

### Problems Encountered
- Issues hit and resolutions

### Submodule Changes
- Any changes to `ghostty` or `vendor/bonsplit` submodules
- New commits pushed to forks

### Next Steps
- Outstanding work and follow-ups

## Output

Save to: `workspace/notes/${CLAUDE_SESSION_ID}.md`

## Format

```markdown
# Session Notes: ${CLAUDE_SESSION_ID}

**Date**: [date]
**Branch**: [branch]

## Decisions
- [decision]: [rationale]

## Files Modified
- `Sources/Path/To/File.swift` - [what changed]

## Submodule Changes
- [submodule]: [commit summary, fork branch pushed to]

## Problems
- [problem] → [resolution]

## Next Steps
- [ ] [task]
```

Keep notes clean, compact, and actionable.
