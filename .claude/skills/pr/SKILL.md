---
name: pr
description: Review changes and create a pull request
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(git *), Bash(xcodebuild *), mcp__github__*
---

Review current changes and create a pull request.

## Workflow

### Phase 1: Analyze Changes

```bash
git diff main...HEAD --stat
git log main..HEAD --oneline
```

Review:
- Files changed and scope
- Test coverage for changes
- Code quality issues
- Submodule pointer changes (ghostty, vendor/bonsplit)

### Phase 2: Validate Build

```bash
xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' build
```

### Phase 3: Generate Review

Evaluate against:
- [ ] Build succeeds (`xcodebuild build`)
- [ ] No new compiler warnings
- [ ] Follows project patterns (portal layering, socket threading policy, focus policy)
- [ ] Submodule commits pushed to remote (if applicable)
- [ ] No security issues
- [ ] Custom UTTypes declared in Info.plist (if new drag-and-drop types added)
- [ ] `#if DEBUG` guards on all `dlog()` call sites

### Phase 4: Create PR

Use GitHub MCP:
```
mcp__github__create_pull_request(
  owner: "manaflow-ai",
  repo: "cmux",
  title: "[title]",
  head: "linkt-ai:<current-branch>",
  base: "main",
  body: "[body]"
)
```

## PR Description Format

```markdown
## Summary
[2-3 sentences on what this PR does]

## Changes
- [change 1]
- [change 2]

## Review Notes
[Any concerns, trade-offs, or areas needing attention]

## Testing
- [ ] Build succeeds
- [ ] No new warnings
- [ ] Manual testing completed
- [ ] Follows project patterns

---
*Generated with /pr skill*
```

## Approval Gate

Before creating PR, present:
- Proposed title
- Proposed description
- Build result
- Any review concerns

Wait for user approval to create.
