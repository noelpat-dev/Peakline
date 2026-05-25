import AVFoundation
import SwiftUI
import UIKit

enum NutritionLabelOCRState: Equatable {
    case idle
    case processing
    case result(NutritionOCRResult, NutritionParseResult)
    case noTextDetected
    case permissionDenied
    case cameraUnavailable
    case error(message: String)
}

@MainActor
final class NutritionLabelOCRViewModel: ObservableObject {
    @Published private(set) var state: NutritionLabelOCRState = .idle

    private let ocrService: NutritionLabelOCRServicing
    private let parser: NutritionParser
    private var processingTask: Task<Void, Never>?

    init(
        ocrService: NutritionLabelOCRServicing = NutritionLabelOCRService(),
        parser: NutritionParser = NutritionParser()
    ) {
        self.ocrService = ocrService
        self.parser = parser
    }

    var cameraIsAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func requestCameraAccess(then presentCamera: @escaping () -> Void) {
        guard cameraIsAvailable else {
            state = .cameraUnavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentCamera()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    await MainActor.run {
                        presentCamera()
                    }
                } else {
                    state = .permissionDenied
                }
            }
        case .denied, .restricted:
            state = .permissionDenied
        @unknown default:
            state = .permissionDenied
        }
    }

    func process(image: UIImage) {
        processingTask?.cancel()
        state = .processing

        processingTask = Task {
            do {
                let result = try await PerformanceTracer.traceAsync(.nutritionOCR) {
                    try await ocrService.recognizeText(from: image)
                }
                guard !Task.isCancelled else { return }
                let parseResult = PerformanceTracer.trace(.nutritionOCRParse) {
                    parser.parse(lines: result.lines.map(\.text))
                }
                guard !Task.isCancelled else { return }
                state = .result(result, parseResult)
            } catch NutritionLabelOCRError.noTextDetected {
                guard !Task.isCancelled else { return }
                state = .noTextDetected
            } catch NutritionLabelOCRError.invalidImage {
                guard !Task.isCancelled else { return }
                state = .error(message: NutritionLabelOCRError.invalidImage.localizedDescription)
            } catch {
                guard !Task.isCancelled else { return }
                state = .error(message: error.localizedDescription)
            }

            processingTask = nil
        }
    }

    func reset() {
        processingTask?.cancel()
        processingTask = nil
        state = .idle
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
    }

    func imageSelectionFailed() {
        processingTask?.cancel()
        processingTask = nil
        state = .error(message: "That image could not be loaded. Try another photo or enter the food manually.")
    }
}
