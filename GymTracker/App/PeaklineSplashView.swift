import SwiftData
import SwiftUI
import UIKit

struct PeaklineSplashView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let stageText: String
    let showsProgress: Bool
    let animatesWordmark: Bool
    let onAnimationFinished: () -> Void

    var body: some View {
        ZStack {
            appTheme.colors.backgroundPrimary
                .ignoresSafeArea()

            PeaklineAnimatedWordmark(
                color: appTheme.colors.textPrimary,
                accentColor: appTheme.colors.accent,
                isAnimating: animatesWordmark,
                onAnimationFinished: onAnimationFinished
            )
                .frame(height: 58)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityIdentifier("startup-wordmark")

            if showsProgress {
                VStack(spacing: 10) {
                    SwiftUI.ProgressView()
                        .tint(appTheme.colors.accent)
                    Text(stageText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: 70)
                .accessibilityIdentifier("startup-slow-status")
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .ignoresSafeArea()
        // Keep the splash itself as one stable accessibility element. Combining
        // child semantics can replace the explicitly published slow-stage value
        // while the progress view is being mounted or removed.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Peakline")
        .accessibilityValue(showsProgress ? stageText : "Loading")
        .accessibilityIdentifier("startup-brand-screen")
    }
}

private struct PeaklineAnimatedWordmark: UIViewRepresentable {
    let color: Color
    let accentColor: Color
    let isAnimating: Bool
    let onAnimationFinished: () -> Void

    func makeUIView(context: Context) -> PeaklineWordmarkView {
        PeaklineWordmarkView()
    }

    func updateUIView(_ uiView: PeaklineWordmarkView, context: Context) {
        uiView.update(
            color: UIColor(color),
            accentColor: UIColor(accentColor),
            isAnimating: isAnimating,
            onAnimationFinished: onAnimationFinished
        )
    }
}

private final class PeaklineWordmarkView: UIView {
    private let word = "Peakline"
    private let stack = UIStackView()
    private let accentSweep = CAShapeLayer()
    private var letterLabels: [UILabel] = []
    private var hasStartedAnimation = false
    private var hasScheduledAnimation = false
    private var wantsAnimation = false
    private var didNotifyAnimationFinished = false
    private var animationCompletionDelegate: AnimationCompletionDelegate?
    private var onAnimationFinished: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        accessibilityElementsHidden = true

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        accentSweep.fillColor = nil
        accentSweep.lineWidth = 2.5
        accentSweep.lineCap = .round
        accentSweep.opacity = 0
        layer.addSublayer(accentSweep)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        letterLabels = word.map { character in
            let label = UILabel()
            label.text = String(character)
            label.font = .systemFont(ofSize: 48, weight: .bold)
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

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: bounds.midX - 46, y: bounds.midY + 47))
        path.addLine(to: CGPoint(x: bounds.midX + 46, y: bounds.midY + 47))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        accentSweep.frame = bounds
        accentSweep.path = path.cgPath
        CATransaction.commit()
    }

    func update(
        color: UIColor,
        accentColor: UIColor,
        isAnimating: Bool,
        onAnimationFinished: @escaping () -> Void
    ) {
        letterLabels.forEach { $0.textColor = color }
        accentSweep.strokeColor = accentColor.cgColor
        self.onAnimationFinished = onAnimationFinished
        wantsAnimation = isAnimating

        guard isAnimating else {
            stopAtRest()
            return
        }
        guard !hasStartedAnimation, !hasScheduledAnimation else { return }
        hasStartedAnimation = true
        hasScheduledAnimation = true
        didNotifyAnimationFinished = false

        // Core Animation owns the one-shot sequence so SwiftData preparation on
        // the main actor cannot produce per-frame SwiftUI invalidations.
        DispatchQueue.main.async { [weak self] in
            self?.startOneShotAnimation()
        }
    }

    private func startOneShotAnimation() {
        hasScheduledAnimation = false
        guard wantsAnimation else {
            stopAtRest()
            return
        }

        let start = CACurrentMediaTime() + 0.08
        let stagger = 0.09
        let riseDuration = 1.10
        let waveDuration = riseDuration + Double(letterLabels.count - 1) * stagger

        for (index, label) in letterLabels.enumerated() {
            let primary = CAAnimationGroup()
            primary.animations = [
                keyframes("transform.translation.y", values: [0, -9, 0], keyTimes: [0, 0.46, 1]),
                keyframes("transform.scale", values: [1, 1.035, 1], keyTimes: [0, 0.46, 1])
            ]
            primary.duration = riseDuration
            primary.beginTime = start + (Double(index) * stagger)
            label.layer.add(primary, forKey: "peakline-primary-rise")
        }

        let sweep = CAAnimationGroup()
        sweep.animations = [
            keyframes("strokeStart", values: [0, 0, 0.7, 1], keyTimes: [0, 0.18, 0.82, 1]),
            keyframes("strokeEnd", values: [0, 0.3, 1, 1], keyTimes: [0, 0.18, 0.82, 1]),
            keyframes("opacity", values: [0, 0.85, 0.85, 0], keyTimes: [0, 0.18, 0.82, 1])
        ]
        sweep.duration = waveDuration
        sweep.beginTime = start + 0.16
        accentSweep.add(sweep, forKey: "peakline-accent-sweep")

        let settle = keyframes(
            "transform.scale",
            values: [1, 1.012, 1],
            keyTimes: [0, 0.48, 1]
        )
        settle.duration = 0.45
        settle.beginTime = start + waveDuration

        let completionDelegate = AnimationCompletionDelegate { [weak self] in
            self?.notifyAnimationFinished()
        }
        animationCompletionDelegate = completionDelegate
        settle.delegate = completionDelegate
        stack.layer.add(settle, forKey: "peakline-settle")
    }

    private func stopAtRest() {
        wantsAnimation = false
        hasScheduledAnimation = false
        guard hasStartedAnimation || stack.layer.animation(forKey: "peakline-settle") != nil else {
            notifyAnimationFinished()
            return
        }
        hasStartedAnimation = false
        animationCompletionDelegate = nil
        letterLabels.forEach {
            $0.layer.removeAllAnimations()
            $0.layer.transform = CATransform3DIdentity
            $0.layer.opacity = 1
        }
        stack.layer.removeAllAnimations()
        stack.layer.transform = CATransform3DIdentity
        accentSweep.removeAllAnimations()
        notifyAnimationFinished()
    }

    private func notifyAnimationFinished() {
        guard !didNotifyAnimationFinished else { return }
        didNotifyAnimationFinished = true
        DispatchQueue.main.async { [weak self] in
            self?.onAnimationFinished?()
        }
    }

    private func keyframes(
        _ keyPath: String,
        values: [NSNumber],
        keyTimes: [NSNumber]
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        animation.timingFunctions = (1..<values.count).map { _ in
            CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        }
        return animation
    }
}

private final class AnimationCompletionDelegate: NSObject, CAAnimationDelegate {
    private let completion: () -> Void

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag else { return }
        completion()
    }
}
