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
                    presentCamera()
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
        state = .processing

        Task {
            do {
                let result = try await ocrService.recognizeText(from: image)
                let parseResult = parser.parse(lines: result.lines.map(\.text))
                state = .result(result, parseResult)
            } catch NutritionLabelOCRError.noTextDetected {
                state = .noTextDetected
            } catch NutritionLabelOCRError.invalidImage {
                state = .error(message: NutritionLabelOCRError.invalidImage.localizedDescription)
            } catch {
                state = .error(message: error.localizedDescription)
            }
        }
    }

    func reset() {
        state = .idle
    }

    func imageSelectionFailed() {
        state = .error(message: "That image could not be loaded. Try another photo or enter the food manually.")
    }
}
