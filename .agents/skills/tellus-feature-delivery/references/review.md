# Follow CI and review

Share the PR link early. On each pass, read the PR state, current head SHA, available check runs, and Codex review activity. Use the PR's Checks view or equivalent connector data to identify CI for its current revision. GitHub Actions may run on a temporary merge commit. Match Codex review activity to the feature branch head. After a push, recheck both.

## CI and Codex review

Tellus's workflow runs bundled data validation, SwiftLint, and iOS tests with coverage on PRs. Use the actual GitHub check results. Investigate failures using the logs and available result bundles, fix feature regressions on the same branch, and rerun the relevant checks. Describe infrastructure failures separately and retry only when the failure appears recoverable.

The intended repository setting is **Automatic review** on, **Review** set to **All PRs**, and **Trigger** set to **On PR open**. Verify observed review activity before treating that setting as effective. The GitHub bot applies applicable `AGENTS.md` review guidance. Follow [OpenAI's GitHub review guide](https://learn.chatgpt.com/docs/third-party/github) for current trigger behavior.

Look for an acknowledgment or review summary, then for a completed review on the current head. If the bot has acknowledged a request or is already reviewing that commit, let it finish. Recheck for review activity after moving a draft to ready or pushing to a PR configured for review on open. If the bot has not acknowledged, give it time to start and recheck before falling back. If CI is already being followed, use that interval for the recheck. If no review starts, use `@codex review` as a new PR Conversation comment when the user explicitly authorized posting it. Otherwise give the owner the exact comment and the PR link. Read the conversation before retrying an uncertain post. Keep a manual request to one per head unless the preceding run explicitly failed or the owner asks to retry.

While actively following a run, check at reasonable intervals until the checks and review resolve. Keep the owner informed about meaningful changes. If the trigger never acknowledges, access is unavailable, or an external service reports a persistent failure, report the last observable state and the specific action needed to resume. A pending or unavailable review stays pending or unavailable in the report.

## Handle findings and hand off

Read the findings and verify them against the current implementation and acceptance criteria. Fix substantiated in-scope issues and reverify. Bring decisions that change scope, provider, or user-visible behavior back to the owner. Explain findings that no longer apply or need a decision. Keep corrections in the existing PR and avoid unrelated cleanup.

When handing off, give the issue and PR links, the verified check and Codex review state for the current commit, any findings still open, and the specific behavior or evidence the owner should inspect. The owner can then review and merge through GitHub. A completed Codex review is one input to that decision.
