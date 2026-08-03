import AppKit
import SwiftUI

/// A SwiftUI label that distinguishes primary and middle mouse clicks.
struct PointerButton<Label: View>: NSViewRepresentable {
    let primaryAction: () -> Void
    let middleAction: () -> Void
    let label: Label

    init(
        primaryAction: @escaping () -> Void,
        middleAction: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.primaryAction = primaryAction
        self.middleAction = middleAction
        self.label = label()
    }

    func makeNSView(context: Context) -> PointerButtonView<Label> {
        let view = PointerButtonView(rootView: label)
        view.primaryAction = primaryAction
        view.middleAction = middleAction
        return view
    }

    func updateNSView(_ nsView: PointerButtonView<Label>, context: Context) {
        nsView.rootView = label
        nsView.primaryAction = primaryAction
        nsView.middleAction = middleAction
    }
}

final class PointerButtonView<Content: View>: NSHostingView<Content> {
    var primaryAction: () -> Void = {}
    var middleAction: () -> Void = {}

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        primaryAction()
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 {
            middleAction()
        } else {
            super.otherMouseUp(with: event)
        }
    }
}
