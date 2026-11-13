# AI development workflow for Tellus

Use Codex to implement and verify one change at a time. Review the diff and check the behavior in Xcode before merging.

## From idea to pull request

1. Start a chat for the change and keep related fixes in that chat. Select **Worktree** in Codex when the task needs a separate checkout while you work in Xcode.
2. Describe the screen or code path, what should happen, and how you will check it. Attach a screenshot, sample response, or error log when it helps reproduce the issue. Use the prompt below.
3. Follow [Verify Tellus](#verify-tellus) and inspect the diff. For UI changes, open the affected screen in a simulator and compare it with your acceptance criteria. Run `/review` for changes to shared code, parsing, or async loading and check the findings against the diff.
4. Open a pull request and check the SwiftLint and iOS test jobs. The iOS job runs the full scheme and reports app line coverage. [GitHub Actions workflow](../.github/workflows/tests.yml)

## Task prompt

```text
In Tellus, change [screen or code path] so that [expected behavior].

Done when:
- [What I can see or do, and what triggers it]
- [What happens in a relevant edge case]

Follow AGENTS.md. Keep the change scoped and run the relevant checks.
For a UI change, verify the affected screen on an iPhone simulator.
Summarize what changed, what you verified, and any remaining manual checks.
```

For example, a Country Guide bug report could say that switching destinations while a request is in flight must show the new country's advisory, even if the previous request finishes later.

## Verify Tellus

Run the commands below from the repository root. Install an iOS simulator runtime in Xcode and make SwiftLint 0.65.1 available on your `PATH`. [SwiftLint download](../README.md#project-layout)

```sh
git diff --check
(cd iOS && swiftlint lint --strict)
xcodebuild -project iOS/Tellus.xcodeproj -scheme Tellus -showdestinations
```

Use an iPhone or iPad simulator ID from the destination list to run the unit tests with strict concurrency checking.

```sh
xcodebuild -project iOS/Tellus.xcodeproj -scheme Tellus \
  -destination 'platform=iOS Simulator,id=<UUID>' \
  -only-testing:TellusTests SWIFT_STRICT_CONCURRENCY=complete test
```

For changes to UI automation or CI, run **Product → Test** in Xcode with the Tellus scheme to include UI tests. [Tellus development instructions](../AGENTS.md)

Try this on three changes and note where you still have to step in. Add a recurring project rule to `AGENTS.md`. When you repeat a procedure that needs judgment, such as reviewing a new data provider, turn that procedure into a project skill. [Codex skills](https://learn.chatgpt.com/docs/build-skills)
