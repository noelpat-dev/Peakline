import UIKit
import XCTest
@testable import GymTracker

final class ExerciseGuideCatalogTests: XCTestCase {
    func testBundledManifestRetainsAllExercisesAndThreeFrames() throws {
        let exercises = ExerciseGuideCatalog.exercises

        XCTAssertEqual(exercises.count, 302)
        XCTAssertEqual(Set(exercises.map(\.id)).count, exercises.count)
        XCTAssertEqual(Set(exercises.map(\.slug)).count, exercises.count)

        let benchPress = try XCTUnwrap(ExerciseGuideCatalog.entry(forSlug: "bench-press"))
        XCTAssertEqual(benchPress.name, "Bench Press")
        XCTAssertEqual(benchPress.equipment, "Barbell")
        XCTAssertEqual(benchPress.primaryMuscle, "Chest")
        XCTAssertEqual(benchPress.secondaryMuscles, ["Triceps", "Shoulders"])
        XCTAssertEqual(benchPress.frames.map(\.index), [1, 2, 3])
        XCTAssertEqual(
            benchPress.frameAssetNames,
            [
                "workout_guide_bench_press_frame_1",
                "workout_guide_bench_press_frame_2",
                "workout_guide_bench_press_frame_3"
            ]
        )
        XCTAssertEqual(benchPress.assetName(frame: 99), "workout_guide_bench_press_frame_1")
        XCTAssertEqual(benchPress.attribution.creator, "Bryl Lim")
        XCTAssertEqual(benchPress.attribution.license, "CC BY-SA 4.0")
        XCTAssertNotNil(benchPress.attribution.source)
        XCTAssertEqual(
            exercises.filter { $0.attribution.source != nil }.count,
            76
        )
        XCTAssertTrue(exercises.allSatisfy { $0.frames.allSatisfy { $0.attribution.creator == "Bryl Lim" } })
    }

    func testNameLookupKeepsEquipmentVariantsDistinct() {
        XCTAssertNotNil(
            ExerciseGuideCatalog.entry(forName: "Pull-up", equipment: "Bodyweight")
        )
        XCTAssertNil(
            ExerciseGuideCatalog.entry(forName: "Pull-up", equipment: "Machine")
        )
        XCTAssertNotNil(
            ExerciseGuideCatalog.entry(forName: "Seated Cable Row", equipment: "Cable")
        )
        XCTAssertNil(
            ExerciseGuideCatalog.entry(forName: "Seated Cable Row", equipment: "Machine")
        )
    }

    func testEveryImportedGuideFrameResolvesToAnImageAsset() {
        let bundles = [Bundle.main, Bundle(for: ExerciseGuideCatalogTests.self)]
        let missing = ExerciseGuideCatalog.exercises.flatMap { entry in
            entry.frames.compactMap { frame in
                let assetName = entry.assetName(frame: frame.index)
                let isAvailable = bundles.contains {
                    UIImage(named: assetName, in: $0, compatibleWith: nil) != nil
                }
                return isAvailable ? nil : assetName
            }
        }

        XCTAssertTrue(missing.isEmpty, "Missing Workout Guide image assets: \(missing.prefix(5))")
    }

    func testIconKeysExposeWorkoutGuideAssetsForLegacyAndGeneratedKeys() throws {
        XCTAssertEqual(ExerciseIconKey.benchPress.workoutGuideSlug, "bench-press")
        XCTAssertEqual(ExerciseIconKey.closeGripWeightedPullUp.workoutGuideSlug, "weighted-pull-up")
        XCTAssertEqual(ExerciseIconKey.latPulldown.workoutGuideSlug, "lat-pulldown")
        XCTAssertEqual(ExerciseIconKey.benchPress.assetName, "workout_guide_bench_press_frame_1")

        let generatedBenchPress = try XCTUnwrap(
            ExerciseIconKey.guideKey(forSlug: "bench-press")
        )
        XCTAssertEqual(generatedBenchPress.rawValue, "guide_bench-press")
        XCTAssertEqual(
            generatedBenchPress.workoutGuideAssetName(frame: 2),
            "workout_guide_bench_press_frame_2"
        )
        XCTAssertEqual(
            ExerciseGuideCatalog.exercises.compactMap {
                ExerciseIconKey.guideKey(forSlug: $0.slug)
            }.count,
            302
        )
        XCTAssertEqual(
            ExerciseIconMapper.iconKey(forName: "Triceps Pushdown").workoutGuideAssetName(frame: 2),
            "workout_guide_tricep_pushdown_frame_2"
        )
        XCTAssertEqual(
            ExerciseIconMapper.iconKey(forName: "Incline Bench Press"),
            ExerciseIconKey.guideKey(forSlug: "incline-bench-press")
        )
        XCTAssertEqual(
            ExerciseIconMapper.iconKey(forName: "Dumbbell Bench Press"),
            ExerciseIconKey.guideKey(forSlug: "dumbbell-bench-press")
        )
        XCTAssertEqual(
            ExerciseIconMapper.iconKey(forName: "Close-Grip Bench Press"),
            ExerciseIconKey.guideKey(forSlug: "close-grip-bench-press")
        )
        XCTAssertEqual(
            ExerciseIconMapper.iconKey(forName: "Quad Extension"),
            ExerciseIconKey.guideKey(forSlug: "leg-extension")
        )
        XCTAssertEqual(
            ExerciseIconMapper.iconKey(forName: "Single-Leg Quad Extension"),
            .quadExtension
        )
        XCTAssertEqual(
            ExerciseIconMapper.iconKey(forName: "Incline Dumbbell Bench Press").workoutGuideSlug,
            "incline-dumbbell-press"
        )
    }

    func testEveryLegacyIconKeyResolvesToBundledWorkoutGuideArtwork() throws {
        let legacyKeys = ExerciseIconKey.allCases.filter { !$0.rawValue.hasPrefix("guide_") }
        XCTAssertEqual(legacyKeys.count, 47)

        let bundles = [Bundle.main, Bundle(for: ExerciseGuideCatalogTests.self)]
        let invalid = legacyKeys.compactMap { key -> String? in
            guard let slug = key.workoutGuideSlug,
                  let entry = ExerciseGuideCatalog.entry(forSlug: slug),
                  key.assetName == entry.assetName(frame: 1) else {
                return "\(key.rawValue) -> \(key.workoutGuideSlug ?? "nil")"
            }

            let available = bundles.contains {
                UIImage(named: key.assetName, in: $0, compatibleWith: nil) != nil
            }
            return available ? nil : "missing \(key.assetName)"
        }

        XCTAssertTrue(invalid.isEmpty, "Invalid legacy Workout Guide artwork: \(invalid.prefix(5))")
        XCTAssertEqual(ExerciseIconKey.bicepPreacherCurl.workoutGuideSlug, "preacher-curl")
        XCTAssertEqual(ExerciseIconKey.bicepPreacherCurlMachine.workoutGuideSlug, "preacher-curl")
        XCTAssertEqual(ExerciseIconKey.abdominalCrunch.workoutGuideSlug, "weighted-crunch")
    }

    func testAllSeededExerciseNamesUseRepresentativeWorkoutGuideArtwork() {
        let expectedSlugs: [String: String] = [
            "Incline Chest Press (Smith)": "smith-machine-bench-press",
            "Converging Chest Press": "machine-chest-press",
            "Chest Fly": "pec-deck",
            "Low-High Chest Fly": "cable-fly",
            "Incline Chest Press": "incline-bench-press",
            "Bench Press": "bench-press",
            "Triceps Pushdown": "tricep-pushdown",
            "Overhead Triceps Extension": "overhead-tricep-extension",
            "Triceps Cable Press": "tricep-pushdown",
            "One-Arm Triceps Cable": "tricep-pushdown",
            "Seated Triceps Press": "tricep-pushdown",
            "JM Press": "close-grip-bench-press",
            "Lat Pulldown": "lat-pulldown",
            "Diverging Lower Lat Row": "machine-row",
            "Diverging Seated Row": "machine-row",
            "Close Grip Weighted Pull-Up": "weighted-pull-up",
            "Pull-Up": "pull-up",
            "Rear Delt Machine": "reverse-pec-deck",
            "Rear Delt Cable": "cable-rear-delt-fly",
            "Dumbbell Bicep Curl": "bicep-curl",
            "Bicep Preacher Curl": "preacher-curl",
            "Bicep Preacher Curl Machine": "preacher-curl",
            "Seated T-Bar Row": "machine-row",
            "Dumbbell Shoulder Press": "seated-dumbbell-press",
            "Shoulder Press (Smith)": "machine-shoulder-press",
            "Cable Lateral Raise": "cable-lateral-raise",
            "Quad Extension": "leg-extension",
            "Single-Leg Quad Extension": "leg-extension",
            "Hamstring Curl": "leg-curl",
            "Seated Leg Curl": "seated-leg-curl",
            "Leg Press": "leg-press",
            "Standing Calf Raise": "standing-calf-raise",
            "Hip Adduction": "hip-adduction-machine",
            "Abdominal Crunch": "weighted-crunch",
            "Hack Squat": "hack-squat"
        ]

        XCTAssertEqual(expectedSlugs.count, 35)
        for (name, expectedSlug) in expectedSlugs {
            let entry = ExerciseIconMapper.illustrationEntry(forName: name)
            XCTAssertEqual(entry?.slug, expectedSlug, name)
            XCTAssertTrue(
                ExerciseIconMapper.iconKey(forName: name).assetName.hasPrefix("workout_guide_"),
                name
            )
        }
    }

    func testSplitAndCategoryIconsUseWorkoutGuideArtwork() {
        let expected: [String: String] = [
            "Push": "push-up",
            "Pull": "pull-up",
            "Legs": "bodyweight-squat",
            "Lower A": "bodyweight-squat",
            "Upper A": "overhead-press",
            "Unknown split": "bodyweight-squat"
        ]

        for (name, expectedSlug) in expected {
            XCTAssertEqual(
                ExerciseIconMapper.splitIconKey(for: name).workoutGuideSlug,
                expectedSlug,
                name
            )
            XCTAssertTrue(
                ExerciseIconMapper.splitIconKey(for: name).assetName.hasPrefix("workout_guide_"),
                name
            )
        }
    }

    func testMapperAliasesSeedNamesOnlyForMatchingEquipment() throws {
        let cablePushdown = try XCTUnwrap(
            ExerciseIconMapper.guideEntry(forName: "Triceps Pushdown", equipment: .cable)
        )
        XCTAssertEqual(cablePushdown.slug, "tricep-pushdown")

        XCTAssertNil(
            ExerciseIconMapper.guideEntry(forName: "Triceps Pushdown", equipment: .machine)
        )

        let machinePreacher = try XCTUnwrap(
            ExerciseIconMapper.guideEntry(
                forName: "Bicep Preacher Curl Machine",
                equipment: .machine
            )
        )
        XCTAssertEqual(machinePreacher.slug, "preacher-curl")

        let snapshotAlias = try XCTUnwrap(
            ExerciseIconMapper.guideEntry(forName: "Dumbbell Bicep Curl")
        )
        XCTAssertEqual(snapshotAlias.slug, "bicep-curl")

        XCTAssertNil(
            ExerciseIconMapper.guideEntry(
                forName: "Close Grip Weighted Pull-Up",
                equipment: .bodyweight
            )
        )

        XCTAssertEqual(
            ExerciseIconMapper.iconKey(forName: "Rear Delt Machine").workoutGuideSlug,
            "reverse-pec-deck"
        )
        XCTAssertEqual(
            ExerciseIconMapper.iconKey(forName: "Seated T-Bar Row").workoutGuideSlug,
            "machine-row"
        )

        XCTAssertNil(
            ExerciseIconMapper.guideEntry(forName: "Diverging Seated Row", equipment: .machine)
        )
        XCTAssertNil(
            ExerciseIconMapper.guideEntry(forName: "Standing Calf Raise")
        )
    }
}
