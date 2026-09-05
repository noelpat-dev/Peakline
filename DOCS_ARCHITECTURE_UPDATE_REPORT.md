# Docs Architecture Update Report

## Summary

Integrated the Workout Guide catalogue and artwork into Peakline in four increments: themed asset import, exact exercise mapping, native exercise information pages, and focused integration validation. The user-requested Luna agents owned artwork (xhigh), mapping (xhigh), and licensing (medium); the root agent integrated the UI and performed source/build validation. No separate licensing review was performed.

## Evidence Reviewed

- Initial working-tree status and recent Git history. Existing Coach, Readiness, Workout, architecture, project membership, and test changes were preserved.
- Scoped source and project diffs, new catalogue/guide files, the imported asset catalogue, and the licensing agent's completed files.
- Pinned upstream commit `aac599224bb9780305239607ef98540b7e0ce389`: 302 catalogue entries and 906 SVG frames.
- Importer checks: all frames are 512 × 512 monochrome vector artwork with template-rendering metadata; source SVG bytes are unchanged.
- Final exact/explicit-alias coverage: 18 of 35 seeded exercises. Seated T-bar rows and close-grip weighted pull-ups are not treated as interchangeable with less specific source poses.

## Docs Changed

| File | Change | Reason |
|---|---|---|
| `README.md` | Added the offline Exercise Guide. | Make the new capability discoverable. |
| `FEATURE_SUMMARY.md` | Described gallery, details, entry routes, theme rendering, and source boundaries. | Reflect current implemented behaviour. |
| `ARCHITECTURE.md` | Updated the icon pipeline and guide navigation ownership. | Record the bundled manifest, typed keys, retained compatibility, and refresh procedure. |
| `UI_STYLE_GUIDE.md` | Recorded template tint, detailed-pose sizing, and manual pose selection. | Preserve all existing themes and immediate interaction. |
| `KNOWN_ISSUES.md` | Recorded source coverage and the standing-calf-raise equipment collision. | Prevent unsupported illustration matches and overstatement of source content. |
| `THIRD_PARTY_NOTICES.md` | Added artwork/source licensing notices. | Completed by the requested licensing agent. |

## Docs Checked But Not Changed

| File | Reason |
|---|---|
| `ROADMAP.md` | No unrelated roadmap work was expanded. |
| `PERFORMANCE_ACCEPTANCE_GOAL.md` | No timing thresholds changed; this task does not claim full performance acceptance. |
| `NEXT_TASK.md`, `NEXT_CODEX_CHAT.md`, `Docs/AUDIT_INDEX.md` | No planning or historical-audit rewrite was needed for this implementation. |

## Known Issues Updated

The catalogue includes 302 exercises, but 17 starter exercises retain existing art because no safe exact source match was established. Each saved exercise still has an information page using its local metadata. Catalogue browsing is read-only and does not seed 302 records into SwiftData. The source has no written technique instructions.

## Next Task / Next Codex Chat Updated

Neither file was changed. Additional artwork coverage requires matching source poses for the specialised movements, rather than broad substring substitutions.

## Validation

- Baseline lower-split icon regression: 1 test passed.
- Frozen integration build and focused catalogue/mapping/split checks: 6 tests passed, including successful loading of all 906 bundled image assets.
- An earlier build overlapped mapper edits; its UI run lost the app connection during startup and was stopped. Results from that attempt are not claimed as passing validation.
- Exercise Guide search, metadata, pose selection, and empty results: passed on iPhone 17 in blue/dark appearance.
- Saved exercise editor -> information -> editor: passed with the largest accessibility text category in black/light appearance.
- Preview -> guide -> Preview -> Logger -> guide -> Logger: passed in Fitness Green/dark appearance. This also retains the selected exercise when starting after reordering.
- Three focused UI tests passed across two final invocations. Earlier harness attempts targeted the existing profile menu and a row identifier overridden by its parent; the tests were corrected to use Workout's direct Library entry and the existing exercise action label. No unrelated profile-menu or Preview navigation changes were made.
- Screenshots of the guide, dark detail, and large-text light detail were inspected and saved under `/Users/noelpatricks/.codex/visualizations/2026/09/05/01a0719e-a396-7032-86c9-04e4925041d7/`.
- Final `git diff --check`: passed. No full suite or performance acceptance verifier was run.

## Remaining Documentation Risks

Physical-device visual validation and the full performance acceptance verifier are outside the checks run by this task. The source SVG payload is approximately 26 MB; the compiled asset catalogue is larger. No database schema or workout persistence changes were introduced.

## Follow-up: Unified Exercise Editor and Complete Artwork Replacement

The user's follow-up explicitly permits representative images for related movements, superseding the earlier exact-only visual policy. A Luna xhigh agent replaced all 47 legacy exercise/category key mappings with Workout Guide assets; all 35 starter exercises now resolve new artwork. Raw icon keys remain compatible. Exact catalogue metadata remains separate, so a representative illustration never changes the saved exercise's identity or equipment.

Exercise Library now opens the combined editor directly: illustration, bounded playback/manual pose selection, canonical exercise fields, and expandable coach-specific preferences. The toolbar information action opens credits only. `CoachExerciseMetadataService.editorDraft` reconciles shared muscles/movement from the exercise while preserving priority, role, context and notes; no-op updates retain timestamps. Reconciliation occurs on load and exit, not during image playback or note typing.

Follow-up verification:

- Focused Debug build passed on iPhone 17.
- All eight catalogue/artwork tests, two metadata service checks, and the existing lower/upper split regression passed. The first run exposed an `Upper A` categorisation gap, corrected and rerun.
- Existing coach-note save/reopen UI test passed with the consolidated preferences disclosure.
- Combined editor inline poses, largest accessibility text layout, credits navigation and return UI test passed. The test helper was adjusted to avoid tapping a scrolled control underneath navigation chrome and to tap the fixed credits action directly.
- Final large-text editor screenshot inspected; new representative artwork was also observed in the library. Existing user work remains preserved.
- `git diff --check` passed. No full performance verifier or physical-device validation was run for this follow-up.
