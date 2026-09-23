import SwiftUI

// MARK: - Summit Icons

enum CampIcon: CaseIterable {
    case tent
    case canteen
    case flame
    case iceAxe
    case map
    case logbook
    case cairn
    case summitFlag
    case compass
    case carabiner

    var title: String {
        switch self {
        case .tent: return "Tent"
        case .canteen: return "Canteen"
        case .flame: return "Flame"
        case .iceAxe: return "Ice axe"
        case .map: return "Map"
        case .logbook: return "Logbook"
        case .cairn: return "Cairn"
        case .summitFlag: return "Summit flag"
        case .compass: return "Compass"
        case .carabiner: return "Carabiner"
        }
    }
}

struct CampIconView: View {
    @Environment(\.appTheme) private var appTheme

    let icon: CampIcon
    let size: CGFloat
    let accentActive: Bool

    var body: some View {
        ZStack {
            CampIconBaseShape(icon: icon)
                .stroke(
                    appTheme.colors.textPrimary,
                    style: StrokeStyle(lineWidth: size / 16, lineCap: .round, lineJoin: .round)
                )

            CampIconAccentShape(icon: icon)
                .fill(accentActive ? appTheme.colors.alpenglow : appTheme.colors.textPrimary)
                .overlay {
                    CampIconAccentShape(icon: icon)
                        .stroke(
                            accentActive ? appTheme.colors.alpenglow : appTheme.colors.textPrimary,
                            style: StrokeStyle(lineWidth: size / 16, lineCap: .round, lineJoin: .round)
                        )
                }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct CampIconBaseShape: Shape {
    let icon: CampIcon

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch icon {
        case .tent:
            path.move(to: CGPoint(x: 2, y: 20))
            path.addLine(to: CGPoint(x: 12, y: 4))
            path.addLine(to: CGPoint(x: 22, y: 20))
            path.closeSubpath()
            path.move(to: CGPoint(x: 12, y: 4))
            path.addLine(to: CGPoint(x: 12, y: 20))
            path.move(to: CGPoint(x: 9, y: 20))
            path.addLine(to: CGPoint(x: 12, y: 14))
            path.addLine(to: CGPoint(x: 15, y: 20))

        case .canteen:
            path.move(to: CGPoint(x: 10, y: 3))
            path.addLine(to: CGPoint(x: 14, y: 3))
            path.addLine(to: CGPoint(x: 14, y: 6))
            path.addLine(to: CGPoint(x: 16, y: 6))
            path.addQuadCurve(to: CGPoint(x: 18, y: 8), control: CGPoint(x: 18, y: 6))
            path.addLine(to: CGPoint(x: 18, y: 19))
            path.addQuadCurve(to: CGPoint(x: 16, y: 21), control: CGPoint(x: 18, y: 21))
            path.addLine(to: CGPoint(x: 8, y: 21))
            path.addQuadCurve(to: CGPoint(x: 6, y: 19), control: CGPoint(x: 6, y: 21))
            path.addLine(to: CGPoint(x: 6, y: 8))
            path.addQuadCurve(to: CGPoint(x: 8, y: 6), control: CGPoint(x: 6, y: 6))
            path.addLine(to: CGPoint(x: 10, y: 6))
            path.closeSubpath()
            path.move(to: CGPoint(x: 6, y: 12))
            path.addLine(to: CGPoint(x: 18, y: 12))

        case .flame:
            path.move(to: CGPoint(x: 12, y: 3))
            path.addCurve(
                to: CGPoint(x: 17, y: 14),
                control1: CGPoint(x: 13, y: 7),
                control2: CGPoint(x: 17, y: 9)
            )
            path.addCurve(
                to: CGPoint(x: 7, y: 14),
                control1: CGPoint(x: 17, y: 20),
                control2: CGPoint(x: 7, y: 20)
            )
            path.addCurve(
                to: CGPoint(x: 9, y: 7),
                control1: CGPoint(x: 7, y: 11),
                control2: CGPoint(x: 9, y: 10)
            )
            path.addCurve(
                to: CGPoint(x: 11, y: 11),
                control1: CGPoint(x: 10.5, y: 8.5),
                control2: CGPoint(x: 11, y: 10)
            )
            path.addCurve(
                to: CGPoint(x: 12, y: 3),
                control1: CGPoint(x: 12.5, y: 9),
                control2: CGPoint(x: 12.5, y: 6)
            )
            path.closeSubpath()

        case .iceAxe:
            path.move(to: CGPoint(x: 3, y: 7))
            path.addQuadCurve(to: CGPoint(x: 21, y: 6), control: CGPoint(x: 11, y: 3))
            path.move(to: CGPoint(x: 11.5, y: 5))
            path.addLine(to: CGPoint(x: 13.5, y: 21))
            path.addLine(to: CGPoint(x: 14, y: 23))

        case .map:
            path.move(to: CGPoint(x: 3, y: 6))
            path.addLine(to: CGPoint(x: 9, y: 4))
            path.addLine(to: CGPoint(x: 15, y: 6))
            path.addLine(to: CGPoint(x: 21, y: 4))
            path.addLine(to: CGPoint(x: 21, y: 18))
            path.addLine(to: CGPoint(x: 15, y: 20))
            path.addLine(to: CGPoint(x: 9, y: 18))
            path.addLine(to: CGPoint(x: 3, y: 20))
            path.closeSubpath()
            path.move(to: CGPoint(x: 9, y: 4))
            path.addLine(to: CGPoint(x: 9, y: 18))
            path.move(to: CGPoint(x: 15, y: 6))
            path.addLine(to: CGPoint(x: 15, y: 20))

        case .logbook:
            path.move(to: CGPoint(x: 6, y: 3))
            path.addLine(to: CGPoint(x: 19, y: 3))
            path.addLine(to: CGPoint(x: 19, y: 21))
            path.addLine(to: CGPoint(x: 8, y: 21))
            path.addQuadCurve(to: CGPoint(x: 6, y: 19), control: CGPoint(x: 6, y: 21))
            path.closeSubpath()
            path.move(to: CGPoint(x: 6, y: 19))
            path.addQuadCurve(to: CGPoint(x: 8, y: 17), control: CGPoint(x: 6, y: 17))
            path.addLine(to: CGPoint(x: 19, y: 17))
            path.move(to: CGPoint(x: 10, y: 7))
            path.addLine(to: CGPoint(x: 16, y: 7))
            path.move(to: CGPoint(x: 10, y: 10))
            path.addLine(to: CGPoint(x: 14, y: 10))

        case .cairn:
            path.addEllipse(in: CGRect(x: 5, y: 17.3, width: 14, height: 4.4))
            path.addEllipse(in: CGRect(x: 7, y: 14.05, width: 10, height: 3.8))
            path.addEllipse(in: CGRect(x: 9, y: 10, width: 6.4, height: 3.2))

        case .summitFlag:
            path.move(to: CGPoint(x: 2, y: 21))
            path.addLine(to: CGPoint(x: 10, y: 9))
            path.addLine(to: CGPoint(x: 13, y: 13))
            path.addLine(to: CGPoint(x: 15, y: 11))
            path.addLine(to: CGPoint(x: 22, y: 21))
            path.closeSubpath()
            path.move(to: CGPoint(x: 10, y: 9))
            path.addLine(to: CGPoint(x: 10, y: 2))

        case .compass:
            path.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            path.move(to: CGPoint(x: 15.5, y: 8.5))
            path.addLine(to: CGPoint(x: 13.2, y: 13.2))
            path.addLine(to: CGPoint(x: 8.5, y: 15.5))
            path.addLine(to: CGPoint(x: 10.8, y: 10.8))
            path.closeSubpath()

        case .carabiner:
            path.move(to: CGPoint(x: 9, y: 3))
            path.addLine(to: CGPoint(x: 14, y: 3))
            path.addCurve(
                to: CGPoint(x: 19, y: 8),
                control1: CGPoint(x: 16.76, y: 3),
                control2: CGPoint(x: 19, y: 5.24)
            )
            path.addLine(to: CGPoint(x: 19, y: 16))
            path.addCurve(
                to: CGPoint(x: 14, y: 21),
                control1: CGPoint(x: 19, y: 18.76),
                control2: CGPoint(x: 16.76, y: 21)
            )
            path.addLine(to: CGPoint(x: 10, y: 21))
            path.addCurve(
                to: CGPoint(x: 5, y: 16),
                control1: CGPoint(x: 7.24, y: 21),
                control2: CGPoint(x: 5, y: 18.76)
            )
            path.addLine(to: CGPoint(x: 5, y: 7))
            path.addCurve(
                to: CGPoint(x: 9, y: 3),
                control1: CGPoint(x: 5, y: 4.79),
                control2: CGPoint(x: 6.79, y: 3)
            )
            path.closeSubpath()
            path.move(to: CGPoint(x: 9, y: 7))
            path.addLine(to: CGPoint(x: 9, y: 16))
        }

        return scaled(path, to: rect)
    }
}

private struct CampIconAccentShape: Shape {
    let icon: CampIcon

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch icon {
        case .cairn:
            path.addEllipse(in: CGRect(x: 10.6, y: 6.1, width: 3.6, height: 2.2))
        case .summitFlag:
            path.move(to: CGPoint(x: 10, y: 2))
            path.addLine(to: CGPoint(x: 16, y: 4))
            path.addLine(to: CGPoint(x: 10, y: 6))
            path.closeSubpath()
        default:
            break
        }
        return scaled(path, to: rect)
    }
}

private func scaled(_ path: Path, to rect: CGRect) -> Path {
    let scaleX = rect.width / 24
    let scaleY = rect.height / 24
    var transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
    transform.tx = rect.minX
    transform.ty = rect.minY
    return path.applying(transform)
}

#Preview("Camp icons · dark") {
    CampIconPreviewGrid()
        .environment(\.appTheme, .black)
        .preferredColorScheme(.dark)
}

#Preview("Camp icons · light") {
    CampIconPreviewGrid()
        .environment(\.appTheme, .black)
        .preferredColorScheme(.light)
}

private struct CampIconPreviewGrid: View {
    @Environment(\.appTheme) private var appTheme
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 2)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(Array(CampIcon.allCases.enumerated()), id: \.offset) { index, icon in
                HStack(spacing: 12) {
                    CampIconView(icon: icon, size: 36, accentActive: index == 6 || index == 7)
                    Text(icon.title)
                        .font(.subheadline.weight(.medium))
                }
                .frame(minHeight: 44, alignment: .leading)
            }
        }
        .padding(24)
        .background(appTheme.colors.backgroundPrimary)
    }
}
