import SwiftUI
import UIKit
import XCTest
@testable import GymTracker

@MainActor
final class ThemeContrastTests: XCTestCase {
    func testStatusBadgeTextHasReadableContrastAcrossThemesAndAppearances() {
        let roles: [StatusBadge.Role] = [.neutral, .accent, .success, .warning, .danger, .hydration]
        for theme in AppTheme.allCases {
            for appearance: UIUserInterfaceStyle in [.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: appearance)
                let colors = theme.colors
                let card = rgba(colors.cardBackground, traits: traits)
                for role in roles {
                    let fill = rgba(role.fillColor(colors), traits: traits)
                    let text = rgba(role.textColor(colors), traits: traits)
                    let background = (0..<3).map { fill[$0] * fill[3] + card[$0] * (1 - fill[3]) }
                    let foreground = (0..<3).map { text[$0] * text[3] + background[$0] * (1 - text[3]) }
                    let levels = [luminance(foreground), luminance(background)].sorted()
                    let ratio = (levels[1] + 0.05) / (levels[0] + 0.05)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(theme) \(appearance) \(role): \(ratio)")
                }
            }
        }
    }

    private func rgba(_ color: Color, traits: UITraitCollection) -> [Double] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return [red, green, blue, alpha].map(Double.init)
    }

    private func luminance(_ rgb: [Double]) -> Double {
        let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }
}
