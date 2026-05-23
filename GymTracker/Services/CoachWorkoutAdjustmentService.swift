import Foundation

struct CoachWorkoutAdjustmentService {
    func recommendations(
        for snapshot: CoachIntelligenceSnapshot,
        plannedExercises: [PlannedWorkoutExercise],
        plannedMuscleFatigue: [MuscleGroupFatigue],
        calibration: CoachCalibrationContext = .empty
    ) -> [CoachWorkoutActionRecommendation] {
        let suggestedActions = suggestedActionSet(
            for: snapshot,
            plannedMuscleFatigue: plannedMuscleFatigue,
            calibration: calibration
        )

        return CoachWorkoutAdjustmentAction.allCases.compactMap { action in
            if action == .deloadStyleSession, !deloadPlannerIsUseful(for: snapshot.fatigueRisk) {
                return nil
            }
            let baseConfidence = confidence(for: action, snapshot: snapshot)
            let calibrationResult = calibratedRecommendation(
                action: action,
                baseConfidence: baseConfidence,
                calibration: calibration
            )
            let summary = recommendationSummary(
                for: action,
                snapshot: snapshot,
                plannedExercises: plannedExercises,
                preferences: calibration.preferences,
                splitMetadata: calibration.splitMetadata
            )

            return CoachWorkoutActionRecommendation(
                action: action,
                title: action.displayName,
                summary: [summary, calibrationResult.summarySuffix].compactMap { $0 }.joined(separator: " "),
                isCoachSuggested: suggestedActions.contains(action),
                confidence: calibrationResult.confidence,
                calibrationNote: calibrationResult.reason
            )
        }
    }

    func makePreview(
        action: CoachWorkoutAdjustmentAction,
        plannedExercises: [PlannedWorkoutExercise],
        snapshot: CoachIntelligenceSnapshot,
        exercises: [Exercise],
        plannedMuscleFatigue: [MuscleGroupFatigue],
        deloadPlan: ManualDeloadPlan? = nil,
        splitName: String? = nil,
        exerciseMetadata: [CoachExerciseMetadata] = []
    ) -> CoachWorkoutAdjustmentPreview {
        makePreview(
            action: action,
            plannedExercises: plannedExercises,
            snapshot: snapshot,
            exercises: exercises,
            plannedMuscleFatigue: plannedMuscleFatigue,
            deloadPlan: deloadPlan,
            splitName: splitName,
            exerciseMetadata: exerciseMetadata,
            preferences: .default,
            splitMetadata: nil
        )
    }

    func makePreview(
        action: CoachWorkoutAdjustmentAction,
        plannedExercises: [PlannedWorkoutExercise],
        snapshot: CoachIntelligenceSnapshot,
        exercises: [Exercise],
        plannedMuscleFatigue: [MuscleGroupFatigue],
        deloadPlan: ManualDeloadPlan? = nil,
        splitName: String? = nil,
        exerciseMetadata: [CoachExerciseMetadata] = [],
        preferences: CoachPreferencesSnapshot,
        splitMetadata: CoachSplitMetadataSnapshot?
    ) -> CoachWorkoutAdjustmentPreview {
        let adjustedExercises = adjustedPlan(
            action: action,
            plannedExercises: plannedExercises,
            exercises: exercises,
            deloadPlan: deloadPlan,
            splitName: splitName,
            exerciseMetadata: exerciseMetadata,
            preferences: preferences,
            splitMetadata: splitMetadata
        )
        let exerciseAdjustments = zip(plannedExercises, adjustedExercises).map { before, after in
            CoachWorkoutExerciseAdjustment(
                plannedExerciseId: before.id,
                exerciseId: before.exerciseId,
                name: before.exerciseNameSnapshot,
                beforeSets: before.targetSets,
                afterSets: after.targetSets,
                beforeNotes: before.notes,
                afterNotes: after.notes,
                reason: adjustmentReason(action: action, before: before, after: after, deloadPlan: deloadPlan)
            )
        }
        let beforeTotalSets = plannedExercises.reduce(0) { $0 + $1.targetSets }
        let afterTotalSets = adjustedExercises.reduce(0) { $0 + $1.targetSets }
        let changedCount = exerciseAdjustments.filter(\.changed).count
        let metadataSignals = classificationDiagnostics(
            plannedExercises: plannedExercises,
            exercises: exercises,
            splitName: splitName,
            exerciseMetadata: exerciseMetadata,
            splitMetadata: splitMetadata
        )

        return CoachWorkoutAdjustmentPreview(
            id: previewID(action: action, deloadPlan: deloadPlan),
            action: action,
            deloadPlan: deloadPlan,
            title: previewTitle(action: action, deloadPlan: deloadPlan),
            summary: previewSummary(
                action: action,
                snapshot: snapshot,
                changedCount: changedCount,
                beforeTotalSets: beforeTotalSets,
                afterTotalSets: afterTotalSets,
                deloadPlan: deloadPlan
            ),
            confidence: confidence(for: action, snapshot: snapshot),
            whySuggested: whySuggested(action: action, snapshot: snapshot, plannedMuscleFatigue: plannedMuscleFatigue, deloadPlan: deloadPlan),
            contributingSignals: Array(
                (
                    contributingSignals(from: snapshot, plannedMuscleFatigue: plannedMuscleFatigue)
                        + preferenceDiagnostics(preferences: preferences, splitMetadata: splitMetadata)
                        + metadataSignals
                ).prefix(8)
            ),
            changes: changes(action: action, changedCount: changedCount, beforeTotalSets: beforeTotalSets, afterTotalSets: afterTotalSets, deloadPlan: deloadPlan),
            unchanged: unchanged(action: action),
            beforeExerciseCount: plannedExercises.count,
            afterExerciseCount: adjustedExercises.count,
            beforeTotalSets: beforeTotalSets,
            afterTotalSets: afterTotalSets,
            exerciseAdjustments: exerciseAdjustments,
            adjustedExercises: adjustedExercises
        )
    }

    func defaultDeloadPlan(for risk: CoachFatigueRisk) -> ManualDeloadPlan {
        ManualDeloadPlan(
            duration: risk.level == .deloadWatch ? .sevenDays : .fiveDays,
            volumeReduction: risk.level == .deloadWatch ? .fortyPercent : .twentyFivePercent,
            focus: .maintainFrequency
        )
    }

    func deloadPlannerIsUseful(for risk: CoachFatigueRisk) -> Bool {
        risk.level == .high || risk.level == .deloadWatch
    }

    func editableDraft(from preview: CoachWorkoutAdjustmentPreview) -> EditableCoachWorkoutAdjustmentDraft {
        EditableCoachWorkoutAdjustmentDraft(
            basePreview: preview,
            exerciseAdjustments: preview.exerciseAdjustments.map { adjustment in
                EditableCoachWorkoutExerciseAdjustment(
                    id: adjustment.id,
                    exerciseId: adjustment.exerciseId,
                    name: adjustment.name,
                    beforeSets: adjustment.beforeSets,
                    suggestedSets: adjustment.afterSets,
                    beforeNotes: adjustment.beforeNotes,
                    suggestedNotes: adjustment.afterNotes,
                    reason: adjustment.reason,
                    editedSets: adjustment.afterSets,
                    editedNotes: adjustment.afterNotes ?? ""
                )
            }
        )
    }

    func resetAdjustment(
        exerciseId: UUID,
        in draft: EditableCoachWorkoutAdjustmentDraft
    ) -> EditableCoachWorkoutAdjustmentDraft {
        var updated = draft
        guard let index = updated.exerciseAdjustments.firstIndex(where: { $0.id == exerciseId }) else {
            return updated
        }
        updated.exerciseAdjustments[index].editedSets = updated.exerciseAdjustments[index].beforeSets
        updated.exerciseAdjustments[index].editedNotes = updated.exerciseAdjustments[index].beforeNotes ?? ""
        return updated
    }

    func resetAllAdjustments(
        in draft: EditableCoachWorkoutAdjustmentDraft
    ) -> EditableCoachWorkoutAdjustmentDraft {
        var updated = draft
        updated.exerciseAdjustments = updated.exerciseAdjustments.map { adjustment in
            var copy = adjustment
            copy.editedSets = adjustment.beforeSets
            copy.editedNotes = adjustment.beforeNotes ?? ""
            return copy
        }
        return updated
    }

    func makePreview(from draft: EditableCoachWorkoutAdjustmentDraft) -> CoachWorkoutAdjustmentPreview {
        let base = draft.basePreview
        let editsById = Dictionary(uniqueKeysWithValues: draft.exerciseAdjustments.map { ($0.id, $0) })
        let adjustedExercises = base.adjustedExercises.map { exercise in
            guard let edit = editsById[exercise.id] else { return exercise }
            return PlannedWorkoutExercise(
                id: exercise.id,
                exerciseId: exercise.exerciseId,
                name: exercise.name,
                targetSets: edit.editedSets,
                minReps: exercise.minReps,
                maxReps: exercise.maxReps,
                notes: edit.editedNotesValue
            )
        }
        let exerciseAdjustments = draft.exerciseAdjustments.map { edit in
            CoachWorkoutExerciseAdjustment(
                plannedExerciseId: edit.id,
                exerciseId: edit.exerciseId,
                name: edit.name,
                beforeSets: edit.beforeSets,
                afterSets: edit.editedSets,
                beforeNotes: edit.beforeNotes,
                afterNotes: edit.editedNotesValue,
                reason: editedAdjustmentReason(edit)
            )
        }
        let afterTotalSets = adjustedExercises.reduce(0) { $0 + $1.targetSets }
        let changedCount = exerciseAdjustments.filter(\.changed).count
        let changes: [String]

        if changedCount == 0 {
            changes = ["All exercise adjustments are reset to the original plan."]
        } else if draft.hasUserEdits {
            changes = ["User-edited targets are ready for this preview.", "\(changedCount) exercises differ from the original plan."]
        } else {
            changes = base.changes
        }

        return CoachWorkoutAdjustmentPreview(
            id: base.id,
            action: base.action,
            deloadPlan: base.deloadPlan,
            title: base.title,
            summary: editedPreviewSummary(base: base, changedCount: changedCount, afterTotalSets: afterTotalSets, hasUserEdits: draft.hasUserEdits),
            confidence: base.confidence,
            whySuggested: base.whySuggested,
            contributingSignals: base.contributingSignals,
            changes: changes,
            unchanged: base.unchanged,
            beforeExerciseCount: base.beforeExerciseCount,
            afterExerciseCount: adjustedExercises.count,
            beforeTotalSets: base.beforeTotalSets,
            afterTotalSets: afterTotalSets,
            exerciseAdjustments: exerciseAdjustments,
            adjustedExercises: adjustedExercises
        )
    }

    private func adjustedPlan(
        action: CoachWorkoutAdjustmentAction,
        plannedExercises: [PlannedWorkoutExercise],
        exercises: [Exercise],
        deloadPlan: ManualDeloadPlan?,
        splitName: String?,
        exerciseMetadata: [CoachExerciseMetadata],
        preferences: CoachPreferencesSnapshot,
        splitMetadata: CoachSplitMetadataSnapshot?
    ) -> [PlannedWorkoutExercise] {
        let exerciseLookup = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let metadataLookup = Dictionary(exerciseMetadata.map { ($0.exerciseId, $0) }, uniquingKeysWith: { first, _ in first })
        let protectCompounds = preferences.reductionPreference == .protectPriorityLifts
            || splitMetadata?.protectCompounds == true
            || splitMetadata?.preferredAdjustmentStyle == .protectMainLifts
        let reduceAccessoriesFirst = preferences.reductionPreference == .reduceAccessoriesFirst
            || splitMetadata?.accessoriesFlexible == true
            || splitMetadata?.preferredAdjustmentStyle == .reduceAccessoriesFirst
        let evenReduction = preferences.reductionPreference == .reduceTotalVolumeEvenly
            || splitMetadata?.preferredAdjustmentStyle == .reduceVolumeEvenly

        return plannedExercises.enumerated().map { index, exercise in
            let metadata = exerciseLookup[exercise.exerciseId]
            let classification = classify(
                exercise: exercise,
                index: index,
                metadata: metadata,
                coachMetadata: metadataLookup[exercise.exerciseId],
                splitName: splitName
            )
            let shouldTrimAsAccessory = classification.role.receivesAccessoryReduction
            let isProtectedCompound = protectCompounds && isProtectedLift(classification.role)
            let adjustedSets: Int
            let note: String?

            switch action {
            case .keepPlan:
                adjustedSets = exercise.targetSets
                note = exercise.notes
            case .reduceAccessories:
                let reduction = shouldTrimAsAccessory ? (reduceAccessoriesFirst ? 1 : 1) : 0
                adjustedSets = adjustedAccessorySets(
                    from: exercise.targetSets,
                    classification: classification,
                    defaultReduction: reduction
                )
                note = shouldTrimAsAccessory ? appendedNote("Coach action: one accessory set trimmed for today.", to: exercise.notes) : exercise.notes
            case .reduceTotalVolume:
                adjustedSets = isProtectedCompound
                    ? exercise.targetSets
                    : evenReduction
                    ? max(1, exercise.targetSets - 1)
                    : classification.role == .priorityLift
                    ? max(1, exercise.targetSets - 1)
                    : reducedSets(from: exercise.targetSets, multiplier: 0.75)
                note = isProtectedCompound
                    ? appendedNote("Coach action: priority lift protected by your coach settings.", to: exercise.notes)
                    : appendedNote("Coach action: total volume reduced for today.", to: exercise.notes)
            case .techniqueFocus:
                adjustedSets = exercise.targetSets
                note = appendedNote("Coach action: technique focus. Keep reps clean and leave 2 reps in reserve.", to: exercise.notes)
            case .avoidPRAttempts:
                adjustedSets = exercise.targetSets
                note = appendedNote("Coach action: avoid PR attempts. Repeat known loads and stop before form breaks down.", to: exercise.notes)
            case .recoveryFocusedSession:
                adjustedSets = isProtectedCompound ? exercise.targetSets : max(1, exercise.targetSets - 1)
                note = isProtectedCompound
                    ? appendedNote("Coach action: priority lift protected; keep effort easy.", to: exercise.notes)
                    : appendedNote("Coach action: recovery focus. Keep effort easy and treat accessories as optional.", to: exercise.notes)
            case .deloadStyleSession:
                let plan = deloadPlan ?? ManualDeloadPlan(duration: .fiveDays, volumeReduction: .twentyFivePercent, focus: .maintainFrequency)
                adjustedSets = isProtectedCompound && plan.focus != .techniqueOnly
                    ? max(1, exercise.targetSets - 1)
                    : classification.role == .priorityLift
                    ? max(1, exercise.targetSets - 1)
                    : plan.focus == .techniqueOnly
                    ? min(2, max(1, exercise.targetSets - 1))
                    : reducedSets(from: exercise.targetSets, multiplier: plan.volumeReduction.multiplier)
                note = appendedNote("Coach action: \(plan.title.lowercased()). \(plan.summary)", to: exercise.notes)
            }

            return PlannedWorkoutExercise(
                id: exercise.id,
                exerciseId: exercise.exerciseId,
                name: exercise.name,
                targetSets: adjustedSets,
                minReps: exercise.minReps,
                maxReps: exercise.maxReps,
                notes: note
            )
        }
    }

    private func classificationDiagnostics(
        plannedExercises: [PlannedWorkoutExercise],
        exercises: [Exercise],
        splitName: String?,
        exerciseMetadata: [CoachExerciseMetadata],
        splitMetadata: CoachSplitMetadataSnapshot?
    ) -> [String] {
        let exerciseLookup = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let metadataLookup = Dictionary(exerciseMetadata.map { ($0.exerciseId, $0) }, uniquingKeysWith: { first, _ in first })

        var diagnostics = plannedExercises.enumerated().prefix(4).map { index, exercise in
            let classification = classify(
                exercise: exercise,
                index: index,
                metadata: exerciseLookup[exercise.exerciseId],
                coachMetadata: metadataLookup[exercise.exerciseId],
                splitName: splitName
            )
            return "\(exercise.exerciseNameSnapshot): \(classification.source.displayName), \(classification.role.displayName)"
        }

        if let splitMetadata {
            diagnostics.append("\(splitMetadata.splitName): \(splitMetadata.primaryGoal.displayName) intent, \(splitMetadata.expectedFatigue.displayName.lowercased()) expected fatigue.")
        }

        return diagnostics
    }

    private func suggestedActionSet(
        for snapshot: CoachIntelligenceSnapshot,
        plannedMuscleFatigue: [MuscleGroupFatigue],
        calibration: CoachCalibrationContext
    ) -> Set<CoachWorkoutAdjustmentAction> {
        var actions: Set<CoachWorkoutAdjustmentAction> = [.keepPlan]
        let hasLocalFatigue = plannedMuscleFatigue.contains { $0.state == .loaded || $0.state == .fatigued }
        let preferences = calibration.preferences
        let splitMetadata = calibration.splitMetadata

        if snapshot.readiness.confidence == .low, snapshot.fatigueRisk.confidence == .low {
            actions.insert(.techniqueFocus)
            return actions
        }

        switch snapshot.adaptiveGuidance.mode {
        case .push:
            actions.insert(.keepPlan)
        case .maintain:
            actions.insert(.techniqueFocus)
        case .reduce:
            actions.formUnion([.reduceAccessories, .techniqueFocus, .avoidPRAttempts])
        case .recoveryFocus:
            actions.formUnion([.recoveryFocusedSession, .avoidPRAttempts, .reduceTotalVolume])
        }

        if hasLocalFatigue {
            actions.formUnion([.reduceAccessories, .avoidPRAttempts])
        }

        if snapshot.fatigueRisk.level == .high {
            actions.formUnion([.reduceTotalVolume, .deloadStyleSession])
        } else if snapshot.fatigueRisk.level == .deloadWatch {
            actions.formUnion([.recoveryFocusedSession, .deloadStyleSession])
        }

        if splitMetadata?.expectedFatigue == .high {
            actions.formUnion([.reduceAccessories, .avoidPRAttempts])
        }

        if splitMetadata?.primaryGoal == .recovery || splitMetadata?.primaryGoal == .technique {
            actions.formUnion([.techniqueFocus, .avoidPRAttempts])
            actions.remove(.reduceTotalVolume)
        }

        switch preferences.recommendationFrequency {
        case .minimal:
            actions = actions.filter { action in
                action == .keepPlan
                    || action == .techniqueFocus
                    || (snapshot.fatigueRisk.level == .high || snapshot.fatigueRisk.level == .deloadWatch) && action == .deloadStyleSession
            }
        case .standard:
            break
        case .proactive:
            if snapshot.adaptiveGuidance.mode == .maintain {
                actions.insert(.reduceAccessories)
            }
            if hasLocalFatigue {
                actions.insert(.techniqueFocus)
            }
        }

        return actions
    }

    private func confidence(for action: CoachWorkoutAdjustmentAction, snapshot: CoachIntelligenceSnapshot) -> ReadinessConfidence {
        switch action {
        case .keepPlan, .techniqueFocus, .avoidPRAttempts:
            return snapshot.readiness.confidence
        case .reduceAccessories, .reduceTotalVolume, .recoveryFocusedSession, .deloadStyleSession:
            return snapshot.fatigueRisk.confidence
        }
    }

    func calibratedRecommendation(
        action: CoachWorkoutAdjustmentAction,
        baseConfidence: ReadinessConfidence,
        calibration: CoachCalibrationContext
    ) -> CoachCalibrationResult {
        let relevantFeedback = calibration.recentFeedback.filter { $0.action == nil || $0.action == action }
        let tooConservativeCount = relevantFeedback.filter { $0.tags.contains(.tooConservative) }.count
        let tooAggressiveCount = relevantFeedback.filter { $0.tags.contains(.tooAggressive) || $0.tags.contains(.preferredRecovery) }.count
        let inaccurateCount = relevantFeedback.filter { $0.tags.contains(.feltInaccurate) || $0.tags.contains(.notHelpful) }.count
        let deloadCancelledCount = calibration.actionHistory.filter {
            $0.action == .deloadStyleSession && ($0.outcome == .cancelled || $0.outcome == .bypassed)
        }.count

        var suffix: String?
        var confidence = baseConfidence
        var reasons: [String] = []

        if action == .deloadStyleSession, deloadCancelledCount >= 2 {
            suffix = "You have skipped similar deload prompts before, so treat this as a review step unless fatigue is clearly high."
            reasons.append("Recent deload guidance was often cancelled or bypassed.")
            confidence = lowered(confidence)
        } else if tooConservativeCount > tooAggressiveCount, action == .reduceAccessories || action == .reduceTotalVolume {
            suffix = "Recent feedback says these trims can feel conservative, so keep the main work honest if warm-ups feel strong."
            reasons.append("Feedback marked similar guidance too conservative.")
        } else if tooAggressiveCount > tooConservativeCount {
            suffix = "Recent feedback says softer recovery wording fits better, so keep this optional and adjust after warm-ups."
            reasons.append("Feedback marked similar guidance too aggressive or recovery-preferred.")
            confidence = lowered(confidence)
        }

        if inaccurateCount >= 2 {
            confidence = lowered(confidence)
            reasons.append("Recent feedback marked coach guidance inaccurate or unhelpful.")
        }

        if action == .keepPlan, calibration.activeDeloadBlocks.isEmpty == false {
            suffix = "An active deload block is saved, so keep effort lower even if you keep the plan."
            reasons.append("Active saved deload block is influencing wording.")
        }

        switch calibration.preferences.aggressiveness {
        case .conservative:
            if action == .reduceAccessories || action == .reduceTotalVolume || action == .recoveryFocusedSession || action == .deloadStyleSession {
                confidence = lowered(confidence)
                suffix = [suffix, "Your conservative coach setting keeps this as a softer option."].compactMap { $0 }.joined(separator: " ")
                reasons.append("Coach aggressiveness preference is conservative.")
            }
        case .balanced:
            break
        case .assertive:
            if tooAggressiveCount == 0, action == .reduceAccessories || action == .reduceTotalVolume {
                suffix = [suffix, "Your assertive coach setting keeps the adjustment practical but decisive."].compactMap { $0 }.joined(separator: " ")
                reasons.append("Coach aggressiveness preference is assertive.")
            }
        }

        if action == .deloadStyleSession {
            switch calibration.preferences.deloadWording {
            case .gentle:
                suffix = [suffix, "Deload wording is gentle by preference."].compactMap { $0 }.joined(separator: " ")
                reasons.append("Deload wording preference is gentle.")
            case .direct:
                suffix = [suffix, "Deload wording is direct by preference."].compactMap { $0 }.joined(separator: " ")
                reasons.append("Deload wording preference is direct.")
            case .minimal:
                suffix = [suffix, "Deload wording is kept minimal by preference."].compactMap { $0 }.joined(separator: " ")
                reasons.append("Deload wording preference is minimal.")
            }
        }

        if let splitMetadata = calibration.splitMetadata {
            if splitMetadata.priority == .high, action == .reduceTotalVolume {
                confidence = lowered(confidence)
                suffix = [suffix, "\(splitMetadata.splitName) is marked high priority, so review reductions before applying."].compactMap { $0 }.joined(separator: " ")
                reasons.append("Split metadata marks the workout as high priority.")
            }

            if splitMetadata.expectedFatigue == .high, action == .reduceAccessories {
                suffix = [suffix, "This split is expected to run fatiguing, so accessory trimming is favored first."].compactMap { $0 }.joined(separator: " ")
                reasons.append("Split metadata marks expected fatigue high.")
            }
        }

        return CoachCalibrationResult(
            summarySuffix: suffix,
            confidence: confidence,
            reason: reasons.isEmpty ? nil : reasons.joined(separator: " ")
        )
    }

    private func recommendationSummary(
        for action: CoachWorkoutAdjustmentAction,
        snapshot: CoachIntelligenceSnapshot,
        plannedExercises: [PlannedWorkoutExercise],
        preferences: CoachPreferencesSnapshot,
        splitMetadata: CoachSplitMetadataSnapshot?
    ) -> String {
        switch action {
        case .keepPlan:
            if preferences.trainingPriority == .consistency {
                return "Preserve the planned rhythm and keep effort honest."
            }
            return snapshot.adaptiveGuidance.mode == .push ? "Good default when warm-ups feel normal." : "Preserve the planned session."
        case .reduceAccessories:
            if splitMetadata?.accessoriesFlexible == true || preferences.reductionPreference == .reduceAccessoriesFirst {
                return "Trim flexible accessory work while protecting the main lifts."
            }
            return "Trim accessory work while keeping main lifts."
        case .reduceTotalVolume:
            let setCount = plannedExercises.reduce(0) { $0 + $1.targetSets }
            if preferences.reductionPreference == .protectPriorityLifts {
                return "Lower today's \(setCount) sets mostly away from priority work."
            }
            return "Lower today's total set count from \(setCount) sets."
        case .techniqueFocus:
            return preferences.trainingPriority == .strength
                ? "Keep the main lifts, but make clean repeatable reps the goal."
                : "Keep exercises, but shift effort toward cleaner reps."
        case .avoidPRAttempts:
            return "Keep the plan and repeat known loads."
        case .recoveryFocusedSession:
            return "Lower stress while still training the pattern."
        case .deloadStyleSession:
            return "Optional lighter plan when fatigue signs are elevated."
        }
    }

    private func previewTitle(action: CoachWorkoutAdjustmentAction, deloadPlan: ManualDeloadPlan?) -> String {
        if let deloadPlan {
            return "\(deloadPlan.title): \(action.displayName)"
        }
        return action.displayName
    }

    private func previewSummary(
        action: CoachWorkoutAdjustmentAction,
        snapshot: CoachIntelligenceSnapshot,
        changedCount: Int,
        beforeTotalSets: Int,
        afterTotalSets: Int,
        deloadPlan: ManualDeloadPlan?
    ) -> String {
        if action == .keepPlan {
            return "No workout changes will be applied. You can start the original plan as written."
        }

        if let deloadPlan {
            return "\(deloadPlan.summary) This applies to the current workout preview only."
        }

        let delta = max(0, beforeTotalSets - afterTotalSets)
        if delta > 0 {
            return "\(changedCount) exercises change and \(delta) sets are removed from today's preview."
        }

        return "\(changedCount) exercises receive coaching notes while sets stay the same."
    }

    private func whySuggested(
        action: CoachWorkoutAdjustmentAction,
        snapshot: CoachIntelligenceSnapshot,
        plannedMuscleFatigue: [MuscleGroupFatigue],
        deloadPlan: ManualDeloadPlan?
    ) -> String {
        if action == .keepPlan {
            return "Keeping the plan is safe when you want the original workout and will monitor warm-ups yourself."
        }

        if action == .deloadStyleSession {
            return "\(snapshot.fatigueRisk.title). \(deloadPlan?.summary ?? snapshot.fatigueRisk.recommendedAction)"
        }

        if let fatigued = plannedMuscleFatigue.first(where: { $0.state == .fatigued }) {
            return "\(fatigued.muscleGroup.displayName) fatigue is elevated, so a more controlled session is reasonable."
        }

        return snapshot.adaptiveGuidance.summary
    }

    private func contributingSignals(
        from snapshot: CoachIntelligenceSnapshot,
        plannedMuscleFatigue: [MuscleGroupFatigue]
    ) -> [String] {
        var signals = snapshot.readiness.topFactors.map { "\($0.kind.displayName): \($0.title)" }
        signals.append(contentsOf: snapshot.fatigueRisk.factors.prefix(3))
        signals.append(contentsOf: plannedMuscleFatigue
            .filter { $0.state == .loaded || $0.state == .fatigued }
            .prefix(2)
            .map { "\($0.muscleGroup.displayName): \($0.detail)" })

        return Array(signals.prefix(6))
    }

    private func preferenceDiagnostics(
        preferences: CoachPreferencesSnapshot,
        splitMetadata: CoachSplitMetadataSnapshot?
    ) -> [String] {
        var diagnostics = [
            "Coach preference: \(preferences.aggressiveness.displayName), \(preferences.reductionPreference.displayName.lowercased())."
        ]

        if let splitMetadata {
            diagnostics.append("Split intent: \(splitMetadata.primaryGoal.displayName), \(splitMetadata.preferredAdjustmentStyle.displayName.lowercased()).")
        }

        return diagnostics
    }

    private func changes(
        action: CoachWorkoutAdjustmentAction,
        changedCount: Int,
        beforeTotalSets: Int,
        afterTotalSets: Int,
        deloadPlan: ManualDeloadPlan?
    ) -> [String] {
        switch action {
        case .keepPlan:
            return ["No sets, exercises, or notes change."]
        case .reduceAccessories:
            return ["Accessory exercises lose one set where possible.", "Main lifts stay in the workout."]
        case .reduceTotalVolume:
            return ["Total working sets move from \(beforeTotalSets) to \(afterTotalSets).", "\(changedCount) exercises are adjusted."]
        case .techniqueFocus:
            return ["Coach notes add a technique focus.", "Set counts stay unchanged."]
        case .avoidPRAttempts:
            return ["Coach notes remind you to repeat known loads.", "No PR-oriented target is forced."]
        case .recoveryFocusedSession:
            return ["Each exercise loses up to one set.", "Effort shifts toward easy, controlled work."]
        case .deloadStyleSession:
            let planText = deloadPlan?.summary ?? "Volume is reduced for a lighter session."
            return [planText, "This only adjusts today's preview."]
        }
    }

    private func unchanged(action: CoachWorkoutAdjustmentAction) -> [String] {
        switch action {
        case .keepPlan:
            return ["Original split template", "Current exercise order", "Target rep ranges"]
        case .reduceAccessories, .reduceTotalVolume, .recoveryFocusedSession, .deloadStyleSession:
            return ["Original split template", "Exercise order", "Target rep ranges"]
        case .techniqueFocus, .avoidPRAttempts:
            return ["Original split template", "Exercise order", "Set counts", "Target rep ranges"]
        }
    }

    private func adjustmentReason(
        action: CoachWorkoutAdjustmentAction,
        before: PlannedWorkoutExercise,
        after: PlannedWorkoutExercise,
        deloadPlan: ManualDeloadPlan?
    ) -> String {
        if before.targetSets != after.targetSets {
            return "\(before.targetSets) to \(after.targetSets) sets"
        }

        if before.notes != after.notes {
            return "Coach note added"
        }

        if action == .deloadStyleSession, let deloadPlan {
            return deloadPlan.summary
        }

        return "No change"
    }

    private func previewID(action: CoachWorkoutAdjustmentAction, deloadPlan: ManualDeloadPlan?) -> String {
        if let deloadPlan {
            return "\(action.rawValue)-\(deloadPlan.duration.rawValue)-\(deloadPlan.volumeReduction.rawValue)-\(deloadPlan.focus.rawValue)"
        }
        return action.rawValue
    }

    func classify(
        exercise: PlannedWorkoutExercise,
        index: Int,
        metadata: Exercise?,
        coachMetadata: CoachExerciseMetadata? = nil,
        splitName: String? = nil
    ) -> CoachExerciseClassification {
        let lowerName = exercise.exerciseNameSnapshot.lowercased()
        let splitContext = splitContext(from: splitName)

        if let coachMetadata {
            let role = roleFromUserMetadata(coachMetadata, index: index, splitContext: splitContext)
            return CoachExerciseClassification(
                role: role,
                reason: userMetadataReason(coachMetadata),
                source: .userMetadata
            )
        }

        if isWarmUpOrLowPriorityName(lowerName) || isWarmUpOrLowPriorityNote(exercise.notes) {
            return CoachExerciseClassification(
                role: .warmUpOrLowPriority,
                reason: "Name or note marks it as warm-up or optional work.",
                source: .fallbackName
            )
        }

        if let metadata {
            if metadata.movementPattern == .isolation || !metadata.isCompound {
                if index <= 1, splitContext.map({ groupMatchesContext(metadata.primaryMuscleGroup, context: $0) }) == true {
                    return CoachExerciseClassification(
                        role: .isolation,
                        reason: "Structured metadata marks an early isolation movement.",
                        source: .exerciseLibrary
                    )
                }
                return CoachExerciseClassification(
                    role: index >= 2 ? .accessory : .isolation,
                    reason: "Structured metadata marks a non-compound movement.",
                    source: .exerciseLibrary
                )
            }

            if let splitContext, groupMatchesContext(metadata.primaryMuscleGroup, context: splitContext), index <= 1 {
                return CoachExerciseClassification(
                    role: .primaryCompound,
                    reason: "Compound movement matches the split focus.",
                    source: .exerciseLibrary
                )
            }

            if metadata.isCompound {
                return CoachExerciseClassification(
                    role: index <= 1 ? .secondaryCompound : .accessory,
                    reason: "Structured metadata marks a compound movement outside the primary slot.",
                    source: .exerciseLibrary
                )
            }
        }

        if looksLikeIsolation(lowerName) {
            return CoachExerciseClassification(
                role: index >= 2 ? .accessory : .isolation,
                reason: "Conservative name fallback suggests isolation work.",
                source: .fallbackName
            )
        }

        if looksLikeCompound(lowerName) {
            return CoachExerciseClassification(
                role: index <= 1 ? .primaryCompound : .secondaryCompound,
                reason: "Conservative name fallback suggests a compound movement.",
                source: .fallbackName
            )
        }

        if index >= 2 {
            return CoachExerciseClassification(
                role: .accessory,
                reason: "Later exercise slot is treated as accessory when metadata is missing.",
                source: .fallbackSlot
            )
        }

        return CoachExerciseClassification(
            role: .secondaryCompound,
            reason: "Metadata is missing, so the early exercise is preserved conservatively.",
            source: .fallbackSlot
        )
    }

    private func editedPreviewSummary(
        base: CoachWorkoutAdjustmentPreview,
        changedCount: Int,
        afterTotalSets: Int,
        hasUserEdits: Bool
    ) -> String {
        if changedCount == 0 {
            return "All suggested changes are reset. Starting from this preview will keep the original plan."
        }

        if hasUserEdits {
            return "\(changedCount) exercises include user-reviewed targets. This applies to the current workout preview only."
        }

        return base.summary.replacingOccurrences(of: "\(base.afterTotalSets)", with: "\(afterTotalSets)")
    }

    private func editedAdjustmentReason(_ edit: EditableCoachWorkoutExerciseAdjustment) -> String {
        if !edit.changedFromOriginal {
            return "Reset to original"
        }

        if edit.beforeSets != edit.editedSets {
            return "\(edit.beforeSets) to \(edit.editedSets) sets"
        }

        if edit.beforeNotes != edit.editedNotesValue {
            return edit.changedFromSuggestion ? "Coach note edited" : "Coach note added"
        }

        return edit.reason
    }

    private func lowered(_ confidence: ReadinessConfidence) -> ReadinessConfidence {
        switch confidence {
        case .high:
            return .medium
        case .medium:
            return .low
        case .low:
            return .low
        }
    }

    private func roleFromUserMetadata(
        _ metadata: CoachExerciseMetadata,
        index: Int,
        splitContext: SplitContext?
    ) -> CoachExerciseRole {
        let effectiveSplitContext = self.splitContext(from: metadata.splitClassification) ?? splitContext

        if metadata.priority == .high || metadata.role == .priorityLift {
            return .priorityLift
        }

        if metadata.priority == .low || metadata.role == .warmUp {
            return .warmUpOrLowPriority
        }

        switch metadata.role {
        case .priorityLift:
            return .priorityLift
        case .compound:
            if let effectiveSplitContext, groupMatchesContext(metadata.primaryMuscleGroup, context: effectiveSplitContext), index <= 1 {
                return .primaryCompound
            }
            return index <= 1 ? .secondaryCompound : .accessory
        case .accessory:
            return .accessory
        case .isolation:
            return .isolation
        case .warmUp:
            return .warmUpOrLowPriority
        }
    }

    private func userMetadataReason(_ metadata: CoachExerciseMetadata) -> String {
        var parts = ["User metadata marks this as \(metadata.role.displayName.lowercased())."]
        if metadata.priority != .normal {
            parts.append("Priority is \(metadata.priority.displayName.lowercased()).")
        }
        if metadata.splitClassification != .unspecified {
            parts.append("Split context is \(metadata.splitClassification.displayName).")
        }
        return parts.joined(separator: " ")
    }

    private func adjustedAccessorySets(
        from sets: Int,
        classification: CoachExerciseClassification,
        defaultReduction: Int
    ) -> Int {
        guard defaultReduction > 0 else { return sets }
        if classification.role == .priorityLift {
            return sets
        }
        if classification.role == .warmUpOrLowPriority {
            return max(1, sets - 2)
        }
        return max(1, sets - defaultReduction)
    }

    private func isProtectedLift(_ role: CoachExerciseRole) -> Bool {
        switch role {
        case .priorityLift, .primaryCompound:
            return true
        case .secondaryCompound, .accessory, .isolation, .warmUpOrLowPriority:
            return false
        }
    }

    private enum SplitContext {
        case push
        case pull
        case legs
        case fullBody
    }

    private func splitContext(from splitName: String?) -> SplitContext? {
        guard let splitName else { return nil }
        let lower = splitName.lowercased()

        if lower.contains("push") || lower.contains("chest") || lower.contains("tricep") || lower.contains("shoulder") {
            return .push
        }
        if lower.contains("pull") || lower.contains("back") || lower.contains("bicep") {
            return .pull
        }
        if lower.contains("leg") || lower.contains("lower") || lower.contains("quad") || lower.contains("hamstring") {
            return .legs
        }
        if lower.contains("full") {
            return .fullBody
        }

        return nil
    }

    private func splitContext(from classification: CoachSplitClassification) -> SplitContext? {
        switch classification {
        case .push:
            return .push
        case .pull:
            return .pull
        case .legs:
            return .legs
        case .fullBody:
            return .fullBody
        case .unspecified:
            return nil
        }
    }

    private func groupMatchesContext(_ group: MuscleGroup, context: SplitContext) -> Bool {
        switch context {
        case .push:
            return [.chest, .shoulders, .triceps].contains(group)
        case .pull:
            return [.back, .biceps, .shoulders].contains(group)
        case .legs:
            return [.quads, .hamstrings, .glutes, .calves, .core].contains(group)
        case .fullBody:
            return true
        }
    }

    private func isWarmUpOrLowPriorityName(_ lowerName: String) -> Bool {
        lowerName.contains("warm-up")
            || lowerName.contains("warmup")
            || lowerName.contains("activation")
            || lowerName.contains("mobility")
            || lowerName.contains("optional")
    }

    private func isWarmUpOrLowPriorityNote(_ notes: String?) -> Bool {
        guard let notes else { return false }
        let lower = notes.lowercased()
        return lower.contains("warm-up")
            || lower.contains("warmup")
            || lower.contains("optional")
            || lower.contains("activation")
            || lower.contains("mobility")
    }

    private func looksLikeIsolation(_ lowerName: String) -> Bool {
        let markers = [
            "fly", "raise", "curl", "extension", "pushdown", "pressdown",
            "calf", "crunch", "adduction", "abduction", "rear delt"
        ]
        return markers.contains { lowerName.contains($0) }
    }

    private func looksLikeCompound(_ lowerName: String) -> Bool {
        let markers = [
            "bench", "press", "squat", "deadlift", "hinge", "row",
            "pulldown", "pull-up", "pull up", "leg press", "hack squat"
        ]
        return markers.contains { lowerName.contains($0) }
    }

    private func reducedSets(from sets: Int, multiplier: Double) -> Int {
        guard sets > 1 else { return 1 }
        let reduced = Int((Double(sets) * multiplier).rounded(.down))
        return max(1, min(sets - 1, reduced))
    }

    private func appendedNote(_ addition: String, to existing: String?) -> String {
        guard let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return addition
        }
        return "\(existing) \(addition)"
    }
}

struct CoachActionHistoryService {
    func makeEntry(
        preview: CoachWorkoutAdjustmentPreview,
        outcome: CoachActionHistoryOutcome,
        snapshot: CoachIntelligenceSnapshot,
        splitName: String?,
        date: Date = .now
    ) -> CoachActionHistoryEntry {
        CoachActionHistoryEntry(
            action: preview.action,
            outcome: outcome,
            createdAt: date,
            readinessCategory: snapshot.readiness.category,
            fatigueRiskLevel: snapshot.fatigueRisk.level,
            confidence: preview.confidence,
            shortReason: shortReason(for: preview, outcome: outcome),
            workoutName: splitName,
            splitName: splitName,
            beforeTotalSets: preview.beforeTotalSets,
            afterTotalSets: preview.afterTotalSets,
            contributingSignals: preview.contributingSignals,
            diagnosticSummary: preview.whySuggested
        )
    }

    private func shortReason(
        for preview: CoachWorkoutAdjustmentPreview,
        outcome: CoachActionHistoryOutcome
    ) -> String {
        switch outcome {
        case .applied:
            return preview.hasWorkoutChanges ? preview.summary : "Kept the original workout after preview."
        case .cancelled:
            return "Preview closed without changing the workout."
        case .reset:
            return "Applied coach changes were reset to the original plan."
        case .bypassed:
            return "Original plan was chosen while coach guidance was available."
        }
    }
}

struct CoachActionHistoryFilterService {
    func filter(
        _ entries: [CoachActionHistoryEntry],
        using filter: CoachActionHistoryFilter
    ) -> [CoachActionHistoryEntry] {
        entries.filter { entry in
            if let outcome = filter.outcome, entry.outcome != outcome {
                return false
            }
            if let action = filter.action, entry.action != action {
                return false
            }
            if let splitName = filter.splitName, (entry.splitName ?? "Unknown") != splitName {
                return false
            }
            if let readinessCategory = filter.readinessCategory, entry.readinessCategory != readinessCategory {
                return false
            }
            if let fatigueRiskLevel = filter.fatigueRiskLevel, entry.fatigueRiskLevel != fatigueRiskLevel {
                return false
            }
            return true
        }
    }
}

struct CoachExerciseMetadataService {
    func metadata(for exercise: Exercise, in metadata: [CoachExerciseMetadata]) -> CoachExerciseMetadata? {
        metadata.first { $0.exerciseId == exercise.id }
    }

    func makeMetadata(from draft: CoachExerciseMetadataDraft, exercise: Exercise) -> CoachExerciseMetadata {
        CoachExerciseMetadata(
            exerciseId: exercise.id,
            role: draft.role,
            primaryMuscleGroup: draft.primaryMuscleGroup,
            secondaryMuscleGroups: draft.secondaryMuscleGroups,
            movementPattern: draft.movementPattern,
            splitClassification: draft.splitClassification,
            priority: draft.priority,
            userNote: draft.userNote
        )
    }

    func update(_ metadata: CoachExerciseMetadata, from draft: CoachExerciseMetadataDraft) {
        metadata.update(
            role: draft.role,
            primaryMuscleGroup: draft.primaryMuscleGroup,
            secondaryMuscleGroups: draft.secondaryMuscleGroups,
            movementPattern: draft.movementPattern,
            splitClassification: draft.splitClassification,
            priority: draft.priority,
            userNote: draft.userNote
        )
    }
}

struct CoachPreferencesService {
    func snapshot(from preferences: [CoachPreferences]) -> CoachPreferencesSnapshot {
        preferences.sorted { $0.updatedAt > $1.updatedAt }.first?.snapshot ?? .default
    }

    func makePreferences(from snapshot: CoachPreferencesSnapshot = .default) -> CoachPreferences {
        CoachPreferences(
            aggressiveness: snapshot.aggressiveness,
            deloadWording: snapshot.deloadWording,
            detailLevel: snapshot.detailLevel,
            trainingPriority: snapshot.trainingPriority,
            reductionPreference: snapshot.reductionPreference,
            recommendationFrequency: snapshot.recommendationFrequency,
            showDiagnostics: snapshot.showDiagnostics
        )
    }

    func update(_ preferences: CoachPreferences, from snapshot: CoachPreferencesSnapshot) {
        preferences.update(from: snapshot)
    }
}

struct CoachSplitMetadataService {
    func metadata(for splitId: UUID, in metadata: [CoachSplitMetadata]) -> CoachSplitMetadata? {
        metadata.first { $0.splitId == splitId }
    }

    func snapshot(for split: TrainingSplit, metadata: [CoachSplitMetadata]) -> CoachSplitMetadataSnapshot {
        metadata.first { $0.splitId == split.id }?.snapshot
            ?? CoachSplitMetadataSnapshot.defaultFor(splitId: split.id, splitName: split.name)
    }

    func makeMetadata(from snapshot: CoachSplitMetadataSnapshot) -> CoachSplitMetadata {
        CoachSplitMetadata(
            splitId: snapshot.splitId,
            splitName: snapshot.splitName,
            priority: snapshot.priority,
            plannedIntensity: snapshot.plannedIntensity,
            primaryGoal: snapshot.primaryGoal,
            expectedFatigue: snapshot.expectedFatigue,
            protectCompounds: snapshot.protectCompounds,
            accessoriesFlexible: snapshot.accessoriesFlexible,
            preferredAdjustmentStyle: snapshot.preferredAdjustmentStyle,
            userNote: snapshot.userNote
        )
    }

    func update(_ metadata: CoachSplitMetadata, from snapshot: CoachSplitMetadataSnapshot) {
        metadata.update(from: snapshot)
    }
}

struct CoachBulkMetadataService {
    func review(
        scope: CoachBulkMetadataScope,
        selectedExerciseIds: Set<UUID> = [],
        muscleGroup: MuscleGroup? = nil,
        splitClassification: CoachSplitClassification? = nil,
        exercises: [Exercise],
        existingMetadata: [CoachExerciseMetadata],
        update: CoachBulkMetadataUpdate,
        overwriteExisting: Bool
    ) -> CoachBulkMetadataReview {
        let matched = matchingExercises(
            scope: scope,
            selectedExerciseIds: selectedExerciseIds,
            muscleGroup: muscleGroup,
            splitClassification: splitClassification,
            exercises: exercises,
            existingMetadata: existingMetadata
        )
        let existingIds = Set(existingMetadata.map(\.exerciseId))
        let existingCount = matched.filter { existingIds.contains($0.id) }.count
        let createCount = matched.count - existingCount
        let updateCount = overwriteExisting ? existingCount : 0

        return CoachBulkMetadataReview(
            scope: scope,
            matchedExerciseIds: matched.map(\.id),
            matchedExerciseNames: matched.map(\.name),
            changedFieldNames: update.changedFieldNames,
            willCreateCount: createCount,
            willUpdateCount: updateCount,
            skippedExistingCount: overwriteExisting ? 0 : existingCount
        )
    }

    func matchingExercises(
        scope: CoachBulkMetadataScope,
        selectedExerciseIds: Set<UUID> = [],
        muscleGroup: MuscleGroup? = nil,
        splitClassification: CoachSplitClassification? = nil,
        exercises: [Exercise],
        existingMetadata: [CoachExerciseMetadata]
    ) -> [Exercise] {
        let metadataByExerciseId = Dictionary(existingMetadata.map { ($0.exerciseId, $0) }, uniquingKeysWith: { first, _ in first })

        return exercises.filter { exercise in
            let metadata = metadataByExerciseId[exercise.id]
            switch scope {
            case .selectedExercises:
                return selectedExerciseIds.contains(exercise.id)
            case .muscleGroup:
                guard let muscleGroup else { return false }
                return (metadata?.primaryMuscleGroup ?? exercise.primaryMuscleGroup) == muscleGroup
            case .splitClassification:
                guard let splitClassification else { return false }
                return metadata?.splitClassification == splitClassification
            case .accessories:
                return metadata?.role == .accessory || (!exercise.isCompound && exercise.movementPattern != .isolation)
            case .isolation:
                return metadata?.role == .isolation || exercise.movementPattern == .isolation
            case .priorityLifts:
                return metadata?.role == .priorityLift || metadata?.priority == .high
            case .warmUps:
                return metadata?.role == .warmUp || exercise.name.localizedCaseInsensitiveContains("warm")
            }
        }
    }

    func updatedDraft(
        for exercise: Exercise,
        existingMetadata: CoachExerciseMetadata?,
        update: CoachBulkMetadataUpdate,
        overwriteExisting: Bool
    ) -> CoachExerciseMetadataDraft? {
        if existingMetadata != nil, !overwriteExisting {
            return nil
        }

        var draft = CoachExerciseMetadataDraft(exercise: exercise, metadata: existingMetadata)
        if let role = update.role { draft.role = role }
        if let priority = update.priority { draft.priority = priority }
        if let primaryMuscleGroup = update.primaryMuscleGroup { draft.primaryMuscleGroup = primaryMuscleGroup }
        if let secondaryMuscleGroups = update.secondaryMuscleGroups { draft.secondaryMuscleGroups = secondaryMuscleGroups }
        if let splitClassification = update.splitClassification { draft.splitClassification = splitClassification }
        if let movementPattern = update.movementPattern { draft.movementPattern = movementPattern }
        return draft
    }
}

struct CoachRecommendationFeedbackService {
    func makeFeedback(
        for entry: CoachActionHistoryEntry,
        tags: [CoachRecommendationFeedbackTag],
        note: String? = nil,
        date: Date = .now
    ) -> CoachRecommendationFeedback {
        CoachRecommendationFeedback(
            createdAt: date,
            historyEntryId: entry.id,
            action: entry.action,
            tags: tags,
            note: note,
            splitName: entry.splitName,
            readinessCategory: entry.readinessCategory,
            fatigueRiskLevel: entry.fatigueRiskLevel,
            confidence: entry.confidence
        )
    }

    func feedbackSummary(_ feedback: [CoachRecommendationFeedback]) -> String {
        let tags = feedback.flatMap(\.tags)
        guard !tags.isEmpty else { return "No feedback yet." }

        let helpful = tags.filter { $0 == .helpful || $0 == .feltAccurate }.count
        let needsTuning = tags.filter { $0 == .notHelpful || $0 == .feltInaccurate || $0 == .tooAggressive || $0 == .tooConservative }.count

        if needsTuning > helpful {
            return "Feedback suggests this coach guidance needs lighter confidence wording."
        }
        if helpful > 0 {
            return "Feedback suggests this guidance has felt useful."
        }
        return "Feedback is recorded locally for future wording."
    }

    func calibrationDiagnostics(from context: CoachCalibrationContext) -> [String] {
        let feedback = context.recentFeedback
        guard !feedback.isEmpty else { return ["No local feedback yet."] }

        let tooAggressive = feedback.filter { $0.tags.contains(.tooAggressive) || $0.tags.contains(.preferredRecovery) }.count
        let tooConservative = feedback.filter { $0.tags.contains(.tooConservative) }.count
        let inaccurate = feedback.filter { $0.tags.contains(.feltInaccurate) || $0.tags.contains(.notHelpful) }.count

        return [
            "\(feedback.count) recent feedback entries considered.",
            "\(tooAggressive) marked too aggressive or recovery-preferred.",
            "\(tooConservative) marked too conservative.",
            "\(inaccurate) marked inaccurate or unhelpful."
        ]
    }
}

struct SavedCoachDeloadBlockService {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func makeBlock(
        plan: ManualDeloadPlan,
        startDate: Date = .now,
        reason: String,
        splitName: String?
    ) -> SavedCoachDeloadBlock {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(byAdding: .day, value: plan.duration.dayCount - 1, to: start) ?? start

        return SavedCoachDeloadBlock(
            startsAt: start,
            endsAt: end,
            duration: plan.duration,
            volumeReduction: plan.volumeReduction,
            focus: plan.focus,
            reason: reason,
            splitName: splitName
        )
    }

    func complete(_ block: SavedCoachDeloadBlock, date: Date = .now) {
        block.state = .completed
        block.updatedAt = date
    }

    func cancel(_ block: SavedCoachDeloadBlock, date: Date = .now) {
        block.state = .cancelled
        block.updatedAt = date
    }
}

struct CoachDeloadCalendarReviewService {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func preview(
        plan: ManualDeloadPlan,
        startDate: Date = .now,
        activeSplits: [TrainingSplit] = []
    ) -> CoachDeloadCalendarPreview {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(byAdding: .day, value: plan.duration.dayCount - 1, to: start) ?? start
        let estimatedTrainingDays = estimatedAffectedTrainingDays(for: plan.duration, activeSplits: activeSplits)

        return CoachDeloadCalendarPreview(
            plan: plan,
            startsAt: start,
            endsAt: end,
            estimatedAffectedTrainingDays: estimatedTrainingDays,
            volumeSummary: "\(plan.volumeReduction.displayName) volume target across the block.",
            focusExplanation: plan.summary,
            affectedSplitNames: activeSplits.map(\.name).prefix(4).map { $0 }
        )
    }

    private func estimatedAffectedTrainingDays(
        for duration: ManualDeloadDuration,
        activeSplits: [TrainingSplit]
    ) -> Int {
        let weeklyFrequency = activeSplits.reduce(0) { $0 + max(1, $1.daysPerWeek) }
        let averageTrainingDays = weeklyFrequency == 0 ? 4 : min(6, max(2, weeklyFrequency / max(1, activeSplits.count)))
        let estimate = Double(duration.dayCount) / 7.0 * Double(averageTrainingDays)
        return max(1, Int(estimate.rounded(.toNearestOrAwayFromZero)))
    }
}

struct CoachWorkoutChangeExplanationService {
    func explanation(
        for preview: CoachWorkoutAdjustmentPreview,
        preferences: CoachPreferencesSnapshot = .default,
        splitMetadata: CoachSplitMetadataSnapshot? = nil
    ) -> CoachWorkoutChangeExplanation {
        let changed = preview.changedExerciseAdjustments
        let reduced = changed.filter { $0.afterSets < $0.beforeSets }
        let protected = preview.exerciseAdjustments.filter { adjustment in
            !adjustment.changed && (adjustment.reason == "No change" || adjustment.afterSets == adjustment.beforeSets)
        }

        return CoachWorkoutChangeExplanation(
            originalTotalSets: preview.beforeTotalSets,
            adjustedTotalSets: preview.afterTotalSets,
            exercisesChanged: changed.map(\.name),
            exercisesProtected: Array(protected.map(\.name).prefix(4)),
            exercisesReduced: reduced.map(\.name),
            mainReason: preview.whySuggested,
            readinessFatigueSignals: Array(preview.contributingSignals.prefix(4)),
            preferenceInfluence: preferenceInfluence(preferences),
            metadataInfluence: metadataInfluence(preview: preview, splitMetadata: splitMetadata),
            confidence: preview.confidence
        )
    }

    private func preferenceInfluence(_ preferences: CoachPreferencesSnapshot) -> String? {
        let pieces = [
            preferences.aggressiveness != .balanced ? preferences.aggressiveness.displayName : nil,
            preferences.reductionPreference.displayName
        ].compactMap { $0 }
        guard !pieces.isEmpty else { return nil }
        return pieces.joined(separator: " · ")
    }

    private func metadataInfluence(
        preview: CoachWorkoutAdjustmentPreview,
        splitMetadata: CoachSplitMetadataSnapshot?
    ) -> String? {
        if let splitMetadata {
            return "\(splitMetadata.splitName): \(splitMetadata.primaryGoal.displayName), \(splitMetadata.preferredAdjustmentStyle.displayName.lowercased())"
        }

        let metadataSignal = preview.contributingSignals.first {
            $0.localizedCaseInsensitiveContains("metadata")
                || $0.localizedCaseInsensitiveContains("fallback")
                || $0.localizedCaseInsensitiveContains("priority")
        }
        return metadataSignal
    }
}

struct CoachHistoryExportService {
    func csv(
        entries: [CoachActionHistoryEntry],
        feedback: [CoachRecommendationFeedback] = []
    ) -> String {
        let header = [
            "timestamp",
            "action_type",
            "outcome",
            "split_or_workout",
            "readiness",
            "fatigue_risk",
            "confidence",
            "reason",
            "user_feedback",
            "before_total_sets",
            "after_total_sets"
        ].joined(separator: ",")
        let feedbackByHistoryId = Dictionary(grouping: feedback.compactMap { item -> (UUID, CoachRecommendationFeedback)? in
            guard let historyEntryId = item.historyEntryId else { return nil }
            return (historyEntryId, item)
        }, by: \.0)

        let rows = entries.map { entry in
            let feedbackText = feedbackByHistoryId[entry.id, default: []]
                .flatMap { $0.1.tags.map(\.displayName) }
                .joined(separator: "; ")
            return [
                csvEscape(entry.createdAt.ISO8601Format()),
                csvEscape(entry.action.displayName),
                csvEscape(entry.outcome.displayName),
                csvEscape(entry.splitName ?? entry.workoutName ?? ""),
                csvEscape(entry.readinessCategory.displayName),
                csvEscape(entry.fatigueRiskLevel.displayName),
                csvEscape(entry.confidence.displayName),
                csvEscape(entry.shortReason),
                csvEscape(feedbackText),
                "\(entry.beforeTotalSets)",
                "\(entry.afterTotalSets)"
            ].joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
