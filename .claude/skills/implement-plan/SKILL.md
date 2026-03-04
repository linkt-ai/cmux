---
name: implement-plan
description: Create a comprehensive implementation plan following TDD guidelines
disable-model-invocation: true
---

Create an implementation plan and save to `workspace/plans/PLAN.md`.

## Required Sections

1. **Header** - Feature name, date, approach (TDD)
2. **Executive Summary** - What, why, key decisions, impact
3. **Current State** - Data flow, challenges, file links
4. **Target Solution** - Data flow, design decisions with WHY
5. **Phases** - Implementation phases (see structure below)
6. **Risk Assessment** - Low/Medium/High with mitigation
7. **Success Criteria** - Verifiable requirements

## Phase Structure (MANDATORY)

Plans ALWAYS end with these two phases:
- **Phase N-1**: Documentation Updates
- **Phase N**: Manual Testing & Human Handoff

## TDD Pattern (Every Phase 1 through N-2)

### Phase X: [Name] (TDD)

#### Step A: Write Tests FIRST

For **Swift unit tests** (`cmuxTests/`):
**File**: `cmuxTests/FeatureNameTests.swift`
- Complete XCTest code (no pseudocode)
- **Validation**: Tests should FAIL (build but assertions fail, or new test targets compile)

For **Python socket/integration tests** (`tests/`):
**File**: `tests/test_feature_name.py`
- Complete pytest-style code using the `cmux.py` helper
- **Validation**: Tests should FAIL

For **UI tests** (`cmuxUITests/`):
**File**: `cmuxUITests/FeatureNameUITests.swift`
- Complete XCUITest code
- **Validation**: Tests should FAIL

#### Step B: Implement to Pass
**File**: `Sources/path/to/source.swift` (or relevant source path)
- **Validation**: Tests should PASS

## Standards

- Swift: follow existing project conventions (SwiftUI + AppKit patterns)
- Test files: `Sources/X/Y.swift` -> `cmuxTests/YTests.swift`
- Python tests: `tests/test_feature_name.py` (socket-based, run on VM)
- File refs: `[file.swift](Sources/path/to/file.swift)` or `[file.swift:42](Sources/path/to/file.swift#L42)`
- Build validation: `xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' build`
- Unit test validation: `xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' test`
- Python test validation: run via `ssh cmux-vm` (see CLAUDE.md)

## Output

Save to: `workspace/plans/PLAN.md`

---

$ARGUMENTS
