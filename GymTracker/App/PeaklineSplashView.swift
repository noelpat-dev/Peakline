import SwiftUI
import UIKit
import CoreText

struct PeaklineSplashView: View {
    @Environment(\.appTheme) private var appTheme

    let animatesWordmark: Bool
    let onAnimationFinished: () -> Void

    var body: some View {
        ZStack {
            appTheme.colors.backgroundPrimary
                .ignoresSafeArea()

            PeaklineAnimatedWordmark(
                color: appTheme.colors.textPrimary,
                isAnimating: animatesWordmark,
                onAnimationFinished: onAnimationFinished
            )
                .frame(height: 58)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityIdentifier("startup-wordmark")
        }
        .ignoresSafeArea()
        // Keep the splash itself as one stable accessibility element while the
        // animated wordmark is mounted and removed.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Peakline")
        .accessibilityValue("Brand animation")
        .accessibilityIdentifier("startup-brand-screen")
    }
}

private struct PeaklineAnimatedWordmark: UIViewRepresentable {
    let color: Color
    let isAnimating: Bool
    let onAnimationFinished: () -> Void

    func makeUIView(context: Context) -> PeaklineWordmarkView {
        PeaklineWordmarkView()
    }

    func updateUIView(_ uiView: PeaklineWordmarkView, context: Context) {
        uiView.update(
            color: UIColor(color),
            isAnimating: isAnimating,
            onAnimationFinished: onAnimationFinished
        )
    }
}

private final class PeaklineWordmarkView: UIView {
    private let word = "Peakline"
    private let tittleIndex = 5
    private let stack = UIStackView()
    private let contourRings = (0..<9).map { _ in CAShapeLayer() }
    private let tittleOverlay = CAShapeLayer()
    private let ripple = CAShapeLayer()
    private var letterLabels: [UILabel] = []
    private var wordmarkColor: UIColor = .label
    private var geometry: SplashGeometry?
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
        clipsToBounds = false
        layer.masksToBounds = false

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
            label.font = .systemFont(ofSize: 48, weight: .bold)
            label.textAlignment = .center
            label.isAccessibilityElement = false
            stack.addArrangedSubview(label)
            return label
        }

        contourRings.enumerated().forEach { index, ring in
            ring.fillColor = nil
            ring.lineWidth = index.isMultiple(of: 4) ? 1.5 : 1
            ring.lineJoin = .round
            ring.opacity = 0
            layer.insertSublayer(ring, below: stack.layer)
        }

        tittleOverlay.fillColor = nil
        tittleOverlay.opacity = 1
        layer.addSublayer(tittleOverlay)

        ripple.fillColor = nil
        ripple.lineWidth = 1.7
        ripple.opacity = 0
        layer.addSublayer(ripple)

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.applyWordmarkColor()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The stack positions its letters in its own layout pass, which would
        // otherwise leave the glyph-derived geometry using stale frames.
        stack.layoutIfNeeded()
        guard bounds.width > 0, bounds.height > 0,
              let geometry = makeSplashGeometry() else { return }
        self.geometry = geometry

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let contourExtent: CGFloat = 275
        contourRings.enumerated().forEach { index, ring in
            ring.bounds = CGRect(x: -contourExtent, y: -contourExtent, width: contourExtent * 2, height: contourExtent * 2)
            ring.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            ring.position = geometry.summit
            ring.path = geometry.contourPaths[index]
        }

        tittleOverlay.bounds = CGRect(origin: .zero, size: bounds.size)
        tittleOverlay.anchorPoint = CGPoint(
            x: geometry.summit.x / bounds.width,
            y: geometry.summit.y / bounds.height
        )
        tittleOverlay.position = geometry.summit
        tittleOverlay.path = geometry.tittlePath

        ripple.bounds = CGRect(origin: .zero, size: bounds.size)
        ripple.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        ripple.position = CGPoint(x: bounds.midX, y: bounds.midY)
        ripple.path = Self.circlePath(center: geometry.summit, radius: geometry.tittleRadius)

        CATransaction.commit()
    }

    func update(
        color: UIColor,
        isAnimating: Bool,
        onAnimationFinished: @escaping () -> Void
    ) {
        wordmarkColor = color
        letterLabels.forEach { $0.textColor = color }
        applyWordmarkColor()
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

    private func applyWordmarkColor() {
        let resolved = wordmarkColor.resolvedColor(with: traitCollection).cgColor
        contourRings.forEach { $0.strokeColor = resolved }
        tittleOverlay.fillColor = resolved
        ripple.strokeColor = resolved
    }

    private func startOneShotAnimation() {
        hasScheduledAnimation = false
        guard wantsAnimation else {
            stopAtRest()
            return
        }
        layoutIfNeeded()
        guard let geometry else {
            notifyAnimationFinished()
            return
        }

        let start = CACurrentMediaTime() + 0.08
        let sampleCount = 30
        let keyTimes = (0...sampleCount).map {
            NSNumber(value: Double($0) / Double(sampleCount))
        }
        var latestEndTime = start

        func includeInCompletionTime(_ animation: CAAnimation) {
            latestEndTime = max(latestEndTime, animation.beginTime + animation.duration)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for index in contourRings.indices {
            let ring = contourRings[index]
            let baseOpacity = index.isMultiple(of: 4) ? 0.42 : 0.26

            // The model holds each final value; backwards-filled animations
            // keep the contour hidden or at its drawn state until its next phase.
            ring.strokeEnd = 1
            ring.opacity = 0
            ring.transform = CATransform3DMakeScale(0.03, 0.03, 1)

            let drawValues = (0...sampleCount).map { step in
                NSNumber(value: Self.easeInOutCubic(Double(step) / Double(sampleCount)))
            }
            let draw = keyframes("strokeEnd", values: drawValues, keyTimes: keyTimes)
            draw.duration = 0.52
            draw.beginTime = start + (40 + 85 * Double(8 - index)) / 1_000
            draw.fillMode = .backwards
            includeInCompletionTime(draw)
            ring.add(draw, forKey: "topography-draw")

            let contractionValues = (0...sampleCount).map { step in
                let progress = Self.easeInOutCubic(Double(step) / Double(sampleCount))
                return NSNumber(value: 1 - 0.97 * progress)
            }
            let contraction = keyframes("transform.scale", values: contractionValues, keyTimes: keyTimes)
            contraction.duration = 0.65
            contraction.beginTime = start + (1_000 + 45 * Double(index)) / 1_000
            contraction.fillMode = .backwards
            includeInCompletionTime(contraction)
            ring.add(contraction, forKey: "topography-contract")

            let fade = keyframes(
                "opacity",
                values: [NSNumber(value: baseOpacity), NSNumber(value: 0)],
                keyTimes: [0, 1]
            )
            fade.duration = 0.45
            fade.beginTime = start + (1_250 + 45 * Double(index)) / 1_000
            fade.fillMode = .backwards
            includeInCompletionTime(fade)
            ring.add(fade, forKey: "topography-fade")
        }

        let pulseValues = (0...sampleCount).map { step in
            let time = Double(step) / Double(sampleCount)
            let pulse: Double
            if time < 0.36 {
                pulse = sin(.pi * 0.5 * time / 0.36)
            } else if time < 0.71 {
                pulse = cos(.pi * 0.5 * (time - 0.36) / (0.71 - 0.36))
            } else {
                pulse = 0
            }
            return NSNumber(value: 1 + 0.8 * pulse)
        }
        let tittlePulse = keyframes("transform.scale", values: pulseValues, keyTimes: keyTimes)
        tittlePulse.duration = 0.38
        tittlePulse.beginTime = start + 1.68
        tittlePulse.fillMode = .backwards
        includeInCompletionTime(tittlePulse)
        tittleOverlay.add(tittlePulse, forKey: "tittle-pulse")

        for (index, label) in letterLabels.enumerated() {
            let frame = label.convert(label.bounds, to: self)
            let baseline = Self.baselineY(for: label, in: self)
            let distance = hypot(
                Double(frame.midX - geometry.summit.x),
                Double(baseline - 25 - geometry.summit.y)
            )
            let liftValues = (0...sampleCount).map { step in
                let progress = Double(step) / Double(sampleCount)
                return NSNumber(value: -2.8 * sin(.pi * progress))
            }
            let lift = keyframes("transform.translation.y", values: liftValues, keyTimes: keyTimes)
            lift.duration = 0.38
            lift.beginTime = start + (1_720 + 2.12 * distance) / 1_000
            lift.fillMode = .backwards
            includeInCompletionTime(lift)
            label.layer.add(lift, forKey: "topography-lift-\(index)")
        }

        let rippleValues = (0...sampleCount).map { step -> CGPath in
            let progress = Self.easeOutCubic(Double(step) / Double(sampleCount))
            return Self.circlePath(
                center: geometry.summit,
                radius: geometry.tittleRadius + CGFloat(28 * progress)
            )
        }
        ripple.path = rippleValues.last
        let ripplePath = keyframes("path", values: rippleValues, keyTimes: keyTimes)
        ripplePath.duration = 0.65
        let rippleOpacity = keyframes(
            "opacity",
            values: [NSNumber(value: 0.7), NSNumber(value: 0)],
            keyTimes: [0, 1]
        )
        rippleOpacity.duration = 0.65
        let rippleSequence = CAAnimationGroup()
        rippleSequence.animations = [ripplePath, rippleOpacity]
        rippleSequence.duration = 0.65
        rippleSequence.beginTime = start + 1.72
        includeInCompletionTime(rippleSequence)
        ripple.add(rippleSequence, forKey: "topography-ripple")

        let completion = CABasicAnimation(keyPath: "opacity")
        completion.fromValue = 1
        completion.toValue = 1
        completion.duration = 0.01
        completion.beginTime = latestEndTime - completion.duration
        let completionDelegate = AnimationCompletionDelegate { [weak self] in
            self?.notifyAnimationFinished()
        }
        animationCompletionDelegate = completionDelegate
        completion.delegate = completionDelegate
        stack.layer.add(completion, forKey: "topography-completion")

        CATransaction.commit()
        // Commit absolute begin times before launch preparation occupies the
        // main run loop.
        CATransaction.flush()
    }

    private func stopAtRest() {
        wantsAnimation = false
        hasScheduledAnimation = false
        hasStartedAnimation = false
        animationCompletionDelegate = nil

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        letterLabels.forEach {
            $0.layer.removeAllAnimations()
            $0.layer.transform = CATransform3DIdentity
            $0.layer.opacity = 1
        }
        stack.layer.removeAllAnimations()
        stack.layer.transform = CATransform3DIdentity
        contourRings.forEach { ring in
            ring.removeAllAnimations()
            ring.strokeEnd = 0
            ring.opacity = 0
            ring.transform = CATransform3DIdentity
        }
        tittleOverlay.removeAllAnimations()
        tittleOverlay.transform = CATransform3DIdentity
        tittleOverlay.opacity = 1
        ripple.removeAllAnimations()
        ripple.transform = CATransform3DIdentity
        ripple.opacity = 0
        if let geometry {
            ripple.path = Self.circlePath(center: geometry.summit, radius: geometry.tittleRadius)
        }
        CATransaction.commit()
        notifyAnimationFinished()
    }

    private func notifyAnimationFinished() {
        guard !didNotifyAnimationFinished else { return }
        didNotifyAnimationFinished = true
        DispatchQueue.main.async { [weak self] in
            self?.onAnimationFinished?()
        }
    }

    private func keyframes<Value>(
        _ keyPath: String,
        values: [Value],
        keyTimes: [NSNumber]
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        animation.calculationMode = .linear
        animation.timingFunctions = (1..<values.count).map { _ in
            CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
        }
        return animation
    }

    private struct SplashGeometry {
        let summit: CGPoint
        let tittlePath: CGPath
        let tittleRadius: CGFloat
        let contourPaths: [CGPath]
    }

    private func makeSplashGeometry() -> SplashGeometry? {
        guard letterLabels.indices.contains(tittleIndex),
              let tittle = tittleGeometry(for: letterLabels[tittleIndex]) else { return nil }
        return SplashGeometry(
            summit: tittle.center,
            tittlePath: tittle.path,
            tittleRadius: tittle.radius,
            contourPaths: (0..<9).map { Self.contourPath(index: $0) }
        )
    }

    private func tittleGeometry(for label: UILabel) -> (path: CGPath, center: CGPoint, radius: CGFloat)? {
        guard let font = label.font else { return nil }
        let ctFont = font as CTFont
        var character: UniChar = 105
        var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1),
              let glyphPath = CTFontCreatePathForGlyph(ctFont, glyph, nil) else { return nil }

        let xHeight = CGFloat(CTFontGetXHeight(ctFont))
        guard let tittleSubpath = Self.subpaths(in: glyphPath).first(where: {
            $0.boundingBoxOfPath.minY > xHeight + 0.5
        }) else { return nil }

        var advance = CGSize.zero
        _ = CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)
        let textRect = label.textRect(forBounds: label.bounds, limitedToNumberOfLines: 1)
        let textOriginX = textRect.minX + (textRect.width - advance.width) / 2
        let baseline = Self.baselineYInLabel(for: label)
        let origin = label.convert(CGPoint(x: textOriginX, y: baseline), to: self)
        var glyphToView = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: origin.x, ty: origin.y)
        guard let path = tittleSubpath.copy(using: &glyphToView) else { return nil }
        let box = path.boundingBoxOfPath
        return (path, CGPoint(x: box.midX, y: box.midY), max(box.width, box.height) / 2)
    }

    private static func baselineYInLabel(for label: UILabel) -> CGFloat {
        label.bounds.minY
            + (label.bounds.height - label.font.lineHeight) / 2
            + label.font.ascender
    }

    private static func baselineY(for label: UILabel, in view: UIView) -> CGFloat {
        label.convert(CGPoint(x: 0, y: baselineYInLabel(for: label)), to: view).y
    }

    private static func subpaths(in path: CGPath) -> [CGMutablePath] {
        var paths: [CGMutablePath] = []
        var current: CGMutablePath?
        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                current = CGMutablePath()
                current?.move(to: points[0])
                if let current { paths.append(current) }
            case .addLineToPoint:
                current?.addLine(to: points[0])
            case .addQuadCurveToPoint:
                current?.addQuadCurve(to: points[1], control: points[0])
            case .addCurveToPoint:
                current?.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closeSubpath:
                current?.closeSubpath()
            @unknown default:
                break
            }
        }
        return paths
    }

    private static func contourPath(index: Int) -> CGPath {
        let baseRadius = 16.9 + 21.9 * Double(index)
        let offsetX = 3.67 * Double(index)
        let offsetY = 4.52 * Double(index)
        let path = UIBezierPath()
        let sampleCount = 72

        for sample in 0..<sampleCount {
            let theta = 2 * Double.pi * Double(sample) / Double(sampleCount)
            let radius = baseRadius * (
                1
                    + 0.13 * sin(2 * theta + 0.7 * Double(index))
                    + 0.07 * sin(3 * theta + 1.3 * Double(index) + 1)
                    + 0.035 * sin(5 * theta + 0.4 * Double(index) + 2)
            )
            let point = CGPoint(
                x: CGFloat(offsetX + radius * cos(theta)),
                y: CGFloat(offsetY + radius * sin(theta) * 0.78)
            )
            if sample == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.close()
        return path.cgPath
    }

    private static func circlePath(center: CGPoint, radius: CGFloat) -> CGPath {
        UIBezierPath(ovalIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )).cgPath
    }

    private static func easeInOutCubic(_ value: Double) -> Double {
        value < 0.5
            ? 4 * value * value * value
            : 1 - pow(-2 * value + 2, 3) / 2
    }

    private static func easeOutCubic(_ value: Double) -> Double {
        1 - pow(1 - value, 3)
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
