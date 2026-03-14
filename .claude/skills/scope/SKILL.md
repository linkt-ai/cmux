---
name: scope
description: Flesh out a Linear ticket into a fully-scoped issue with requirements and success criteria
disable-model-invocation: false
---

Transform a draft Linear ticket into a comprehensive, well-defined issue specification.

## Prerequisites

- Run `/sync-context` first to populate `workspace/context.md`
- Linear ticket should exist with at least a title and basic description

## Workflow

### Phase 1: Context Gathering (Parallel)

Spawn multiple Explore subagents concurrently to gather information:

1. **Codebase Exploration**
   - Identify relevant existing code patterns in `Sources/`
   - Find files that will need modification
   - Understand current architecture for the feature area
   - Check submodule boundaries (ghostty, vendor/bonsplit)

2. **External Documentation**
   - Web search for relevant library/framework docs
   - Fetch key documentation pages
   - Summarize implementation patterns and best practices

### Phase 2: Interview Questionnaire

Use `AskUserQuestion` tool to clarify requirements through structured questionnaires.

**Questionnaire Categories** (ask in batches of 2-4 questions):

1. **Architecture**
   - SwiftUI vs AppKit approach
   - Threading model (@MainActor, off-main handling)
   - Ghostty/Bonsplit integration points
   - Socket command design (if applicable)

2. **UI/UX**
   - Panel type (terminal, browser, sidebar)
   - Portal layering considerations
   - Keyboard shortcuts and chord bindings
   - Drag-and-drop support

3. **Submodule Impact**
   - Does this touch the ghostty fork?
   - Does this touch Bonsplit?
   - Both? Cross-submodule coordination needed?

4. **Testing**
   - Xcode UI tests (run on VM via `ssh cmux-vm`)?
   - Python socket tests (`tests/test_*.py`)?
   - E2E tests?
   - Which test suites apply?

5. **Release Impact**
   - Version bump needed (minor/patch)?
   - Changelog entry required?
   - Ghostty fork docs update (`docs/ghostty-fork.md`)?

**Question Format**:
- Each question should have 2-4 options
- Include a recommended option where applicable
- Add "(Recommended)" at the end of the label
- Provide clear descriptions for each option

### Phase 3: Linear Ticket Update

Update the Linear ticket with the full specification using `mcp__linear__save_issue`.

**Required Sections**:

```markdown
## Overview
[1-2 paragraph summary of what this ticket implements and why]

---

## Issue 1: [Component Name]

**Problem:** [What problem does this solve]

**Solution:** [How we'll solve it]

**Implementation Details:**
* [Bullet points with specifics]

**Key Files to Create/Modify:**
* `Sources/Path/To/File.swift` - [purpose]

**Success Criteria:**
- [ ] [Verifiable requirement 1]
- [ ] [Verifiable requirement 2]

---

[Repeat Issue sections for each discrete unit of work]

---

## Key Files

**New Files:**
* `Sources/Path/To/NewFile.swift` - [description]

**Modified Files:**
* `Sources/Path/To/ExistingFile.swift` - [what changes]

---

## Testing Requirements

- [ ] Unit tests for [component]
- [ ] Python socket tests for [command]
- [ ] Xcode UI tests for [flow]
- [ ] E2E tests for [scenario]

---

## Release Workflow

1. **Build**: `xcodebuild` succeeds with no new warnings
2. **Test**: Run applicable test suites on VM
3. **Submodules**: Push fork commits before parent pointer update
4. **Version**: Bump version if needed (`./scripts/bump-version.sh`)
5. **Changelog**: Update `CHANGELOG.md`

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| [Topic] | [Choice] | [Why] |
```

### Phase 4: Context Update

Update `workspace/context.md` with:
- Summary of technical decisions
- Key files list
- Issues summary
- Release workflow notes

## Output

1. **Linear Ticket**: Fully populated with all sections
2. **workspace/context.md**: Updated with decisions summary
3. **Inline Summary**: Key decisions and next steps

## Standards

- Each issue should be independently implementable
- Success criteria must be verifiable (checkboxes)
- File paths should be specific, not placeholders
- Technical decisions table captures the "why"
- Testing requirements specify which test approach (VM UI tests, Python socket tests, etc.)

---

$ARGUMENTS
