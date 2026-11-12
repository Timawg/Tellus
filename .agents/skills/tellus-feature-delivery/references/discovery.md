# Discover and define the feature

Read the relevant Tellus code or README sections before proposing features or asking about behavior that the repository can answer. For idea requests, offer a short list tied to what Tellus already does. For each idea, say what someone could do with it and identify the uncertainty most likely to change its scope. Let the owner choose one.

## Ask questions that affect the build

Ask in small batches, starting with the decisions that would change the first version. Give a recommendation and concrete tradeoffs when the choice is technical. Use a follow-up only when an answer creates a meaningful gap or conflict. Infer reversible defaults from Tellus conventions and state them in the brief.

- **User and entry point.** Who uses this, for what decision, and from which screen, layer, or selection?
- **Success and boundaries.** What should the user see or do? What belongs in this version, and what can wait?
- **Behavior at the edges.** Ask about the cases that actually apply, such as missing or stale data, slow responses, selection changes, disabled layers, map zoom, and accessibility.
- **Data feasibility.** If the feature depends on a provider, establish whether its coverage, update cadence, reuse terms, attribution, and rate limits support the requested experience. Use official sources for claims that determine scope and mark unknowns explicitly.
- **Acceptance.** Turn the owner's answers into observable scenarios. Include the failure case or edge case most likely to affect the experience.

For example, for a flight map feature, ask what should happen after tapping an aircraft, how the display should behave when a route is unavailable, and whether it should stay aligned with the aircraft after a position refresh. These answers can become separate acceptance criteria that someone can check in the simulator.

## Decide when to move forward

The brief is ready when the intended experience, scope boundary, and acceptance criteria are clear enough to implement and verify. Include a data source or a decision about data only when the feature needs one. Keep confirmed facts, product decisions, and open questions distinguishable.

When the owner has authorized delivery and their answers settle the material questions, summarize the brief in commentary and continue to delivery in that turn. Routine implementation choices can be resolved during delivery. If evidence is needed to settle a product choice, do the available read-only research or a local prototype, then bring the concrete options back. If the owner asks to track feasibility separately, create a research issue with a decision to produce and record its outcome before implementing the feature.

When the user wants discovery alone, return the ideas or agreed brief and any material open decision. An existing issue can supply the brief if it already specifies the behavior and acceptance criteria.
