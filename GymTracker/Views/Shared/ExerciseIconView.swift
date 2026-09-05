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

        return tint ?? (iconKey.workoutGuideSlug == nil ? appTheme.colors.accent : appTheme.colors.textAccent)
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

    private var assetName: String {
        // The enum rawValue remains the compatibility key for decoding, while
        // its visual asset is now always Workout Guide artwork.
        return iconKey.assetName
    }

    @ViewBuilder
    private var icon: some View {
        if ExerciseIconAssetCache.hasAsset(named: assetName) {
            Image(assetName)
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
        guard showBackground else { return size }
        // Detailed exercise poses need more space than the original compact glyphs.
        return size * (assetName.hasPrefix("workout_guide_") ? 0.80 : 0.54)
    }

    @MainActor
    static func prewarm<S: Sequence>(_ keys: S) where S.Element == ExerciseIconKey {
        for key in keys {
            if let guideAsset = key.workoutGuideAssetName(),
               ExerciseIconAssetCache.hasAsset(named: guideAsset) {
                continue
            }
            _ = ExerciseIconAssetCache.hasAsset(named: key.assetName)
        }
    }
}

private enum ExerciseIconAssetCache {
    private static let cache = NSCache<NSString, NSNumber>()

    static func hasAsset(named name: String) -> Bool {
        let key = name as NSString
        if let cached = cache.object(forKey: key) {
            return cached.boolValue
        }

        let exists = UIImage(named: name) != nil
        cache.setObject(NSNumber(value: exists), forKey: key)
        return exists
    }
}
