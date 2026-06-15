# UI Style Guide

Current file: `UI_STYLE_GUIDE.md`

## Direction

Peakline should feel dark-first, metric-led, compact, and motivating. It can be inspired by the broad feel of Apple Fitness and Workout apps, but it must not copy Apple's exact Activity Rings, screen layouts, icons, colors, or branded identity.

The active design language is a lifting-focused system: clear cards, strong metrics, restrained glass, exact exercise imagery where available, and fast controls that work in the gym.

## Principles

- Dark-first: dark mode should feel like the primary product identity.
- Metrics first: lead with the number, target, split, duration, or action.
- Fast gym use: large tap targets, short copy, minimal forms, no friction-heavy pre-workout questions.
- Explainable coaching: every recommendation needs a short reason.
- Original visual identity: use platform conventions, not copied Apple assets or layouts.
- Consistency over decoration: shared cards, chips, buttons, motion, and theme tokens should carry the interface.

## Theme Tokens

Use semantic theme values from `AppTheme` rather than hardcoded colors.

Important token groups:

- Backgrounds: primary screen, secondary surface, card surface.
- Borders: subtle card and divider strokes.
- Text: primary, secondary, muted.
- Accent: selected theme color.
- States: success, warning, danger.
- Materials: glass and elevated surfaces where appropriate.

Destructive actions must stay system red or semantic danger. Do not tint delete actions with the selected accent.

## Cards, Buttons, And Chips

- Use `FitnessCard` for primary dashboard cards, compact rows, and repeated content.
- Use shared metrics from `appTheme.metrics` for radius, spacing, icon size, button height, and chip padding.
- Avoid stacking cards inside cards.
- Use `DashboardSection` for repeated screen sections.
- Use filled primary buttons for the main action on a screen.
- Use chips for mode/filter/selection states.
- Use native or shared swipe-reveal patterns for delete actions.

Delete behavior:

- Do not show permanent red trash controls on normal dashboard rows.
- Prefer native trailing swipe actions for `List` rows.
- For card rows in `ScrollView`, slide the row left and reveal a red circular delete action.
- Use confirmation dialogs for costly deletes such as workouts, sleep sessions, split templates, or saved foods.

## Typography

Use system fonts and Dynamic Type where practical.

- Screen title: bold title or shared screen header.
- Hero metric: large rounded bold type where space allows.
- Card title: headline or title3 bold.
- Body details: subheadline.
- Reasons, labels, and helper text: footnote or caption.

Text should remain readable in light and dark mode and should not rely on color alone for meaning.

## Motion

Motion should communicate state, not decoration. Use shared `AppMotion` roles so interaction feedback stays immediate, scoped, and Reduce Motion-aware.

Motion roles:

- `tapDown`, `tapRelease`, `cardPress`, and `buttonPress`: acknowledge touch within about 100ms with tiny scale or opacity only.
- `chipSelect`, `modeChange`, `ratingSelect`, and `checkInSelect`: animate only the selected control, not the whole screen or list.
- `rowInsert`, `rowRemove`, and `rowReorder`: use only for small local Preview/order changes, never for full-list refreshes.
- `sheetPresent`, `sheetDismiss`, `modalPresent`, and `modalDismiss`: keep native-feeling presentation; do not wait for heavy data before showing the shell.
- `routePush` and `routePop`: mutate route state immediately and let native navigation carry the transition.
- `loadingReveal`: show the route or shell first, then reveal hydrated coach/target data progressively.
- `metricChange`: reserve numeric transitions for small metric values that do not relayout their container.
- `successConfirm`, `destructiveConfirm`, and `celebration`: use for completed sets, saves, deletes, and workout completion; never block logging or dismissal.

Rules:

- Prefer `PressableCardButtonStyle`, `PeaklineButtonPressStyle`, shared fitness button styles, and `AppMotion` helpers over local one-off animation curves.
- Card and button press feedback should use scale around `0.985` plus subtle opacity; do not bounce large containers.
- Chips, filters, ratings, and check-in controls can use haptics sparingly on selection.
- Live workout logging stays restrained: no slow steppers, no full-card transitions for weight/reps edits, and no noisy haptics for every tiny update.
- Loading follows `tap -> feedback -> route shell -> content -> progressive hydration`.
- Reduce Motion removes movement and keeps opacity or instant state changes.

Banned patterns:

- Broad root `.animation` modifiers.
- Animating long lists on every render or filter refresh.
- Heavy blur, shadow, or material animation inside scrolling hot paths.
- Delaying navigation, save, dismissal, or route mutation for an animation.
- Using animation to hide slow data retrieval.

## Feature Patterns

- Today: quick status, next action, and compact recovery/nutrition/sleep context.
- Workout Preview: split, mode, exercise order, last best, target, remove/reorder, and start.
- Live Logger: timer, current exercise, set controls, rest timer, quick complete, finish.
- Session Summary: completed work, duration, rating, improvements, next suggestion.
- Splits: training-day cards, last trained state, target rows, progression badges.
- Coach: recommendation, action, reason, confidence/status; avoid walls of analytics.
- Nutrition/Sleep/Hydration: reviewable local data, compact summaries, and clear permission/unavailable states.

## Accessibility

- Keep contrast high in dark mode.
- Support Dynamic Type where practical.
- Use labels for icon-only controls.
- Do not communicate fatigue, danger, success, or progress by color alone.
- Keep workout controls large enough for tired hands during a session.
- Smoke test smaller iPhone layouts for clipped rows or crowded controls.

## Implementation Notes

Prefer shared primitives in `GymTracker/Views/Shared/`:

```text
AppTheme.swift
AppMotion.swift
FitnessCard.swift
FitnessScreenHeader.swift
MetricTile.swift
MetricPill.swift
CoachBadgeView.swift
ExerciseTargetRow.swift
ExerciseIconView.swift
ExerciseIconTile.swift
GlassCard.swift
GlassIconBadge.swift
ProgressArcView.swift
SplitCardView.swift
StepperValueControl.swift
WorkoutModePicker.swift
```

If a feature needs a new visual pattern, first check whether it can be expressed as a small extension of an existing shared component.
