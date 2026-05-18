# GymTracker UI Style Guide

## Purpose

This file defines the visual direction for the GymTracker redesign. The goal is to create an interface that feels inspired by Apple's Fitness and Workout apps in broad design principles: dark, clean, card-based, high-contrast, metric-led, and motivating.

Do not copy Apple's exact Activity Rings, Fitness screens, icons, or branded visual identity. GymTracker needs its own lifting-focused design language.

## Design Principles

1. **Dark-first**
   - Workout and Coach screens should feel best in dark mode.
   - Light mode can exist, but the product identity should be strongest in dark mode.

2. **Metrics first**
   - Show the important number clearly: target weight, reps, duration, sets, PR, or split.
   - Use supporting text only after the key metric is visible.

3. **Cards over tables**
   - Use rounded cards for dashboard sections.
   - Avoid dense spreadsheet-like layouts except in history detail or set editing.

4. **Fast gym use**
   - Buttons must be large enough to tap during a workout.
   - Avoid forms during active sessions.
   - Prefer steppers, chips, and one-tap actions.

5. **Explainable coaching**
   - Every suggestion should include a short reason.
   - No mysterious score without explanation.

6. **Original, not a clone**
   - Use Apple's platform conventions, not Apple's exact branding.
   - GymTracker can use circular progress visuals, but they should not be exact Activity Rings.

## Colour Direction

### Core Palette

Use semantic colours rather than hardcoding everywhere.

Suggested semantic tokens:

```swift
AppColors.backgroundPrimary
AppColors.backgroundSecondary
AppColors.cardBackground
AppColors.cardBorder
AppColors.primaryAccent
AppColors.secondaryAccent
AppColors.success
AppColors.warning
AppColors.danger
AppColors.mutedText
```

### Default Theme

Keep Workout Green as the primary identity colour:

```text
Workout Green: #7CFC00
```

Suggested supporting colours:

```text
Background: near-black / system black
Card: dark gray with subtle contrast
Text primary: white
Text secondary: gray
Warning: orange/yellow
Danger: system red
Progress opportunity: green
Plateau/fatigue: orange
```

### Avoid

- Do not use the exact Activity Ring colour system as the core brand.
- Do not make every card bright green.
- Do not use theme accent for destructive actions. Delete should remain system red.

## Typography

Use system fonts and dynamic type.

Suggested hierarchy:

- Large dashboard number: `.system(size: 44, weight: .bold, design: .rounded)` if appropriate.
- Card title: `.headline` or `.title3.bold()`.
- Main metric: `.title.bold()`.
- Detail text: `.subheadline`.
- Explanatory reason: `.footnote` or `.caption`.

## Layout Patterns

### Dashboard Card

Use for Today, Coach, Progress summary, and Session Summary.

Contents:

- Small label.
- Large metric.
- Short explanation.
- Optional CTA.

### Coach Card

Use for coaching recommendations.

Contents:

- Icon.
- Recommendation title.
- Suggested action.
- Reason.
- Confidence/status badge.

### Split Card

Use for Push/Pull/Legs.

Contents:

- Split name.
- Last trained date.
- Estimated duration.
- Exercise count.
- Coach badge.
- Start button.

### Exercise Target Row

Use in workout preview and split detail.

Contents:

- Exercise name.
- Last best set.
- Suggested target.
- Badge: increase/repeat/reduce/plateau.

### Live Workout Header

Persistent top section during workout:

- Active timer.
- Pause/resume.
- Current exercise index.
- Finish button.

## Progress Visuals

Create original lifting-focused progress visuals:

- Weekly training arc.
- Split coverage arc.
- Progress opportunity arc.

Do not label them as Activity Rings. Do not copy the exact Move/Exercise/Stand model.

Suggested GymTracker arcs:

- **Train**: completed workouts this week.
- **Progress**: exercises with a clear target improvement.
- **Balance**: Push/Pull/Legs coverage.

## Animation and Motion

Use subtle motion:

- Card fade/slide on appear.
- Smooth number changes when target updates.
- Lightweight completion celebration after finishing.

Avoid:

- Heavy animations in the live logger.
- Anything that delays set entry.

## Accessibility

- Support Dynamic Type where practical.
- Keep contrast high in dark mode.
- Avoid using colour alone to communicate fatigue/progress.
- Add text labels for badges and icons.
- Large tap targets for workout controls.

## Codex Implementation Notes

Create reusable components before redesigning every screen:

```text
Views/Shared/
  FitnessCard.swift
  MetricTile.swift
  CoachBadgeView.swift
  ProgressArcView.swift
  SplitCardView.swift
  ExerciseTargetRow.swift
  LiveWorkoutHeader.swift
```

Initial implementation should focus on reusable components and applying them to Today, Coach, Workout Preview, and Session Summary. Do not redesign every screen in one Codex pass.
