---
name: tellus-feature-delivery
description: Guide a Tellus feature from discovery and product questions through a GitHub issue, coordinated subagents, implementation, simulator verification, and a pull request for Codex and owner review. Use when the user wants feature discovery, delivery of a chosen feature, or resumption of a Tellus feature issue or PR through this workflow.
---

# Deliver a Tellus feature

Work in the `Timawg/Tellus` repository. Follow the applicable `AGENTS.md` for the app and verification. The product owner chooses the behavior and makes the merge decision. The primary agent coordinates delivery and owns the integrated diff, verification, and GitHub handoff.

## Find the next step

- **Ideas or undecided scope.** Read [discovery](references/discovery.md). Help the owner pick a feature and settle behavior. Keep a request for ideas in discovery until the owner chooses an idea and has asked to proceed with delivery.
- **Agreed scope or an issue ready to build.** Read [delivery](references/delivery.md). In a requested delivery run, the owner's answers settling the material questions are the handoff to issue creation and implementation. State the agreed scope briefly and proceed. Ask again only if the user requested a separate decision or new evidence changes the scope materially.
- **Existing PR, CI, or review follow-up.** Read [review](references/review.md). Verify the issue, head branch, latest commit, and PR state on GitHub. Resume from the first unfinished step and keep the same issue and PR. Read discovery or delivery again only if a product or implementation decision needs reopening.

A request to run the full workflow through PR authorizes filing the agreed issue, delegating, pushing its feature branch, and opening its PR. Follow narrower requests as stated. An explicitly requested review comment can be posted on the feature PR if needed. When the user asks to keep work local, retain the brief and verification in the chat.

## Keep one delivery record

Use the feature issue for the agreed behavior and acceptance criteria. Keep the branch and PR tied to that issue. Subagents report to the primary agent, which checks their conclusions against the brief and integrates changes. Use linked issues only for independent deliverables or a feasibility question that needs its own decision. Reuse existing records when resuming.

Carry a full delivery run through a ready PR, CI, and Codex review as far as the available tools and configured trigger allow. Surface the PR link as soon as it is open. End the handoff with what was verified on the current commit, any actionable blockers, and what the owner needs to review or decide. The owner merges after review unless they separately request a merge.
