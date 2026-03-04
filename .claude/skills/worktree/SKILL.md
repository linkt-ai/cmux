---
name: worktree
description: Manage git worktrees for parallel development
disable-model-invocation: false
allowed-tools: Bash, Read
---

Manage git worktrees for parallel development on cmux.

## Commands

- `/worktree create <BRANCH>` - Create worktree with submodule setup
- `/worktree list` - List all worktrees with status
- `/worktree remove <BRANCH>` - Remove worktree and cleanup

## Implementation

### Create

```bash
# Create worktree from main
git worktree add worktrees/wt-<BRANCH> -b <BRANCH> main

# Initialize submodules in worktree
cd worktrees/wt-<BRANCH>
git submodule update --init --recursive

# Symlink GhosttyKit.xcframework from main repo (avoid rebuilding)
ln -s "$(cd ../.. && pwd)/GhosttyKit.xcframework" GhosttyKit.xcframework
```

### Post-Create Checklist

After creating a worktree, verify:
- [ ] Submodules initialized (`ghostty/`, `vendor/bonsplit/`)
- [ ] GhosttyKit.xcframework symlinked
- [ ] Can build: `cd worktrees/wt-<BRANCH> && xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' build`

### Building in a Worktree

Use the `--tag` system for isolated debug builds:
```bash
cd worktrees/wt-<BRANCH> && ./scripts/reload.sh --tag <BRANCH>
```

This creates an isolated app with its own name, bundle ID, socket, and derived data path.

### List

```bash
git worktree list
```

Show each worktree with:
- Branch name
- Path
- Last commit summary
- Whether it has uncommitted changes

### Remove

```bash
git worktree remove worktrees/wt-<BRANCH>
```

Before removing:
- Check for uncommitted changes (warn user)
- Clean up any tagged app artifacts in `/tmp/cmux-<BRANCH>/`

## Worktree Directory Structure

```
worktrees/
└── wt-<BRANCH>/
    ├── GhosttyKit.xcframework  → symlink to main repo
    ├── ghostty/                 # Submodule (initialized)
    ├── vendor/bonsplit/         # Submodule (initialized)
    ├── Sources/                 # Git worktree source
    └── ...
```

## Limits

- Max 3 worktrees (native app, no server infrastructure to manage)
- `worktrees/` directory is gitignored

## Notes

- No Docker, no port allocation — cmux is a native macOS app
- The `--tag` flag in `reload.sh` provides build isolation (separate app name, bundle ID, socket)
- Always check for uncommitted changes before removing a worktree
- GhosttyKit.xcframework symlink avoids expensive Zig rebuilds per worktree

---

User request:

$ARGUMENTS
