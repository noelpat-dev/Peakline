import Foundation

struct NutritionTextNormalizer {
    func lines(from rawText: String) -> [String] {
        rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func normalize(lines: [String]) -> [String] {
        lines.map(normalizeLine)
    }

    func normalizeLine(_ line: String) -> String {
        var text = line.lowercased()
        text = text.replacingOccurrences(of: "–", with: "-")
        text = text.replacingOccurrences(of: "—", with: "-")
        text = text.replacingOccurrences(of: "−", with: "-")
        text = text.replacingOccurrences(of: ",", with: ".")
        text = text.replacingOccurrences(of: "k cal", with: "kcal")
        text = text.replacingOccurrences(of: "k.cal", with: "kcal")
        text = text.replacingOccurrences(of: "kcals", with: "kcal")
        text = text.replacingOccurrences(of: "kcalories", with: "kcal")
        text = text.replacingOccurrences(of: "kilocalories", with: "kcal")
        text = text.replacingOccurrences(of: "k j", with: "kj")
        text = text.replacingOccurrences(of: "kilojoules", with: "kj")
        text = text.replacingOccurrences(of: "grammes", with: "g")
        text = text.replacingOccurrences(of: "grams", with: "g")
        text = text.replacingOccurrences(of: " gms", with: " g")
        text = text.replacingOccurrences(of: "millilitres", with: "ml")
        text = text.replacingOccurrences(of: "milliliters", with: "ml")
        text = text.replacingOccurrences(of: " m l", with: " ml")

        text = text.replacingMatches(of: #"(?<=\d)o(?=\d|\s*(?:kj|kcal|g|ml))"#, with: "0")
        text = text.replacingMatches(of: #"(?<=\s)o(?=\d)"#, with: "0")
        text = text.replacingMatches(of: #"(?<=\s)l(?=\d)"#, with: "1")
        text = text.replacingMatches(of: #"(?<=\d)l(?=\d)"#, with: "1")
        text = text.replacingMatches(of: #"per\s+[1l]0[o0]\s*g"#, with: "per 100g")
        text = text.replacingMatches(of: #"per\s+[1l]0[o0]\s*ml"#, with: "per 100ml")
        text = text.replacingMatches(of: #"per\s+100\s*g"#, with: "per 100g")
        text = text.replacingMatches(of: #"per\s+100\s*ml"#, with: "per 100ml")
        text = text.replacingMatches(of: #"\s+"#, with: " ")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct NutritionParser {
    private let normalizer = NutritionTextNormalizer()

    func parse(rawText: String) -> NutritionParseResult {
        parse(lines: normalizer.lines(from: rawText))
    }

    func parse(lines rawLines: [String]) -> NutritionParseResult {
        let sourceLines = stitchSplitTableRows(from: rawLines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let normalizedLines = normalizer.normalize(lines: sourceLines)
        let context = detectContext(from: normalizedLines)
        let servingSize = detectServingSize(rawLines: sourceLines, normalizedLines: normalizedLines)
        var warnings = Set<NutritionParseWarning>()
        var valuesByNutrient: [NutritionNutrientKind: ParsedNutrientValue] = [:]

        if context.didApplyOCRCorrection {
            warnings.insert(.ocrLikelyMisread)
        }

        if context.basisWasInferred {
            warnings.insert(.basisInferredFromComposition)
        }

        if context.availableBases.isEmpty {
            warnings.insert(.basisNotDetected)
        }

        if context.selectedBasis == .perServing {
            warnings.insert(.onlyServingValuesDetected)
            if servingSize == nil {
                warnings.insert(.servingSizeMissing)
            }
        }

        for (index, line) in normalizedLines.enumerated() {
            guard !shouldSkipLine(line), let nutrient = detectNutrient(in: line) else { continue }

            let sourceLine = sourceLines[index]
            if nutrient == .calories || nutrient == .energyKJ {
                if let parsed = parseEnergyRow(
                    line,
                    sourceLine: sourceLine,
                    sourceLineIndex: index,
                    context: context,
                    servingSize: servingSize
                ) {
                    valuesByNutrient[.calories] = parsed.value
                    parsed.warnings.forEach { warnings.insert($0) }
                }
            } else if let parsed = parseMassRow(
                line,
                nutrient: nutrient,
                sourceLine: sourceLine,
                sourceLineIndex: index,
                context: context,
                servingSize: servingSize
            ) {
                valuesByNutrient[nutrient] = parsed.value
                parsed.warnings.forEach { warnings.insert($0) }
            }
        }

        if valuesByNutrient[.salt] == nil, let sodium = valuesByNutrient[.sodium] {
            valuesByNutrient[.salt] = ParsedNutrientValue(
                nutrient: .salt,
                amount: sodium.amount * 2.5,
                unit: .grams,
                basis: sodium.basis,
                confidence: sodium.confidence == .high ? .medium : .low,
                sourceLine: sodium.sourceLine,
                sourceLineIndex: sodium.sourceLineIndex,
                warnings: [.sodiumConvertedToSalt]
            )
            warnings.insert(.sodiumConvertedToSalt)
        }

        if valuesByNutrient[.calories] == nil { warnings.insert(.missingCalories) }
        if valuesByNutrient[.protein] == nil { warnings.insert(.missingProtein) }
        if valuesByNutrient[.carbohydrates] == nil { warnings.insert(.missingCarbs) }
        if valuesByNutrient[.fat] == nil { warnings.insert(.missingFat) }

        let checked = sanityChecked(values: Array(valuesByNutrient.values), warnings: warnings)
        let values = checked.values.sorted { lhs, rhs in
            nutrientSortIndex(lhs.nutrient) < nutrientSortIndex(rhs.nutrient)
        }
        let finalWarnings = Array(checked.warnings).sorted { $0.rawValue < $1.rawValue }

        return NutritionParseResult(
            values: values,
            selectedBasis: context.selectedBasis,
            availableBases: context.availableBases,
            servingSize: servingSize,
            warnings: finalWarnings,
            overallConfidence: overallConfidence(values: values, warnings: finalWarnings, context: context),
            rawLines: sourceLines,
            normalizedLines: normalizedLines
        )
    }

    private func detectContext(from lines: [String]) -> ParserContext {
        var bases: [NutritionBasis] = []
        for line in lines {
            if line.contains("per 100g") {
                bases.append(.per100g)
            }
            if line.contains("per 100ml") {
                bases.append(.per100ml)
            }
            if line.contains("per serving") || line.contains("per portion") || line.contains("per pack") || line.contains("serving contains") || line.contains("each serving") {
                bases.append(.perServing)
            }
        }

        let explicitBases = uniqueBases(bases)
        let inferredBasis = explicitBases.isEmpty ? inferredCompositionBasis(from: lines) : nil
        let availableBases = inferredBasis.map { [$0] } ?? explicitBases
        let selectedBasis = preferredBasis(from: availableBases)
        return ParserContext(
            availableBases: availableBases,
            selectedBasis: selectedBasis,
            didApplyOCRCorrection: false,
            basisWasInferred: inferredBasis != nil
        )
    }

    private func inferredCompositionBasis(from lines: [String]) -> NutritionBasis? {
        guard
            let water = compositionAmount(in: lines.first(where: { $0.contains("water") })),
            let carbohydrates = compositionAmount(for: .carbohydrates, in: lines),
            let protein = compositionAmount(for: .protein, in: lines),
            let fat = compositionAmount(for: .fat, in: lines)
        else {
            return nil
        }

        let compositionTotal = water + carbohydrates + protein + fat
        guard (90...105).contains(compositionTotal) else { return nil }
        return .per100g
    }

    private func compositionAmount(for nutrient: NutritionNutrientKind, in lines: [String]) -> Double? {
        compositionAmount(in: lines.first(where: { detectExplicitNutrient(in: $0) == nutrient }))
    }

    private func compositionAmount(in line: String?) -> Double? {
        guard let line else { return nil }
        return nutritionMatches(in: line, allowedUnits: [.grams])
            .first(where: { $0.unit == .grams })?
            .amount
    }

    private func parseEnergyRow(
        _ line: String,
        sourceLine: String,
        sourceLineIndex: Int,
        context: ParserContext,
        servingSize: ParsedServingSize?
    ) -> ParsedRow? {
        let valueLine = nutritionValueLine(from: line)
        let kcalMatches = nutritionMatches(in: valueLine, allowedUnits: [.kcal])
        let kjMatches = nutritionMatches(in: valueLine, allowedUnits: [.kj])
        let basisOrder = rowBasisOrder(for: line, context: context, valueCount: max(kcalMatches.count, kjMatches.count))
        var warnings: [NutritionParseWarning] = []

        if let selected = selectedMatch(from: kcalMatches, basisOrder: basisOrder, selectedBasis: context.selectedBasis) {
            return ParsedRow(value: makeValue(
                nutrient: .calories,
                selected: selected,
                matches: kcalMatches,
                basisOrder: basisOrder,
                sourceLine: sourceLine,
                sourceLineIndex: sourceLineIndex,
                context: context,
                servingSize: servingSize,
                warnings: warnings
            ), warnings: warnings)
        }

        guard let selected = selectedMatch(from: kjMatches, basisOrder: basisOrder, selectedBasis: context.selectedBasis) else {
            let unitless = unitlessNumbers(in: valueLine)
            guard let first = unitless.first else { return nil }
            let match = ParsedAmount(amount: first, unit: .kcal, isLessThan: false, hadUnit: false)
            warnings.append(.ambiguousColumn)
            return ParsedRow(value: makeValue(
                nutrient: .calories,
                selected: match,
                matches: [match],
                basisOrder: basisOrder.isEmpty ? [.unknown] : basisOrder,
                sourceLine: sourceLine,
                sourceLineIndex: sourceLineIndex,
                context: context,
                servingSize: servingSize,
                warnings: warnings
            ), warnings: warnings)
        }

        warnings.append(.usedKJToKcalConversion)
        let kcalMatch = ParsedAmount(amount: selected.amount / 4.184, unit: .kcal, isLessThan: selected.isLessThan, hadUnit: true)
        return ParsedRow(value: makeValue(
            nutrient: .calories,
            selected: kcalMatch,
            matches: kjMatches.map { ParsedAmount(amount: $0.amount / 4.184, unit: .kcal, isLessThan: $0.isLessThan, hadUnit: true) },
            basisOrder: basisOrder,
            sourceLine: sourceLine,
            sourceLineIndex: sourceLineIndex,
            context: context,
            servingSize: servingSize,
            warnings: warnings
        ), warnings: warnings)
    }

    private func parseMassRow(
        _ line: String,
        nutrient: NutritionNutrientKind,
        sourceLine: String,
        sourceLineIndex: Int,
        context: ParserContext,
        servingSize: ParsedServingSize?
    ) -> ParsedRow? {
        let valueLine = nutritionValueLine(from: line)
        let matches = nutritionMatches(in: valueLine, allowedUnits: [.grams, .milligrams, .unknown])
        guard !matches.isEmpty else {
            if line.contains("trace") || line.contains("nil") {
                let zero = ParsedAmount(amount: 0, unit: .grams, isLessThan: false, hadUnit: false)
                return ParsedRow(value: makeValue(
                    nutrient: nutrient,
                    selected: zero,
                    matches: [zero],
                    basisOrder: rowBasisOrder(for: line, context: context, valueCount: 1),
                    sourceLine: sourceLine,
                    sourceLineIndex: sourceLineIndex,
                    context: context,
                    servingSize: servingSize,
                    warnings: [.valueLooksTooLow]
                ), warnings: [.valueLooksTooLow])
            }
            return nil
        }

        let basisOrder = rowBasisOrder(for: line, context: context, valueCount: matches.count)
        guard let selected = selectedMatch(from: matches, basisOrder: basisOrder, selectedBasis: context.selectedBasis) else { return nil }
        var warnings: [NutritionParseWarning] = []
        if selected.isLessThan || !selected.hadUnit {
            warnings.append(.ambiguousColumn)
        }

        return ParsedRow(value: makeValue(
            nutrient: nutrient,
            selected: selected,
            matches: matches,
            basisOrder: basisOrder,
            sourceLine: sourceLine,
            sourceLineIndex: sourceLineIndex,
            context: context,
            servingSize: servingSize,
            warnings: warnings
        ), warnings: warnings)
    }

    private func makeValue(
        nutrient: NutritionNutrientKind,
        selected: ParsedAmount,
        matches: [ParsedAmount],
        basisOrder: [NutritionBasis],
        sourceLine: String,
        sourceLineIndex: Int,
        context: ParserContext,
        servingSize: ParsedServingSize?,
        warnings: [NutritionParseWarning]
    ) -> ParsedNutrientValue {
        let selectedBasis = basisOrder[safe: selectedBasisIndex(in: basisOrder, selectedBasis: context.selectedBasis)] ?? context.selectedBasis
        let mapped = mappedAmount(selected.amount, unit: selected.unit, basis: selectedBasis, servingSize: servingSize)
        var valueWarnings = warnings
        if mapped.wasInferred {
            valueWarnings.append(.onlyServingValuesDetected)
        }

        return ParsedNutrientValue(
            nutrient: nutrient,
            amount: mapped.amount,
            unit: mapped.unit,
            basis: mapped.basis,
            confidence: confidence(for: selected, basis: mapped.basis, context: context, wasInferred: mapped.wasInferred),
            sourceLine: sourceLine,
            sourceLineIndex: sourceLineIndex,
            alternatives: alternatives(from: matches, basisOrder: basisOrder, sourceLine: sourceLine),
            warnings: valueWarnings
        )
    }

    private func mappedAmount(_ amount: Double, unit: NutritionUnit, basis: NutritionBasis, servingSize: ParsedServingSize?) -> (amount: Double, unit: NutritionUnit, basis: NutritionBasis, wasInferred: Bool) {
        let normalizedAmount = unit == .milligrams ? amount / 1_000 : amount
        let normalizedUnit: NutritionUnit = unit == .milligrams ? .grams : unit

        guard basis == .perServing, let servingSize, servingSize.amount > 0 else {
            return (normalizedAmount, normalizedUnit, basis, false)
        }

        let divisor = servingSize.amount / 100
        guard divisor > 0 else {
            return (normalizedAmount, normalizedUnit, basis, false)
        }

        let inferredBasis: NutritionBasis = servingSize.unit == .millilitres ? .per100ml : .per100g
        return (normalizedAmount / divisor, normalizedUnit, inferredBasis, true)
    }

    private func nutritionMatches(in line: String, allowedUnits: Set<NutritionUnit>) -> [ParsedAmount] {
        let pattern = #"(?<![%\d])(<\s*)?(\d+(?:\.\d+)?)\s*(kcal|kj|mg|g|ml)?"#
        return line.regexMatches(pattern).compactMap { match in
            guard let amountText = match.group(2), let amount = Double(amountText) else { return nil }
            let unit = unit(from: match.group(3))
            guard allowedUnits.contains(unit) else { return nil }
            if match.trailingText.trimmingCharacters(in: .whitespaces).hasPrefix("%") { return nil }
            return ParsedAmount(amount: amount, unit: unit, isLessThan: match.group(1) != nil, hadUnit: match.group(3) != nil)
        }
    }

    private func unitlessNumbers(in line: String) -> [Double] {
        line.regexMatches(#"(?<![%\d])(\d+(?:\.\d+)?)(?!\s*%)"#).compactMap { Double($0.group(1) ?? "") }
    }

    private func nutritionValueLine(from line: String) -> String {
        line.replacingMatches(of: #"per\s+100g|per\s+100ml|per\s+serving|per\s+portion"#, with: "")
    }

    private func unit(from raw: String?) -> NutritionUnit {
        switch raw {
        case "kcal":
            return .kcal
        case "kj":
            return .kj
        case "g":
            return .grams
        case "mg":
            return .milligrams
        case "ml":
            return .millilitres
        default:
            return .unknown
        }
    }

    private func selectedMatch(from matches: [ParsedAmount], basisOrder: [NutritionBasis], selectedBasis: NutritionBasis) -> ParsedAmount? {
        guard !matches.isEmpty else { return nil }
        let index = selectedBasisIndex(in: basisOrder, selectedBasis: selectedBasis)
        return matches[safe: index] ?? matches.first
    }

    private func selectedBasisIndex(in basisOrder: [NutritionBasis], selectedBasis: NutritionBasis) -> Int {
        if let index = basisOrder.firstIndex(of: selectedBasis) {
            return index
        }
        return 0
    }

    private func rowBasisOrder(for line: String, context: ParserContext, valueCount: Int) -> [NutritionBasis] {
        var bases: [NutritionBasis] = []
        if line.contains("per 100g") { bases.append(.per100g) }
        if line.contains("per 100ml") { bases.append(.per100ml) }
        if line.contains("per serving") || line.contains("per portion") { bases.append(.perServing) }
        if bases.isEmpty {
            bases = context.availableBases
        }
        if bases.count == 1, valueCount > 1, context.availableBases.count > 1 {
            bases = context.availableBases
        }
        if bases.isEmpty {
            bases = [.unknown]
        }
        return bases
    }

    private func alternatives(from matches: [ParsedAmount], basisOrder: [NutritionBasis], sourceLine: String) -> [ParsedNutrientAlternative] {
        matches.enumerated().map { index, match in
            ParsedNutrientAlternative(
                amount: match.amount,
                unit: match.unit,
                basis: basisOrder[safe: index] ?? .unknown,
                sourceLine: sourceLine
            )
        }
    }

    private func detectNutrient(in line: String) -> NutritionNutrientKind? {
        if let nutrient = detectExplicitNutrient(in: line) {
            return nutrient
        }
        if isStandaloneNutritionAmountLine(line) {
            return nil
        }
        if line.contains("energy") || line.contains("calories") || line.contains(" kcal") || line.contains("kcal") {
            return .calories
        }
        if line.contains(" kj") || line.contains("kj") {
            return .energyKJ
        }
        return nil
    }

    private func detectExplicitNutrient(in line: String) -> NutritionNutrientKind? {
        if line.contains("saturates") || line.contains("saturated fat") || line.contains("saturated") {
            return .saturatedFat
        }
        if line.contains("sugars") || line.contains("sugar") {
            return .sugars
        }
        if line.contains("carbohydrate") || line.contains("carbohydrates") || line.contains("carbs") {
            return .carbohydrates
        }
        if line.contains("total fat") || line.hasPrefix("fat ") || line == "fat" || line.contains(" fat ") {
            return .fat
        }
        if line.contains("fibre") || line.contains("fiber") {
            return .fibre
        }
        if line.contains("protein") || line.contains("proteins") {
            return .protein
        }
        if line.contains("sodium") {
            return .sodium
        }
        if line.contains("salt") {
            return .salt
        }
        if line.contains("energy") || line.contains("calories") || line.contains("calorie") {
            return .calories
        }
        return nil
    }

    private func detectServingSize(rawLines: [String], normalizedLines: [String]) -> ParsedServingSize? {
        for (index, line) in normalizedLines.enumerated() {
            guard line.contains("serving") || line.contains("portion") else { continue }
            let matches = nutritionMatches(in: line, allowedUnits: [.grams, .millilitres])
            guard let match = matches.first(where: { $0.unit == .grams || $0.unit == .millilitres }) else { continue }
            return ParsedServingSize(
                amount: match.amount,
                unit: match.unit,
                sourceLine: rawLines[index],
                confidence: line.contains("serving size") || line.contains("portion size") ? .high : .medium
            )
        }
        return nil
    }

    private func shouldSkipLine(_ line: String) -> Bool {
        let referenceTerms = ["reference intake", "average adult", " ri ", "% ri", "daily value", "adult's reference"]
        return referenceTerms.contains { line.contains($0) } || isStandaloneNutritionAmountLine(line)
    }

    private func stitchSplitTableRows(from rawLines: [String]) -> [String] {
        let trimmedLines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var stitchedLines: [String] = []
        var index = 0

        while index < trimmedLines.count {
            let line = trimmedLines[index]
            let normalizedLine = normalizer.normalizeLine(line)

            guard
                detectExplicitNutrient(in: normalizedLine) != nil,
                !containsNutritionAmount(in: normalizedLine)
            else {
                stitchedLines.append(line)
                index += 1
                continue
            }

            var rowCells = [line]
            var lookahead = index + 1
            var valueCellCount = 0

            while lookahead < trimmedLines.count {
                let nextLine = trimmedLines[lookahead]
                let normalizedNextLine = normalizer.normalizeLine(nextLine)

                if detectExplicitNutrient(in: normalizedNextLine) != nil {
                    break
                }

                guard isTableValueCell(normalizedNextLine) else {
                    break
                }

                rowCells.append(nextLine)
                valueCellCount += 1
                lookahead += 1

                if valueCellCount >= 4 {
                    break
                }
            }

            if valueCellCount > 0 {
                stitchedLines.append(rowCells.joined(separator: " "))
                index = lookahead
            } else {
                stitchedLines.append(line)
                index += 1
            }
        }

        return stitchedLines
    }

    private func containsNutritionAmount(in line: String) -> Bool {
        !nutritionMatches(in: line, allowedUnits: [.kcal, .kj, .grams, .milligrams, .millilitres, .unknown]).isEmpty
    }

    private func isTableValueCell(_ line: String) -> Bool {
        line.range(
            of: #"^<\s*\d+(?:\.\d+)?\s*(?:kcal|kj|mg|g|ml)?$|^\d+(?:\.\d+)?\s*(?:kcal|kj|mg|g|ml)?$"#,
            options: .regularExpression
        ) != nil
    }

    private func isStandaloneNutritionAmountLine(_ line: String) -> Bool {
        guard containsNutritionAmount(in: line) else { return false }
        let remainder = line
            .replacingMatches(of: #"(<\s*)?\d+(?:\.\d+)?\s*(?:kcal|kj|mg|g|ml)?"#, with: "")
            .replacingMatches(of: #"[\s,/|;:()\-]+"#, with: "")
        return remainder.isEmpty
    }

    private func sanityChecked(values: [ParsedNutrientValue], warnings: Set<NutritionParseWarning>) -> (values: [ParsedNutrientValue], warnings: Set<NutritionParseWarning>) {
        var warnings = warnings
        var checkedValues = values

        for value in checkedValues {
            guard value.basis == .per100g || value.basis == .per100ml else { continue }
            switch value.nutrient {
            case .calories where value.amount > 900:
                warnings.insert(.valueLooksTooHigh)
            case .fat, .saturatedFat, .carbohydrates, .sugars, .fibre, .protein:
                if value.amount > 100 {
                    warnings.insert(.valueLooksTooHigh)
                }
            case .salt where value.amount > 10:
                warnings.insert(.valueLooksTooHigh)
            default:
                break
            }
        }

        if let sugar = checkedValues.first(where: { $0.nutrient == .sugars }),
           let carbs = checkedValues.first(where: { $0.nutrient == .carbohydrates }),
           sugar.amount > carbs.amount {
            warnings.insert(.sugarGreaterThanCarbs)
        }

        if let saturates = checkedValues.first(where: { $0.nutrient == .saturatedFat }),
           let fat = checkedValues.first(where: { $0.nutrient == .fat }),
           saturates.amount > fat.amount {
            warnings.insert(.saturatedFatGreaterThanFat)
        }

        if let calories = checkedValues.first(where: { $0.nutrient == .calories }),
           let protein = checkedValues.first(where: { $0.nutrient == .protein }),
           let carbs = checkedValues.first(where: { $0.nutrient == .carbohydrates }),
           let fat = checkedValues.first(where: { $0.nutrient == .fat }) {
            let macroCalories = protein.amount * 4 + carbs.amount * 4 + fat.amount * 9
            if macroCalories > 0 {
                let differenceRatio = abs(calories.amount - macroCalories) / max(calories.amount, macroCalories)
                if differenceRatio > 0.35 {
                    warnings.insert(.energyDoesNotMatchMacros)
                }
            }
        }

        checkedValues = checkedValues.map { value in
            var value = value
            value.warnings = Array(Set(value.warnings).union(warningsForValue(value))).sorted { $0.rawValue < $1.rawValue }
            return value
        }

        return (checkedValues, warnings)
    }

    private func warningsForValue(_ value: ParsedNutrientValue) -> Set<NutritionParseWarning> {
        guard value.basis == .per100g || value.basis == .per100ml else { return [] }
        switch value.nutrient {
        case .calories where value.amount > 900:
            return [.valueLooksTooHigh]
        case .fat, .saturatedFat, .carbohydrates, .sugars, .fibre, .protein:
            return value.amount > 100 ? [.valueLooksTooHigh] : []
        case .salt where value.amount > 10:
            return [.valueLooksTooHigh]
        default:
            return []
        }
    }

    private func confidence(for selected: ParsedAmount, basis: NutritionBasis, context: ParserContext, wasInferred: Bool) -> NutritionParseConfidence {
        if wasInferred || selected.isLessThan || basis == .unknown {
            return .low
        }
        if context.basisWasInferred {
            return .medium
        }
        if selected.hadUnit, context.availableBases.contains(basis) {
            return .high
        }
        return .medium
    }

    private func overallConfidence(values: [ParsedNutrientValue], warnings: [NutritionParseWarning], context: ParserContext) -> NutritionParseConfidence {
        if values.isEmpty || context.selectedBasis == .unknown || warnings.contains(.basisNotDetected) {
            return .low
        }
        if context.basisWasInferred
            || values.contains(where: { $0.confidence == .low })
            || warnings.contains(.onlyServingValuesDetected) {
            return .medium
        }
        return .high
    }

    private func uniqueBases(_ bases: [NutritionBasis]) -> [NutritionBasis] {
        var seen = Set<NutritionBasis>()
        return bases.filter { seen.insert($0).inserted }
    }

    private func preferredBasis(from bases: [NutritionBasis]) -> NutritionBasis {
        for basis in [NutritionBasis.per100g, .per100ml, .perServing] where bases.contains(basis) {
            return basis
        }
        return .unknown
    }

    private func nutrientSortIndex(_ nutrient: NutritionNutrientKind) -> Int {
        switch nutrient {
        case .calories:
            return 0
        case .protein:
            return 1
        case .carbohydrates:
            return 2
        case .fat:
            return 3
        case .sugars:
            return 4
        case .fibre:
            return 5
        case .saturatedFat:
            return 6
        case .salt:
            return 7
        case .sodium:
            return 8
        case .energyKJ:
            return 9
        }
    }
}

private struct ParserContext {
    let availableBases: [NutritionBasis]
    let selectedBasis: NutritionBasis
    let didApplyOCRCorrection: Bool
    let basisWasInferred: Bool
}

private struct ParsedAmount {
    let amount: Double
    let unit: NutritionUnit
    let isLessThan: Bool
    let hadUnit: Bool
}

private struct ParsedRow {
    let value: ParsedNutrientValue
    let warnings: [NutritionParseWarning]
}

private struct RegexMatch {
    let text: String
    let groups: [String?]
    let trailingText: String

    func group(_ index: Int) -> String? {
        groups[safe: index] ?? nil
    }
}

private extension String {
    func replacingMatches(of pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let range = NSRange(startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: replacement)
    }

    func regexMatches(_ pattern: String) -> [RegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = self as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        return regex.matches(in: self, range: fullRange).map { result in
            let groups = (0..<result.numberOfRanges).map { index -> String? in
                let range = result.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return nsString.substring(with: range)
            }
            let end = result.range.location + result.range.length
            let trailingRange = NSRange(location: end, length: max(0, nsString.length - end))
            return RegexMatch(
                text: nsString.substring(with: result.range),
                groups: groups,
                trailingText: nsString.substring(with: trailingRange)
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
