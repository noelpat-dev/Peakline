import SwiftUI

struct ProgressArcView: View {
    @Environment(\.appTheme) private var appTheme

    let value: Double
    let label: String
    let caption: String?

    var body: some View {
        ZStack {
            Circle()
                .stroke(appTheme.elevatedCardBackground, lineWidth: 12)

            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(appTheme.colors.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
                    .font(AppTypography.cardTitle)
                Text(label)
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(appTheme.mutedText)
                if let caption {
                    Text(caption)
                        .font(AppTypography.badge)
                        .foregroundStyle(appTheme.mutedText)
                }
            }
        }
        .frame(width: 118, height: 118)
        .accessibilityElement(children: .combine)
    }
}

struct AttendanceRingView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double
    let label: String
    let caption: String?
    let generation: String
    @Binding var revealedGeneration: String?

    @State private var animatedValue = 0.0
    @State private var revealTask: Task<Void, Never>?

    init(
        value: Double,
        label: String,
        caption: String?,
        generation: String,
        revealedGeneration: Binding<String?>
    ) {
        self.value = value
        self.label = label
        self.caption = caption
        self.generation = generation
        _revealedGeneration = revealedGeneration
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(appTheme.elevatedCardBackground, lineWidth: 10)

            Circle()
                .trim(from: 0, to: displayedArcValue)
                .stroke(appTheme.colors.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
                    .font(AppTypography.cardTitle.monospacedDigit())
                Text(label)
                    .font(AppTypography.badge)
                    .foregroundStyle(appTheme.mutedText)
                if let caption {
                    Text(caption)
                        .font(AppTypography.badge)
                        .foregroundStyle(appTheme.mutedText)
                }
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
        .onAppear {
            revealIfNeeded()
        }
        .onChange(of: generation) { _, _ in
            revealIfNeeded()
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
        }
    }

    private var displayedArcValue: Double {
        let finalValue = min(max(value, 0), 1)
        return reduceMotion || revealedGeneration == generation ? finalValue : min(max(animatedValue, 0), 1)
    }

    private var accessibilityValue: String {
        let percentage = Int((min(max(value, 0), 1) * 100).rounded())
        if let caption, !caption.isEmpty {
            return "\(percentage) percent, \(caption)"
        }
        return "\(percentage) percent"
    }

    private func revealIfNeeded() {
        guard revealedGeneration != generation else { return }
        let finalValue = min(max(value, 0), 1)
        guard !reduceMotion else { return }

        revealTask?.cancel()
        animatedValue = 0
        revealTask = Task { @MainActor in
            // Let the root tab's stable-frame turn complete before the chart
            // starts drawing. This keeps motion from owning route readiness.
            await Task.yield()
            await Task.yield()
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.attendanceRing(reduceMotion: false)) {
                revealedGeneration = generation
                animatedValue = finalValue
            }
            revealTask = nil
        }
    }
}
