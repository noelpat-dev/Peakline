# Gym Tracker iOS App — Codex Development Brief

## 1. Product Summary

Build a local-first iOS gym tracker that helps the user:

- Define their training split.
- Log gym sessions quickly.
- Record exercises, sets, reps, weight, RPE, duration, and notes.
- Track progress over time.
- Receive simple, explainable recommendations for the next workout.
- Evaluate consistency, volume, strength progression, and plateaus.

The first version should be a reliable workout logger with rule-based coaching. Do not start with AI, accounts, cloud sync, or Apple Watch support.

## 2. Core MVP Goal

Version 1 should deliver this:

> An iOS app that lets me create my training split, log workouts, view progress per exercise, and receive basic next-session recommendations based on my recent performance, experience level, and consistency.

## 3. Recommended Tech Stack

Use:

- Swift
- SwiftUI
- SwiftData for local persistence
- Swift Charts for progress graphs
- UserNotifications for daily check-ins/reminders

Avoid in version 1:

- Login/accounts
- Backend
- Cloud sync
- AI API integration
- Apple Watch app
- HealthKit integration
- Subscription/payments
- Social features

## 4. Apple Free Provisioning Constraint

The developer does not yet have paid Apple Developer Program access.

Assume local device testing through Xcode with free provisioning. The app may need to be reinstalled periodically because free provisioning profiles expire. Do not rely on TestFlight, App Store distribution, push notifications, iCloud, or advanced entitlements for the MVP.

Use local notifications only, not remote push notifications.

## 5. Target User

Primary user:

- A gym-goer who wants to track workouts and get guidance.
- Experience may range from 3 months to several years.
- Wants suggestions based on actual performance, not generic plans.
- Needs fast logging during workouts.

## 6. User Experience Principles

The workout logger must be fast.

During a workout, the user should be able to:

- Start a planned workout in one or two taps.
- Add a set quickly.
- Copy previous set values.
- See last session performance for the same exercise.
- Adjust weight/reps/RPE with minimal typing.
- Finish the workout easily.

Avoid long forms during active workouts.

## 7. Main App Tabs / Screens

### 7.1 Today Screen

Purpose: daily entry point.

Show:

- Suggested split for today.
- Last workout summary.
- Quick check-in button.
- "Start Workout" button.
- "Rest Day" button.
- Consistency streak or weekly completion status.
- Coach recommendation card.

Example recommendation:

> Suggested today: Pull  
> Reason: You last trained pull 6 days ago. Your push and legs sessions are more recent.

### 7.2 Start Workout Screen

Purpose: choose or start the workout.

Features:

- Select split.
- Load exercises from the split template.
- Start empty workout.
- Resume active workout if one exists.
- Show estimated duration.

### 7.3 Workout Logger Screen

Purpose: record the session.

For each exercise:

- Exercise name
- Target sets and reps
- Previous performance summary
- Set rows
- Add set button
- Add exercise button
- Notes field
- Finish workout button

Each set row:

- Set number
- Weight
- Reps
- RPE
- Warm-up toggle
- Completed toggle

Useful actions:

- Copy previous set
- Copy last session’s working weight
- Mark all sets complete
- Delete set
- Reorder exercises

### 7.4 Splits Screen

Purpose: create and edit routines.

Features:

- Create split
- Edit split name
- Assign exercises
- Set target sets
- Set target rep range
- Set rest period
- Set exercise order
- Mark primary/secondary muscles

Default split examples:

- Push
- Pull
- Legs
- Upper
- Lower
- Full Body
- Custom

### 7.5 Exercise Library Screen

Purpose: manage exercises.

Features:

- Add custom exercise
- Edit exercise
- Select muscle groups
- Select equipment
- Select movement pattern
- Mark compound/isolation
- Archive exercise

### 7.6 History Screen

Purpose: review past sessions.

Show:

- Calendar/list of sessions
- Split performed
- Duration
- Exercises completed
- Total sets
- Total volume
- Notes
- Edit previous workout

### 7.7 Progress Screen

Purpose: performance analysis.

Show:

- Exercise-specific trends
- Estimated 1RM chart
- Working weight trend
- Weekly volume
- PRs
- Training frequency
- Split consistency
- Bodyweight trend if bodyweight is logged

### 7.8 Coach Screen

Purpose: explain recommendations.

Show:

- Suggested next split
- Suggested weight changes
- Plateau warnings
- Deload suggestions
- Missed split warnings
- Weekly summary
- Clear reasoning behind every recommendation

### 7.9 Settings/Profile Screen

Purpose: manage user setup.

Fields:

- Experience level
- Lifting start date
- Main goal
- Training days per week
- Preferred split
- Bodyweight
- Equipment available
- Exercises to avoid
- Injury notes
- Notification preferences
- Units: kg/lb

## 8. Initial Setup Flow

When the user first opens the app, ask:

1. What is your main goal?
   - Strength
   - Hypertrophy
   - Fat loss
   - General fitness
   - Sport performance

2. How long have you been lifting?
   - Less than 3 months
   - 3–6 months
   - 6–12 months
   - 1–3 years
   - 3+ years

3. What is your experience level?
   - Beginner
   - Intermediate
   - Advanced
   - Unsure

4. How many days per week do you want to train?

5. What split do you use?
   - Push/Pull/Legs
   - Upper/Lower
   - Full Body
   - Bro Split
   - Custom

6. What equipment do you have?
   - Commercial gym
   - Dumbbells
   - Barbell
   - Machines
   - Cables
   - Home gym
   - Bodyweight only

7. Any injuries or exercises to avoid?

8. What units do you use?
   - kg
   - lb

After setup, generate starter split templates that the user can edit.

## 9. Daily Check-In Flow

At a chosen time, ask:

> Did you go to the gym today?

Options:

- Yes, log workout
- No, rest day
- Not yet
- Skip

If yes:

1. What split did you do?
2. How long did you train?
3. Which exercises did you perform?
4. For each exercise, log sets/reps/weight/RPE.
5. How hard was the overall workout?
6. Any notes?

If no:

1. Was this a planned rest day?
2. Energy level?
3. Soreness?
4. Optional bodyweight?

## 10. Data Model

Use SwiftData models.

### 10.1 UserProfile

Fields:

- id: UUID
- createdAt: Date
- updatedAt: Date
- goal: TrainingGoal
- experienceLevel: ExperienceLevel
- liftingStartDate: Date?
- trainingDaysPerWeek: Int
- preferredSplitType: SplitType
- bodyweight: Double?
- unitSystem: UnitSystem
- injuryNotes: String?
- exercisesToAvoid: [String]
- notificationsEnabled: Bool
- dailyCheckInTime: Date?

### 10.2 TrainingSplit

Fields:

- id: UUID
- name: String
- splitType: SplitType
- createdAt: Date
- updatedAt: Date
- isActive: Bool
- daysPerWeek: Int
- exercises: [SplitExercise]

### 10.3 SplitExercise

Fields:

- id: UUID
- splitId: UUID
- exerciseId: UUID
- orderIndex: Int
- targetSets: Int
- minReps: Int
- maxReps: Int
- restSeconds: Int?
- notes: String?

### 10.4 Exercise

Fields:

- id: UUID
- name: String
- primaryMuscleGroup: MuscleGroup
- secondaryMuscleGroups: [MuscleGroup]
- movementPattern: MovementPattern
- equipment: EquipmentType
- isCompound: Bool
- isArchived: Bool
- createdAt: Date
- updatedAt: Date

### 10.5 WorkoutSession

Fields:

- id: UUID
- date: Date
- splitId: UUID?
- splitNameSnapshot: String
- startedAt: Date?
- endedAt: Date?
- durationMinutes: Int?
- perceivedDifficulty: Int?
- energyLevel: Int?
- sorenessLevel: Int?
- notes: String?
- completed: Bool
- exerciseLogs: [ExerciseLog]

### 10.6 ExerciseLog

Fields:

- id: UUID
- workoutSessionId: UUID
- exerciseId: UUID
- exerciseNameSnapshot: String
- orderIndex: Int
- notes: String?
- setLogs: [SetLog]

### 10.7 SetLog

Fields:

- id: UUID
- exerciseLogId: UUID
- setNumber: Int
- weight: Double
- reps: Int
- rpe: Double?
- isWarmup: Bool
- completed: Bool

### 10.8 Recommendation

Fields:

- id: UUID
- createdAt: Date
- type: RecommendationType
- splitId: UUID?
- exerciseId: UUID?
- title: String
- message: String
- reason: String
- confidence: Double
- dismissed: Bool

### 10.9 BodyweightLog

Fields:

- id: UUID
- date: Date
- weight: Double
- unit: UnitSystem
- notes: String?

## 11. Enums

### TrainingGoal

- strength
- hypertrophy
- fatLoss
- generalFitness
- sportPerformance

### ExperienceLevel

- beginner
- intermediate
- advanced
- unsure

### SplitType

- pushPullLegs
- upperLower
- fullBody
- broSplit
- custom

### UnitSystem

- metric
- imperial

### MuscleGroup

- chest
- back
- shoulders
- biceps
- triceps
- quads
- hamstrings
- glutes
- calves
- core
- fullBody
- other

### MovementPattern

- push
- pull
- squat
- hinge
- carry
- isolation
- core
- other

### EquipmentType

- barbell
- dumbbell
- machine
- cable
- bodyweight
- kettlebell
- smithMachine
- other

### RecommendationType

- nextSplit
- increaseWeight
- repeatWeight
- reduceWeight
- deload
- missedSplit
- plateau
- volumeWarning
- consistency
- recovery

## 12. Recommendation Engine — Version 1

Build this as a separate service/class.

Suggested name:

`RecommendationEngine`

It should accept:

- user profile
- active splits
- recent workout sessions
- exercise history
- bodyweight logs if available

It should return:

- recommended next split
- per-exercise progression advice
- consistency warnings
- fatigue/deload suggestions

### 12.1 Recommended Next Split Rule

Logic:

1. Look at active split list.
2. Find when each split was last trained.
3. Prioritize the split with the longest gap.
4. If a split was trained yesterday, avoid recommending it again unless the user has no alternative.
5. If the user has a planned sequence, follow it unless recovery data suggests otherwise.

Example output:

> Pull is recommended because it has been 6 days since your last pull session.

### 12.2 Double Progression Rule

For exercises with a target rep range, for example 8–12 reps:

If all working sets hit the max rep target and average RPE is 8 or lower:

- Recommend increasing weight next time.

If most sets are within range:

- Recommend repeating the same weight.

If most sets are below the minimum rep target:

- Recommend reducing weight or reducing volume.

Example:

- Target: 3 sets of 8–12
- Actual: 12, 12, 12 at RPE 8
- Recommendation: increase weight next time

### 12.3 Plateau Rule

If performance on an exercise has not improved for 3 consecutive sessions:

- Mark possible plateau.
- Suggest one of:
  - repeat weight
  - reduce load by 5–10%
  - reduce sets for one session
  - swap accessory exercise
  - improve rest/sleep

### 12.4 Fatigue Rule

If performance drops for 2 consecutive sessions and RPE is high:

- Suggest recovery intervention.

Possible message:

> Your bench performance has dropped for two sessions while RPE stayed high. Consider repeating the weight, reducing one set, or taking a lighter push session.

### 12.5 Consistency Rule

If the user misses a split for more than 7–10 days:

- Recommend prioritizing it.

Example:

> Legs have not been trained in 11 days. Prioritize legs next.

### 12.6 Experience-Level Rules

For beginner or 3-month lifter:

- Keep recommendations simple.
- Focus on consistency.
- Avoid complex periodization.
- Use fewer exercises.
- Recommend repeating weights until form is stable.

For intermediate:

- Use volume, RPE, and trend-based recommendations.
- Detect plateaus.
- Suggest small load increases.

For advanced:

- Allow top set/back-off set style later.
- Allow deload blocks later.
- Track volume more carefully.

## 13. Progress Metrics

Calculate these:

### 13.1 Total Volume

Formula:

`volume = sets × reps × weight`

For each exercise:

`exerciseVolume = sum(weight * reps for completed working sets)`

Exclude warm-up sets by default.

### 13.2 Estimated 1RM

Use Epley formula:

`estimated1RM = weight * (1 + reps / 30)`

Only calculate for working sets.

### 13.3 Weekly Volume

Group completed working sets by calendar week.

Show:

- volume per muscle group
- volume per exercise
- total workouts per week

### 13.4 PR Detection

Track:

- heaviest weight
- most reps at a weight
- best estimated 1RM
- highest volume session for exercise

### 13.5 Consistency

Track:

- workouts completed this week
- workouts completed last week
- split frequency
- missed planned sessions

## 14. Default Exercise Library

Include a small starter library.

### Chest

- Barbell Bench Press
- Dumbbell Bench Press
- Incline Dumbbell Press
- Machine Chest Press
- Cable Fly
- Push-Up

### Back

- Pull-Up
- Lat Pulldown
- Barbell Row
- Dumbbell Row
- Seated Cable Row
- Machine Row

### Shoulders

- Overhead Press
- Dumbbell Shoulder Press
- Lateral Raise
- Rear Delt Fly
- Face Pull

### Legs

- Back Squat
- Front Squat
- Leg Press
- Romanian Deadlift
- Leg Curl
- Leg Extension
- Walking Lunge
- Calf Raise

### Arms

- Barbell Curl
- Dumbbell Curl
- Hammer Curl
- Triceps Pushdown
- Overhead Triceps Extension
- Skullcrusher

### Core

- Plank
- Hanging Leg Raise
- Cable Crunch
- Ab Wheel Rollout

## 15. Starter Split Templates

### 15.1 Push

- Bench Press — 3 sets, 6–10 reps
- Incline Dumbbell Press — 3 sets, 8–12 reps
- Shoulder Press — 3 sets, 6–10 reps
- Lateral Raise — 3 sets, 12–20 reps
- Triceps Pushdown — 3 sets, 10–15 reps

### 15.2 Pull

- Pull-Up or Lat Pulldown — 3 sets, 6–12 reps
- Barbell Row or Cable Row — 3 sets, 8–12 reps
- Dumbbell Row — 2 sets, 8–12 reps
- Face Pull — 3 sets, 12–20 reps
- Dumbbell Curl — 3 sets, 10–15 reps

### 15.3 Legs

- Squat or Leg Press — 3 sets, 6–10 reps
- Romanian Deadlift — 3 sets, 8–12 reps
- Leg Curl — 3 sets, 10–15 reps
- Leg Extension — 3 sets, 10–15 reps
- Calf Raise — 3 sets, 10–20 reps

## 16. MVP User Stories

### Workout Setup

As a user, I want to create a training split so that I can reuse it every week.

Acceptance criteria:

- User can create a split.
- User can add exercises to a split.
- User can set target sets and rep ranges.
- User can reorder exercises.

### Workout Logging

As a user, I want to log sets quickly so that I can track my session during the workout.

Acceptance criteria:

- User can start a workout from a split.
- User can add/edit/delete sets.
- User can enter weight, reps, and RPE.
- User can mark sets as warm-up.
- User can finish workout and save it.

### Previous Performance

As a user, I want to see what I did last time for an exercise so that I know what to aim for.

Acceptance criteria:

- Workout logger shows last session result for each exercise.
- If no history exists, show "No previous data".

### Progress Tracking

As a user, I want to see whether I am improving.

Acceptance criteria:

- User can select an exercise.
- App shows working weight trend.
- App shows estimated 1RM trend.
- App shows PRs.

### Recommendations

As a user, I want the app to tell me what to do next.

Acceptance criteria:

- App suggests next split.
- App suggests whether to increase, repeat, or reduce weight.
- Each recommendation includes a reason.

### Daily Check-In

As a user, I want the app to ask whether I trained today.

Acceptance criteria:

- User can enable daily local notification.
- Notification opens app.
- Today screen lets user log workout or rest day.

## 17. Non-Goals for Version 1

Do not build:

- AI chat coach
- Social feed
- Exercise video library
- Apple Watch app
- HealthKit sync
- Subscription system
- Login/signup
- Cloud database
- TestFlight workflow
- App Store listing
- Nutrition tracking
- Meal planning

## 18. Architecture Recommendation

Use a simple MVVM-ish structure.

Suggested folders:

```text
GymTracker/
  App/
    GymTrackerApp.swift
  Models/
    UserProfile.swift
    TrainingSplit.swift
    Exercise.swift
    WorkoutSession.swift
    ExerciseLog.swift
    SetLog.swift
    Recommendation.swift
    BodyweightLog.swift
    Enums.swift
  Views/
    Today/
    Workout/
    Splits/
    ExerciseLibrary/
    History/
    Progress/
    Coach/
    Settings/
  ViewModels/
    TodayViewModel.swift
    WorkoutLoggerViewModel.swift
    SplitEditorViewModel.swift
    ProgressViewModel.swift
    CoachViewModel.swift
  Services/
    RecommendationEngine.swift
    ProgressCalculator.swift
    NotificationManager.swift
    SeedDataService.swift
  Utilities/
    DateHelpers.swift
    UnitConversion.swift
```

## 19. Development Order

Build in this order:

1. Create SwiftUI app shell with tabs.
2. Create SwiftData models.
3. Add seed exercise library.
4. Build split creation/editing.
5. Build workout start flow.
6. Build workout logger.
7. Save completed sessions.
8. Build history screen.
9. Build previous-performance lookup.
10. Build progress calculations.
11. Add charts.
12. Build rule-based recommendation engine.
13. Add local daily notification.
14. Polish UI and reduce taps.

## 20. First Codex Prompt

Use this as the first prompt to Codex:

```text
Create a SwiftUI iOS app called GymTracker.

The app should be local-first and use SwiftData for persistence.

Build the initial project structure with:
- TabView navigation
- Today tab
- Workout tab
- Splits tab
- Progress tab
- Coach tab
- Settings tab

Create SwiftData models for:
- UserProfile
- TrainingSplit
- SplitExercise
- Exercise
- WorkoutSession
- ExerciseLog
- SetLog
- Recommendation
- BodyweightLog

Create enums for:
- TrainingGoal
- ExperienceLevel
- SplitType
- UnitSystem
- MuscleGroup
- MovementPattern
- EquipmentType
- RecommendationType

Add a SeedDataService that inserts a starter exercise library and Push/Pull/Legs split templates if no data exists.

Do not add networking, login, HealthKit, Apple Watch, or AI.

Prioritize clean structure and compile-ready code.
```

## 21. Second Codex Prompt

After the project structure compiles, use:

```text
Implement the Workout Logger flow.

Requirements:
- User can select a TrainingSplit and start a WorkoutSession.
- App creates ExerciseLog entries from the selected split exercises.
- Each ExerciseLog shows exercise name, target sets, target rep range, and previous session summary.
- User can add SetLog rows.
- Each SetLog has weight, reps, RPE, warm-up toggle, and completed toggle.
- User can copy the previous set.
- User can delete a set.
- User can finish and save the workout.
- Finished workouts should appear in the History tab.

Keep UI simple and fast for use during a gym session.
```

## 22. Third Codex Prompt

After workout logging works, use:

```text
Implement ProgressCalculator and RecommendationEngine.

ProgressCalculator should calculate:
- total workout volume
- exercise volume
- estimated 1RM using Epley formula
- weekly volume
- PRs for each exercise
- last performed date for each exercise

RecommendationEngine should return:
- suggested next split
- per-exercise progression advice
- consistency warnings
- plateau warnings
- fatigue warnings

Use rule-based logic only.
Every recommendation must include a title, message, reason, and confidence score.
```

## 23. Fourth Codex Prompt

After recommendations work, use:

```text
Implement local daily check-in notifications.

Requirements:
- User can enable or disable daily check-in reminders.
- User can choose reminder time.
- Use UserNotifications.
- Notification title: "Gym check-in"
- Notification body: "Did you train today?"
- Tapping the notification opens the app to the Today screen if possible.
- Do not use remote push notifications.
```

## 24. Safety and Disclaimer Copy

Include a short disclaimer somewhere in onboarding or settings:

> This app provides general fitness tracking and training suggestions based on your logged workouts. It is not medical advice. Stop exercising and seek professional advice if you experience pain, dizziness, or symptoms that concern you.

## 25. Future Features

After MVP:

- HealthKit integration
- iCloud sync
- CSV export
- Apple Watch companion app
- Rest timer
- Plate calculator
- Advanced periodization
- AI-generated weekly summaries
- Natural-language workout review
- Exercise substitutions
- Deload planner
- Progress photos
- Body measurements
- TestFlight beta distribution
- App Store release

## 26. Quality Checklist

Before using the app daily, verify:

- App launches cleanly.
- Seed data appears once only.
- Splits can be edited.
- Exercises can be added and removed.
- Workout can be started.
- Sets can be added quickly.
- Workout can be saved.
- History persists after closing the app.
- Previous exercise performance appears correctly.
- Progress calculations ignore warm-up sets.
- Recommendation reasons are understandable.
- Daily notification can be enabled and disabled.
- No feature requires internet access.
