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
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appTheme.mutedText)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(appTheme.mutedText)
                }
            }
        }
        .frame(width: 118, height: 118)
        .accessibilityElement(children: .combine)
    }
}
