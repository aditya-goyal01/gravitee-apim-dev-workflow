# Branch Creation Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automatically create/switch to `apim-<N>` branch when `/plan-task` is invoked with a ticket number or Jira link, and guard `/implement-task` from running on the wrong branch.

**Architecture:** Two targeted edits to SKILL.md files — one insertion in `plan-task` Phase 1 after ticket resolution, one insertion in `implement-task` Phase 1 after task-state.md is read.

**Tech Stack:** Bash (skills are markdown with embedded shell instructions for Claude to execute), git CLI.

---

### Task 1: Add branch creation to `plan-task` Phase 1

**Files:**
- Modify: `skills/plan-task/SKILL.md` (Phase 1 section, after ticket number is resolved)

**Step 1: Read the current Phase 1 section**

Read `skills/plan-task/SKILL.md` lines 14–30 to confirm current text before editing.

**Step 2: Write the failing test (manual verification)**

Open `skills/plan-task/SKILL.md` and confirm Phase 1 ends after the AskUserQuestion block — no branch creation exists yet.
Expected: no `git checkout` line anywhere in Phase 1.

Run:
```bash
grep -n "git checkout" skills/plan-task/SKILL.md
```
Expected: no output (or only in Phase 7 if present).

**Step 3: Add branch creation after ticket resolution**

In `skills/plan-task/SKILL.md`, find the end of the "Determine ticket number" block (the AskUserQuestion for missing ticket). Immediately after that block (before the "Check for cached description" paragraph), insert:

```markdown
**Branch setup** — immediately after ticket number is known:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/branch-manager.sh" <N>
```
(Replace `<N>` with the resolved ticket number — digits only, e.g. `12338`.) `branch-manager.sh` handles create-or-switch, stash safety, and prints a branch summary. Run this before any caching check or codebase orientation.
```

The insertion point in the file is after line 19 (the AskUserQuestion block closes) and before line 21 (`Check for cached description in task state:`).

**Step 4: Verify insertion**

```bash
grep -n -A2 "Branch setup" skills/plan-task/SKILL.md
```
Expected: shows the new paragraph at the correct location, before "Check for cached description".

**Step 5: Commit**

```bash
git add skills/plan-task/SKILL.md
git commit -m "feat(plan-task): create/switch apim-<N> branch after ticket resolution"
```

---

### Task 2: Add branch guard to `implement-task` Phase 1

**Files:**
- Modify: `skills/implement-task/SKILL.md` (Phase 1 section, after task-state.md is read)

**Step 1: Read the current Phase 1 section**

Read `skills/implement-task/SKILL.md` lines 13–25 to confirm current text before editing.

**Step 2: Verify no guard exists yet**

```bash
grep -n "branch" skills/implement-task/SKILL.md
```
Expected: no branch-check logic in Phase 1.

**Step 3: Add branch guard after task-state.md is loaded**

In `skills/implement-task/SKILL.md`, find the end of Phase 1's extraction block (after the `NEXT_STEP` bullet, before the "If task-state.md does not exist" line). Insert a new branch guard paragraph:

```markdown
**Branch guard** — after reading task-state.md:
Extract the ticket number from the `Ticket: APIM-<N>` line in task-state.md.
Run `git rev-parse --abbrev-ref HEAD` to get the current branch.
If the current branch does NOT contain `<N>` (case-insensitive match):
  Tell Dev: "⚠ Current branch is `<current-branch>` but task is for APIM-<N>. Run `git checkout apim-<N>` before continuing."
  Stop — do not proceed to Phase 2.
```

The insertion point is after line 22 (the `NEXT_STEP` bullet) and before line 24 (`If task-state.md does not exist`).

**Step 4: Verify insertion**

```bash
grep -n -A5 "Branch guard" skills/implement-task/SKILL.md
```
Expected: shows the guard block before the "If task-state.md does not exist" line.

**Step 5: Commit**

```bash
git add skills/implement-task/SKILL.md
git commit -m "feat(implement-task): guard against running on wrong branch"
```

---

### Task 3: Sync updated files to plugin cache and verify

**Files:**
- Read: `.claude-plugin/plugin.json` (confirm version)
- Copy: `skills/plan-task/SKILL.md` → plugin cache
- Copy: `skills/implement-task/SKILL.md` → plugin cache

**Step 1: Copy updated skill files to cache**

```bash
CACHE=~/.claude/plugins/cache/gravitee-dev-workflow/gravitee-dev-workflow/1.0.0
cp skills/plan-task/SKILL.md "$CACHE/skills/plan-task/SKILL.md"
cp skills/implement-task/SKILL.md "$CACHE/skills/implement-task/SKILL.md"
```

**Step 2: Verify cache matches repo**

```bash
CACHE=~/.claude/plugins/cache/gravitee-dev-workflow/gravitee-dev-workflow/1.0.0
diff "$CACHE/skills/plan-task/SKILL.md" skills/plan-task/SKILL.md && echo "OK" || echo "DIFFER"
diff "$CACHE/skills/implement-task/SKILL.md" skills/implement-task/SKILL.md && echo "OK" || echo "DIFFER"
```
Expected: both print `OK`.

**Step 3: Push to remote**

```bash
git push
```
