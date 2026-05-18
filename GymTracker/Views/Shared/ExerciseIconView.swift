import SwiftUI
import UIKit

struct ExerciseIconView: View {
    @Environment(\.appTheme) private var appTheme

    let iconKey: ExerciseIconKey
    var size: CGFloat = 44
    var tint: Color?
    var showBackground = false
    var isDisabled = false
    var isDecorative = false

    private var tintColor: Color {
        if isDisabled {
            return appTheme.colors.textTertiary
        }

        return tint ?? appTheme.colors.accent
    }

    var body: some View {
        icon
            .frame(width: iconSize, height: iconSize)
            .foregroundStyle(tintColor)
            .frame(width: size, height: size)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: max(8, size * 0.26), style: .continuous))
            .overlay(border)
            .accessibilityHidden(isDecorative)
            .accessibilityLabel("\(iconKey.accessibilityName) exercise icon")
    }

    @ViewBuilder
    private var icon: some View {
        if UIImage(named: iconKey.assetName) != nil {
            Image(iconKey.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: iconKey.fallbackSystemImage)
                .font(.system(size: iconSize * 0.74, weight: .semibold, design: .rounded))
                .symbolRenderingMode(.monochrome)
                .minimumScaleFactor(0.6)
        }
    }

    @ViewBuilder
    private var background: some View {
        if showBackground {
            ZStack {
                appTheme.colors.cardBackgroundElevated
                tintColor.opacity(isDisabled ? 0.06 : 0.14)
            }
        }
    }

    @ViewBuilder
    private var border: some View {
        if showBackground {
            RoundedRectangle(cornerRadius: max(8, size * 0.26), style: .continuous)
                .stroke(tintColor.opacity(isDisabled ? 0.12 : 0.24), lineWidth: 1)
        }
    }

    private var iconSize: CGFloat {
        showBackground ? size * 0.54 : size
    }
}
