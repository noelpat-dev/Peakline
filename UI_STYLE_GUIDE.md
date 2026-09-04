# Peakline UI Style Guide

Current file: `UI_STYLE_GUIDE.md`

Status: canonical implemented standard

Taste baseline: 9 August 2026

Implementation baseline: shared system and major app surfaces migrated on 9 August 2026

Platform baseline: iOS 17+, with native adaptation on newer iOS releases

This guide is the active visual and interaction reference for Peakline. The shared theme and major Today, Workout, Splits, History, Settings, Coach, Progress, Nutrition, Sleep, Preview, Logger, completion, and Summary surfaces now use this baseline. New work and any remaining deep-screen polish must preserve it. The guide supersedes earlier design explorations, including older glass-heavy directions; the implemented system and this file are the active visual contract.

Peakline follows current Apple platform principles of hierarchy, harmony, consistency, restrained materials, and accessible interaction without copying Apple's layouts, Activity Rings, brand assets, or visual identity:

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
- [Apple materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)

## Start Here

When design concerns compete, decide in this order:

1. **Usability and accessibility** — can someone understand and operate it quickly, including with accessibility settings enabled?
2. **Hierarchy** — is the current task, metric, or decision unmistakable?
3. **Consistency** — does it reuse Peakline tokens, components, wording, and interaction patterns?
4. **Brand** — does it feel calm, premium, athletic, and motivating?
5. **Decoration** — add polish only after the first four are resolved.

Decoration never earns permission to obscure content, slow an action, reduce contrast, or create another interaction model.

### The 30-Second Screen Recipe

For a normal Peakline screen:

1. Use one native navigation title; do not repeat it as a large content heading.
2. Lead with one dominant task, recommendation, or metric. Not every screen needs a hero.
3. Order supporting content by immediate usefulness, not by data availability.
4. Use the semantic screen background, then quiet content cards, then native or transient chrome. Stop at three visual layers.
5. Give the current decision one obvious primary action; make alternatives visibly secondary.
6. Verify Light, Dark, large Dynamic Type, VoiceOver, Reduce Motion, and Reduce Transparency before calling the screen finished.

## Visual North Star

Peakline is **premium athletic**: calm enough to trust, strong enough to motivate, and quick enough to use between sets.

- **Metric-led:** the useful number, target, status, or next action leads.
- **Dark-first identity:** Dark Mode is the strongest expression of the brand, while Light Mode remains fully designed rather than inverted as an afterthought.
- **Compact, not cramped:** layouts favour scan speed and comfortable reach without squeezing copy or controls.
- **High contrast:** clear type, semantic states, and disciplined accent use beat decorative effects.
- **Purposeful energy:** strong colour and expressive motion are earned by important states such as a genuine PR.
- **Original:** use platform conventions and Peakline's lifting focus; do not imitate Apple Fitness screens.

| Aim for | Avoid |
|---|---|
| One clear visual lead | Grids where every card shouts equally |
| Solid, quiet content surfaces | Glass or blur on every card |
| Strong metrics with short context | Dense analytics without a decision |
| One accent plus semantic states | Rainbow category colour without meaning |
| Native controls with Peakline styling | Custom replacements for familiar iOS behaviour |
| Sparse earned celebration | Ambient glow, constant bounce, or decorative motion |

## Screen Anatomy

Default vertical order:

1. Native navigation title and genuine toolbar actions.
2. Optional hero for the screen's primary decision, status, or metric.
3. Clearly named sections containing related cards or rows.
4. Primary action placed beside the information needed to choose it.
5. Secondary context, history, and explanation below the main task.

Hierarchy rules:

- Use at most one hero card on a screen.
- Use spacing, alignment, typography, and dividers before adding another container.
- Do not stack cards inside cards. A bordered tile may sit inside a hero only when it represents a distinct metric or control and does not create a third content-card shell.
- Keep dashboard headers naturally left-aligned. Do not reserve trailing space for decorative profile or account glyphs.
- Compact period or month controls may centre the current period between symmetric previous/next controls; this does not change the left alignment of dashboard headers.
- Keep the main action near its decision context. Do not strand the only CTA above or far below the information it depends on.
- Prefer a short, scannable vertical story over a dense mosaic of equal-weight widgets.

Core layout values come from `appTheme.metrics`:

| Role | Current baseline |
|---|---:|
| Screen horizontal inset | 16 pt |
| Screen content spacing | 18 pt |
| Section spacing | 10 pt |
| Card spacing | 12 pt |
| Compact / standard / hero radius | 20 / 24 / 30 pt |
| Minimum interactive target | 44 × 44 pt |

The code token remains the numeric source of truth. Do not reproduce these values as local magic numbers.

## Foundations

### Colour and Theme

Use semantic values from `AppTheme`; never hardcode a colour that already has a theme role.

`Black` is a semantic `AppTheme` choice, not a hardcoded black-and-white treatment. Use the shared theme roles—especially `accent`, `accentForeground`, `accentHighlight`, `accentSurface`, and semantic text colours—for accents, attendance rings, workout dots, selected or filter chips, and text in every appearance.

- Backgrounds: primary screen, secondary surface, card, and elevated card.
- Text: primary, secondary, and tertiary.
- Accent: the selected theme colour for selection, focus, and primary actions.
- States: success, warning, hydration, and danger.
- Borders: subtle separation, not a decorative outline around every element.

Rules:

- Let one accent colour carry the screen. Use semantic colours only when they communicate a real state.
- Destructive actions stay system red or semantic danger; never recolour deletion with the selected accent.
- Do not rely on colour alone for readiness, fatigue, progress, danger, or success.
- Avoid decorative gradients. A gradient is acceptable only when it clarifies a meaningful visual state and remains legible in both appearances.
- Check accent foreground contrast for every theme, including Black, in Light and Dark Mode.

### Materials, Surfaces, and Depth

Treat material as hierarchy, not ornament:

- **Content layer:** use solid semantic `AppTheme` backgrounds and `FitnessCard` surfaces for dashboards, rows, metrics, and forms.
- **Functional layer:** let native navigation bars, tab bars, toolbars, menus, popovers, and sheets adopt the appearance supplied by the running iOS version.
- **Transient layer:** standard material is allowed for a focused overlay, floating control, or isolated hero badge when seeing context behind it is useful.
- **Decision popup:** use one backdrop scrim over the unchanged page and an opaque semantic foreground card. Keep headings, guidance, and controls at full opacity from the first visible frame; never stack page fading with the scrim or stagger the foreground through a low-opacity state that resembles disabled content.

Do not imitate a newer system material on older iOS releases. Prefer native components and availability-aware enhancement so iOS 17 remains coherent and newer releases adapt naturally.

- Use `GlassIconBadge` only as an isolated hero or transient emblem, not as the default icon treatment for every row.
- With Reduce Transparency, replace translucent custom surfaces with an opaque semantic surface and retain a visible border.
- Keep shadows soft and subordinate. Scrolling lists should not repeat expensive or prominent shadows row after row.
- Do not place Liquid Glass-style treatment throughout the content layer, combine several translucent shells, animate blur, or add permanent glow.

### Shape and Density

- Continuous rounded rectangles and capsules are the default geometry.
- Use the component's defined radius rather than introducing nearly identical local variants.
- Hero radius signals emphasis; it is not a licence for oversized empty space.
- Compact rows still preserve readable labels and a 44-point interaction target.
- Avoid repeated pills for passive metadata. A pill should communicate selection, status, or a compact action.

### Typography, Copy, and Measurements

Use the system font through `AppTypography` and built-in text styles. Rounded, bold, or monospaced numeric styles provide Peakline's athletic character; body copy stays quiet and highly legible.

| Content | Preferred treatment |
|---|---|
| Native screen title | System navigation title |
| Hero metric | `heroMetric` or `heroTitle`, tested at large text sizes |
| Card title | `cardTitle` or `compactCardTitle` |
| Body and reason | `body` or `bodyEmphasis` |
| Metadata and helper copy | `metadata` or `metadataEmphasis` |
| Live workout number | `workoutNumber` or `workoutLargeNumber` |

Use the shared `AppTypography` semantic roles across tabs rather than local font declarations. Recommendation heroes use one precise hierarchy: an uppercase context label in `eyebrow`, the recommended split name in `heroTitle`, supporting context or the reason in `body` or `bodyEmphasis`, and compact mode, confidence, or other metadata in `metadataEmphasis`. Today and Workout follow this hierarchy. Do not use `metadataEmphasis` as the eyebrow or `screenTitle` as the hero title. Keep one native inline navigation title, centred by the system, and do not repeat it as a custom content heading.

Copy rules:

- Use one native screen title. Never repeat it as both navigation title and content header.
- Lead with the outcome or action; explain only what changes the decision.
- Prefer short sentence-case labels over title-heavy interfaces.
- Use `PeaklineText` for plural counts, ranges, metadata joining, set/rep summaries, and load notation.
- Use a multiplication sign for load and reps (`60 kg × 8`), a middle dot for compact metadata, and a space before units (`350 mL`, `100 g`).
- Keep `mL` capitalisation consistent. Avoid `100ml`, `60kg x 8`, `1 sets`, unexplained abbreviations, and false coaching certainty.
- Long labels and values may wrap or reflow; do not solve ordinary localisation or Dynamic Type pressure with aggressive scaling.

### Icons and Exercise Imagery

- Prefer familiar SF Symbols for system actions and exact exercise artwork where the asset pipeline provides it.
- An icon must identify an action, state, or subject. Remove it if it only fills space.
- Use one outer border for exercise icon tiles with a smaller background-free glyph centred inside; never add a second nested tile border.
- Icon-only controls require a label, an appropriate hint where needed, and a 44-point hit area even when the visible glyph is smaller.
- Do not mix several unrelated symbol weights or container shapes in one control group.

## Component Choices

Choose the smallest existing primitive that expresses the hierarchy.

| Need | Use | Do not use it for |
|---|---|---|
| Screen scaffold | `FitnessScreen`; `FitnessScreenHeader` only when a content header is genuinely required | Duplicating a native navigation title |
| Dominant decision or metric | `FitnessCard(style: .hero)` | More than one hero on the same screen |
| Normal grouped content | `FitnessCard(style: .standard)` | Wrapping every individual row |
| Dense repeated content | `FitnessCard(style: .compact)` | Shrinking tap targets or copy below comfort |
| Comparable statistic | `MetricTile` | Passive decoration or a single isolated label |
| Repeated section | `DashboardSection` | Adding another card shell around its children |
| Standard row/action icon | `FitnessIconBadge` | Pure decoration |
| Isolated material emblem | `GlassIconBadge` | Repeated list or dashboard-row icons |
| Main action | `PrimaryFitnessButtonStyle` | Multiple equal-priority actions in one decision |
| Alternative action | `SecondaryFitnessButtonStyle` | Destructive actions |
| Quiet utility action | `NeutralFitnessButtonStyle` | Hiding the main CTA |
| Tappable card feedback | `PressableCardButtonStyle` or `PeaklineButtonPressStyle` | Adding a second gesture to the same action |
| Weight, reps, or bounded values | `StepperValueControl` | Slow animated value entry or tiny controls |
| Scroll-view deletion | `SwipeRevealRow` | Rows already using native `List` swipe actions |
| Exercise identity | `ExerciseIconView` or `ExerciseIconTile` | A nested decorative icon tile |

### Buttons, Chips, Menus, and Sheets

- A decision context has one filled primary action. Secondary and neutral actions must look quieter.
- Use chips for modes, filters, and mutually exclusive compact choices. Do not use them as passive labels when plain metadata is clearer.
- Row-level secondary actions belong in an anchored `Menu` attached to the row that owns them.
- Use native sheets with normal detents and drag indicators. Present the usable shell immediately and keep the primary dismissal or completion action available.
- Informational action cards place explanation first and the embedded CTA after the final relevant information.
- Fully tappable cards, menus, steppers, filters, date arrows, Undo, and reorder handles retain their specialised layouts rather than being forced into the informational-card pattern.

Deletion rules:

- Do not show permanent red trash controls on ordinary dashboard rows.
- Prefer native trailing swipe actions for `List` rows.
- For card rows in a `ScrollView`, use `SwipeRevealRow`. Own one active-row ID at page level so opening a row closes its sibling with one settled animation.
- Do not combine swipe deletion with a redundant row context menu. Keep an accessibility delete action available.
- Confirm costly deletion such as a workout, sleep session, split template, or saved food.

Keyboard rules:

- Input screens dismiss the keyboard interactively while scrolling.
- Text keyboards may use native Done or Next when focus can advance.
- Do not add a custom keyboard toolbar or a page-wide tap recogniser that competes with buttons, scrolling, sheets, or accessibility gestures.

## Interaction and Motion

The experience contract is:

```text
immediate acknowledgement -> one state mutation -> native presentation -> stable useful first frame
```

- Show press feedback within about 100 ms.
- A tap produces one route mutation. Use `NavigationInteraction` for programmatic routes, reject duplicate requests, and clear the request when the destination's first stable frame appears.
- Mutate route state immediately and let native navigation or sheet presentation carry the transition; do not wrap route changes in custom `withAnimation`.
- Prepared Coach and Workout Preview routes show their real actionable value-backed hero first. Do not replace known content with a fake shell, spinner, or delayed progress label.
- Deep scanners, charts, and unbounded history may hydrate after stable navigation chrome and the primary task are available.
- Root `TabView` selection is immediate and preserves each tab's navigation state. Never add a whole-screen fade, scale, slide, or broad animation transaction.

Implementation and latency ownership live in [ARCHITECTURE.md](ARCHITECTURE.md) and [PERFORMANCE_ACCEPTANCE_GOAL.md](PERFORMANCE_ACCEPTANCE_GOAL.md). This guide owns what the interaction must feel like.

### Motion Roles

Use `AppMotion`; do not create local curves for an existing role.

- `snappy` — response `0.32`, damping `0.85` for presses, chips, steppers, reorder, and swipes.
- `smooth` — response `0.42`, damping `0.92` for cards, sheet content, and committed row collapse.
- `expressive` — response `0.55`, damping `0.75` for meaningful hero metrics and genuine PR presentation only.
- Durations use micro up to 120 ms, standard 220–280 ms, and expressive 350–500 ms. The 150 ms numeric roll and 180 ms set checkmark are explicit bounded interaction timings.
- Cascades use 35 ms per item for the first eight items; everything after eight enters as one group.

| Behaviour | Roles | Expected feel |
|---|---|---|
| Touch acknowledgement | `tapDown`, `tapRelease`, `cardPress`, `buttonPress`, `primaryAction`, `secondaryAction` | Immediate, tiny scale or opacity, no bounce |
| Selection | `chipSelect`, `tabSelect`, `modeChange`, `ratingSelect`, `checkInSelect` | Animate only the control whose state changed |
| Local structure | `cardAppear`, `cardDisappear`, `rowInsert`, `rowRemove`, `rowReorder`, `swipeSnap` | Small local movement; never animate a refreshed full list |
| Presentation | `sheetPresent`, `sheetDismiss`, `modalPresent`, `modalDismiss`, `routePush`, `routePop`, `loadingReveal` | Native-feeling, opacity-led, and non-blocking |
| Feedback | `metricChange`, `successConfirm`, `destructiveConfirm`, `celebration` | Brief confirmation proportional to importance |

Rules:

- Card and button feedback uses roughly `0.985` scale with subtle opacity, 80 ms press-down, and 120 ms release. Reduce Motion keeps opacity only.
- Chips, filters, ratings, and check-ins may use one restrained selection haptic.
- Live workout logging stays quiet: no slow steppers, whole-card transitions for weight/reps edits, or haptics for every tiny update.
- Completing a set mutates and saves first, then draws one checkmark, flashes one local accent surface, and presents rest timing. The final ten seconds use warning colour plus opacity only; Rest Complete crossfades without an alarm or scale pulse.
- Meaningful readiness, attendance, and Progress metrics animate only from a valid previous value. Their visual interpolation is hidden from accessibility while the final value remains exposed.
- Native sheets may reveal inner content once after the shared 70 ms content delay; dismissal and primary actions remain available immediately.
- Success, deletion, and completion feedback never delay logging, saving, dismissal, Done, or navigation.
- Reduce Motion removes spatial movement, scale, peripheral sparks, and bounce; retain opacity or instant state change.

Earned celebration:

- A genuine newly detected workout PR is the only flashy Logger completion.
- Use exactly 12 deterministic gold/accent sparks, two expanding rings, and one spring-driven trophy pop over roughly 0.75–0.9 seconds.
- The burst plays once around the trophy. It ignores hit testing and accessibility and never blocks Done or Summary.
- Ordinary completions do not use the burst.
- With Reduce Motion, omit sparks, rings, and trophy movement while retaining the static gold trophy, PR copy, success haptic, and immediately usable Done action.
- Do not add full-screen confetti, loops, timers, heavy blur, or ambient celebration.

Startup motion:

- Show only the centred Peakline wordmark on the semantic primary background.
- Use the existing restrained one-shot ascending-letter sequence with a small rise, tiny scale, and no bounce.
- Readiness always wins and begins the 280 ms opacity-led exit immediately. Five seconds is a ceiling, never an artificial minimum.
- Reduce Motion keeps the wordmark static and removes exit scale.
- Do not add a logo, blur, gradient, sound, haptic, repeating animation, or animated tracking.

Banned motion patterns:

- Broad root `.animation` modifiers.
- Animating long lists during every render, query, or filter refresh.
- Heavy blur, shadow, or material animation in scrolling hot paths.
- Delaying navigation, save, route mutation, dismissal, or user input for animation.
- Using motion or a loading shell to hide slow data retrieval.

## Accessibility and Adaptation

Accessibility is part of the visual standard, not a later QA pass.

- **Light and Dark:** verify hierarchy, contrast, accent foregrounds, borders, materials, shadows, and semantic states in both.
- **Dynamic Type:** prefer text styles, allow copy to wrap, and let horizontal layouts stack or use `ViewThatFits` at accessibility sizes.
- **VoiceOver:** label icon-only controls, keep reading order aligned with visual order, combine elements only when the result remains meaningful, and announce value plus unit.
- **Touch:** keep every interaction at least 44 × 44 points and give tired hands forgiving spacing during a workout.
- **Colour:** pair state colour with text, iconography, shape, or value.
- **Reduce Motion:** remove nonessential movement and preserve the state change.
- **Reduce Transparency:** replace custom translucent surfaces with opaque semantic backgrounds and retain separation.
- **Increase Contrast:** ensure controls, borders, and selected states remain distinguishable without depending on subtle opacity alone.
- **Gestures:** core actions need a visible or accessibility alternative; a swipe or drag cannot be the only way to complete an essential task.
- **Small screens:** smoke test the smallest supported iPhone for clipped rows, crowded controls, horizontal scrolling, and hidden actions.

## Feature Patterns

These patterns define composition and behaviour. Architecture and performance detail remains in the linked canonical documents.

- **Today:** lead with current status and the next useful action, followed by compact recovery, nutrition, sleep, and hydration context.
- **Quick Actions:** route immediately to a usable value-backed screen. Start Workout must expose Preview navigation and start controls without waiting for unrelated data.
- **Workout Preview:** show split, mode, Coach Brief, Start, one eager full-detail exercise order, last best, targets, and adjustments from one pinned prepared generation. Use handle-only reordering with row geometry ready before the first drag. Lift only the active row, let it follow vertical finger movement, mark the exact landing edge with a thin accent insertion cue, and apply the order once on release with one damped settle. Avoid hard full-row target outlines, continuously reshuffling siblings during the drag, or clipping the lifted row. Under Reduce Motion, keep the source row spatially still while retaining the static insertion cue and immediate reorder; always preserve Move Up and Move Down accessibility actions. Keep row actions in the tapped row's anchored menu. Do not add bootstrap sleeps, temporary shells, live queries, or whole-screen replacement animation. Preserve existing identifiers including `quick-action-workout`, `workout-recommended-preview`, `workout-preview-hydrated-content`, `workout-preview-basic-exercise-rows`, `workout-preview-guidance-chips`, `workout-preview-reorder-handle`, and `workout-preview-start`.
- **Check-In:** present the prepared draft from Today's page-level native sheet, use one large detent and native drag indicator, and animate only the changed rating. Do not duplicate Check-In in Coach or Weekly Review.
- **Live Logger:** prioritise timer, current exercise, weight/reps controls, complete-set action, rest timer, and finish. While a rest timer is active, show its countdown, +30s, and Skip controls once; keep the manual duration presets only in the dedicated Rest Timer section. Show Warm-up or Logged when meaningful; do not label an ordinary incomplete set Draft. Continue overlays use the session's nonrepeating motivational rotation. The rating popup uses a single scrim and a fully opaque semantic card with full-strength text and enabled rating controls on its first visible frame. Before rating a session recorded at four hours or more, present the measured duration with Edit Duration, Use Recorded Time, and Cancel paths. Final completion follows the PR-only celebration rule.
- **Session Summary:** lead with completed work, duration, rating, genuine improvements, and one practical next suggestion.
- **Splits:** show the active programme, readable adaptive day chips, explicit Edit Rotation, training-day cards, last-trained state, target rows, and progression badges. Keep per-exercise template notes out of Split Edit; preserve workout-level and logger/history note surfaces.
- **Coach:** lead with the real snapshot-backed Today's Call, its short reason or status, its prepared first explanation, and an immediately usable Preview action. Keep the split name as the hero headline; carry provisional readiness in one `Provisional` badge rather than repeating the label or appending status to the H1. When readiness evidence is sparse, keep the numeric estimate, show “X of 5 signals included”, state that missing signals do not lower the score, and render unavailable factors as `Not included`; included factors show their signed point contribution. Do not let a provisional category colour or message imply a Push or Recovery prescription. Deeper supporting analytics may follow; avoid a wall of equal-weight insight cards or false precision.
- **History:** use one native inline title, then a compact month-navigation row. Lead with the current month's filter-independent attendance hero: month title and count, attendance ring, goal action, duration, and previous-month comparison. Keep the ring beside its supporting metrics at normal widths and stack the same group only when constrained; use a clear Set Goal state when no profile exists. Keep the calendar as compact orientation rather than the dominant dashboard: start with a selected week centred on the selected day, allow full-month expansion, and keep each day at the shared 44 × 44 pt minimum hit target. Use compact weekday labels and a small accent workout dot; a selected unlogged current day remains unfilled, while a logged selected day may use accent fill and a contrasting dot. Put a compact selected-day summary below the calendar; it is supporting detail, not a second hero. Keep filters as compact horizontally scrolling semantic chips, with detailed choices in the filter sheet and Clear shown only when active. Render recent sessions as concise, fully tappable rows with split/date, exercise/set/duration metadata, optional rating, and a chevron. Use `AppTheme` semantic colours for attendance, selection, dots, text, surfaces, and borders.
- **Settings:** keep Profile compact and adaptive with `ViewThatFits`, and expose only truthful preferences. Use the user-facing names Workout Tools and Appearance; do not restore Gym Utilities or label Appearance as Themes.
- **Nutrition and Hydration:** use compact reviewable summaries, honest permission or unavailable states, and clear editing boundaries. Nutrition provides previous/next day controls, a native date picker, optional fibre progress, and visibly read-only past days.
- **Sleep:** design explicitly for no-data, populated, and active-session states. No-data shows one compact explanation and an immediately reachable Start Sleep Mode action, with Add Sleep and Log Nap secondary. Populated leads with last-night duration and restrained source/quality/confidence context, then one conservative readiness support section, a bounded seven-night trend, and flat recent rows; hide empty trends and stages, and never turn provisional readiness into a Push or Recovery prescription. Active Sleep Mode makes elapsed or estimated sleep and Confirm Wake Time dominant. Use adaptive stacks and native menu/checkmark selection for long source labels, keep quality optional, and confirm every running-timer, discard, and delete path.

## Worked Decisions

### Dashboard Hero

Use one `FitnessCard(style: .hero)` containing the current decision, its strongest metric or status, one short reason, and one primary action. Follow it with quieter `DashboardSection` content. Do not build a top grid of equally elevated cards or add glass to make the hero stand out.

### Live Logger Control

Use `StepperValueControl` or the existing logging control with a 44-point target, monospaced workout numbers, immediate press feedback, and no whole-card animation. Completing a set may use a short success confirmation; editing one value should not shake, glow, or reflow the screen.

### Workout Completion Overlay

Treat the overlay as a transient layer over the frozen completed Logger. Done is available on the first frame. An ordinary completion stays restrained. A completion backed by prepared genuine PR records may use the single focused trophy burst; its decoration is noninteractive, hidden from accessibility, one-shot, and absent under Reduce Motion.

## Do and Avoid

| Do | Avoid |
|---|---|
| Use one hero and clear section order | Promote every card to hero styling |
| Use solid cards beneath native chrome | Recreate Liquid Glass across scrolling content |
| Write `60 kg × 8 · 3 sets` | Write `60kg x 8, 3 set` |
| Put one filled CTA beside its context | Scatter several equal filled buttons |
| Use an anchored row menu | Present a detached screen-level action dialog |
| Reveal prepared real content immediately | Insert a fake loading shell for known data |
| Celebrate an earned PR once | Add confetti or ambient looping motion |

## Final UI Review Checklist

Before merging a new or polished screen, confirm:

- [ ] The screen's purpose is understandable within a few seconds.
- [ ] One task, decision, or metric leads; there is at most one hero.
- [ ] One primary action is obvious and alternatives are quieter.
- [ ] The screen uses no more than three visual layers and contains no nested card stack.
- [ ] Colours, spacing, radii, typography, and motion come from shared tokens or primitives.
- [ ] Content cards are solid semantic surfaces; material is functional, isolated, or transient.
- [ ] Copy is short, modest, correctly pluralised, and uses standard unit formatting.
- [ ] Tap targets, menus, sheets, swipe actions, keyboard behaviour, and navigation use established patterns.
- [ ] Light, Dark, small-screen, and large Dynamic Type layouts remain clear.
- [ ] VoiceOver labels and order communicate the same hierarchy as the visual layout.
- [ ] Reduce Motion and Reduce Transparency retain meaning, contrast, and immediate actions.
- [ ] No animation, query, or hydration work blocks a tap, route, save, dismissal, or logging control.
- [ ] The result feels premium athletic and recognisably Peakline, not like an Apple Fitness copy or a generic analytics dashboard.

## Implementation References

Prefer and extend shared primitives in `GymTracker/Views/Shared/`:

```text
AppTheme.swift
AppMotion.swift
FitnessCard.swift
FitnessScreenHeader.swift
MetricTile.swift
TodayDashboardComponents.swift
CoachBadgeView.swift
ExerciseTargetRow.swift
ExerciseIconView.swift
ExerciseIconTile.swift
GlassIconBadge.swift
LiveWorkoutHeader.swift
ProgressArcView.swift
SplitCardView.swift
StepperValueControl.swift
WorkoutModePicker.swift
```

Before adding a foundational visual primitive, confirm that an existing component cannot express the need with a small extension. A genuinely new primitive must use semantic theme tokens, support relevant accessibility settings, preserve performance-sensitive interactions, and be added to this guide.
