import SwiftUI
import UIKit

/// Lets a lifter choose an unlocked Summit app icon.
struct SummitAppIconPicker: View {
    let totalMetres: Int

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App icon")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(SummitAppIcon.allCases, id: \.self) { icon in
                    iconTile(icon)
                }
            }
        }
    }

    @ViewBuilder
    private func iconTile(_ icon: SummitAppIcon) -> some View {
        let isUnlocked = icon.unlockMetres <= totalMetres
        let peakName = SummitCatalog.peaks.first { $0.metres == icon.unlockMetres }?.name ?? "the next summit"
        let detail = isUnlocked
            ? "Unlocked"
            : "Unlocks at \(peakName) · \(icon.unlockMetres.formatted()) m"

        Button {
            guard isUnlocked else { return }
            UIApplication.shared.setAlternateIconName(icon.alternateIconName) { _ in
                // The system owns the confirmation UI; failures leave the current icon unchanged.
            }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .topTrailing) {
                    SummitAppIconThumbnail(icon: icon)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if !isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                    }
                }

                Text(icon.rawValue.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .opacity(isUnlocked ? 1 : 0.62)
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(icon.rawValue.capitalized), \(detail)")
        .accessibilityValue(isUnlocked ? "Unlocked" : "Locked")
        .accessibilityHint(isUnlocked ? "Double-tap to use this app icon." : "Reach \(peakName) to unlock this icon.")
    }
}

/// App icon catalog entries aren't ordinary image-set resources, so draw their
/// small gallery previews directly rather than relying on `Image("AppIcon…")`.
private struct SummitAppIconThumbnail: View {
    let icon: SummitAppIcon

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 132
            var context = context
            context.scaleBy(x: scale, y: scale)
            context.clip(to: Path(roundedRect: CGRect(x: 0, y: 0, width: 132, height: 132), cornerRadius: 30))
            draw(icon, in: &context)
        }
    }

    private func draw(_ icon: SummitAppIcon, in context: inout GraphicsContext) {
        switch icon {
        case .topo:
            context.fill(rectangle, with: .color(.black))
            drawContours(in: &context, center: CGPoint(x: 70, y: 62), count: 7, step: 9, scaleX: 1.15, scaleY: 0.9, color: .white.opacity(0.55), lineWidth: 1.3)
            context.fill(Path(ellipseIn: CGRect(x: 64.5, y: 56.5, width: 11, height: 11)), with: .color(.white))
            drawBorder(in: &context)
        case .night:
            context.fill(rectangle, with: .color(.black))
            var seed: Int64 = 7
            for index in 0..<22 {
                seed = (seed * 16_807) % 2_147_483_647
                let x = 10 + CGFloat(seed) / 2_147_483_647 * 112
                seed = (seed * 16_807) % 2_147_483_647
                let y = 12 + CGFloat(seed) / 2_147_483_647 * 62
                let radius: CGFloat = index % 5 == 0 ? 1.3 : 0.8
                context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(Color(red: 0.96, green: 0.96, blue: 0.97)))
            }
            var moon = Path()
            moon.move(to: CGPoint(x: 92, y: 30))
            moon.addCurve(to: CGPoint(x: 102, y: 51), control1: CGPoint(x: 79, y: 31), control2: CGPoint(x: 83, y: 51))
            moon.addCurve(to: CGPoint(x: 92, y: 30), control1: CGPoint(x: 95, y: 50), control2: CGPoint(x: 91, y: 34))
            moon.closeSubpath()
            context.stroke(moon, with: .color(Color(red: 0.96, green: 0.96, blue: 0.97)), lineWidth: 1.5)

            var ridge = Path()
            ridge.move(to: CGPoint(x: 0, y: 104))
            ridge.addLines([CGPoint(x: 22, y: 88), CGPoint(x: 40, y: 94), CGPoint(x: 64, y: 64), CGPoint(x: 80, y: 80), CGPoint(x: 94, y: 70), CGPoint(x: 132, y: 100), CGPoint(x: 132, y: 132), CGPoint(x: 0, y: 132)])
            ridge.closeSubpath()
            context.fill(ridge, with: .color(.black))
            context.stroke(ridge, with: .color(Color(red: 0.96, green: 0.96, blue: 0.97)), lineWidth: 2)
            drawBorder(in: &context)
        case .alpenglow:
            context.fill(rectangle, with: .color(.black))
            stroke([
                CGPoint(x: 0, y: 110), CGPoint(x: 24, y: 96), CGPoint(x: 42, y: 100), CGPoint(x: 58, y: 72), CGPoint(x: 66, y: 60),
                CGPoint(x: 74, y: 70), CGPoint(x: 90, y: 84), CGPoint(x: 108, y: 80), CGPoint(x: 132, y: 98)
            ], in: &context, color: .white.opacity(0.5), lineWidth: 1.6)
            stroke([CGPoint(x: 44, y: 96), CGPoint(x: 58, y: 72), CGPoint(x: 66, y: 60), CGPoint(x: 74, y: 70), CGPoint(x: 86, y: 82)], in: &context, color: Color(red: 1, green: 0.61, blue: 0.48), lineWidth: 3)
            stroke([CGPoint(x: 66, y: 60), CGPoint(x: 66, y: 36)], in: &context, color: Color(red: 1, green: 0.61, blue: 0.48), lineWidth: 2)
            fillPennant(in: &context, poleX: 66, topY: 36, color: Color(red: 1, green: 0.61, blue: 0.48))
            drawBorder(in: &context)
        case .everest:
            context.fill(rectangle, with: .color(Color(red: 0.95, green: 0.94, blue: 0.90)))
            drawContours(in: &context, center: CGPoint(x: 66, y: 120), count: 6, step: 12, scaleX: 1.4, scaleY: 0.7, color: Color(red: 0.08, green: 0.08, blue: 0.08).opacity(0.25), lineWidth: 1)
            stroke([
                CGPoint(x: 8, y: 112), CGPoint(x: 30, y: 90), CGPoint(x: 44, y: 96), CGPoint(x: 66, y: 50), CGPoint(x: 78, y: 66),
                CGPoint(x: 88, y: 58), CGPoint(x: 124, y: 108)
            ], in: &context, color: Color(red: 0.08, green: 0.08, blue: 0.08), lineWidth: 2.4)
            stroke([CGPoint(x: 66, y: 50), CGPoint(x: 66, y: 26)], in: &context, color: Color(red: 0.82, green: 0.38, blue: 0.24), lineWidth: 2)
            fillPennant(in: &context, poleX: 66, topY: 26, color: Color(red: 0.82, green: 0.38, blue: 0.24))
            drawBorder(in: &context)
        }
    }

    private var rectangle: Path {
        Path(CGRect(x: 0, y: 0, width: 132, height: 132))
    }

    private func drawContours(
        in context: inout GraphicsContext,
        center: CGPoint,
        count: Int,
        step: CGFloat,
        scaleX: CGFloat,
        scaleY: CGFloat,
        color: Color,
        lineWidth: CGFloat
    ) {
        for ring in 1...count {
            let radius = 6 + CGFloat(ring) * step
            var path = Path()
            for index in 0...64 {
                let angle = CGFloat(index) / 64 * 2 * .pi
                let wobble = 1
                    + 0.08 * sin(3 * angle + CGFloat(ring) * 0.6)
                    + 0.05 * sin(5 * angle - CGFloat(ring) * 0.4)
                let point = CGPoint(
                    x: center.x - CGFloat(ring) * 1.2 + cos(angle) * radius * wobble * scaleX,
                    y: center.y + CGFloat(ring) * 1.6 + sin(angle) * radius * wobble * scaleY
                )
                if index == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
            path.closeSubpath()
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }

    private func stroke(_ points: [CGPoint], in context: inout GraphicsContext, color: Color, lineWidth: CGFloat) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        path.addLines(Array(points.dropFirst()))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    private func fillPennant(in context: inout GraphicsContext, poleX: CGFloat, topY: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: poleX, y: topY))
        path.addLines([CGPoint(x: poleX + 14, y: topY + 5), CGPoint(x: poleX, y: topY + 10)])
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    private func drawBorder(in context: inout GraphicsContext) {
        let border = Path(roundedRect: CGRect(x: 0.75, y: 0.75, width: 130.5, height: 130.5), cornerRadius: 30)
        context.stroke(border, with: .color(Color(red: 0.17, green: 0.17, blue: 0.18)), lineWidth: 1)
    }
}
