import SwiftUI
import UIKit

extension View {
    /// Calls `action` with whether a foldable's hinge is partially open, once
    /// with the current state and again on every change (tdr/0020). Never
    /// called before iOS 27.1 or on a device without a hinge, so callers keep
    /// their default of "not partially open".
    func onHingePartiallyOpenChange(_ action: @escaping (Bool) -> Void) -> some View {
        background {
            if #available(iOS 27.1, *) {
                HingeObserver(onChange: action)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// An invisible view carrying a `UIHingeInteraction`; SwiftUI has no hinge
/// API of its own.
@available(iOS 27.1, *)
private struct HingeObserver: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        view.addInteraction(UIHingeInteraction { _, update in
            // A nil hinge means this hierarchy gets no hinge updates.
            coordinator.report(update.hinge?.status == .partiallyOpen)
        })
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChange = onChange
    }

    final class Coordinator {
        var onChange: (Bool) -> Void
        private var last: Bool?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
        }

        /// The first update can arrive while SwiftUI is still building the
        /// view, so it is passed on asynchronously; repeats are dropped.
        func report(_ isPartiallyOpen: Bool) {
            guard isPartiallyOpen != last else { return }
            last = isPartiallyOpen
            Task { @MainActor in self.onChange(isPartiallyOpen) }
        }
    }
}
