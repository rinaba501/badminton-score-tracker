---
name: ship-pr
description: The repeatable loop for shipping a change to this repo — branch, PR, CI-gated merge, and cleanup. Use whenever asked to implement a fix/feature/issue in badminton-score-tracker and get it merged.
---

# Shipping a PR in this repo

This project has no local Xcode/Swift toolchain available to most agent sessions — CI is the only build/test gate. Follow this loop for every change, small or large.

## 1. Branch

```
git checkout main && git pull origin main
git checkout -B <branch-name>
```

If a PR just merged and you're continuing work, always restart from the fresh `main` — don't stack new commits on old, already-merged history.

## 2. Before implementing anything non-trivial

Per `CLAUDE.md`'s "Reviewing risky changes": use plan mode before writing code for anything beyond a mechanical change (docs, string localization, dead-code removal). This is doubly true for anything touching `CloudSyncManager`/`AppStore` — that's where both real bugs found in this codebase have lived, and CI cannot catch architectural/interaction bugs, only compile errors and the logic that has unit tests.

## 3. Implement, with verification proportional to risk

- Pure logic changes (anything in `PersistenceStore`, `Player`, `BadmintonMatch`, etc.) → add unit tests. This is the only way correctness gets *verified* rather than asserted, since there's no local compiler.
- SwiftUI view changes → check brace/paren balance by hand (`grep -o "{" file | wc -l` vs `}`) as a cheap sanity check before pushing; watch for the `OTHER_SWIFT_FLAGS` long-expression-type-checking warning in CI output.
- Multi-file/architectural changes → run a `/code-review` pass before opening the PR, not just after CI is green.

## 4. Commit, push, open the PR

Follow `.github/PULL_REQUEST_TEMPLATE.md`'s shape (Summary/Changes/Verification/Docs checklist) even if the tool you're using doesn't auto-populate it. Update `SPEC.md`/`CLAUDE.md`/`README.md` per the rules in `CLAUDE.md`'s "Keeping the Docs Up-to-Date" section — in the same commit, not a follow-up.

After opening the PR, enable auto-merge immediately: `gh pr merge <number> --auto --merge --delete-branch`. `main`'s branch protection marks all 7 CI jobs as required status checks, so GitHub won't merge until they're all green — auto-merge doesn't skip the gate, it just removes the need to poll for it. (The repo's `required_approving_review_count: 1` doesn't block this either: you're the sole collaborator and `enforce_admins` is off, so your own PRs bypass the approval requirement.)

## 5. Watch CI, don't guess

Auto-merge handles the "wait and merge" mechanics, but still watch for failures rather than assuming success:

- Check `get_check_runs` for the PR's head SHA.
- On failure, pull the **full** job log (not just the tail) and find the actual `file:line` diagnostic before forming a hypothesis — guessing which expression/file is at fault costs multiple blind CI round-trips (this has happened before in this repo; see `GameView.swift`'s type-check saga in the git history).
- `main` can move while you're working (other sessions/PRs merge concurrently). Auto-merge requires GitHub's own mergeability check to pass; if it reports a conflict, rebase and resolve by understanding both sides' intent, not by picking one blindly. Auto-merge stays armed across a rebase/re-push.
- If a required check fails, auto-merge just sits there — fix the issue, push, and it resumes waiting. No need to re-enable it.

## 6. After merge, clean up locally

Once auto-merge completes the merge (merge commit, not squash/rebase, per CLAUDE.md — `--delete-branch` already removed the remote branch):
```
git checkout main && git pull origin main
git branch -D <branch-name>
```
Don't leave stale local branches.
