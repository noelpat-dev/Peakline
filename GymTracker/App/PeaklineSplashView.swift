import SwiftData
import SwiftUI
import UIKit

struct PeaklineSplashView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let stageText: String
    let showsProgress: Bool
    let animatesWordmark: Bool

    var body: some View {
        ZStack {
            appTheme.colors.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 16) {
                PeaklineAnimatedWordmark(
                    color: appTheme.colors.textPrimary,
                    isAnimating: animatesWordmark
                )
                    .frame(height: 48)
                    .accessibilityIdentifier("startup-wordmark")

                if showsProgress {
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(appTheme.colors.accent)
                        Text(stageText)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                    .accessibilityIdentifier("startup-slow-status")
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Peakline")
        .accessibilityValue(showsProgress ? stageText : "Loading")
        .accessibilityIdentifier("startup-brand-screen")
    }
}

private struct PeaklineAnimatedWordmark: UIViewRepresentable {
    let color: Color
    let isAnimating: Bool

    func makeUIView(context: Context) -> PeaklineWordmarkView {
        PeaklineWordmarkView()
    }

    func updateUIView(_ uiView: PeaklineWordmarkView, context: Context) {
        uiView.update(color: UIColor(color), isAnimating: isAnimating)
    }
}

private final class PeaklineWordmarkView: UIView {
    private let word = "Peakline"
    private let stack = UIStackView()
    private var letterLabels: [UILabel] = []
    private var hasStartedAnimation = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        accessibilityElementsHidden = true

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        letterLabels = word.map { character in
            let label = UILabel()
            label.text = String(character)
            label.font = .systemFont(ofSize: 36, weight: .bold)
            label.textAlignment = .center
            label.isAccessibilityElement = false
            stack.addArrangedSubview(label)
            return label
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(color: UIColor, isAnimating: Bool) {
        letterLabels.forEach { $0.textColor = color }

        guard isAnimating else {
            stopAtRest()
            return
        }
        guard !hasStartedAnimation else { return }
        hasStartedAnimation = true

        // Core Animation owns the one-shot sequence so SwiftData preparation on
        // the main actor cannot produce per-frame SwiftUI invalidations.
        DispatchQueue.main.async { [weak self] in
            self?.startOneShotAnimation()
        }
    }

    private func startOneShotAnimation() {
        let start = CACurrentMediaTime() + 0.20

        for (index, label) in letterLabels.enumerated() {
            let primary = CAAnimationGroup()
            primary.animations = [
                keyframes("transform.translation.y", values: [0, -8, 0], keyTimes: [0, 0.48, 1]),
                keyframes("transform.scale", values: [1, 1.025, 1], keyTimes: [0, 0.48, 1]),
                keyframes("opacity", values: [1, 0.82, 1], keyTimes: [0, 0.48, 1])
            ]
            primary.duration = 0.72
            primary.beginTime = start + (Double(index) * 0.075)
            primary.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            label.layer.add(primary, forKey: "peakline-primary-rise")

            let microWave = CAAnimationGroup()
            microWave.animations = [
                keyframes("transform.translation.y", values: [0, -3, 0], keyTimes: [0, 0.5, 1]),
                keyframes("transform.scale", values: [1, 1.01, 1], keyTimes: [0, 0.5, 1]),
                keyframes("opacity", values: [1, 0.93, 1], keyTimes: [0, 0.5, 1])
            ]
            microWave.duration = 0.62
            microWave.beginTime = start + 2.0 + (Double(index) * 0.055)
            microWave.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            label.layer.add(microWave, forKey: "peakline-micro-wave")
        }

        let breath = CAKeyframeAnimation(keyPath: "transform.scale")
        breath.values = [1, 1.012, 1]
        breath.keyTimes = [0, 0.45, 1]
        breath.duration = 1.55
        breath.beginTime = start + 3.25
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        stack.layer.add(breath, forKey: "peakline-breath")
    }

    private func stopAtRest() {
        guard hasStartedAnimation else { return }
        hasStartedAnimation = false
        letterLabels.forEach {
            $0.layer.removeAllAnimations()
            $0.layer.transform = CATransform3DIdentity
            $0.layer.opacity = 1
        }
        stack.layer.removeAllAnimations()
        stack.layer.transform = CATransform3DIdentity
    }

    private func keyframes(
        _ keyPath: String,
        values: [NSNumber],
        keyTimes: [NSNumber]
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        return animation
    }
}
