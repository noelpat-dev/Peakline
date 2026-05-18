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

    var assetName: String {
        switch self {
        case .bicepCurl, .bicepPreacherCurl, .bicepPreacherCurlMachine:
            return "icon_exercise_bicep_curl"
        case .chestFly:
            return "icon_exercise_chest_fly"
        case .divergingRow, .divergingSeatedRow, .divergingLowerLatRow, .lowerLatRow, .rearDeltCable, .seatedRow:
            return "icon_exercise_diverging_row"
        case .dumbbellShoulderPress, .shoulderPressSmith, .shoulderPress:
            return "icon_exercise_dumbbell_shoulder_press"
        case .hackSquat:
            return "icon_exercise_hack_squat"
        case .hipAdduction:
            return "icon_exercise_hip_adduction"
        case .inclineChestPress, .inclineChestPressSmith, .benchPress, .convergingChestPress, .chestPress:
            return "icon_exercise_incline_chest_press"
        case .latPulldown:
            return "icon_exercise_lat_pulldown"
        case .legCurl, .seatedLegCurl:
            return "icon_exercise_leg_curl"
        case .legExtension, .quadExtension:
            return "icon_exercise_leg_extension"
        case .legPress:
            return "icon_exercise_leg_press"
        case .legs, .genericLegs:
            return "icon_exercise_legs"
        case .pullUps, .closeGripWeightedPullUp, .pullUp:
            return "icon_exercise_pull_ups"
        case .standingCalfRaise:
            return "icon_exercise_standing_calf_raise"
        case .tricepPushDown, .tricepsPushdown, .overheadTricepsExtension:
            return "icon_exercise_tricep_push_down"
        case .abdominalCrunch, .cableLateralRaise, .genericPush, .genericPull, .genericCore, .genericMachine, .genericDumbbell, .genericBarbell, .genericCable, .genericExercise:
            return "icon_exercise_\(rawValue.snakeCased)"
        }
    }

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
        case .genericPush, .inclineChestPressSmith, .inclineChestPress, .convergingChestPress, .chestPress, .chestFly, .dumbbellShoulderPress, .shoulderPressSmith, .shoulderPress, .cableLateralRaise, .tricepsPushdown, .tricepPushDown, .overheadTricepsExtension, .divergingRow, .divergingSeatedRow, .seatedRow, .divergingLowerLatRow, .lowerLatRow, .rearDeltCable, .genericExercise:
            return "figure.strengthtraining.traditional"
        }
    }

    var accessibilityName: String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }
}

private extension String {
    var snakeCased: String {
        replacingOccurrences(of: "([a-z])([A-Z])", with: "$1_$2", options: .regularExpression)
            .lowercased()
    }
}
