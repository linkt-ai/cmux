Merge a feature branch to a target branch with proper rebase, preview testing, and PR merge.

## Arguments

$ARGUMENTS may contain:
- A branch name (e.g., `feat/git-tree`). If omitted, detect from current branch.
- `--into <target>` to specify the target branch. If omitted, defaults to `main`.

Parse $ARGUMENTS to extract BRANCH and TARGET.

## Definitions

```
MAIN_REPO=/Users/jackmoffatt/Development/repositories/manaflow-ai/cmux
GITHUB_OWNER=linkt-ai
GITHUB_REPO=cmux
```

---

## Phase 1: Determine Branch and Initial State

### 1.1 Determine Branch

If $ARGUMENTS contains a branch name, use it as BRANCH. Otherwise:

```bash
git branch --show-current
```

If on the TARGET branch, abort with error - must specify branch name or be on feature branch.

### 1.2 Fetch Latest State

```bash
git fetch origin $TARGET
git fetch origin $BRANCH
```

### 1.3 Check for Uncommitted Changes

```bash
git status --porcelain
```

If there are uncommitted changes, use `AskUserQuestion`:

**Header**: "Uncommitted changes"

**Options**:
1. **Stash and continue**: Stash changes, continue with merge process
2. **Abort**: Stop and let user handle changes manually

---

## Phase 2: Ensure Feature Branch is Pushed

### 2.1 Checkout Feature Branch

```bash
git checkout $BRANCH
```

### 2.2 Check for Unpushed Commits

```bash
git log origin/$BRANCH..$BRANCH --oneline
```

If there are unpushed commits, push them:

```bash
git push origin $BRANCH
```

### 2.3 Check for Uncommitted Changes on Feature Branch

```bash
git status --porcelain
```

If dirty, use `AskUserQuestion` to confirm committing and pushing:

```bash
git add -A
git commit -m "<message from user>"
git push origin $BRANCH
```

---

## Phase 3: Rebase Feature Branch on Target

### 3.1 Start Rebase

```bash
git rebase origin/$TARGET
```

### 3.2 Handle Conflicts (if any)

If rebase fails with conflicts:

1. Show the conflicts:
   ```bash
   git status
   git diff --name-only --diff-filter=U
   ```

2. For each conflicted file, show the conflict:
   ```bash
   git diff <file>
   ```

3. Use `AskUserQuestion` for each conflict:

   **Header**: "Resolve conflict"

   **Options**:
   1. **Keep ours (feature branch)**: `git checkout --ours <file>`
   2. **Keep theirs (target)**: `git checkout --theirs <file>`
   3. **Manual resolution**: Open file and let user resolve
   4. **Abort rebase**: `git rebase --abort`

4. After resolving each file:
   ```bash
   git add <file>
   ```

5. Continue rebase:
   ```bash
   git rebase --continue
   ```

6. Repeat until rebase completes.

### 3.3 Force Push Rebased Branch

After successful rebase:

```bash
git push origin $BRANCH --force-with-lease
```

---

## Phase 4: Preview Merge Locally

### 4.1 Checkout Target and Preview

```bash
git checkout $TARGET
git reset --hard origin/$TARGET
git merge --no-commit --no-ff origin/$BRANCH
```

### 4.2 Show Preview Summary

```bash
git diff --cached --stat
```

### 4.3 Wait for Manual Testing

Display message:

```markdown
## Preview Ready

The merge has been staged locally. Please test manually:

- Build: `xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' build`
- Run: `./scripts/reload.sh --tag merge-preview`

When testing is complete, respond with your results.
```

Use `AskUserQuestion`:

**Header**: "Testing complete?"

**Options**:
1. **Tests pass, ready to merge**: Continue to Phase 6
2. **Need to make fixes**: Go to Phase 5 (tweaks)
3. **Abort merge**: Clean up and exit

---

## Phase 5: Handle Tweaks (if needed)

If user made changes during testing or selected "Need to make fixes":

### 5.1 Show Current Changes

```bash
git status
git diff
```

### 5.2 Commit Tweaks to Feature Branch

```bash
# Stash the preview state (includes both merge + tweaks)
git stash

# Reset target to clean state
git checkout $TARGET
git reset --hard origin/$TARGET

# Checkout feature branch
git checkout $BRANCH

# Apply the stash
git stash pop

# Show what changed
git status
git diff
```

### 5.3 Commit and Push Tweaks

Use `AskUserQuestion` to get commit message:

```bash
git add -A
git commit -m "<message from user>"
git push origin $BRANCH
```

### 5.4 Re-preview (loop back to Phase 4)

```bash
git checkout $TARGET
git reset --hard origin/$TARGET
git merge --no-commit --no-ff origin/$BRANCH
```

Return to Phase 4.3 for another round of testing.

---

## Phase 6: Clear Local Tree

### 6.1 Clear Preview State

```bash
git checkout .
git clean -fd
git reset HEAD
```

### 6.2 Verify Clean State

```bash
git status
```

Should show "nothing to commit, working tree clean".

---

## Phase 7: Merge via PR

### 7.1 Find or Create PR

Use GitHub MCP:
```
mcp__github__list_pull_requests(owner: "linkt-ai", repo: "cmux", head: "linkt-ai:$BRANCH", state: "open")
```

If no PR exists, create one:
```
mcp__github__create_pull_request(
  owner: "linkt-ai",
  repo: "cmux",
  title: "$BRANCH: <title from Linear or commits>",
  head: "$BRANCH",
  base: "$TARGET",
  body: "<PR body with summary>"
)
```

### 7.2 Verify PR is Ready

Check:
- PR is open
- Base is `$TARGET`
- Head is `$BRANCH`
- CI checks pass (use `mcp__github__get_pull_request_status`)

### 7.3 Execute Merge

Use merge commit to preserve history:

```
mcp__github__merge_pull_request(
  owner: "linkt-ai",
  repo: "cmux",
  pull_number: <PR_NUMBER>,
  merge_method: "merge",
  commit_title: "merge: $BRANCH --> $TARGET"
)
```

### 7.4 Pull Merged Changes

```bash
git checkout $TARGET
git pull origin $TARGET
```

---

## Phase 8: Update Linear

### 8.1 Get Linear Issue

If the branch name matches a Linear issue ID pattern (e.g., `MAN-42`):

```
mcp__linear__get_issue(id: "$BRANCH")
```

### 8.2 Update Status

If merging to `main`:
```
mcp__linear__save_issue(id: "$BRANCH", stateId: <"Done" state ID>)
```

If merging to another branch, skip Linear update unless user requests it.

---

## Phase 9: Verification & Summary

### 9.1 Verify Merge

```bash
git log --oneline -5
git status
```

Confirm:
- Latest commit is the merge commit
- Working tree is clean
- Branch is up to date with origin/$TARGET

### 9.2 Display Summary

```markdown
## Merge Complete

**Branch:** $BRANCH
**Target:** $TARGET
**PR:** #<PR_NUMBER> (merged)
**Commit:** <SHA>

### Changes Merged
<summary of files changed>

### Next Steps
- [ ] Verify CI passes on $TARGET
- [ ] Smoke test the build
```

---

## Error Recovery

### Rebase Fails Completely

```bash
git rebase --abort
git checkout $BRANCH
git reset --hard origin/$BRANCH
```

Then investigate the conflict manually.

### PR Merge Fails

If GitHub reports merge conflicts (shouldn't happen after rebase):

```markdown
**Error:** PR cannot be merged. This shouldn't happen after rebasing.

Check if someone pushed to $TARGET after your rebase:
```bash
git fetch origin $TARGET
git log origin/$TARGET --oneline -5
```

If so, re-run the rebase (Phase 3).
```

### Linear Update Fails

Continue with summary but note:
```markdown
**Warning:** Linear status update failed. Manually update the issue.
```

---

## Quick Reference

| Phase | Action |
|-------|--------|
| 1. Determine | Get branch name, fetch latest |
| 2. Push | Ensure feature branch is pushed to origin |
| 3. Rebase | Rebase feature branch on target, resolve conflicts |
| 4. Preview | Merge locally for manual testing |
| 5. Tweaks | Commit any fixes back to feature branch |
| 6. Clear | Clean local tree |
| 7. Merge | Merge PR via GitHub |
| 8. Linear | Update issue status |
| 9. Verify | Confirm merge and display summary |

---

## Why This Flow?

1. **Rebase first**: Ensures clean commit history with feature commits stacked on target
2. **Local preview**: Allows manual testing before committing to the merge
3. **Tweaks to feature branch**: Any fixes during testing become part of the feature, not orphaned commits on target
4. **PR merge**: Maintains GitHub history, triggers CI, enables code review
5. **Merge commit**: Preserves full history and allows `git branch --merged` to work correctly
