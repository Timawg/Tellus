# File, delegate, build, and publish

## Create or resume the GitHub issue

Verify the repository and base branch from the local remote and GitHub. The usual target is `Timawg/Tellus` and `main`. Inspect the working tree and protect any unrelated changes by using a clean worktree when needed.

Use the GitHub connector for issue and PR operations when it can perform them. Otherwise use an authenticated GitHub CLI if available. Use the existing Git remote and credentials for branch pushes. If Git push is unavailable and the authenticated connector can write Git objects, it can publish the verified change by creating a tree and commit from the intended parent, then creating or advancing the feature ref. Verify the resulting tree against the local commit and never overwrite a diverged branch. Repository credentials and app provider credentials are separate. Report the exact failing operation if authentication or permissions block a write, and continue any local work that remains possible.

Search for an existing issue and PR that match the agreed work. Reuse a confirmed match. If an earlier write timed out or its result is unknown, read GitHub before retrying to avoid a duplicate. Create one issue per feature by default. Use a checklist for work within it. If separate issues are warranted, link them and record their dependencies. Add work to a GitHub Project when the owner has identified a board and requested it.

Use this issue structure, omitting sections that do not help the reviewer:

- **Title** describes the capability or problem.
- **Outcome** explains who benefits and what changes in Tellus.
- **Scope** records agreed behavior, constraints, and explicit deferrals.
- **Acceptance criteria** list observable checks and the relevant failure cases.
- **Delivery checklist** tracks research, prototype, implementation, and verification as needed. Record a provider decision or supporting issue here when it affects the work.

Verify that the issue exists and retain its URL. Start the feature branch from the current agreed base, for example `codex/123-aircraft-route`, where `123` is the feature issue number. Reuse an existing branch tied to the issue when resuming. Keep unrelated work out of the branch.

## Delegate independent work

Spawn subagents for useful independent work when running the requested feature workflow. Give each agent the issue brief, its acceptance criteria, owned files or worktree, and the evidence to return. A small change may need one agent to examine edge cases or verification while the primary agent implements it. Delegate implementation as well when a slice is independently buildable.

- **Research** checks feasibility and cites primary sources. For a new or changed provider, use the requirements in `AGENTS.md` and the current `DATA-LICENSE-AUDIT.md` to identify decisions that affect the feature.
- **Prototype** verifies an uncertain interaction or technical approach with a small fixture, spike, or simulator run. Record what it proves and what still needs verification.
- **Implementation** delivers an owned slice through the app's normal entry point. Give concurrent writers separate worktrees or disjoint files. Assign a single writer to shared integration files such as `iOS/Tellus.xcodeproj/project.pbxproj`.
- **Verification** derives checks from acceptance criteria and reports commands, outcomes, and gaps. Coordinate simulator access when agents would contend for the same device or build directory.

Research and unrelated exploration can overlap. When a prototype or provider result determines the implementation, collect it before starting dependent code. The primary agent reviews and integrates each result, resolves conflicts, and owns GitHub writes. If delegation is unavailable, keep moving on the work the primary agent can do and report the constraint.

## Verify and open the PR

Verify the integrated diff against the issue and `AGENTS.md`. Match the checks to the change: use the `Tellus` scheme and an available simulator for app behavior, relevant map zooms and layer combinations for overlays, and `scripts/validate_bundled_data.py` when bundled inputs change. Run the concurrency checks required by `AGENTS.md` when changing Swift, and distinguish existing unrelated diagnostics from regressions. Follow the CI workflow for its current checks. Run `git diff --check`. If a required check cannot run locally, record the specific reason and the CI or manual check needed to cover it.

Commit the feature, push its branch, and verify the GitHub branch points to the intended commit. Open or update one PR against the agreed base. Open it ready for review when the agreed acceptance criteria are met and available local checks have run. Use a draft when the owner requested one or the PR is needed to expose a remaining verification or integration gap. Explain that gap and move the draft to ready when it is resolved.

Lead the PR with the behavior that changed. Include `Closes #123` for the completed feature issue, relevant test results, and any remaining manual checks. Use screenshots or a short reproduction only when they help verify the feature. Update the description if scope or verification changes. Verify the PR number, URL, base, head, and draft status before proceeding to [review](review.md).
