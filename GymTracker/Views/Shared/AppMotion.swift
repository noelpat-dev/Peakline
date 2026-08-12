import SwiftUI
import UIKit

enum AppMotion {
    enum Role: String, CaseIterable {
        case tapDown
        case tapRelease
        case cardPress
        case buttonPress
        case primaryAction
        case secondaryAction
        case chipSelect
        case tabSelect
        case modeChange
        case ratingSelect
        case checkInSelect
        case cardAppear
        case cardDisappear
        case rowInsert
        case rowRemove
        case rowReorder
        case sheetPresent
        case sheetDismiss
        case modalPresent
        case modalDismiss
        case routePush
        case routePop
        case loadingReveal
        case metricChange
        case successConfirm
        case destructiveConfirm
        case celebration
        case swipeSnap
        case reduceMotionFallback
    }

    struct RoleSpec {
        let duration: ClosedRange<TimeInterval>
        let feel: String
    }

    static let popupMountDelay: UInt64 = 16_000_000
    static let popupExitDuration: UInt64 = 200_000_000
    static let ratingSelectionDelay: UInt64 = 90_000_000
    static let popupContentRevealDelay: UInt64 = 70_000_000
    static let popupSecondaryRevealDelay: UInt64 = 80_000_000
    static let celebrationIconPulseDuration: TimeInterval = 0.58
    static let prCelebrationSparkDuration: TimeInterval = 0.74
    static let prCelebrationRingDuration: TimeInterval = 0.88
    static let prCelebrationSparkStagger: TimeInterval = 0.018
    static let cardPressScale: CGFloat = 0.985
    static let selectedControlScale: CGFloat = 1.02
    static let emphasizedControlScale: CGFloat = 1.035
    static let cardAppearOffset: CGFloat = 10
    static let navigationPressDownDuration: TimeInterval = 0.08
    static let navigationPressReleaseDuration: TimeInterval = 0.12

    static func instantOr(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.01) : animation
    }

    static func spec(for role: Role) -> RoleSpec {
        switch role {
        case .tapDown:
            return RoleSpec(duration: 0.06...0.10, feel: "immediate subtle acknowledgement")
        case .tapRelease:
            return RoleSpec(duration: 0.10...0.16, feel: "quick settle")
        case .cardPress:
            return RoleSpec(duration: 0.08...0.14, feel: "tiny scale with no bounce")
        case .buttonPress:
            return RoleSpec(duration: 0.08...0.14, feel: "subtle opacity and scale")
        case .primaryAction:
            return RoleSpec(duration: 0.10...0.18, feel: "decisive action feedback")
        case .secondaryAction:
            return RoleSpec(duration: 0.10...0.18, feel: "quiet action feedback")
        case .chipSelect, .ratingSelect, .checkInSelect:
            return RoleSpec(duration: 0.14...0.22, feel: "smooth selection state")
        case .tabSelect:
            return RoleSpec(duration: 0.16...0.24, feel: "native tab selection with light feedback")
        case .modeChange:
            return RoleSpec(duration: 0.18...0.28, feel: "clean mode transition")
        case .cardAppear, .rowInsert:
            return RoleSpec(duration: 0.18...0.28, feel: "opacity with a small local lift")
        case .cardDisappear, .rowRemove:
            return RoleSpec(duration: 0.12...0.20, feel: "fast fade and settle")
        case .rowReorder:
            return RoleSpec(duration: 0.18...0.26, feel: "snappy ordered movement")
        case .sheetPresent, .modalPresent:
            return RoleSpec(duration: 0.22...0.32, feel: "calm native presentation")
        case .sheetDismiss, .modalDismiss:
            return RoleSpec(duration: 0.14...0.22, feel: "faster dismissal")
        case .routePush, .routePop:
            return RoleSpec(duration: 0.20...0.28, feel: "native navigation, state changes immediately")
        case .loadingReveal:
            return RoleSpec(duration: 0.16...0.26, feel: "opacity-led progressive reveal")
        case .metricChange:
            return RoleSpec(duration: 0.16...0.24, feel: "numeric change without layout shift")
        case .successConfirm:
            return RoleSpec(duration: 0.18...0.28, feel: "short confirmation")
        case .destructiveConfirm:
            return RoleSpec(duration: 0.12...0.20, feel: "fast explicit confirmation")
        case .celebration:
            return RoleSpec(duration: 0.30...0.90, feel: "one-shot earned emphasis, never blocking")
        case .swipeSnap:
            return RoleSpec(duration: 0.18...0.28, feel: "interactive snap")
        case .reduceMotionFallback:
            return RoleSpec(duration: 0.01...0.01, feel: "instant or opacity-only")
        }
    }

    static func animation(for role: Role, reduceMotion: Bool) -> Animation {
        switch role {
        case .tapDown:
            return instantOr(.easeOut(duration: 0.08), reduceMotion: reduceMotion)
        case .tapRelease:
            return instantOr(.easeOut(duration: 0.12), reduceMotion: reduceMotion)
        case .cardPress:
            return instantOr(.easeOut(duration: 0.10), reduceMotion: reduceMotion)
        case .buttonPress, .primaryAction, .secondaryAction:
            return instantOr(.easeOut(duration: 0.12), reduceMotion: reduceMotion)
        case .chipSelect, .ratingSelect, .checkInSelect:
            return instantOr(.smooth(duration: 0.18), reduceMotion: reduceMotion)
        case .tabSelect:
            return instantOr(.smooth(duration: 0.18), reduceMotion: reduceMotion)
        case .modeChange:
            return instantOr(.smooth(duration: 0.20), reduceMotion: reduceMotion)
        case .cardAppear, .rowInsert:
            return instantOr(.smooth(duration: 0.22), reduceMotion: reduceMotion)
        case .cardDisappear, .rowRemove:
            return instantOr(.easeIn(duration: 0.16), reduceMotion: reduceMotion)
        case .rowReorder:
            return instantOr(.smooth(duration: 0.20), reduceMotion: reduceMotion)
        case .sheetPresent, .modalPresent:
            return instantOr(.smooth(duration: 0.28), reduceMotion: reduceMotion)
        case .sheetDismiss, .modalDismiss:
            return reduceMotion ? .easeOut(duration: 0.01) : .easeInOut(duration: 0.18)
        case .routePush, .routePop:
            return instantOr(.smooth(duration: 0.24), reduceMotion: reduceMotion)
        case .loadingReveal:
            return reduceMotion ? .easeOut(duration: 0.01) : .easeInOut(duration: 0.18)
        case .metricChange:
            return reduceMotion ? .easeOut(duration: 0.01) : .easeOut(duration: 0.20)
        case .successConfirm:
            return instantOr(.spring(response: 0.22, dampingFraction: 0.82, blendDuration: 0.04), reduceMotion: reduceMotion)
        case .destructiveConfirm:
            return instantOr(.easeInOut(duration: 0.16), reduceMotion: reduceMotion)
        case .celebration:
            return instantOr(.spring(response: 0.38, dampingFraction: 0.82, blendDuration: 0.05), reduceMotion: reduceMotion)
        case .swipeSnap:
            return instantOr(.interactiveSpring(response: 0.26, dampingFraction: 0.9, blendDuration: 0.06), reduceMotion: reduceMotion)
        case .reduceMotionFallback:
            return .easeOut(duration: 0.01)
        }
    }

    static func press(reduceMotion: Bool) -> Animation {
        animation(for: .buttonPress, reduceMotion: reduceMotion)
    }

    static func buttonPress(reduceMotion: Bool) -> Animation {
        animation(for: .buttonPress, reduceMotion: reduceMotion)
    }

    static func cardPress(reduceMotion: Bool) -> Animation {
        animation(for: .cardPress, reduceMotion: reduceMotion)
    }

    static func route(reduceMotion: Bool) -> Animation {
        animation(for: .routePush, reduceMotion: reduceMotion)
    }

    static func cardIn(reduceMotion: Bool) -> Animation {
        animation(for: .cardAppear, reduceMotion: reduceMotion)
    }

    static func cardOut(reduceMotion: Bool) -> Animation {
        animation(for: .cardDisappear, reduceMotion: reduceMotion)
    }

    static func modalIn(reduceMotion: Bool) -> Animation {
        animation(for: .modalPresent, reduceMotion: reduceMotion)
    }

    static func modalOut(reduceMotion: Bool) -> Animation {
        animation(for: .modalDismiss, reduceMotion: reduceMotion)
    }

    static func chip(reduceMotion: Bool) -> Animation {
        animation(for: .chipSelect, reduceMotion: reduceMotion)
    }

    static func chipSelect(reduceMotion: Bool) -> Animation {
        animation(for: .chipSelect, reduceMotion: reduceMotion)
    }

    static func modeChange(reduceMotion: Bool) -> Animation {
        animation(for: .modeChange, reduceMotion: reduceMotion)
    }

    static func ratingSelect(reduceMotion: Bool) -> Animation {
        animation(for: .ratingSelect, reduceMotion: reduceMotion)
    }

    static func checkInSelect(reduceMotion: Bool) -> Animation {
        animation(for: .checkInSelect, reduceMotion: reduceMotion)
    }

    static func swipeSnap(reduceMotion: Bool) -> Animation {
        animation(for: .swipeSnap, reduceMotion: reduceMotion)
    }

    static func celebration(reduceMotion: Bool) -> Animation {
        animation(for: .celebration, reduceMotion: reduceMotion)
    }

    static func prCelebrationSpark(index: Int, reduceMotion: Bool) -> Animation {
        instantOr(
            .easeOut(duration: prCelebrationSparkDuration)
                .delay(Double(index % 4) * prCelebrationSparkStagger),
            reduceMotion: reduceMotion
        )
    }

    static func prCelebrationRing(index: Int, reduceMotion: Bool) -> Animation {
        instantOr(
            .easeOut(duration: prCelebrationRingDuration)
                .delay(Double(index) * 0.08),
            reduceMotion: reduceMotion
        )
    }

    static func prCelebrationIconPop(reduceMotion: Bool) -> Animation {
        instantOr(
            .spring(response: 0.44, dampingFraction: 0.58, blendDuration: 0.04),
            reduceMotion: reduceMotion
        )
    }

    static func navigation(reduceMotion: Bool) -> Animation {
        animation(for: .routePush, reduceMotion: reduceMotion)
    }

    static func tapConfirm(reduceMotion: Bool) -> Animation {
        animation(for: .successConfirm, reduceMotion: reduceMotion)
    }

    static func cardAppear(reduceMotion: Bool) -> Animation {
        cardIn(reduceMotion: reduceMotion)
    }

    static func listChange(reduceMotion: Bool) -> Animation {
        animation(for: .rowReorder, reduceMotion: reduceMotion)
    }

    static func selection(reduceMotion: Bool) -> Animation {
        animation(for: .chipSelect, reduceMotion: reduceMotion)
    }

    static func progress(reduceMotion: Bool) -> Animation {
        instantOr(.easeOut(duration: 0.34), reduceMotion: reduceMotion)
    }

    static func swipeReveal(reduceMotion: Bool) -> Animation {
        swipeSnap(reduceMotion: reduceMotion)
    }

    static func sheet(reduceMotion: Bool) -> Animation {
        animation(for: .sheetPresent, reduceMotion: reduceMotion)
    }

    static func sheetPopup(reduceMotion: Bool) -> Animation {
        sheet(reduceMotion: reduceMotion)
    }

    static func toggle(reduceMotion: Bool) -> Animation {
        instantOr(.spring(response: 0.25, dampingFraction: 0.82, blendDuration: 0.03), reduceMotion: reduceMotion)
    }

    static func workoutCompletion(reduceMotion: Bool) -> Animation {
        celebration(reduceMotion: reduceMotion)
    }

    static func popupEntrance(reduceMotion: Bool) -> Animation {
        sheet(reduceMotion: reduceMotion)
    }

    static func popupExit(reduceMotion: Bool) -> Animation {
        animation(for: .sheetDismiss, reduceMotion: reduceMotion)
    }

    static func quickSpring(reduceMotion: Bool) -> Animation {
        instantOr(.spring(response: 0.28, dampingFraction: 0.84), reduceMotion: reduceMotion)
    }

    static func swipeRevealSnap(reduceMotion: Bool) -> Animation {
        swipeReveal(reduceMotion: reduceMotion)
    }

    static func selectionSpring(reduceMotion: Bool) -> Animation {
        animation(for: .chipSelect, reduceMotion: reduceMotion)
    }

    static func reorderSpring(reduceMotion: Bool) -> Animation {
        listChange(reduceMotion: reduceMotion)
    }

    static func previewReorderLift(reduceMotion: Bool) -> Animation {
        instantOr(
            .spring(response: 0.22, dampingFraction: 0.92, blendDuration: 0.02),
            reduceMotion: reduceMotion
        )
    }

    static func previewReorderTarget(reduceMotion: Bool) -> Animation {
        instantOr(.easeOut(duration: 0.12), reduceMotion: reduceMotion)
    }

    static func previewReorderCommit(reduceMotion: Bool) -> Animation {
        instantOr(
            .spring(response: 0.30, dampingFraction: 0.94, blendDuration: 0.02),
            reduceMotion: reduceMotion
        )
    }

    static func progressFill(reduceMotion: Bool) -> Animation {
        progress(reduceMotion: reduceMotion)
    }

    static func transientConfirmation(reduceMotion: Bool) -> Animation {
        tapConfirm(reduceMotion: reduceMotion)
    }

    static func gentleFade(reduceMotion: Bool) -> Animation {
        animation(for: .loadingReveal, reduceMotion: reduceMotion)
    }

    static func cardTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity
                    .combined(with: .offset(y: cardAppearOffset)),
                removal: .opacity
                    .combined(with: .offset(y: 6))
            )
    }

    static func rowInsertRemoveTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity
                    .combined(with: .offset(y: 6)),
                removal: .opacity
                    .combined(with: .offset(y: 4))
            )
    }

    static func loadingRevealTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4))
    }

    static func popupTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity
                    .combined(with: .scale(scale: 0.98, anchor: .center))
                    .combined(with: .offset(y: 16)),
                removal: .opacity
                    .combined(with: .scale(scale: 0.99, anchor: .center))
                    .combined(with: .offset(y: 8))
            )
    }

    @MainActor
    static func smoothNavigate(reduceMotion: Bool, _ action: @escaping @MainActor () -> Void) {
        PerformanceTracer.trace(.motionRoutePush) {
            action()
        }
    }

    static func withoutAnimation(_ action: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            action()
        }
    }
}

enum NavigationInteractionHaptic {
    case none
    case selection
    case light
    case medium

    @MainActor
    func prepare() {
        switch self {
        case .none:
            break
        case .selection:
            AppHaptics.prepareSelection()
        case .light:
            AppHaptics.prepareImpact(.light)
        case .medium:
            AppHaptics.prepareImpact(.medium)
        }
    }

    @MainActor
    func play() {
        switch self {
        case .none:
            break
        case .selection:
            AppHaptics.selection()
        case .light:
            AppHaptics.lightImpact()
        case .medium:
            AppHaptics.mediumImpact()
        }
    }
}

enum NavigationDestinationClass {
    case warm
    case deep

    var thresholdMilliseconds: Int {
        switch self {
        case .warm: 300
        case .deep: 500
        }
    }
}

@MainActor
enum NavigationInteraction {
    private struct PendingRequest {
        let id: UUID
        let requestedAt: Date
        let destinationClass: NavigationDestinationClass
    }

    private static let pendingRequestTimeoutMilliseconds = 1_000
    private static var pendingRequests: [String: PendingRequest] = [:]
    private static var pendingRequestExpiryTasks: [String: Task<Void, Never>] = [:]

    @discardableResult
    static func perform(
        key: String,
        destinationClass: NavigationDestinationClass = .warm,
        haptic: NavigationInteractionHaptic = .selection,
        action: () -> Void
    ) -> Bool {
        guard pendingRequests[key] == nil else {
            PerformanceTracer.mark(.navigationInteraction, "request_deduplicated key=\(key)")
            return false
        }

        let request = PendingRequest(
            id: UUID(),
            requestedAt: .now,
            destinationClass: destinationClass
        )
        pendingRequests[key] = request
        scheduleExpiry(for: key, requestID: request.id)
        haptic.prepare()
        haptic.play()

        PerformanceTracer.mark(
            .navigationInteraction,
            "requested key=\(key) threshold_ms=\(destinationClass.thresholdMilliseconds)"
        )
        PerformanceTracer.trace(.motionRoutePush) {
            action()
        }
        return true
    }

    private static func scheduleExpiry(for key: String, requestID: UUID) {
        pendingRequestExpiryTasks[key]?.cancel()
        pendingRequestExpiryTasks[key] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(pendingRequestTimeoutMilliseconds))
            guard !Task.isCancelled,
                  let request = pendingRequests[key],
                  request.id == requestID else { return }

            pendingRequests.removeValue(forKey: key)
            pendingRequestExpiryTasks.removeValue(forKey: key)
            PerformanceTracer.mark(
                .navigationInteraction,
                "expired key=\(key) timeout_ms=\(pendingRequestTimeoutMilliseconds)"
            )
        }
    }

    static func destinationDidAppear(key: String) {
        guard let request = pendingRequests.removeValue(forKey: key) else { return }
        pendingRequestExpiryTasks[key]?.cancel()
        pendingRequestExpiryTasks.removeValue(forKey: key)
        let elapsedMilliseconds = max(
            0,
            Int(Date.now.timeIntervalSince(request.requestedAt) * 1_000)
        )
        PerformanceTracer.mark(
            .navigationInteraction,
            "stable_frame key=\(key) elapsed_ms=\(elapsedMilliseconds) threshold_ms=\(request.destinationClass.thresholdMilliseconds)"
        )
    }

    static func cancel(key: String, reason: String) {
        guard pendingRequests.removeValue(forKey: key) != nil else { return }
        pendingRequestExpiryTasks[key]?.cancel()
        pendingRequestExpiryTasks.removeValue(forKey: key)
        PerformanceTracer.mark(
            .navigationInteraction,
            "cancelled key=\(key) reason=\(reason)"
        )
    }

    static func resetForTesting() {
        pendingRequestExpiryTasks.values.forEach { $0.cancel() }
        pendingRequestExpiryTasks.removeAll()
        pendingRequests.removeAll()
    }
}

enum AppHaptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static var lastSelectionAt = Date.distantPast
    private static var lastImpactAt = Date.distantPast
    private static var lastNotificationAt = Date.distantPast
    private static let selectionInterval: TimeInterval = 0.06
    private static let impactInterval: TimeInterval = 0.08
    private static let notificationInterval: TimeInterval = 0.18

    static func selection() {
        perform {
            guard shouldPlay(since: &lastSelectionAt, minimumInterval: selectionInterval) else { return }
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        }
    }

    static func prepareSelection() {
        perform {
            selectionGenerator.prepare()
        }
    }

    static func prepareImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        perform {
            impactGenerator(for: style).prepare()
        }
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        perform {
            guard shouldPlay(since: &lastImpactAt, minimumInterval: impactInterval) else { return }
            let impactGenerator = impactGenerator(for: style)
            impactGenerator.prepare()
            impactGenerator.impactOccurred()
        }
    }

    static func lightImpact() {
        impact(.light)
    }

    static func mediumImpact() {
        impact(.medium)
    }

    static func success() {
        notify(.success)
    }

    static func warning() {
        notify(.warning)
    }

    static func error() {
        notify(.error)
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        perform {
            guard shouldPlay(since: &lastNotificationAt, minimumInterval: notificationInterval) else { return }
            notificationGenerator.notificationOccurred(type)
            notificationGenerator.prepare()
        }
    }

    private static func impactGenerator(
        for style: UIImpactFeedbackGenerator.FeedbackStyle
    ) -> UIImpactFeedbackGenerator {
        style == .medium ? mediumImpactGenerator : lightImpactGenerator
    }

    private static func perform(_ feedback: @escaping () -> Void) {
        if Thread.isMainThread {
            feedback()
        } else {
            DispatchQueue.main.async {
                feedback()
            }
        }
    }

    private static func shouldPlay(since lastPlayedAt: inout Date, minimumInterval: TimeInterval) -> Bool {
        let now = Date.now
        guard now.timeIntervalSince(lastPlayedAt) >= minimumInterval else { return false }
        lastPlayedAt = now
        return true
    }
}

private struct SmoothPopupCardMotion: ViewModifier {
    let isVisible: Bool
    let reduceMotion: Bool
    let hiddenScale: CGFloat
    let hiddenOffset: CGFloat
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : hiddenScale), anchor: anchor)
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (isVisible ? 0 : hiddenOffset))
    }
}

struct PeaklineButtonPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var pressedOpacity: Double = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .navigationPressFeedback(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion,
                pressedOpacity: pressedOpacity
            )
    }
}

private struct SelectionMotionModifier: ViewModifier {
    let isSelected: Bool
    let reduceMotion: Bool
    let scale: CGFloat
    let role: AppMotion.Role

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : (isSelected ? scale : 1))
            .animation(AppMotion.animation(for: role, reduceMotion: reduceMotion), value: isSelected)
    }
}

private struct NavigationPressFeedbackModifier: ViewModifier {
    let isPressed: Bool
    let reduceMotion: Bool
    let pressedOpacity: Double

    func body(content: Content) -> some View {
        content
            .opacity(isPressed ? pressedOpacity : 1)
            .scaleEffect(
                reduceMotion ? 1 : (isPressed ? AppMotion.cardPressScale : 1)
            )
            .animation(
                .easeOut(
                    duration: isPressed
                        ? AppMotion.navigationPressDownDuration
                        : AppMotion.navigationPressReleaseDuration
                ),
                value: isPressed
            )
    }
}

private struct LoadingRevealModifier: ViewModifier {
    let isVisible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (isVisible ? 0 : 4))
            .animation(AppMotion.animation(for: .loadingReveal, reduceMotion: reduceMotion), value: isVisible)
    }
}

extension View {
    func navigationPressFeedback(
        isPressed: Bool,
        reduceMotion: Bool,
        pressedOpacity: Double = 0.94
    ) -> some View {
        modifier(
            NavigationPressFeedbackModifier(
                isPressed: isPressed,
                reduceMotion: reduceMotion,
                pressedOpacity: pressedOpacity
            )
        )
    }

    func smoothPopupCardMotion(
        isVisible: Bool,
        reduceMotion: Bool,
        hiddenScale: CGFloat = 0.94,
        hiddenOffset: CGFloat = 28,
        anchor: UnitPoint = .center
    ) -> some View {
        modifier(
            SmoothPopupCardMotion(
                isVisible: isVisible,
                reduceMotion: reduceMotion,
                hiddenScale: hiddenScale,
                hiddenOffset: hiddenOffset,
                anchor: anchor
            )
        )
    }

    func peaklineSelectionMotion(
        isSelected: Bool,
        reduceMotion: Bool,
        scale: CGFloat = AppMotion.selectedControlScale,
        role: AppMotion.Role = .chipSelect
    ) -> some View {
        modifier(
            SelectionMotionModifier(
                isSelected: isSelected,
                reduceMotion: reduceMotion,
                scale: scale,
                role: role
            )
        )
    }

    func loadingReveal(isVisible: Bool = true, reduceMotion: Bool) -> some View {
        modifier(LoadingRevealModifier(isVisible: isVisible, reduceMotion: reduceMotion))
    }

    func rowInsertRemoveMotion(reduceMotion: Bool) -> some View {
        transition(AppMotion.rowInsertRemoveTransition(reduceMotion: reduceMotion))
    }

    func metricValueMotion<Value: Equatable>(value: Value, reduceMotion: Bool) -> some View {
        contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(AppMotion.animation(for: .metricChange, reduceMotion: reduceMotion), value: value)
    }
}

struct PeaklinePopupBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    let isVisible: Bool

    var body: some View {
        Color.black
            .opacity(colorScheme == .dark ? 0.48 : 0.22)
        .opacity(isVisible ? 1 : 0)
        .accessibilityHidden(true)
    }
}

struct PeaklinePopupCard<Content: View>: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 34
    var padding: CGFloat = 24
    @ViewBuilder var content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background {
                shape.fill(appTheme.colors.cardBackground)
            }
            .overlay {
                shape
                    .stroke(appTheme.colors.cardBorder.opacity(0.92), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.26 : 0.12), radius: 18, x: 0, y: 12)
    }
}
