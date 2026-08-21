import SwiftData
import SwiftUI

let healthKitSleepAuthorizationRequestedKey = "sleep.healthkit.authorizationRequested.v1"

@MainActor
final class SleepHealthKitExportStatusStore: ObservableObject {
    static let shared = SleepHealthKitExportStatusStore()

    @Published private(set) var message: String?

    private init() {}

    func begin() {
        message = "Saving confirmed sleep to Apple Health…"
    }

    func succeeded(sampleCount: Int) {
        message = sampleCount == 1
            ? "Saved confirmed sleep to Apple Health (1 sample)."
            : "Saved confirmed sleep to Apple Health (\(sampleCount) samples)."
    }

    func failed(_ message: String) {
        self.message = message
    }
}

@MainActor
private func applySleepHealthKitExport(
    _ ids: [String],
    to sessionID: UUID,
    in container: ModelContainer,
    statusStore: SleepHealthKitExportStatusStore
) {
    // Resolve the app's live context only after HealthKit has returned. The
    // container is stable across the suspension; a ModelContext or model must
    // not be retained by the task while the HealthKit write is in flight.
    let modelContext = container.mainContext
    let descriptor = FetchDescriptor<SleepSession>(
        predicate: #Predicate<SleepSession> { $0.id == sessionID }
    )

    do {
        guard let session = try modelContext.fetch(descriptor).first else {
            statusStore.failed("Apple Health accepted the sleep, but Peakline could not record the export. Local sleep was saved.")
            return
        }

        let previousSampleIDs = session.healthKitSampleIds
        let hadChangesBeforeExport = modelContext.hasChanges
        session.healthKitSampleIds = ids

        do {
            try modelContext.save()
            statusStore.succeeded(sampleCount: ids.count)
        } catch {
            // Keep unrelated pending edits in this context, but never leave a
            // failed export's sample IDs dirty for a later unrelated save.
            if hadChangesBeforeExport {
                session.healthKitSampleIds = previousSampleIDs
            } else {
                modelContext.rollback()
            }
            throw error
        }
    } catch {
        statusStore.failed("Apple Health accepted the sleep, but Peakline could not record the export. Local sleep was saved. \(error.localizedDescription)")
    }
}

@MainActor
func scheduleSleepHealthKitExport(
    for session: SleepSession,
    in modelContext: ModelContext
) {
    scheduleSleepHealthKitExport(
        for: session,
        in: modelContext,
        statusStore: SleepHealthKitExportStatusStore.shared
    )
}

@MainActor
func scheduleSleepHealthKitExport(
    for session: SleepSession,
    in modelContext: ModelContext,
    statusStore: SleepHealthKitExportStatusStore
) {
    let writeSnapshot = HealthKitSleepWriteSnapshot(session: session)
    let sessionID = writeSnapshot.id
    let container = modelContext.container
    statusStore.begin()
    PerformanceTracer.mark(.healthKitSleepBridge, "export scheduled session=\(sessionID.uuidString)")

    Task(priority: .utility) { @MainActor in
        do {
            let ids = try await HealthKitSleepService().writeConfirmedSession(writeSnapshot)
            applySleepHealthKitExport(ids, to: sessionID, in: container, statusStore: statusStore)
        } catch {
            statusStore.failed("Apple Health export failed. Local sleep was saved. \(error.localizedDescription)")
        }
    }
}

struct SleepCard<Content: View>: View {
    var style: FitnessCardStyle = .standard
    var padding: CGFloat?
    @ViewBuilder var content: () -> Content

    var body: some View {
        FitnessCard(style: style, padding: padding) {
            content()
        }
    }
}

struct SleepIcon: View {
    let systemImage: String
    var size: CGFloat = 44
    var tint: Color?

    var body: some View {
        FitnessIconBadge(systemImage: systemImage, size: size, tint: tint)
    }
}

struct SleepRow<Trailing: View>: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color?
    var showsChevron = false
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color? = nil,
        showsChevron: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.showsChevron = showsChevron
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SleepIcon(systemImage: systemImage, size: appTheme.metrics.rowIconSize, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            trailing()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(appTheme.colors.textTertiary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

struct SleepQuietAction: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: appTheme.metrics.minimumHitTarget)
                .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(appTheme.colors.cardBorder, lineWidth: 1)
                }
        }
        .buttonStyle(PeaklineButtonPressStyle())
    }
}

struct SleepActionButton: View {
    enum Style {
        case primary
        case secondary
        case neutral
        case danger
    }

    @Environment(\.appTheme) private var appTheme

    let title: String
    let systemImage: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(labelFont)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(foreground)
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: appTheme.metrics.buttonHeight)
                .frame(maxWidth: .infinity)
                .background(background, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(border, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PeaklineButtonPressStyle())
    }

    private var labelFont: Font {
        switch style {
        case .primary:
            return .headline.weight(.semibold)
        case .secondary, .neutral, .danger:
            return .subheadline.weight(.semibold)
        }
    }

    private var horizontalPadding: CGFloat {
        style == .primary ? 16 : 10
    }

    private var foreground: Color {
        switch style {
        case .primary:
            return appTheme.colors.accentForeground
        case .secondary:
            return appTheme.colors.textPrimary
        case .neutral:
            return appTheme.colors.textSecondary
        case .danger:
            return .white
        }
    }

    private var background: Color {
        switch style {
        case .primary:
            return appTheme.colors.accent
        case .secondary, .neutral:
            return appTheme.colors.cardBackgroundElevated
        case .danger:
            return appTheme.colors.danger
        }
    }

    private var border: Color {
        switch style {
        case .primary:
            return appTheme.colors.accent.opacity(0.45)
        case .secondary, .neutral:
            return appTheme.colors.cardBorder
        case .danger:
            return appTheme.colors.danger.opacity(0.45)
        }
    }
}

struct SleepMetric: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let value: String
    var systemImage: String?
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }

                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
            }
            .foregroundStyle(tint ?? appTheme.colors.textSecondary)

            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

struct SleepMiniMetric: View {
    let title: String
    let value: String

    var body: some View {
        SleepMetric(title: title, value: value)
    }
}

struct SleepStageBreakdownView: View {
    @Environment(\.appTheme) private var appTheme

    let breakdown: SleepStageBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apple Health stages")
                .font(.caption.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
                .textCase(.uppercase)

            FlowLayout(spacing: 8) {
                if let awakeMinutes = breakdown.awakeMinutes {
                    SleepMiniMetric(title: "Awake", value: SleepScoringService.durationText(minutes: awakeMinutes))
                }
                if let remMinutes = breakdown.remMinutes {
                    SleepMiniMetric(title: "REM", value: SleepScoringService.durationText(minutes: remMinutes))
                }
                if let coreMinutes = breakdown.coreMinutes {
                    SleepMiniMetric(title: "Core", value: SleepScoringService.durationText(minutes: coreMinutes))
                }
                if let deepMinutes = breakdown.deepMinutes {
                    SleepMiniMetric(title: "Deep", value: SleepScoringService.durationText(minutes: deepMinutes))
                }
            }
        }
    }
}

struct SleepQualityPicker: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var selection: Int?

    var body: some View {
        Menu {
            Button {
                update(nil)
            } label: {
                if selection == nil {
                    Label("Not rated", systemImage: "checkmark")
                } else {
                    Text("Not rated")
                }
            }

            ForEach(1...5, id: \.self) { value in
                Button {
                    update(value)
                } label: {
                    if selection == value {
                        Label(Self.label(for: value), systemImage: "checkmark")
                    } else {
                        Text(Self.label(for: value))
                    }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sleep quality")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textSecondary)
                    Text(selection.map(Self.label) ?? "Not rated")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: appTheme.metrics.minimumHitTarget, alignment: .leading)
        }
        .accessibilityLabel("Sleep quality")
        .accessibilityValue(selection.map(Self.label) ?? "Not rated")
        .accessibilityIdentifier("sleep-quality-picker")
    }

    private func update(_ value: Int?) {
        AppHaptics.selection()
        PerformanceTracer.trace(.motionRatingSelect) {
            withAnimation(AppMotion.ratingSelect(reduceMotion: reduceMotion)) {
                selection = value
            }
        }
    }

    static func label(for value: Int) -> String {
        switch value {
        case 1:
            return "Very poor"
        case 2:
            return "Poor"
        case 3:
            return "Okay"
        case 4:
            return "Good"
        default:
            return "Excellent"
        }
    }

}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
