---
name: implement
description: Execute the implementation plan from workspace/plans/PLAN.md
disable-model-invocation: true
model: opus
---

Execute the implementation plan at `workspace/plans/PLAN.md`.

## Workflow

1. Read `workspace/plans/PLAN.md` completely
2. Identify all phases and their dependencies
3. Execute each phase sequentially using forked subagents
4. Report completion summary when all phases done

## Phase Execution (Per Phase)

For each phase, spawn a subagent with:
- Full phase context from plan
- TDD workflow enforcement
- Validation checkpoint at end

### TDD Workflow (Phases 1 through N-2)
1. Read the full phase section
2. Write ALL tests first (should fail)
3. Implement minimum code to pass
4. Verify all tests pass, no regressions
5. Mark phase complete

#### Build & Test Commands
- **Build**: `xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' build`
- **Unit tests**: `xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' test`
- **Tagged reload**: `./scripts/reload.sh --tag <plan-name>`
- **Python tests** (on VM): `ssh cmux-vm 'cd /Users/cmux/GhosttyTabs && python3 tests/test_<name>.py'`

### Phase N-1: Documentation
- Update relevant docs in `docs/`
- Ensure code comments are complete where non-obvious
- Verify build succeeds

### Phase N: Manual Handoff
- Run full test suite
- Launch tagged Debug app for manual verification
- Present manual verification scenarios
- Release control to human

## Execution Mode

Run phases autonomously. Only pause if:
- Tests fail after implementation
- Ambiguity in plan requirements
- Phase N reached (human handoff)

Ultrathink and begin.
