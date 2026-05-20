# Enhanced Food Tracking + HealthKit Architecture Brief

## Recommendation

Implement the food tracking module as a local-first nutrition system, then add Apple Health / HealthKit as a secondary sync layer later.

Do **not** replace the food tracking system with HealthKit integration. HealthKit can store and read health/nutrition samples, but it does not solve the product-level problems your app needs to solve:

- barcode-to-product lookup
- nutrition label OCR
- product correction
- reusable personal food database
- source confidence and verification
- fast repeat logging
- gym-specific nutrition insights

The best architecture is:

```text
Local Food Database + Food Log = source of truth
Open Food Facts = external lookup/fallback
Nutrition Label OCR = correction/recovery tool
HealthKit = optional export/import bridge
```

This keeps the app useful on its own while still allowing Apple Health integration later.

---

## Why This Feature Is Worth Building

This feature is worth implementing because it directly improves the identity of the gym tracking app. Your app is already about progressive overload, splits, workout history, and coaching. Nutrition is the missing context that makes the training data more useful.

A gym app that can answer:

```text
Did my lifts improve while my calories/protein were consistent?
Did my weight change while my intake changed?
Did low food intake correlate with poor workout performance?
```

is more valuable than a basic workout logger.

However, the feature should be scoped carefully. A full MyFitnessPal-style system is too large for the next step. The right approach is a lean, staged module that starts with manual entry and local saved foods, then adds barcode lookup, then OCR.

---

## Decision: Food Tracking vs HealthKit First

### Build Food Tracking First

Prioritise this if the goal is to make your app better as a gym/nutrition product.

Benefits:

- Gives your app its own unique feature set.
- Supports barcode scanning and nutrition label scanning.
- Lets you maintain your own corrected food database.
- Makes food logging fast after repeated use.
- Creates data that can drive coaching insights.
- Works even without HealthKit permission.
- Better portfolio value because it demonstrates database design, API mapping, OCR parsing, validation, user flows, and local-first architecture.

### Add HealthKit Later

Prioritise this if the goal is quick interoperability with Apple Health.

Benefits:

- Lets your app read useful external context such as body mass, steps, active energy, and workouts.
- Lets your app write nutrition totals or workout data into Apple Health.
- Makes the app feel more native to iOS.
- Reduces the need to manually duplicate some health data.

Limitations:

- HealthKit will not scan barcodes for you.
- HealthKit will not identify products from labels.
- HealthKit will not maintain your personal corrected product catalogue.
- HealthKit permission flows add complexity.
- HealthKit should not become your app's internal database.

### Final Decision

```text
Stage 1: Local food database + manual food logging
Stage 2: Barcode lookup with Open Food Facts fallback
Stage 3: Nutrition label OCR with confirmation/editing
Stage 4: Food analytics inside your app
Stage 5: HealthKit bridge for import/export
```

HealthKit should be a **bridge**, not the foundation.

---

## Product Archetype

This should feel like a **training-focused nutrition assistant**, not a generic calorie counter.

The feature should support the user before and after training:

```text
Before workout:
- Have I eaten enough today?
- Am I low on protein?
- Did I under-eat compared with my normal training days?

After workout:
- Did I hit protein?
- Did today's session performance line up with my intake?
- Am I in a consistent surplus/deficit/maintenance pattern?
```

The design should be minimal, fast, and correction-focused.

The feature should not try to guess everything automatically. It should suggest, then let the user confirm.

---

## Core Design Principle

Use this priority order everywhere:

```text
User-confirmed local data
> Edited imported data
> Open Food Facts data
> Raw OCR output
> Unverified manual draft
```

The app should never silently trust public database data or raw OCR output.

---

## System Architecture

### Recommended Module Name

```text
NutritionKit
```

This keeps the feature separate from the existing workout/training system.

### Main Layers

```text
Presentation Layer
↓
ViewModel / Coordinator Layer
↓
Nutrition Services Layer
↓
Parsing + Validation Layer
↓
Persistence Layer
↓
Optional HealthKit Bridge
```

---

## Enhanced Component Architecture

### Views

```text
NutritionDashboardView
AddFoodHubView
BarcodeScannerView
FoodSearchView
FoodConfirmationView
NutritionLabelScannerView
OCRReviewView
ManualFoodEntryView
FoodLogView
FoodDetailView
FoodDatabaseView
HealthSyncSettingsView
```

### ViewModels

```text
NutritionDashboardViewModel
AddFoodViewModel
BarcodeScanViewModel
FoodConfirmationViewModel
OCRReviewViewModel
FoodLogViewModel
FoodDatabaseViewModel
HealthSyncViewModel
```

### Services

```text
FoodDatabaseService
FoodLogService
BarcodeScannerService
OpenFoodFactsService
NutritionLabelOCRService
NutritionParserService
NutritionValidationService
NutritionCalculatorService
HealthKitNutritionBridge
HealthKitActivityBridge
```

### Supporting Utilities

```text
NutritionUnitConverter
MacroRoundingPolicy
FoodSourceConfidenceEvaluator
OCRTextNormaliser
NutritionTableColumnDetector
```

---

## Recommended Data Flow

### Add Food by Barcode

```text
User taps Add Food
→ Selects Scan Barcode
→ BarcodeScannerService returns barcode
→ FoodDatabaseService checks local match
→ If local verified item exists, show FoodConfirmationView
→ If no local match, OpenFoodFactsService fetches product
→ Map Open Food Facts response into FoodDraft
→ NutritionValidationService checks missing/suspicious values
→ FoodConfirmationView displays editable values
→ User confirms
→ Save FoodItem locally
→ Create FoodLogEntry if user wants to log it immediately
```

### Add Food by Nutrition Label OCR

```text
User taps Add Food
→ Selects Scan Label
→ Camera captures image
→ NutritionLabelOCRService extracts raw text
→ OCRTextNormaliser cleans text
→ NutritionParserService detects nutrition rows and columns
→ NutritionValidationService flags uncertainty
→ OCRReviewView shows detected values and raw text
→ User edits/confirms
→ Save FoodItem locally
→ Create FoodLogEntry if needed
```

### Add Food Manually

```text
User taps Add Food
→ Selects Manual Entry
→ Enters food name and nutrition values
→ App calculates per 100g/per serving values where possible
→ Save FoodItem locally
→ Optionally log immediately
```

---

## Enhanced Data Model

### FoodItem

```swift
@Model
final class FoodItem {
    @Attribute(.unique) var id: UUID
    var barcode: String?
    var name: String
    var brand: String?
    var category: String?

    var defaultServingQuantity: Double?
    var defaultServingUnit: String?
    var servingDescription: String?

    var caloriesPer100g: Double?
    var proteinPer100g: Double?
    var carbsPer100g: Double?
    var fatPer100g: Double?
    var saturatedFatPer100g: Double?
    var sugarPer100g: Double?
    var fibrePer100g: Double?
    var saltPer100g: Double?

    var dataSource: FoodDataSource
    var verificationStatus: FoodVerificationStatus
    var confidenceScore: Double?

    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    init(...) { }
}
```

### FoodDataSource

```swift
enum FoodDataSource: String, Codable, CaseIterable {
    case manual
    case openFoodFacts
    case editedOpenFoodFacts
    case labelScan
    case editedLabelScan
    case combinedBarcodeAndLabelScan
}
```

### FoodVerificationStatus

```swift
enum FoodVerificationStatus: String, Codable, CaseIterable {
    case draft
    case importedUnverified
    case ocrParsedUnverified
    case userConfirmed
    case userEdited
}
```

### FoodLogEntry

```swift
@Model
final class FoodLogEntry {
    @Attribute(.unique) var id: UUID
    var foodItemId: UUID
    var mealType: MealType

    var consumedQuantity: Double
    var consumedUnit: String

    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var sugar: Double?
    var fibre: Double?
    var salt: Double?

    var loggedAt: Date
    var createdAt: Date
    var updatedAt: Date
}
```

### MealType

```swift
enum MealType: String, Codable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack
    case preWorkout
    case postWorkout
    case unassigned
}
```

### FoodDraft

Use a draft model before saving to SwiftData.

```swift
struct FoodDraft: Identifiable, Codable {
    let id: UUID
    var barcode: String?
    var name: String?
    var brand: String?
    var servingSize: String?

    var caloriesPer100g: Double?
    var proteinPer100g: Double?
    var carbsPer100g: Double?
    var fatPer100g: Double?
    var sugarPer100g: Double?
    var fibrePer100g: Double?
    var saltPer100g: Double?

    var rawOCRText: String?
    var source: FoodDataSource
    var confidenceScore: Double?
    var warnings: [NutritionWarning]
}
```

### NutritionWarning

```swift
enum NutritionWarning: String, Codable, CaseIterable {
    case missingCalories
    case missingProtein
    case missingCarbs
    case missingFat
    case suspiciousCalories
    case suspiciousMacroTotal
    case parsedPerServingOnly
    case multipleColumnsDetected
    case lowOCRConfidence
    case saltSodiumNeedsConversion
}
```

---

## Nutrition Parser Design

The parser should not try to be perfect immediately. It should have staged intelligence.

### Parser Inputs

```text
raw OCR text
OCR line blocks
possible table rows
possible column headings
product context if barcode already exists
```

### Parser Outputs

```text
FoodDraft
confidence score
warnings
raw extracted text
matched row evidence
```

### Parsing Strategy

1. Normalise OCR text.
2. Detect whether values are per 100g, per 100ml, per serving, or mixed.
3. Find nutrient rows using keyword aliases.
4. Extract numeric values and units.
5. Prefer per 100g/per 100ml values.
6. Fall back to serving values only if per 100g/per 100ml is unavailable.
7. Flag uncertainty rather than guessing silently.

### Keyword Aliases

```text
Calories:
energy, kcal, calories, cal

Protein:
protein

Carbohydrates:
carbohydrate, carbohydrates, carbs

Sugar:
sugars, of which sugars

Fat:
fat, total fat

Saturated fat:
saturates, saturated fat, of which saturates

Fibre:
fibre, fiber

Salt:
salt

Sodium:
sodium
```

---

## Validation Rules

Use simple rules at first.

```text
Calories per 100g should usually be between 0 and 900 kcal.
Protein per 100g should usually be between 0 and 100g.
Carbs per 100g should usually be between 0 and 100g.
Fat per 100g should usually be between 0 and 100g.
Sugar should not normally exceed carbs.
Saturated fat should not normally exceed total fat.
Protein + carbs + fat should not obviously exceed 100g.
```

Do not block the user from saving. Instead, show warnings:

```text
“This value looks unusual. Please check before saving.”
```

---

## UX Design Direction

The UI should match the app's modern fitness direction: dark-first, card-based, metric-heavy, Apple Fitness inspired but original.

### Add Food Hub

Use three large action cards:

```text
Scan Barcode
Fastest for packaged foods

Scan Nutrition Label
Best when barcode data is missing or wrong

Manual Entry
Best for custom meals or simple foods
```

### Confirmation Screen

The confirmation screen is the most important screen in this feature.

It should show:

```text
Product name
Brand
Source badge
Confidence badge
Per 100g/per serving toggle
Editable macro fields
Warnings
Save button
Log now button
```

### Source Badges

```text
Verified Local
Edited Import
Open Food Facts
Label Scan
Manual
Needs Review
```

### OCR Review Screen

Use a split design:

```text
Top: detected macro cards
Middle: editable fields
Bottom: raw OCR text collapsed inside “View detected text”
```

Do not show raw OCR text as the main experience. It should be available, but the user should mainly interact with the corrected values.

---

## HealthKit Integration Design

HealthKit should be implemented as a separate bridge after the local nutrition module is stable.

### HealthKit Should Read

```text
body mass
step count
active energy burned
workouts
possibly resting energy burned
```

These values can improve coaching and nutrition context.

### HealthKit Should Write

```text
dietary energy consumed
protein
carbohydrates
total fat
sugar
fibre
sodium, if converted from salt correctly
water, if you add hydration later
workouts, if you want Apple Health workout history support
```

### Important Design Rule

Do not make HealthKit the app's food database.

Use this direction:

```text
FoodItem + FoodLogEntry stored locally
↓
Daily nutrition totals calculated locally
↓
HealthKit bridge writes nutrition samples/correlations if enabled
```

### Permission UX

HealthKit permissions should live in Settings, not interrupt the first-time food logging flow.

Recommended settings section:

```text
Settings
→ Apple Health Sync
   → Read body weight
   → Read steps/activity
   → Write workouts
   → Write nutrition totals
   → Sync now
```

Health sync should be optional and clearly explained.

---

## HealthKit Sync Strategy

### Recommended Approach

For a first version, write daily totals rather than every individual food item.

```text
Food logs for today
→ Calculate daily nutrition total
→ Write one HealthKit nutrition summary per day
```

This is simpler and reduces duplication risk.

### Later Approach

Once stable, you can export meals as food correlations.

```text
Breakfast correlation
- energy consumed sample
- protein sample
- carbs sample
- fat sample

Lunch correlation
- energy consumed sample
- protein sample
- carbs sample
- fat sample
```

### Duplicate Prevention

Add local sync metadata:

```swift
struct HealthKitSyncState: Codable {
    var healthKitUUID: UUID?
    var lastSyncedAt: Date?
    var syncStatus: SyncStatus
}
```

Possible sync statuses:

```swift
enum SyncStatus: String, Codable {
    case notSynced
    case synced
    case pendingUpdate
    case failed
}
```

---

## Suggested Feature Roadmap

### Phase 1: Nutrition Foundation

Build:

- FoodItem model
- FoodLogEntry model
- MealType enum
- ManualFoodEntryView
- FoodLogView
- FoodDatabaseView
- NutritionCalculatorService

Goal:

```text
User can manually create foods and log meals locally.
```

### Phase 2: Barcode Lookup

Build:

- BarcodeScannerService
- BarcodeScannerView
- OpenFoodFactsService
- FoodConfirmationView
- local-first lookup order

Goal:

```text
User can scan a barcode, import a food, edit it, save it locally, and log it.
```

### Phase 3: Nutrition Label OCR MVP

Build:

- NutritionLabelScannerView
- NutritionLabelOCRService
- OCRReviewView
- raw OCR text display
- manual correction into fields

Goal:

```text
User can photograph a nutrition label and use detected text to create a food item.
```

### Phase 4: Automatic OCR Parsing

Build:

- NutritionParserService
- OCRTextNormaliser
- NutritionTableColumnDetector
- warning/confidence system

Goal:

```text
The app auto-fills macros from OCR, but the user still confirms before saving.
```

### Phase 5: Training Nutrition Insights

Build:

- daily calorie/protein targets
- protein consistency card
- training-day intake summary
- pre/post-workout meal tagging
- simple correlations between training performance and nutrition

Goal:

```text
Nutrition data starts improving coaching instead of just sitting in a food log.
```

### Phase 6: HealthKit Bridge

Build:

- HealthKitNutritionBridge
- HealthKitActivityBridge
- HealthSyncSettingsView
- permission handling
- read bodyweight/activity
- optional nutrition export

Goal:

```text
The app becomes connected to Apple Health without depending on it.
```

---

## Codex Implementation Prompt

Use this prompt with Codex when starting the feature:

```text
You are working on a local-first SwiftUI/SwiftData iOS gym tracking app. Implement a new NutritionKit module for food tracking. The module should be staged and should not depend on HealthKit initially.

Primary goal for this implementation slice:
1. Add local models for FoodItem and FoodLogEntry.
2. Add a MealType enum.
3. Add a FoodDataSource enum and FoodVerificationStatus enum.
4. Add a basic NutritionCalculatorService.
5. Add ManualFoodEntryView so the user can create a food manually.
6. Add FoodLogView so the user can log a saved food with consumed quantity.
7. Add FoodDatabaseView so the user can view/edit saved foods.
8. Keep architecture clean using MVVM/services.
9. Preserve existing workout tracking functionality.
10. Do not add HealthKit yet.

Design requirements:
- Dark-first, modern fitness-card UI.
- Match the app's existing visual direction.
- Use clear source/verification badges.
- Prioritise speed and correction over complexity.
- No AI APIs.
- Local-first storage using SwiftData.

Data rules:
- Store food nutrition primarily per 100g/per 100ml where possible.
- Allow optional serving size fields.
- Always allow the user to edit food values.
- Do not silently overwrite user-confirmed local food data.

Future compatibility:
- Structure services so barcode lookup, Open Food Facts import, OCR parsing, and HealthKit sync can be added later without rewriting the local models.
```

---

## Final Product Decision

Build this feature, but build it in the right order.

The strongest route is:

```text
Manual food logging
→ Local food database
→ Barcode scanning
→ Open Food Facts fallback
→ Nutrition label OCR
→ Nutrition/training insights
→ HealthKit sync
```

Do not move straight into HealthKit as the next major feature. HealthKit is valuable, but it should support your app, not define it.
