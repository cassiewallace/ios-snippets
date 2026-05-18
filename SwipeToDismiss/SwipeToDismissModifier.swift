import SwiftUI

/// Downward swipe-to-dismiss for full-screen overlays. Fades a scrim with the gesture, slides the
/// content off-screen past the dismiss threshold, and snaps back otherwise. Honors Reduce Motion.
private struct SwipeToDismissModifier: ViewModifier {
    let isEnabled: Bool
    let dragStartMaxY: CGFloat?
    let isDragging: Binding<Bool>?
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var viewSize: CGSize = .zero
    @State private var isDismissing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .opacity(backdropOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: _SizePreferenceKey.self, value: proxy.size)
                    }
                )
                .onPreferenceChange(_SizePreferenceKey.self) { viewSize = $0 }
                .offset(y: dragOffset)
                .allowsHitTesting(!isDismissing)
        }
        .simultaneousGesture(
            swipeGesture,
            including: (isDismissing || !isEnabled) ? .none : .all
        )
    }

    /// Full at rest, zero when dragged a full screen down, so the backdrop fades with the gesture.
    private var backdropOpacity: Double {
        guard viewSize.height > 0 else { return 1 }
        let progress = min(1, dragOffset / viewSize.height)
        return 1 - progress
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }

    /// When `dragStartMaxY` is set, restrict the gesture to drags that begin within that y-offset
    /// from the top of the modifier's view (e.g., the toolbar area).
    private func isDragOriginAllowed(_ value: DragGesture.Value) -> Bool {
        guard let dragStartMaxY else { return true }
        return value.startLocation.y <= dragStartMaxY
    }

    /// Ignores horizontal-dominant drags so a TabView page swipe is never hijacked. Once a vertical
    /// drag is underway, follows the finger in both directions (clamped to ≥ 0) so the view tracks
    /// smoothly back toward its rest position when the user reverses direction mid-gesture.
    private func handleDragChanged(_ value: DragGesture.Value) {
        guard isDragOriginAllowed(value) else { return }
        let h = value.translation.height
        let isVerticalDominant = h > 0 && h > abs(value.translation.width)
        guard isVerticalDominant || dragOffset > 0 else { return }
        isDragging?.wrappedValue = true
        dragOffset = max(0, h)
    }

    /// Commits dismissal past the threshold (slide off-screen, then `onDismiss`) or snaps back.
    private func handleDragEnded(_ value: DragGesture.Value) {
        guard isDragOriginAllowed(value) else { return }
        isDragging?.wrappedValue = false
        let shouldDismiss = Self.shouldDismiss(
            translation: value.translation,
            predictedEndTranslation: value.predictedEndTranslation
        )
        if shouldDismiss {
            isDismissing = true
            if reduceMotion {
                commitDismissal()
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    dragOffset = viewSize.height
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    commitDismissal()
                }
            }
        } else if reduceMotion {
            dragOffset = 0
        } else {
            withAnimation(.interactiveSpring()) {
                dragOffset = 0
            }
        }
    }

    /// Calls `onDismiss` with animations disabled to avoid any navigation-layer fade running
    /// concurrently and swallowing fast taps on the underlying screen.
    private func commitDismissal() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { onDismiss() }
    }

    /// Vertical-dominance guard keeps a diagonal TabView page swipe from triggering dismissal
    /// even when its vertical component crosses the distance threshold.
    static func shouldDismiss(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        distanceThreshold: CGFloat = 120,
        velocityThreshold: CGFloat = 200
    ) -> Bool {
        let isVerticalDownward = translation.height > 0
            && translation.height > abs(translation.width)
        return isVerticalDownward
            && (translation.height > distanceThreshold
                || predictedEndTranslation.height > velocityThreshold)
    }
}

extension View {
    /// Downward swipe-to-dismiss for full-screen overlays.
    ///
    /// Apply to the outermost view of a full-screen overlay or sheet. A semi-transparent scrim
    /// fades in behind the content as the drag progresses and the view slides off the bottom
    /// once past the threshold.
    ///
    /// - Parameters:
    ///   - isEnabled: Set `false` to suspend the gesture while a child view should own the touch
    ///     (e.g. a zoomed scroll view).
    ///   - dragStartMaxY: Optional y-coordinate ceiling for where a drag may begin (relative to the
    ///     modifier's view). Use this when the content has its own scrolling and the dismiss
    ///     gesture should originate from a top handle/toolbar only.
    ///   - isDragging: Mirrors live drag state. Pass when an inner UIKit view (TabView, WebView)
    ///     must be paused to avoid competing with the gesture.
    ///   - onDismiss: Called when the drag commits past the dismiss threshold.
    func swipeToDismiss(
        isEnabled: Bool = true,
        dragStartMaxY: CGFloat? = nil,
        isDragging: Binding<Bool>? = nil,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(SwipeToDismissModifier(
            isEnabled: isEnabled,
            dragStartMaxY: dragStartMaxY,
            isDragging: isDragging,
            onDismiss: onDismiss
        ))
    }
}

// MARK: - Private helpers

private struct _SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
