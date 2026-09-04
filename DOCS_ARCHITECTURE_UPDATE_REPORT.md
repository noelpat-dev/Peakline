# Docs Architecture Update Report

## Summary

Updated the canonical UI style guide to record the landed History redesign and the current Today/Workout typography alignment. The documentation stays token- and semantic-role-based, and no Swift or project files were changed by this documentation pass. The orchestrator already ran a full Debug build against the current source branch and it succeeded; no test suites were run. This report records the evidence and documentation decisions for the docs-only pass.

## Evidence Reviewed

- Initial `git status --short`: existing `StartWorkoutView.swift` typography diff plus untracked user files `AGENTS_SCREENSHOT_TRANSCRIPTION.md` and `MOTION_BLUEPRINT_HANDOVER.md`; all were preserved.
- `git log --oneline -n 10`, current branch `codex/workout-today-typography-consistency`, `git diff --stat`, and `git diff`.
- `git diff main..HEAD` and the landed History commits:
  - `770ebee` — History dashboard, attendance overview, compact month navigation, and session-row layout.
  - `df27f0e` — compact collapsed calendar and prominent horizontal filter chips.
  - `8c293b7` — workout dots and consistent logged-day treatment.
  - `bd82520` — selected but unlogged current day remains unfilled.
  - `65be7d7` — selected day is centred in the collapsed week.
- `GymTracker/Views/History/HistoryView.swift`: current render order, attendance hero, month controls, calendar density, selected-day summary, filters, tappable rows, and semantic theme usage.
- `GymTracker/Views/Shared/AppTheme.swift`: shared `AppTypography`, `AppTheme` colours, and `minimumHitTarget` metrics.
- `GymTracker/Views/Shared/TodayDashboardComponents.swift`, `GymTracker/Views/Today/TodayView.swift`, and the current `StartWorkoutView.swift` diff for the shared `eyebrow`/`heroTitle`/`bodyEmphasis` hierarchy.
- Historical context reports `Docs/investigations/HISTORY_HEADER_WARM_START_PERFORMANCE_REPORT.md` and `Docs/investigations/QUICK_ACTION_PREVIEW_FREEZE_HISTORY_REHAUL_REPORT.md`; current committed source and current diff were treated as authoritative.

## Docs Changed

| File | Change | Reason |
|---|---|---|
| `UI_STYLE_GUIDE.md` | Added shared cross-tab hero typography guidance and expanded the History pattern for native title treatment, attendance hero, compact calendar/month navigation, shared hit targets, workout dots, selected-day behavior, filters, concise session rows, and semantic theme colours. | Codifies the current implemented visual contract without adding History-specific magic values. |
| `DOCS_ARCHITECTURE_UPDATE_REPORT.md` | Captured this pass's evidence and validation in the required audit report. The repository ignores `*_REPORT.md` by default, so this report is intended to be force-added for review. | Keeps the docs-update audit trail aligned with this change. |

## Docs Checked But Not Changed

| File | Reason |
|---|---|
| `README.md` | No product overview or route claim changed. |
| `FEATURE_SUMMARY.md` | Existing History feature summary remains accurate; this pass changes the visual contract only. |
| `ARCHITECTURE.md` | No ownership, navigation, data, or service architecture changed. |
| `KNOWN_ISSUES.md` | No known issue was resolved or introduced by documentation-only work. |
| `PERFORMANCE_ACCEPTANCE_GOAL.md` | No performance contract or validation result changed. |
| `ROADMAP.md` | No roadmap priority changed. |
| `NEXT_TASK.md` | The active handoff remains valid and was not superseded. |
| `NEXT_CODEX_CHAT.md` | No follow-up handoff wording was required. |
| `Docs/AUDIT_INDEX.md` | The existing archive index does not need a new canonical style-guide entry. |
| `Docs/investigations/HISTORY_HEADER_WARM_START_PERFORMANCE_REPORT.md` | Historical implementation evidence; left unchanged. |
| `Docs/investigations/QUICK_ACTION_PREVIEW_FREEZE_HISTORY_REHAUL_REPORT.md` | Historical rehaul report; current source and commits were more specific for this update. |
| `AGENTS_SCREENSHOT_TRANSCRIPTION.md` | Untracked user file; explicitly left untouched. |
| `MOTION_BLUEPRINT_HANDOVER.md` | Untracked user file; explicitly left untouched. |

## Known Issues Updated

None. The existing physical-device, accessibility, and visual-regression risks remain unchanged.

## Next Task / Next Codex Chat Updated

None. `NEXT_TASK.md` and `NEXT_CODEX_CHAT.md` remain unchanged.

## Validation

- `git diff --check`: passed.
- Full Debug build on the current source branch (already run by the orchestrator): passed.
- Test suites: not run.

## Remaining Documentation Risks

- The Today/Workout typography alignment is represented by the current `StartWorkoutView.swift` working-tree diff at the time of this pass; if that implementation diff is later dropped, the corresponding style-guide statement must be revisited.
- The historical investigation reports retain earlier descriptions of the History layout and may be read as chronology rather than the current contract.
- Device-level Dynamic Type, VoiceOver, Reduce Motion, and Reduce Transparency review was not repeated during this docs-only pass.
