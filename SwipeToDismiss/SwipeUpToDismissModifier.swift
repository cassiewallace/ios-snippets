import SwiftUI

private struct SwipeUpToDismissModifier: ViewModifier {

    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.height < 0 {
                            onDismiss()
                        }
                    }
            )
    }
}

extension View {
    /// Dismisses the view when the user swipes upward.
    ///
    /// - Parameter onDismiss: Called at the end of an upward swipe. Use this
    ///   to remove the view from the hierarchy.
    func swipeUpToDismiss(onDismiss: @escaping () -> Void) -> some View {
        modifier(SwipeUpToDismissModifier(onDismiss: onDismiss))
    }
}
