import AVFoundation
import SwiftData
import SwiftUI

struct BarcodeScannerView: View {
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \FoodItem.name)
    private var foodItems: [FoodItem]

    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var lookupState: BarcodeLookupState = .idle
    @State private var isScanning = true
    @State private var isManualEntryPresented = false
    @State private var manualBarcode = ""
    @State private var editingFood: FoodItem?
    @State private var scannerErrorMessage: String?
    @State private var pendingManualBarcode: String?
    @State private var delayedLookupTask: Task<Void, Never>?
    @State private var lookupTask: Task<Void, Never>?
    @State private var selectedRoute: BarcodeScannerRoute?

    private let lookupService = BarcodeFoodLookupService()

    var body: some View {
        FitnessScreen(
            title: "Scan Barcode",
            subtitle: "Check saved foods first, then import nutrition data.",
            systemImage: "barcode.viewfinder"
        ) {
            switch authorizationStatus {
            case .authorized:
                if cameraAvailable {
                    scannerContent
                } else {
                    scannerUnavailableCard(
                        title: "Camera unavailable",
                        message: "This device cannot open a barcode scanner. Enter a barcode manually to use the same local-first lookup flow.",
                        systemImage: "camera.fill"
                    )
                }
            case .notDetermined:
                permissionRequestCard
            case .denied, .restricted:
                scannerUnavailableCard(
                    title: "Camera access needed",
                    message: "Enable camera access to scan barcodes, or enter a barcode manually.",
                    systemImage: "camera.fill"
                )
            @unknown default:
                scannerUnavailableCard(
                    title: "Camera unavailable",
                    message: "Enter a barcode manually to use the same local-first lookup flow.",
                    systemImage: "camera.fill"
                )
            }
        }
        .navigationTitle("Scan Barcode")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshAuthorization()
        }
        .sheet(isPresented: $isManualEntryPresented) {
            manualBarcodeSheet
        }
        .sheet(item: $editingFood) { food in
            ManualFoodEntryView(food: food)
        }
        .navigationDestination(item: $selectedRoute) { route in
            barcodeDestination(route)
        }
        .onChange(of: isManualEntryPresented) { _, isPresented in
            guard !isPresented, let barcode = pendingManualBarcode else { return }
            pendingManualBarcode = nil
            scheduleLookup(for: barcode, afterNanoseconds: 150_000_000)
        }
        .onDisappear {
            delayedLookupTask?.cancel()
            lookupTask?.cancel()
        }
    }

    @ViewBuilder
    private var scannerContent: some View {
        if case .idle = lookupState, isScanning {
            if let scannerErrorMessage {
                scannerUnavailableCard(
                    title: "Camera unavailable",
                    message: scannerErrorMessage,
                    systemImage: "camera.fill"
                )
            } else {
                scannerPreviewCard
            }
        }

        lookupStateContent

        Button {
            isManualEntryPresented = true
        } label: {
            Label("Enter Barcode Manually", systemImage: "keyboard")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryFitnessButtonStyle())
    }

    private var scannerPreviewCard: some View {
        FitnessCard(padding: 0) {
            ZStack {
                BarcodeScannerRepresentable { barcode in
                    handleDetectedBarcode(barcode)
                } onError: { message in
                    scannerErrorMessage = message
                    isScanning = false
                }
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                VStack {
                    Spacer()

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(appTheme.colors.accent, lineWidth: 3)
                        .frame(height: 150)
                        .padding(.horizontal, 34)
                        .shadow(color: appTheme.colors.accent.opacity(0.32), radius: 18)

                    Spacer()

                    Text("Hold the barcode inside the frame")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.52), in: Capsule())
                        .padding(.bottom, 18)
                }
                .accessibilityHidden(true)
            }
        }
    }

    private var cameraAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    @ViewBuilder
    private var lookupStateContent: some View {
        switch lookupState {
        case .idle:
            NutritionScannerStatusCard(
                title: "Ready to scan",
                message: "GymTracker will stop after the first barcode and check your saved foods before using Open Food Facts.",
                systemImage: "barcode.viewfinder"
            )
        case .checkingLocal(let barcode):
            NutritionLoadingCard(title: "Checking saved foods", message: barcode)
        case .fetchingRemote(let barcode):
            NutritionLoadingCard(title: "Searching Open Food Facts", message: barcode)
        case .localFound(let food):
            localFoundCard(food)
        case .remoteFound(let draft):
            importedDraftCard(draft, isIncomplete: false)
        case .remoteIncomplete(let draft):
            importedDraftCard(draft, isIncomplete: true)
        case .notFound(let barcode):
            notFoundCard(barcode: barcode)
        case .error(let message, let barcode):
            errorCard(message: message, barcode: barcode)
        }
    }

    private var permissionRequestCard: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                NutritionScannerIcon(systemImage: "camera.fill")

                VStack(alignment: .leading, spacing: 5) {
                    Text("Camera permission")
                        .font(.title3.bold())
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text("GymTracker uses the camera to scan food barcodes for nutrition tracking.")
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await requestCameraAccess() }
                } label: {
                    Label("Allow Camera", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())
            }
        }
    }

    private func scannerUnavailableCard(title: String, message: String, systemImage: String) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                NutritionScannerIcon(systemImage: systemImage)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    isManualEntryPresented = true
                } label: {
                    Label("Enter Barcode Manually", systemImage: "keyboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())
            }
        }
    }

    private func localFoundCard(_ food: FoodItem) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 16) {
                ResultHeader(
                    title: "Saved food found",
                    message: "Local verified data wins over public database results.",
                    badge: "Saved Food",
                    systemImage: "checkmark.seal.fill"
                )

                BarcodeFoodSummary(food: food)

                HStack(spacing: 8) {
                    Button {
                        selectedRoute = .logFood(food.id)
                    } label: {
                        Label("Log Food", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())

                    Button {
                        editingFood = food
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .background(appTheme.colors.cardBackgroundElevated, in: Circle())
                    .accessibilityLabel("Edit \(food.name)")
                }

                Button {
                    selectedRoute = .labelScan(
                        barcode: food.barcode,
                        comparisonDraft: nil,
                        localFoodID: food.id
                    )
                } label: {
                    Label("Review against Label", systemImage: "text.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())

                scanAgainButton
            }
        }
    }

    private func importedDraftCard(_ draft: FoodImportDraft, isIncomplete: Bool) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 16) {
                ResultHeader(
                    title: isIncomplete ? "Product needs review" : "Open Food Facts match",
                    message: isIncomplete
                        ? "Some values are missing. Complete them before saving locally."
                        : "Review the public database values before saving them locally.",
                    badge: "Open Food Facts",
                    systemImage: isIncomplete ? "exclamationmark.triangle.fill" : "network"
                )

                ImportedDraftSummary(draft: draft)

                Button {
                    selectedRoute = .reviewDraft(draft)
                } label: {
                    Label(isIncomplete ? "Complete Manually" : "Review & Save", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())

                Button {
                    selectedRoute = .labelScan(
                        barcode: draft.barcode,
                        comparisonDraft: draft,
                        localFoodID: nil
                    )
                } label: {
                    Label(isIncomplete ? "Scan Label to Complete" : "Verify with Label Scan", systemImage: "text.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())

                scanAgainButton
            }
        }
    }

    private func notFoundCard(barcode: String) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 16) {
                ResultHeader(
                    title: "Product not found",
                    message: "No saved food or Open Food Facts product matched this barcode.",
                    badge: barcode,
                    systemImage: "questionmark.circle.fill"
                )

                Button {
                    selectedRoute = .reviewDraft(emptyDraft(for: barcode))
                } label: {
                    Label("Create Food Manually", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())

                Button {
                    selectedRoute = .labelScan(
                        barcode: barcode,
                        comparisonDraft: nil,
                        localFoodID: nil
                    )
                } label: {
                    Label("Scan Label Instead", systemImage: "text.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())

                scanAgainButton
            }
        }
    }

    private func errorCard(message: String, barcode: String?) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 16) {
                ResultHeader(
                    title: "Lookup failed",
                    message: message,
                    badge: barcode ?? "Error",
                    systemImage: "wifi.exclamationmark"
                )

                if let barcode {
                    Button {
                        lookupBarcode(barcode)
                    } label: {
                        Label("Retry Lookup", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())

                    Button {
                        selectedRoute = .labelScan(
                            barcode: barcode,
                            comparisonDraft: nil,
                            localFoodID: nil
                        )
                    } label: {
                        Label("Scan Label Instead", systemImage: "text.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                }

                scanAgainButton
            }
        }
    }

    private var scanAgainButton: some View {
        Button {
            delayedLookupTask?.cancel()
            lookupTask?.cancel()
            scannerErrorMessage = nil
            lookupState = .idle
            isScanning = true
        } label: {
            Label("Scan Again", systemImage: "barcode.viewfinder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(NeutralFitnessButtonStyle())
    }

    private var manualBarcodeSheet: some View {
        NavigationStack {
            FitnessScreen(
                title: "Enter Barcode",
                subtitle: "Use the same local-first lookup without the camera.",
                systemImage: "keyboard"
            ) {
                FitnessCard {
                    VStack(spacing: 14) {
                        TextField("Barcode", text: $manualBarcode)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 52)
                            .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Button {
                            let barcode = manualBarcode
                            pendingManualBarcode = barcode
                            manualBarcode = ""
                            isManualEntryPresented = false
                        } label: {
                            Label("Lookup Barcode", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryFitnessButtonStyle())
                    }
                }
            }
            .navigationTitle("Enter Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isManualEntryPresented = false
                    }
                }
            }
        }
    }

    private func handleDetectedBarcode(_ barcode: String) {
        guard isScanning else { return }
        scheduleLookup(for: barcode, afterNanoseconds: 180_000_000)
    }

    private func scheduleLookup(for barcode: String, afterNanoseconds delay: UInt64) {
        delayedLookupTask?.cancel()
        delayedLookupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            isScanning = false
            lookupBarcode(barcode)
        }
    }

    private func lookupBarcode(_ barcode: String) {
        lookupTask?.cancel()
        scannerErrorMessage = nil

        let normalizedBarcode = BarcodeFoodLookupService.normalizedBarcode(barcode)
        guard !normalizedBarcode.isEmpty else {
            lookupState = .error(message: "Enter a valid barcode.", barcode: nil)
            return
        }

        lookupState = .checkingLocal(normalizedBarcode)
        if let local = lookupService.findLocalFood(by: normalizedBarcode, in: foodItems) {
            lookupState = .localFound(local)
            return
        }

        lookupTask = Task { @MainActor in
            lookupState = .fetchingRemote(normalizedBarcode)
            let result = await lookupService.lookupRemote(barcode: normalizedBarcode)
            guard !Task.isCancelled else { return }
            lookupState = result
        }
    }

    private func refreshAuthorization() async {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func requestCameraAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = granted ? .authorized : AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func emptyDraft(for barcode: String) -> FoodImportDraft {
        FoodImportDraft(
            barcode: BarcodeFoodLookupService.normalizedBarcode(barcode),
            name: "",
            brand: nil,
            servingSize: nil,
            baseUnit: .grams,
            caloriesPer100g: nil,
            proteinPer100g: nil,
            carbsPer100g: nil,
            fatPer100g: nil,
            sugarPer100g: nil,
            fibrePer100g: nil,
            saltPer100g: nil,
            source: .manual
        )
    }

    @ViewBuilder
    private func barcodeDestination(_ route: BarcodeScannerRoute) -> some View {
        switch route {
        case .logFood(let foodID):
            if let food = food(with: foodID) {
                LogFoodView(food: food)
            } else {
                staleFoodRouteCard
            }
        case .reviewDraft(let draft):
            FoodImportReviewView(draft: draft)
        case .labelScan(let barcode, let comparisonDraft, let localFoodID):
            NutritionLabelScanView(
                initialBarcode: barcode,
                comparisonDraft: comparisonDraft,
                localFood: localFoodID.flatMap(food(with:))
            )
        }
    }

    private func food(with id: UUID) -> FoodItem? {
        foodItems.first { $0.id == id }
    }

    private var staleFoodRouteCard: some View {
        FitnessScreen(
            title: "Food unavailable",
            subtitle: "Go back and try again.",
            systemImage: "exclamationmark.triangle"
        ) {
            scannerUnavailableCard(
                title: "Food unavailable",
                message: "The selected food is no longer available.",
                systemImage: "exclamationmark.triangle"
            )
        }
    }
}

private enum BarcodeScannerRoute: Hashable, Identifiable {
    case logFood(UUID)
    case reviewDraft(FoodImportDraft)
    case labelScan(barcode: String?, comparisonDraft: FoodImportDraft?, localFoodID: UUID?)

    var id: Self { self }
}

private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onDetected: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let controller = BarcodeScannerViewController()
        controller.onDetected = onDetected
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {
        uiViewController.onDetected = onDetected
        uiViewController.onError = onError
    }
}

private final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onDetected: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.peakline.barcode-scanner.session", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didDetectBarcode = false
    private var isSessionConfigured = false
    private var isViewVisible = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurePreviewLayer()
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        didDetectBarcode = false
        setSessionVisible(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setSessionVisible(false)
    }

    private func configurePreviewLayer() {
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer
    }

    private func configureSession() {
        guard !isSessionConfigured else { return }

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            reportError("The camera could not be prepared. Check camera permission and try again, or enter the barcode manually.")
            return
        }

        session.beginConfiguration()
        session.addInput(input)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            session.commitConfiguration()
            reportError("The barcode scanner could not be prepared. Enter the barcode manually to continue.")
            return
        }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput.metadataObjectTypes = supportedBarcodeTypes.filter { metadataOutput.availableMetadataObjectTypes.contains($0) }
        session.commitConfiguration()
        isSessionConfigured = true

        if isViewVisible {
            startSessionIfNeeded()
        }
    }

    private func setSessionVisible(_ isVisible: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.isViewVisible = isVisible
            if isVisible {
                self.startSessionIfNeeded()
            } else {
                self.stopSessionIfNeeded()
            }
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            self?.stopSessionIfNeeded()
        }
    }

    private func startSessionIfNeeded() {
        guard isSessionConfigured, !session.isRunning else { return }
        session.startRunning()
    }

    private func stopSessionIfNeeded() {
        guard session.isRunning else { return }
        session.stopRunning()
    }

    private func reportError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(message)
        }
    }

    private var supportedBarcodeTypes: [AVMetadataObject.ObjectType] {
        [.ean13, .ean8, .upce, .code128]
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didDetectBarcode else { return }
        guard
            let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let stringValue = metadataObject.stringValue
        else {
            return
        }

        didDetectBarcode = true
        stopSession()
        DispatchQueue.main.async { [weak self] in
            self?.onDetected?(stringValue)
        }
    }
}

private struct NutritionScannerStatusCard: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                NutritionScannerIcon(systemImage: systemImage)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct NutritionLoadingCard: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let message: String

    var body: some View {
        FitnessCard {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(appTheme.colors.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }
            }
        }
    }
}

private struct ResultHeader: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let message: String
    let badge: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NutritionScannerIcon(systemImage: systemImage)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(appTheme.colors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(appTheme.colors.accentSurface, in: Capsule())
                        .lineLimit(1)
                }

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BarcodeFoodSummary: View {
    @Environment(\.appTheme) private var appTheme

    let food: FoodItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(food.name)
                .font(.headline)
            if let brand = food.brand, !brand.isEmpty {
                Text(brand)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
            MacroPreviewLine(
                calories: food.caloriesPer100g,
                protein: food.proteinPer100g,
                carbs: food.carbsPer100g,
                fat: food.fatPer100g
            )
        }
    }
}

private struct ImportedDraftSummary: View {
    @Environment(\.appTheme) private var appTheme

    let draft: FoodImportDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.name.isEmpty ? "Unnamed product" : draft.name)
                .font(.headline)
            if let brand = draft.brand, !brand.isEmpty {
                Text(brand)
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
            MacroPreviewLine(
                calories: draft.caloriesPer100g,
                protein: draft.proteinPer100g,
                carbs: draft.carbsPer100g,
                fat: draft.fatPer100g
            )
        }
    }
}

private struct MacroPreviewLine: View {
    @Environment(\.appTheme) private var appTheme

    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?

    var body: some View {
        HStack(spacing: 8) {
            macroChip("kcal", calories, suffix: "")
            macroChip("P", protein)
            macroChip("C", carbs)
            macroChip("F", fat)
        }
    }

    private func macroChip(_ title: String, _ value: Double?, suffix: String = "g") -> some View {
        VStack(spacing: 2) {
            Text(value.map { $0.formatted(.number.precision(.fractionLength(0...1))) + suffix } ?? "--")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(value == nil ? appTheme.colors.warning : appTheme.colors.textPrimary)
                .lineLimit(1)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct NutritionScannerIcon: View {
    @Environment(\.appTheme) private var appTheme

    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(appTheme.colors.accent)
            .frame(width: 42, height: 42)
            .background(appTheme.colors.accentSurface, in: Circle())
    }
}
