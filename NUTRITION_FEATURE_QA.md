# Nutrition Feature QA

## Overview

GymTracker nutrition is local-first. Saved foods and food log snapshots live in SwiftData and remain the source of truth. Open Food Facts, OCR parsing, smart comparison, and Apple Health are assistive layers that must stay reviewable, optional, and non-destructive.

## Data Priority

1. User-confirmed food log snapshots
2. User-confirmed saved foods
3. User-edited imported or OCR values
4. Raw Open Food Facts values
5. Raw OCR/parser values
6. Apple Health context

## Main Code Paths

- Models: `FoodItem`, `FoodLogEntry`, nutrition parse/comparison/insight models, HealthKit sync models.
- Services: `NutritionCalculatorService`, `BarcodeFoodLookupService`, `OpenFoodFactsService`, `NutritionParser`, `NutritionComparisonService`, `NutritionInsightsService`, `NutritionHealthKitBridge`, `NutritionDataIntegrityService`.
- Views: nutrition dashboard/add food/manual entry/database/log, barcode scanner, label scan, import review, comparison, insights/targets, and Apple Health settings.

## Manual QA Checklist

- [ ] Create a manual food with calories and macros.
- [ ] Edit a saved food and confirm `updatedAt`-driven UI still refreshes.
- [ ] Log a food for today and confirm the food log snapshot remains correct after editing the saved food.
- [ ] Confirm daily macro summary and meal sections update after logging.
- [ ] Confirm weekly nutrition trends handle days with no food logs.
- [ ] Enter a barcode manually on simulator and confirm local lookup runs before Open Food Facts.
- [ ] Import an Open Food Facts result, edit values, and save only after review.
- [ ] Try saving an imported food with a barcode already saved locally and confirm the duplicate is blocked.
- [ ] Scan or choose a nutrition label image and confirm raw OCR text can be reviewed.
- [ ] Confirm parser confidence/warnings appear and values are editable before saving.
- [ ] Compare Open Food Facts and OCR sources and confirm final values require explicit save.
- [ ] Confirm training-aware insight cards avoid medical/clinical claims.
- [ ] Open Settings > Apple Health with HealthKit off/unavailable and confirm local nutrition still works.
- [ ] Request Apple Health access on a real iPhone, then test manual sync and auto-sync.
- [ ] Revoke Apple Health permissions in iOS Settings and confirm sync fails safely.
- [ ] Check nutrition dashboard, add-food flow, and HealthKit settings in dark mode and on a smaller iPhone simulator.

## Known Limitations

- HealthKit live permission and sample write verification require a physical iPhone.
- There is no automated nutrition test target yet; pure parser/calculator/comparison tests should be added when the project gains a test target.
- HealthKit sample deletion/correlation cleanup remains deferred. Edited synced logs are marked for review instead of duplicated.
- Open Food Facts remains read-only. GymTracker does not upload corrections.
