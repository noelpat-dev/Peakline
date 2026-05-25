import ImageIO
import UIKit
import Vision

protocol NutritionLabelOCRServicing {
    func recognizeText(from image: UIImage) async throws -> NutritionOCRResult
}

struct NutritionLabelOCRService: NutritionLabelOCRServicing {
    private static let maxRecognitionDimension: CGFloat = 2_200

    func recognizeText(from image: UIImage) async throws -> NutritionOCRResult {
        let maxRecognitionDimension = Self.maxRecognitionDimension

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.normalizedCGImage(maxDimension: maxRecognitionDimension) else {
                    continuation.resume(throwing: NutritionLabelOCRError.invalidImage)
                    return
                }

                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false

                let handler = VNImageRequestHandler(
                    cgImage: cgImage,
                    orientation: .up,
                    options: [:]
                )

                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let lines = Self.cleanedLines(from: observations)

                    guard !lines.isEmpty else {
                        continuation.resume(throwing: NutritionLabelOCRError.noTextDetected)
                        return
                    }

                    continuation.resume(returning: NutritionOCRResult(
                        rawText: lines.map(\.text).joined(separator: "\n"),
                        lines: lines,
                        processedAt: Date.now
                    ))
                } catch {
                    continuation.resume(throwing: NutritionLabelOCRError.requestFailed(error.localizedDescription))
                }
            }
        }
    }

    private static func cleanedLines(from observations: [VNRecognizedTextObservation]) -> [NutritionOCRLine] {
        let cells: [NutritionOCRLine] = observations
            .sorted { lhs, rhs in
                let yDelta = abs(lhs.boundingBox.minY - rhs.boundingBox.minY)
                if yDelta > 0.015 {
                    return lhs.boundingBox.minY > rhs.boundingBox.minY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = normalizedLine(candidate.string)
                guard !text.isEmpty else { return nil }
                return NutritionOCRLine(
                    text: text,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
            }

        return groupedRows(from: cells)
    }

    static func normalizedLine(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func groupedRows(from cells: [NutritionOCRLine]) -> [NutritionOCRLine] {
        var rows: [[NutritionOCRLine]] = []

        for cell in cells {
            guard let box = cell.boundingBox else {
                rows.append([cell])
                continue
            }

            if let rowIndex = rows.firstIndex(where: { row in
                guard let rowBox = combinedBox(for: row) else { return false }
                return verticalOverlapRatio(box, rowBox) >= 0.45
                    || abs(box.midY - rowBox.midY) <= max(box.height, rowBox.height) * 0.55
            }) {
                rows[rowIndex].append(cell)
            } else {
                rows.append([cell])
            }
        }

        return rows
            .map { row in row.sorted { ($0.boundingBox?.minX ?? 0) < ($1.boundingBox?.minX ?? 0) } }
            .sorted { lhs, rhs in
                let lhsY = combinedBox(for: lhs)?.midY ?? 0
                let rhsY = combinedBox(for: rhs)?.midY ?? 0
                return lhsY > rhsY
            }
            .compactMap { row in
                let text = normalizedLine(row.map(\.text).joined(separator: " "))
                guard !text.isEmpty else { return nil }

                return NutritionOCRLine(
                    text: text,
                    confidence: averagedConfidence(for: row),
                    boundingBox: combinedBox(for: row)
                )
            }
    }

    private static func combinedBox(for row: [NutritionOCRLine]) -> CGRect? {
        let boxes = row.compactMap(\.boundingBox)
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }

    private static func verticalOverlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let overlap = max(0, min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY))
        let shortestHeight = max(min(lhs.height, rhs.height), 0.0001)
        return overlap / shortestHeight
    }

    private static func averagedConfidence(for row: [NutritionOCRLine]) -> Float? {
        let values = row.compactMap(\.confidence)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }
}

private extension UIImage {
    func normalizedCGImage(maxDimension: CGFloat) -> CGImage? {
        let targetSize = scaledSize(maxDimension: maxDimension)

        if imageOrientation == .up, targetSize == size, let cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }.cgImage
    }

    private func scaledSize(maxDimension: CGFloat) -> CGSize {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension, largestSide > 0 else { return size }

        let scale = maxDimension / largestSide
        return CGSize(
            width: max(1, floor(size.width * scale)),
            height: max(1, floor(size.height * scale))
        )
    }
}
