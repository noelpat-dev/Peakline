import Foundation

enum ExerciseIconKey: String, CaseIterable, Codable, Hashable {
    case bicepCurl
    case divergingRow
    case legCurl
    case legExtension
    case legs
    case pullUps
    case tricepPushDown
    case abdominalCrunch
    case inclineChestPressSmith
    case benchPress
    case convergingChestPress
    case inclineChestPress
    case chestPress
    case chestFly
    case dumbbellShoulderPress
    case shoulderPressSmith
    case shoulderPress
    case cableLateralRaise
    case tricepsPushdown
    case overheadTricepsExtension
    case latPulldown
    case closeGripWeightedPullUp
    case pullUp
    case divergingSeatedRow
    case seatedRow
    case divergingLowerLatRow
    case lowerLatRow
    case rearDeltCable
    case bicepPreacherCurl
    case bicepPreacherCurlMachine
    case hackSquat
    case legPress
    case quadExtension
    case seatedLegCurl
    case standingCalfRaise
    case hipAdduction
    case genericPush
    case genericPull
    case genericLegs
    case genericCore
    case genericMachine
    case genericDumbbell
    case genericBarbell
    case genericCable
    case genericExercise
    case upperBody
    case programmeRotation

    // Generated from Workout Guide manifest at aac599224bb9780305239607ef98540b7e0ce389.
    case guideBenchPress = "guide_bench-press"
    case guideInclineBenchPress = "guide_incline-bench-press"
    case guideInclineDumbbellPress = "guide_incline-dumbbell-press"
    case guideDumbbellBenchPress = "guide_dumbbell-bench-press"
    case guideDeclineBenchPress = "guide_decline-bench-press"
    case guideMachineChestPress = "guide_machine-chest-press"
    case guidePecDeck = "guide_pec-deck"
    case guideCableFly = "guide_cable-fly"
    case guidePushUp = "guide_push-up"
    case guideWeightedPushUp = "guide_weighted-push-up"
    case guideOverheadPress = "guide_overhead-press"
    case guideSeatedDumbbellPress = "guide_seated-dumbbell-press"
    case guideArnoldPress = "guide_arnold-press"
    case guideLateralRaise = "guide_lateral-raise"
    case guideCableLateralRaise = "guide_cable-lateral-raise"
    case guideFrontRaise = "guide_front-raise"
    case guideRearDeltFly = "guide_rear-delt-fly"
    case guideReversePecDeck = "guide_reverse-pec-deck"
    case guideFacePull = "guide_face-pull"
    case guideUprightRow = "guide_upright-row"
    case guideDeadlift = "guide_deadlift"
    case guideRomanianDeadlift = "guide_romanian-deadlift"
    case guideBarbellRow = "guide_barbell-row"
    case guideTBarRow = "guide_t-bar-row"
    case guideDumbbellBentOverRow = "guide_dumbbell-bent-over-row"
    case guideOneArmDumbbellRow = "guide_one-arm-dumbbell-row"
    case guideChestSupportedRow = "guide_chest-supported-row"
    case guideSeatedRow = "guide_seated-row"
    case guideMachineRow = "guide_machine-row"
    case guideLatPulldown = "guide_lat-pulldown"
    case guideCloseGripLatPulldown = "guide_close-grip-lat-pulldown"
    case guideStraightArmPulldown = "guide_straight-arm-pulldown"
    case guidePullUp = "guide_pull-up"
    case guideAssistedPullUp = "guide_assisted-pull-up"
    case guideWeightedPullUp = "guide_weighted-pull-up"
    case guideChinUp = "guide_chin-up"
    case guideShrug = "guide_shrug"
    case guideSquat = "guide_squat"
    case guideFrontSquat = "guide_front-squat"
    case guideHackSquat = "guide_hack-squat"
    case guideLegPress = "guide_leg-press"
    case guideBulgarianSplitSquat = "guide_bulgarian-split-squat"
    case guideWalkingLunge = "guide_walking-lunge"
    case guideStepUp = "guide_step-up"
    case guideLegExtension = "guide_leg-extension"
    case guideLegCurl = "guide_leg-curl"
    case guideSeatedLegCurl = "guide_seated-leg-curl"
    case guideHipThrust = "guide_hip-thrust"
    case guideGluteBridge = "guide_glute-bridge"
    case guideGoodMorning = "guide_good-morning"
    case guideStandingCalfRaise = "guide_standing-calf-raise"
    case guideSeatedCalfRaise = "guide_seated-calf-raise"
    case guideBicepCurl = "guide_bicep-curl"
    case guideHammerCurl = "guide_hammer-curl"
    case guidePreacherCurl = "guide_preacher-curl"
    case guideCableCurl = "guide_cable-curl"
    case guideReverseCurl = "guide_reverse-curl"
    case guideWristCurl = "guide_wrist-curl"
    case guideTricepPushdown = "guide_tricep-pushdown"
    case guideOverheadTricepExtension = "guide_overhead-tricep-extension"
    case guideSkullCrusher = "guide_skull-crusher"
    case guideCloseGripBenchPress = "guide_close-grip-bench-press"
    case guideDip = "guide_dip"
    case guideAssistedDip = "guide_assisted-dip"
    case guidePlank = "guide_plank"
    case guideSidePlank = "guide_side-plank"
    case guideHangingLegRaise = "guide_hanging-leg-raise"
    case guideCableCrunch = "guide_cable-crunch"
    case guideAbWheel = "guide_ab-wheel"
    case guideRunning = "guide_running"
    case guideWalking = "guide_walking"
    case guideCycling = "guide_cycling"
    case guideRowing = "guide_rowing"
    case guideStairClimber = "guide_stair-climber"
    case guideDumbbellFly = "guide_dumbbell-fly"
    case guideInclineCableFly = "guide_incline-cable-fly"
    case guideDeclineDumbbellPress = "guide_decline-dumbbell-press"
    case guideSmithMachineBenchPress = "guide_smith-machine-bench-press"
    case guideLandminePress = "guide_landmine-press"
    case guideChestDip = "guide_chest-dip"
    case guideWeightedDip = "guide_weighted-dip"
    case guideMachineShoulderPress = "guide_machine-shoulder-press"
    case guideStandingDumbbellPress = "guide_standing-dumbbell-press"
    case guidePushPress = "guide_push-press"
    case guideMachineLateralRaise = "guide_machine-lateral-raise"
    case guideCableFrontRaise = "guide_cable-front-raise"
    case guidePlateFrontRaise = "guide_plate-front-raise"
    case guideBentOverRearDeltRaise = "guide_bent-over-rear-delt-raise"
    case guideCableRearDeltFly = "guide_cable-rear-delt-fly"
    case guidePendlayRow = "guide_pendlay-row"
    case guideInvertedRow = "guide_inverted-row"
    case guideMeadowsRow = "guide_meadows-row"
    case guideSingleArmCableRow = "guide_single-arm-cable-row"
    case guideWideGripLatPulldown = "guide_wide-grip-lat-pulldown"
    case guideNeutralGripPullUp = "guide_neutral-grip-pull-up"
    case guideAssistedChinUp = "guide_assisted-chin-up"
    case guideWeightedChinUp = "guide_weighted-chin-up"
    case guideRackPull = "guide_rack-pull"
    case guideBackExtension = "guide_back-extension"
    case guideDumbbellShrug = "guide_dumbbell-shrug"
    case guideGobletSquat = "guide_goblet-squat"
    case guideSmithMachineSquat = "guide_smith-machine-squat"
    case guideBeltSquat = "guide_belt-squat"
    case guideSumoDeadlift = "guide_sumo-deadlift"
    case guideTrapBarDeadlift = "guide_trap-bar-deadlift"
    case guideLyingLegCurl = "guide_lying-leg-curl"
    case guideNordicHamstringCurl = "guide_nordic-hamstring-curl"
    case guideSingleLegRomanianDeadlift = "guide_single-leg-romanian-deadlift"
    case guideReverseLunge = "guide_reverse-lunge"
    case guideSplitSquat = "guide_split-squat"
    case guideCableKickback = "guide_cable-kickback"
    case guideHipAbductionMachine = "guide_hip-abduction-machine"
    case guideSingleLegGluteBridge = "guide_single-leg-glute-bridge"
    case guideBarbellGluteBridge = "guide_barbell-glute-bridge"
    case guideDumbbellGluteBridge = "guide_dumbbell-glute-bridge"
    case guideDumbbellHipThrust = "guide_dumbbell-hip-thrust"
    case guideSmithMachineHipThrust = "guide_smith-machine-hip-thrust"
    case guideSmithMachineRomanianDeadlift = "guide_smith-machine-romanian-deadlift"
    case guideDumbbellRomanianDeadlift = "guide_dumbbell-romanian-deadlift"
    case guideKettlebellRomanianDeadlift = "guide_kettlebell-romanian-deadlift"
    case guideCablePullThrough = "guide_cable-pull-through"
    case guideMachineGluteKickback = "guide_machine-glute-kickback"
    case guideCableStandingHipAbduction = "guide_cable-standing-hip-abduction"
    case guideCableStandingHipAdduction = "guide_cable-standing-hip-adduction"
    case guideHipAdductionMachine = "guide_hip-adduction-machine"
    case guideSmithMachineBulgarianSplitSquat = "guide_smith-machine-bulgarian-split-squat"
    case guideSmithMachineReverseLunge = "guide_smith-machine-reverse-lunge"
    case guideSmithMachineSplitSquat = "guide_smith-machine-split-squat"
    case guideHeelElevatedGobletSquat = "guide_heel-elevated-goblet-squat"
    case guideDumbbellSumoSquat = "guide_dumbbell-sumo-squat"
    case guideDumbbellSumoDeadlift = "guide_dumbbell-sumo-deadlift"
    case guideFrontFootElevatedSplitSquat = "guide_front-foot-elevated-split-squat"
    case guideDeficitReverseLunge = "guide_deficit-reverse-lunge"
    case guideDumbbellLateralLunge = "guide_dumbbell-lateral-lunge"
    case guideDumbbellCurtsyLunge = "guide_dumbbell-curtsy-lunge"
    case guideLandmineSquat = "guide_landmine-squat"
    case guideLandmineRomanianDeadlift = "guide_landmine-romanian-deadlift"
    case guideKettlebellSwing = "guide_kettlebell-swing"
    case guideGluteFocusedBackExtension = "guide_glute-focused-back-extension"
    case guideReverseHyperextension = "guide_reverse-hyperextension"
    case guideDonkeyCalfRaise = "guide_donkey-calf-raise"
    case guideLegPressCalfRaise = "guide_leg-press-calf-raise"
    case guideWallSit = "guide_wall-sit"
    case guideJumpSquat = "guide_jump-squat"
    case guideInclineDumbbellCurl = "guide_incline-dumbbell-curl"
    case guideConcentrationCurl = "guide_concentration-curl"
    case guideEzBarCurl = "guide_ez-bar-curl"
    case guideSpiderCurl = "guide_spider-curl"
    case guideRopeHammerCurl = "guide_rope-hammer-curl"
    case guideDragCurl = "guide_drag-curl"
    case guideRopeTricepPushdown = "guide_rope-tricep-pushdown"
    case guideDumbbellSkullCrusher = "guide_dumbbell-skull-crusher"
    case guideSingleDumbbellSkullcrusher = "guide_single-dumbbell-skullcrusher"
    case guideDumbbellOverheadTricepExtension = "guide_dumbbell-overhead-tricep-extension"
    case guideSingleArmDumbbellTricepExtension = "guide_single-arm-dumbbell-tricep-extension"
    case guideBenchDip = "guide_bench-dip"
    case guideTricepKickback = "guide_tricep-kickback"
    case guideWristExtension = "guide_wrist-extension"
    case guideFarmerCarry = "guide_farmer-carry"
    case guideCrunch = "guide_crunch"
    case guideReverseCrunch = "guide_reverse-crunch"
    case guideRussianTwist = "guide_russian-twist"
    case guideBicycleCrunch = "guide_bicycle-crunch"
    case guideMountainClimber = "guide_mountain-climber"
    case guideDeadBug = "guide_dead-bug"
    case guideBirdDog = "guide_bird-dog"
    case guidePallofPress = "guide_pallof-press"
    case guideCableWoodchop = "guide_cable-woodchop"
    case guideHalfKneelingPallofPress = "guide_half-kneeling-pallof-press"
    case guideCablePallofHold = "guide_cable-pallof-hold"
    case guideHangingKneeRaise = "guide_hanging-knee-raise"
    case guideCaptainsChairKneeRaise = "guide_captains-chair-knee-raise"
    case guideDeclineSitUp = "guide_decline-sit-up"
    case guideWeightedCrunch = "guide_weighted-crunch"
    case guideWeightedRussianTwist = "guide_weighted-russian-twist"
    case guideDumbbellSideBend = "guide_dumbbell-side-bend"
    case guideElliptical = "guide_elliptical"
    case guideSwimming = "guide_swimming"
    case guideJumpRope = "guide_jump-rope"
    case guideAssaultBike = "guide_assault-bike"
    case guideSkierg = "guide_skierg"
    case guideHiking = "guide_hiking"
    case guideTreadmillInclineWalk = "guide_treadmill-incline-walk"
    case guideBattleRopes = "guide_battle-ropes"
    case guideInclinePushUp = "guide_incline-push-up"
    case guideKneePushUp = "guide_knee-push-up"
    case guideWidePushUp = "guide_wide-push-up"
    case guideDiamondPushUp = "guide_diamond-push-up"
    case guideDeclinePushUp = "guide_decline-push-up"
    case guidePikePushUp = "guide_pike-push-up"
    case guideFeetElevatedPikePushUp = "guide_feet-elevated-pike-push-up"
    case guideArcherPushUp = "guide_archer-push-up"
    case guideTypewriterPushUp = "guide_typewriter-push-up"
    case guideExplosivePushUp = "guide_explosive-push-up"
    case guideHinduPushUp = "guide_hindu-push-up"
    case guideScapularPushUp = "guide_scapular-push-up"
    case guidePushUpShoulderTap = "guide_push-up-shoulder-tap"
    case guideWallPushUp = "guide_wall-push-up"
    case guideWallWalk = "guide_wall-walk"
    case guideWallHandstandPushUp = "guide_wall-handstand-push-up"
    case guideHandstandPushUp = "guide_handstand-push-up"
    case guideChairDip = "guide_chair-dip"
    case guideDoorwayRow = "guide_doorway-row"
    case guideTowelRow = "guide_towel-row"
    case guideProneYRaise = "guide_prone-y-raise"
    case guideProneTRaise = "guide_prone-t-raise"
    case guideSuperman = "guide_superman"
    case guideSupermanHold = "guide_superman-hold"
    case guideReverseSnowAngel = "guide_reverse-snow-angel"
    case guideDeadHang = "guide_dead-hang"
    case guideActiveHang = "guide_active-hang"
    case guideScapularPullUp = "guide_scapular-pull-up"
    case guideNegativePullUp = "guide_negative-pull-up"
    case guideCommandoPullUp = "guide_commando-pull-up"
    case guideLSitPullUp = "guide_l-sit-pull-up"
    case guideTowelPullUp = "guide_towel-pull-up"
    case guideBodyweightSquat = "guide_bodyweight-squat"
    case guidePistolSquat = "guide_pistol-squat"
    case guideAssistedPistolSquat = "guide_assisted-pistol-squat"
    case guideShrimpSquat = "guide_shrimp-squat"
    case guideCossackSquat = "guide_cossack-squat"
    case guideSissySquat = "guide_sissy-squat"
    case guideForwardLunge = "guide_forward-lunge"
    case guideLateralLunge = "guide_lateral-lunge"
    case guideCurtsyLunge = "guide_curtsy-lunge"
    case guideSkaterSquat = "guide_skater-squat"
    case guideSingleLegBoxSquat = "guide_single-leg-box-squat"
    case guideStepDown = "guide_step-down"
    case guideCalfRaise = "guide_calf-raise"
    case guideSingleLegCalfRaise = "guide_single-leg-calf-raise"
    case guideGluteBridgeMarch = "guide_glute-bridge-march"
    case guideFrogPump = "guide_frog-pump"
    case guideDonkeyKick = "guide_donkey-kick"
    case guideFireHydrant = "guide_fire-hydrant"
    case guideClamshell = "guide_clamshell"
    case guideHipAirplane = "guide_hip-airplane"
    case guideSideLyingHipAbduction = "guide_side-lying-hip-abduction"
    case guideSideLyingLegRaise = "guide_side-lying-leg-raise"
    case guideLyingHamstringWalkout = "guide_lying-hamstring-walkout"
    case guideTowelHamstringCurl = "guide_towel-hamstring-curl"
    case guideStabilityBallHamstringCurl = "guide_stability-ball-hamstring-curl"
    case guideBandedGluteBridge = "guide_banded-glute-bridge"
    case guideBandedHipThrust = "guide_banded-hip-thrust"
    case guideBandedFrogPump = "guide_banded-frog-pump"
    case guideBandedClamshell = "guide_banded-clamshell"
    case guideBandedLateralWalk = "guide_banded-lateral-walk"
    case guideBandedMonsterWalk = "guide_banded-monster-walk"
    case guideBandedSquat = "guide_banded-squat"
    case guideBandedDonkeyKick = "guide_banded-donkey-kick"
    case guideBandedFireHydrant = "guide_banded-fire-hydrant"
    case guideBandedKickback = "guide_banded-kickback"
    case guideBandedStandingHipAbduction = "guide_banded-standing-hip-abduction"
    case guideBandedSeatedHipAbduction = "guide_banded-seated-hip-abduction"
    case guideBandPullApart = "guide_band-pull-apart"
    case guideBandedFacePull = "guide_banded-face-pull"
    case guideBandedRow = "guide_banded-row"
    case guideBandedLatPulldown = "guide_banded-lat-pulldown"
    case guideBandedPallofPress = "guide_banded-pallof-press"
    case guideBandedWoodchop = "guide_banded-woodchop"
    case guideBandedDeadBug = "guide_banded-dead-bug"
    case guideHollowBodyHold = "guide_hollow-body-hold"
    case guideHollowRock = "guide_hollow-rock"
    case guideVUp = "guide_v-up"
    case guideFlutterKick = "guide_flutter-kick"
    case guideLyingLegRaise = "guide_lying-leg-raise"
    case guideToeTouch = "guide_toe-touch"
    case guideHeelTap = "guide_heel-tap"
    case guidePlankShoulderTap = "guide_plank-shoulder-tap"
    case guidePlankJack = "guide_plank-jack"
    case guideBearPlank = "guide_bear-plank"
    case guideBearCrawl = "guide_bear-crawl"
    case guideCrabWalk = "guide_crab-walk"
    case guideInchworm = "guide_inchworm"
    case guideLSitHold = "guide_l-sit-hold"
    case guideSeatedKneeTuck = "guide_seated-knee-tuck"
    case guideSidePlankHipDip = "guide_side-plank-hip-dip"
    case guideCopenhagenPlank = "guide_copenhagen-plank"
    case guideDragonFlag = "guide_dragon-flag"
    case guideBurpee = "guide_burpee"
    case guideHalfBurpee = "guide_half-burpee"
    case guideSquatThrust = "guide_squat-thrust"
    case guideHighKnees = "guide_high-knees"
    case guideJumpingJack = "guide_jumping-jack"
    case guideSkaterHop = "guide_skater-hop"
    case guideLateralShuffle = "guide_lateral-shuffle"
    case guideFastFeet = "guide_fast-feet"
    case guideSprawl = "guide_sprawl"
    case guideSealJack = "guide_seal-jack"
    case guideCatCowStretch = "guide_cat-cow-stretch"
    case guideArmCircles = "guide_arm-circles"
    case guideWorldsGreatestStretch = "guide_worlds-greatest-stretch"
    case guideLegSwingsStretch = "guide_leg-swings-stretch"
    case guideTorsoTwistStretch = "guide_torso-twist-stretch"
    case guideDoorwayChestStretch = "guide_doorway-chest-stretch"
    case guideChildsPose = "guide_childs-pose"
    case guideKneelingHipFlexorStretch = "guide_kneeling-hip-flexor-stretch"
    case guideHamstringStretch = "guide_hamstring-stretch"
    case guideStandingQuadStretch = "guide_standing-quad-stretch"
    case guideSeatedForwardFoldStretch = "guide_seated-forward-fold-stretch"
    case guideCrossBodyShoulderStretch = "guide_cross-body-shoulder-stretch"
    case guideWallCalfStretch = "guide_wall-calf-stretch"
    case guideButterflyStretch = "guide_butterfly-stretch"

    var assetName: String {
        // Keep this compatibility property for persisted icon keys, but route
        // every key through the imported Workout Guide artwork. The fallback
        // is only defensive: every current enum case has a guide slug.
        workoutGuideAssetName() ?? "workout_guide_bodyweight_squat_frame_1"
    }

    /// Returns the visual Workout Guide slug for generated keys and for the
    /// representative artwork used by legacy persisted keys.
    var workoutGuideSlug: String? {
        if rawValue.hasPrefix("guide_") {
            return String(rawValue.dropFirst("guide_".count))
        }
        return Self.legacyWorkoutGuideSlugs[rawValue]
    }

    static func guideKey(forSlug slug: String) -> ExerciseIconKey? {
        guideKeysBySlug[slug]
    }

    private static let guideKeysBySlug: [String: ExerciseIconKey] = Dictionary(
        uniqueKeysWithValues: allCases.compactMap { key in
            // Legacy cases intentionally share representative slugs with
            // generated cases. Only generated cases identify a catalog key.
            guard key.rawValue.hasPrefix("guide_"),
                  let slug = key.workoutGuideSlug else { return nil }
            return (slug, key)
        }
    )

    /// Returns the imported asset name for a valid Workout Guide frame.
    func workoutGuideAssetName(frame: Int = 1) -> String? {
        guard let workoutGuideSlug else {
            return nil
        }

        let frameIndex = (1...3).contains(frame) ? frame : 1
        return "workout_guide_\(workoutGuideSlug.replacingOccurrences(of: "-", with: "_"))_frame_\(frameIndex)"
    }

    private static let legacyWorkoutGuideSlugs: [String: String] = [
        "bicepCurl": "bicep-curl",
        "divergingRow": "machine-row",
        "legCurl": "leg-curl",
        "legExtension": "leg-extension",
        "legs": "bodyweight-squat",
        "pullUps": "pull-up",
        "tricepPushDown": "tricep-pushdown",
        "abdominalCrunch": "weighted-crunch",
        "inclineChestPressSmith": "smith-machine-bench-press",
        "benchPress": "bench-press",
        "convergingChestPress": "machine-chest-press",
        "inclineChestPress": "incline-bench-press",
        "chestPress": "bench-press",
        "chestFly": "pec-deck",
        "dumbbellShoulderPress": "seated-dumbbell-press",
        "shoulderPressSmith": "machine-shoulder-press",
        "shoulderPress": "overhead-press",
        "cableLateralRaise": "cable-lateral-raise",
        "tricepsPushdown": "tricep-pushdown",
        "overheadTricepsExtension": "overhead-tricep-extension",
        "latPulldown": "lat-pulldown",
        "closeGripWeightedPullUp": "weighted-pull-up",
        "pullUp": "pull-up",
        "divergingSeatedRow": "machine-row",
        "seatedRow": "seated-row",
        "divergingLowerLatRow": "machine-row",
        "lowerLatRow": "machine-row",
        "rearDeltCable": "cable-rear-delt-fly",
        "bicepPreacherCurl": "preacher-curl",
        "bicepPreacherCurlMachine": "preacher-curl",
        "hackSquat": "hack-squat",
        "legPress": "leg-press",
        "quadExtension": "leg-extension",
        "seatedLegCurl": "seated-leg-curl",
        "standingCalfRaise": "standing-calf-raise",
        "hipAdduction": "hip-adduction-machine",
        "genericPush": "push-up",
        "genericPull": "pull-up",
        "genericLegs": "bodyweight-squat",
        "genericCore": "crunch",
        "genericMachine": "machine-chest-press",
        "genericDumbbell": "dumbbell-bench-press",
        "genericBarbell": "bench-press",
        "genericCable": "cable-fly",
        "genericExercise": "bodyweight-squat",
        "upperBody": "overhead-press",
        "programmeRotation": "bodyweight-squat"
    ]

    var fallbackSystemImage: String {
        switch self {
        case .abdominalCrunch, .genericCore:
            return "figure.core.training"
        case .benchPress, .bicepCurl, .bicepPreacherCurl, .bicepPreacherCurlMachine, .genericDumbbell, .genericBarbell:
            return "dumbbell.fill"
        case .latPulldown, .closeGripWeightedPullUp, .pullUp, .pullUps, .genericPull:
            return "figure.pull"
        case .standingCalfRaise:
            return "figure.walk"
        case .hackSquat, .legPress, .quadExtension, .legExtension, .seatedLegCurl, .legCurl, .hipAdduction, .legs, .genericLegs:
            return "figure.strengthtraining.traditional"
        case .genericMachine:
            return "rectangle.stack.fill"
        case .genericCable:
            return "point.3.connected.trianglepath.dotted"
        case .upperBody:
            return "figure.arms.open"
        case .programmeRotation:
            return "arrow.triangle.2.circlepath"
        case .genericPush, .inclineChestPressSmith, .inclineChestPress, .convergingChestPress, .chestPress, .chestFly, .dumbbellShoulderPress, .shoulderPressSmith, .shoulderPress, .cableLateralRaise, .tricepsPushdown, .tricepPushDown, .overheadTricepsExtension, .divergingRow, .divergingSeatedRow, .seatedRow, .divergingLowerLatRow, .lowerLatRow, .rearDeltCable, .genericExercise:
            return "figure.strengthtraining.traditional"
        default:
            return "figure.strengthtraining.traditional"
        }
    }

    var accessibilityName: String {
        if rawValue.hasPrefix("guide_"), let workoutGuideSlug {
            return workoutGuideSlug.replacingOccurrences(of: "-", with: " ").capitalized
        }
        return rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }
}
