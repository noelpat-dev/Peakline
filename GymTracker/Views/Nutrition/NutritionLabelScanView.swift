import PhotosUI
import SwiftUI
import UIKit

struct NutritionLabelScanView: View {
    @Environment(\.appTheme) private var appTheme

    @StateObject private var viewModel = NutritionLabelOCRViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var isManualEntryPresented = false
    @State private var pendingCameraImage: UIImage?
    @State private var photoLoadingTask: Task<Void, Never>?
    @State private var deferredImageProcessingTask: Task<Void, Never>?

    let initialBarcode: String?
    let comparisonDraft: FoodImportDraft?
    let localFood: FoodItem?

    init(initialBarcode: String? = nil, comparisonDraft: FoodImportDraft? = nil, localFood: FoodItem? = nil) {
        self.initialBarcode = initialBarcode
        self.comparisonDraft = comparisonDraft
        self.localFood = localFood
    }

    var body: some View {
        FitnessScreen(
            title: "Scan nutrition label",
            subtitle: "Extract label text locally, then confirm the values yourself.",
            systemImage: "text.viewfinder"
        ) {
            introCard

            switch viewModel.state {
            case .idle:
                captureActions
                tipsCard
            case .processing:
                processingCard
            case .result(let result, let parseResult):
                resultReadyCard(result, parseResult: parseResult)
                captureActions
            case .noTextDetected:
                noTextCard
                captureActions
            case .permissionDenied:
                permissionCard
                fallbackActions
            case .cameraUnavailable:
                unavailableCard
                fallbackActions
            case .error(let message):
                errorCard(message)
                captureActions
            }
        }
        .navigationTitle("Scan Label")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isCameraPresented) {
            NutritionLabelImagePicker(sourceType: .camera) { image in
                pendingCameraImage = image
                isCameraPresented = false
            } onCancel: {
                isCameraPresented = false
            }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isManualEntryPresented) {
            ManualFoodEntryView()
        }
        .onChange(of: selectedPhoto) { _, item in
            photoLoadingTask?.cancel()
            photoLoadingTask = nil
            guard let item else { return }
            photoLoadingTask = Task { @MainActor in
                await loadPhoto(item)
                guard !Task.isCancelled else { return }
                photoLoadingTask = nil
            }
        }
        .onChange(of: isCameraPresented) { _, isPresented in
            guard !isPresented, let image = pendingCameraImage else { return }
            pendingCameraImage = nil
            processImageAfterPickerDismissal(image)
        }
        .onDisappear {
            photoLoadingTask?.cancel()
            photoLoadingTask = nil
            deferredImageProcessingTask?.cancel()
            deferredImageProcessingTask = nil
        }
    }

    private var introCard: some View {
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textAccent)
                    .frame(width: 48, height: 48)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Label OCR")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text("Review required")
                            .font(AppTypography.badge)
                            .foregroundStyle(appTheme.colors.textAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(appTheme.colors.accentSurface, in: Capsule())
                    }

                    Text("Take a clear photo or choose a nutrition screenshot. Peakline reads the table on-device and keeps the final save under your control.")
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var captureActions: some View {
        DashboardSection(title: "Capture Label") {
            VStack(spacing: 12) {
                Button {
                    viewModel.requestCameraAccess {
                        isCameraPresented = true
                    }
                } label: {
                    Label("Take Photo", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())
                .accessibilityLabel("Scan nutrition label")

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())
                .accessibilityLabel("Choose nutrition label photo")

                Button {
                    isManualEntryPresented = true
                } label: {
                    Label("Manual Entry Instead", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeutralFitnessButtonStyle())
            }
        }
    }

    private var fallbackActions: some View {
        DashboardSection(title: "Continue Without Camera") {
            VStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())

                Button {
                    isManualEntryPresented = true
                } label: {
                    Label("Manual Entry", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())
            }
        }
    }

    private var tipsCard: some View {
        DashboardSection(title: "Better OCR") {
            FitnessCard {
                VStack(alignment: .leading, spacing: 12) {
                    labelTip("Keep the label flat", systemImage: "rectangle.compress.vertical")
                    labelTip("Capture the full nutrition table", systemImage: "tablecells")
                    labelTip("Include the food name and per-100 g or serving heading when possible", systemImage: "text.badge.checkmark")
                    labelTip("Avoid glare and shadows", systemImage: "sun.min")
                    labelTip("Make sure the text is sharp", systemImage: "text.magnifyingglass")
                }
            }
        }
    }

    private var processingCard: some View {
        FitnessCard {
            HStack(spacing: 14) {
                SwiftUI.ProgressView()
                    .tint(appTheme.colors.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Reading label...")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text("Extracting text on-device")
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func resultReadyCard(_ result: NutritionOCRResult, parseResult: NutritionParseResult) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "text.viewfinder")
                        .font(AppTypography.compactCardTitle)
                        .foregroundStyle(appTheme.colors.textAccent)
                        .frame(width: 42, height: 42)
                        .background(appTheme.colors.accentSurface, in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text(parseResult.values.isEmpty ? "Text detected" : "Nutrition detected")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(resultSummaryText(result: result, parseResult: parseResult))
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    Text(parseResult.selectedBasis.displayName)
                        .font(AppTypography.badge)
                        .foregroundStyle(appTheme.colors.textAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(appTheme.colors.accentSurface, in: Capsule())

                    Text(parseResult.overallConfidence.displayName)
                        .font(AppTypography.badge)
                        .foregroundStyle(confidenceTint(parseResult.overallConfidence))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(confidenceTint(parseResult.overallConfidence).opacity(0.14), in: Capsule())
                }

                if shouldCompareSources {
                    NavigationLink {
                        NutritionComparisonView(
                            importedDraft: comparisonDraft,
                            labelDraft: draft(from: result, parseResult: parseResult),
                            localFood: localFood
                        )
                    } label: {
                        Label("Compare Sources", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                    .accessibilityLabel("Compare label scan with other nutrition sources")

                    NavigationLink {
                        FoodImportReviewView(draft: draft(from: result, parseResult: parseResult)) {
                            viewModel.reset()
                        }
                    } label: {
                        Label("Review Label Only", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                } else {
                    NavigationLink {
                        FoodImportReviewView(draft: draft(from: result, parseResult: parseResult)) {
                            viewModel.reset()
                        }
                    } label: {
                        Label(parseResult.values.isEmpty ? "Review Detected Text" : "Review Auto-Fill", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                    .accessibilityLabel("Review detected label text")
                }
            }
        }
    }

    private func resultSummaryText(result: NutritionOCRResult, parseResult: NutritionParseResult) -> String {
        if parseResult.values.isEmpty {
            return "\(result.lines.count) lines found, but nutrition values were not detected confidently. You can still fill them manually."
        }

        if shouldCompareSources {
            return "\(parseResult.values.count) values found from \(result.lines.count) OCR lines. Compare them with the existing source before saving."
        }

        return "\(parseResult.values.count) values found from \(result.lines.count) OCR lines. Review the auto-filled fields before saving."
    }

    private func confidenceTint(_ confidence: NutritionParseConfidence) -> Color {
        switch confidence {
        case .high:
            return appTheme.colors.success
        case .medium:
            return appTheme.colors.warning
        case .low:
            return appTheme.colors.danger
        }
    }

    private var noTextCard: some View {
        stateCard(
            title: "Couldn't read the label",
            message: "Try a sharper photo with the full nutrition table visible, or enter the food manually.",
            systemImage: "exclamationmark.triangle",
            tint: appTheme.colors.warning
        )
    }

    private var permissionCard: some View {
        stateCard(
            title: "Camera access is needed",
            message: "Choose an existing photo or use manual entry if you do not want to allow camera access.",
            systemImage: "camera.fill",
            tint: appTheme.colors.warning
        )
    }

    private var unavailableCard: some View {
        stateCard(
            title: "Camera unavailable",
            message: "This device cannot open the camera right now. Photo selection still works for simulator testing.",
            systemImage: "camera.slash",
            tint: appTheme.colors.textSecondary
        )
    }

    private func errorCard(_ message: String) -> some View {
        stateCard(
            title: "Label scan failed",
            message: message,
            systemImage: "exclamationmark.triangle",
            tint: appTheme.colors.danger
        )
    }

    private func stateCard(title: String, message: String, systemImage: String, tint: Color) -> some View {
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(AppTypography.compactCardTitle)
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func labelTip(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(AppTypography.chip)
                .foregroundStyle(appTheme.colors.textAccent)
                .frame(width: 26, height: 26)
                .background(appTheme.colors.accentSurface, in: Circle())

            Text(text)
                .font(AppTypography.body)
                .foregroundStyle(appTheme.colors.textSecondary)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard
                !Task.isCancelled,
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                guard !Task.isCancelled else { return }
                viewModel.imageSelectionFailed()
                return
            }

            guard !Task.isCancelled else { return }
            selectedPhoto = nil
            processImageAfterPickerDismissal(image)
        } catch {
            guard !Task.isCancelled else { return }
            viewModel.imageSelectionFailed()
        }
    }

    private func processImageAfterPickerDismissal(_ image: UIImage) {
        deferredImageProcessingTask?.cancel()
        deferredImageProcessingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            viewModel.process(image: image)
        }
    }

    private func draft(from result: NutritionOCRResult, parseResult: NutritionParseResult) -> FoodImportDraft {
        let values = ParsedNutritionDraftValues(parseResult: parseResult)
        return FoodImportDraft(
            barcode: initialBarcode ?? comparisonDraft?.barcode ?? localFood?.barcode ?? "",
            name: "",
            brand: nil,
            servingSize: parseResult.servingSize?.amount,
            baseUnit: values.baseUnit,
            caloriesPer100g: values.calories,
            proteinPer100g: values.protein,
            carbsPer100g: values.carbs,
            fatPer100g: values.fat,
            sugarPer100g: values.sugar,
            fibrePer100g: values.fibre,
            saltPer100g: values.salt,
            source: .labelScan,
            rawOCRText: result.rawText,
            nutritionParseResult: parseResult
        )
    }

    private var shouldCompareSources: Bool {
        comparisonDraft != nil || localFood != nil
    }
}

struct ParsedNutritionDraftValues {
    let baseUnit: FoodAmountUnit
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let sugar: Double?
    let fibre: Double?
    let salt: Double?

    init(parseResult: NutritionParseResult) {
        baseUnit = parseResult.selectedBasis == .per100ml ? .millilitres : .grams

        guard !parseResult.values.isEmpty else {
            calories = nil
            protein = nil
            carbs = nil
            fat = nil
            sugar = nil
            fibre = nil
            salt = nil
            return
        }

        calories = parseResult.value(for: .calories)?.amount
        protein = parseResult.value(for: .protein)?.amount
        carbs = parseResult.value(for: .carbohydrates)?.amount
        fat = parseResult.value(for: .fat)?.amount
        sugar = parseResult.value(for: .sugars)?.amount
        fibre = parseResult.value(for: .fibre)?.amount
        salt = parseResult.value(for: .salt)?.amount
    }
}
