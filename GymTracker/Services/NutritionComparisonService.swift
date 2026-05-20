import Foundation

struct NutritionComparisonService {
    func compare(
        imported: NutritionSourceSnapshot?,
        label: NutritionSourceSnapshot?,
        local: NutritionSourceSnapshot?
    ) -> NutritionComparisonResult {
        let sources = [local, label, imported].compactMap { $0 }
        let rows = ComparedNutrientKind.allCases.map { nutrient in
            compare(nutrient: nutrient, imported: imported, label: label, local: local, sourceCount: sources.count)
        }

        let productName = local?.productName ?? imported?.productName ?? label?.productName
        let brand = local?.brand ?? imported?.brand ?? label?.brand
        let barcode = local?.barcode ?? imported?.barcode ?? label?.barcode
        let basis = local?.basis ?? imported?.basis ?? label?.basis ?? .unknown
        let warnings = comparisonWarnings(sources: sources, rows: rows)

        return NutritionComparisonResult(
            productName: productName,
            brand: brand,
            barcode: barcode,
            basis: basis,
            sources: sources,
            rows: rows,
            overallStatus: overallStatus(for: rows, sourceCount: sources.count),
            warnings: warnings,
            comparedAt: Date.now
        )
    }

    private func compare(
        nutrient: ComparedNutrientKind,
        imported: NutritionSourceSnapshot?,
        label: NutritionSourceSnapshot?,
        local: NutritionSourceSnapshot?,
        sourceCount: Int
    ) -> NutritionComparisonRow {
        let importedCandidate = candidate(from: imported, nutrient: nutrient)
        let labelCandidate = candidate(from: label, nutrient: nutrient)
        let localCandidate = candidate(from: local, nutrient: nutrient)
        let candidates = [localCandidate, labelCandidate, importedCandidate].compactMap { $0 }
        let presentValues = candidates.compactMap(\.value)
        let warnings = suspiciousWarnings(for: nutrient, candidates: candidates)

        let basisSet = Set(candidates.map(\.basis))
        let hasBasisMismatch = basisSet.count > 1 || basisSet.contains(.unknown)

        let status: NutritionConflictStatus
        let explanation: String?
        if candidates.isEmpty {
            status = .unresolved
            explanation = "No source provided this value."
        } else if hasBasisMismatch {
            status = .basisMismatch
            explanation = "Sources use different nutrition bases. Choose the final per-100 value intentionally."
        } else if !warnings.isEmpty {
            status = .suspiciousValue
            explanation = "One value looks unusual for a per-100 nutrition label."
        } else if candidates.count == 1 {
            status = sourceCount > 1 ? .missingFromOneSource : .onlyOneSourceAvailable
            explanation = sourceCount > 1 ? "Only one source supplied this nutrient." : "This value comes from a single source."
        } else {
            status = differenceStatus(for: nutrient, values: presentValues)
            explanation = statusExplanation(for: status)
        }

        let suggested = suggestion(
            status: status,
            imported: importedCandidate,
            label: labelCandidate,
            local: localCandidate
        )

        return NutritionComparisonRow(
            nutrient: nutrient,
            importedValue: importedCandidate,
            labelScanValue: labelCandidate,
            localValue: localCandidate,
            suggestedValue: suggested,
            finalValue: suggested?.value,
            unit: nutrient.unit,
            status: status,
            explanation: explanation,
            warnings: warnings
        )
    }

    private func candidate(from source: NutritionSourceSnapshot?, nutrient: ComparedNutrientKind) -> NutritionValueCandidate? {
        guard let source, let value = source.value(for: nutrient) else { return nil }
        return NutritionValueCandidate(
            nutrient: nutrient,
            value: value,
            unit: nutrient.unit,
            basis: source.basis,
            source: source.source,
            confidence: source.confidence,
            note: source.basis.displayName
        )
    }

    private func differenceStatus(for nutrient: ComparedNutrientKind, values: [Double]) -> NutritionConflictStatus {
        guard let minValue = values.min(), let maxValue = values.max() else { return .unresolved }
        let absoluteDifference = maxValue - minValue
        let relativeDifference = relativeDifference(min: minValue, max: maxValue)

        switch nutrient {
        case .calories:
            if absoluteDifference <= 5 || relativeDifference <= 0.03 {
                return .match
            }
            if absoluteDifference <= 15 || relativeDifference <= 0.10 {
                return .minorDifference
            }
            return .majorDifference
        case .protein, .carbs, .fat, .sugar, .fibre:
            if absoluteDifference <= 0.5 || relativeDifference <= 0.05 {
                return .match
            }
            if absoluteDifference <= 2 || relativeDifference <= 0.15 {
                return .minorDifference
            }
            return .majorDifference
        case .salt:
            if absoluteDifference <= 0.05 {
                return .match
            }
            if absoluteDifference <= 0.2 {
                return .minorDifference
            }
            return .majorDifference
        }
    }

    private func relativeDifference(min: Double, max: Double) -> Double {
        let denominator = Swift.max(abs(min), abs(max))
        guard denominator > 0.0001 else { return min == max ? 0 : .infinity }
        return abs(max - min) / denominator
    }

    private func statusExplanation(for status: NutritionConflictStatus) -> String? {
        switch status {
        case .match:
            return "Sources are close enough to treat as consistent."
        case .minorDifference:
            return "Small rounding or database differences are possible."
        case .majorDifference:
            return "Values differ enough that the label should be checked before saving."
        case .missingFromOneSource:
            return "One source is missing this value."
        case .onlyOneSourceAvailable:
            return "Only one source is available for comparison."
        case .basisMismatch:
            return "Sources use different nutrition bases."
        case .suspiciousValue:
            return "A value looks unusual and needs a careful review."
        case .unresolved:
            return "Enter a value manually if you want to save it."
        }
    }

    private func suggestion(
        status: NutritionConflictStatus,
        imported: NutritionValueCandidate?,
        label: NutritionValueCandidate?,
        local: NutritionValueCandidate?
    ) -> NutritionValueCandidate? {
        if let local {
            return local
        }

        switch status {
        case .basisMismatch, .unresolved:
            return nil
        case .majorDifference, .suspiciousValue:
            if let label, (label.confidence ?? 0) >= 0.85, (imported?.confidence ?? 0) < 0.6 {
                return label
            }
            if let imported, (imported.confidence ?? 0) >= 0.8, (label?.confidence ?? 0) < 0.5 {
                return imported
            }
            return nil
        case .match, .minorDifference:
            if let label, (label.confidence ?? 0) >= (imported?.confidence ?? 0) {
                return label
            }
            return highestConfidence([label, imported])
        case .missingFromOneSource, .onlyOneSourceAvailable:
            return highestConfidence([label, imported])
        }
    }

    private func highestConfidence(_ candidates: [NutritionValueCandidate?]) -> NutritionValueCandidate? {
        candidates
            .compactMap { $0 }
            .sorted { ($0.confidence ?? 0) > ($1.confidence ?? 0) }
            .first
    }

    private func suspiciousWarnings(for nutrient: ComparedNutrientKind, candidates: [NutritionValueCandidate]) -> [String] {
        var warnings: [String] = []

        for candidate in candidates {
            guard let value = candidate.value else { continue }
            if value < 0 {
                warnings.append("\(candidate.source.displayName) has a negative \(nutrient.displayName.lowercased()) value.")
            }
            switch nutrient {
            case .calories where value > 900:
                warnings.append("\(candidate.source.displayName) calories are unusually high per 100g/ml.")
            case .protein where value > 100,
                 .carbs where value > 100,
                 .fat where value > 100:
                warnings.append("\(candidate.source.displayName) \(nutrient.displayName.lowercased()) is above 100g per 100g/ml.")
            case .sugar where value > 100,
                 .fibre where value > 100:
                warnings.append("\(candidate.source.displayName) \(nutrient.displayName.lowercased()) is above 100g per 100g/ml.")
            case .salt where value > 10:
                warnings.append("\(candidate.source.displayName) salt is unusually high per 100g/ml.")
            default:
                break
            }
        }

        return Array(Set(warnings)).sorted()
    }

    private func comparisonWarnings(sources: [NutritionSourceSnapshot], rows: [NutritionComparisonRow]) -> [String] {
        var warnings = sources.flatMap(\.warnings)

        let names = sources.compactMap { $0.productName?.lowercased() }
        if Set(names).count > 1, names.count > 1 {
            warnings.append("Product names differ between sources. Check that the label and barcode refer to the same food.")
        }

        for source in sources {
            if let sugar = source.sugar, let carbs = source.carbs, sugar > carbs {
                warnings.append("\(source.source.displayName): sugar is higher than total carbs.")
            }

            if
                let calories = source.calories,
                let protein = source.protein,
                let carbs = source.carbs,
                let fat = source.fat
            {
                let estimatedCalories = protein * 4 + carbs * 4 + fat * 9
                let denominator = max(abs(calories), abs(estimatedCalories))
                if denominator > 0, abs(calories - estimatedCalories) / denominator > 0.25 {
                    warnings.append("\(source.source.displayName): calories do not closely match the listed macros. Check the label before saving.")
                }
            }
        }

        if rows.contains(where: { $0.status == .basisMismatch }) {
            warnings.append("At least one nutrient uses different bases across sources.")
        }

        return Array(Set(warnings)).sorted()
    }

    private func overallStatus(for rows: [NutritionComparisonRow], sourceCount: Int) -> NutritionComparisonOverallStatus {
        if sourceCount <= 1 {
            return .singleSource
        }

        if rows.contains(where: { [.majorDifference, .basisMismatch, .suspiciousValue, .unresolved].contains($0.status) }) {
            return .needsReview
        }

        if rows.contains(where: { [.minorDifference, .missingFromOneSource, .onlyOneSourceAvailable].contains($0.status) }) {
            return .someDifferences
        }

        return .consistent
    }
}
