---
name: techdebt
description: Analyze and fix technical debt in the codebase
disable-model-invocation: false
argument-hint: [--deep|--src|--tests]
---

Analyze technical debt and auto-fix safe issues.

## Scope

**Default**: Current branch diff vs `main`
**Flags**:
- `--deep` - Full codebase scan
- `--src` - Entire `Sources/` directory
- `--tests` - Scan `cmuxUITests/` and `tests/` directories

## Detection Categories

1. **Duplicated Code** - Similar blocks that could be consolidated
2. **Dead Code** - Unused functions, variables, imports
3. **TODO/FIXME** - Outstanding work markers
4. **Pattern Inconsistencies** - Code not following established patterns

### Swift-Specific Detection

- Unused imports (`import Foundation` when not needed, etc.)
- Dead `@objc` methods not referenced by selectors or XIBs
- Unused `@Published` properties
- Orphaned `#if DEBUG` blocks (empty or unreachable)
- Unused protocol conformances

### cmux Pattern Violations

- **Socket command threading policy** — `DispatchQueue.main.sync` in high-frequency telemetry hot paths (`report_*`, `ports_kick`, status/progress/log metadata)
- **Focus policy violations** — Non-focus commands that activate the app, raise windows, or mutate focus/selection
- **Portal layering issues** — `SurfaceSearchOverlay` mounted from wrong container (should be `GhosttySurfaceScrollView`, not SwiftUI panel containers)

## Workflow

1. Determine scope from arguments (default: branch diff)
2. Run analysis for each category
3. Classify findings:
   - **Safe to fix**: Dead imports, obvious cleanup
   - **Needs review**: Duplicated code, pattern issues, policy violations

## Actions

**Auto-fix** (no approval needed):
- Remove unused imports
- Remove unused variables (if clearly dead)

**Report only** (requires human decision):
- Duplicated code blocks (show locations)
- Pattern inconsistencies (show examples)
- Policy violations (show code + policy reference)
- TODO/FIXME summary (grouped by priority)

## Output Format

### Auto-Fixed
- [x] Removed N unused imports in M files
- [x] Fixed N dead code issues

### Needs Review
| Category | Location | Description |
|----------|----------|-------------|
| Duplicate | File.swift:42, Other.swift:88 | Similar validation logic |
| Pattern | SocketHandler.swift | main.sync in telemetry path |
| Focus | CommandX.swift | Non-focus command activates app |

### TODOs/FIXMEs
- **High**: [count] (FIXME tags)
- **Medium**: [count] (TODO tags)

---

$ARGUMENTS
