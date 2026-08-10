import AppKit
import SwiftUI

struct PointerContextAction {
    let title: String
    let systemImageName: String?
    let isDestructive: Bool
    let action: () -> Void

    init(
        title: String,
        systemImageName: String? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImageName = systemImageName
        self.isDestructive = isDestructive
        self.action = action
    }
}

/// A SwiftUI label that distinguishes primary and middle mouse clicks.
struct PointerButton<Label: View>: NSViewRepresentable {
    let primaryAction: () -> Void
    let middleAction: () -> Void
    let dragURL: URL?
    let dragStarted: () -> Void
    let receiveDrop: ([URL]) -> Bool
    let contextActions: [PointerContextAction]
    let label: Label

    init(
        primaryAction: @escaping () -> Void,
        middleAction: @escaping () -> Void,
        dragURL: URL? = nil,
        dragStarted: @escaping () -> Void = {},
        receiveDrop: @escaping ([URL]) -> Bool = { _ in false },
        contextActions: [PointerContextAction] = [],
        @ViewBuilder label: () -> Label
    ) {
        self.primaryAction = primaryAction
        self.middleAction = middleAction
        self.dragURL = dragURL
        self.dragStarted = dragStarted
        self.receiveDrop = receiveDrop
        self.contextActions = contextActions
        self.label = label()
    }

    func makeNSView(context: Context) -> PointerButtonView<Label> {
        let view = PointerButtonView(rootView: label)
        view.primaryAction = primaryAction
        view.middleAction = middleAction
        view.dragURL = dragURL
        view.dragStarted = dragStarted
        view.receiveDrop = receiveDrop
        view.contextActions = contextActions
        return view
    }

    func updateNSView(_ nsView: PointerButtonView<Label>, context: Context) {
        nsView.rootView = label
        nsView.primaryAction = primaryAction
        nsView.middleAction = middleAction
        nsView.dragURL = dragURL
        nsView.dragStarted = dragStarted
        nsView.receiveDrop = receiveDrop
        nsView.contextActions = contextActions
    }
}

final class PointerButtonView<Content: View>: NSHostingView<Content> {
    var primaryAction: () -> Void = {}
    var middleAction: () -> Void = {}
    var dragURL: URL?
    var dragStarted: () -> Void = {}
    var receiveDrop: ([URL]) -> Bool = { _ in false }
    var contextActions: [PointerContextAction] = []
    private var mouseDownEvent: NSEvent?
    private var isDraggingFile = false

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL, .URL])
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        isDraggingFile = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDraggingFile,
              let dragURL,
              let mouseDownEvent,
              hypot(event.locationInWindow.x - mouseDownEvent.locationInWindow.x, event.locationInWindow.y - mouseDownEvent.locationInWindow.y) > 3 else { return }
        isDraggingFile = true
        dragStarted()
        let item = NSDraggingItem(pasteboardWriter: dragURL as NSURL)
        item.setDraggingFrame(bounds, contents: nil)
        let session = beginDraggingSession(with: [item], event: mouseDownEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        if !isDraggingFile { primaryAction() }
        mouseDownEvent = nil
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 {
            middleAction()
        } else {
            super.otherMouseUp(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !contextActions.isEmpty else {
            super.rightMouseDown(with: event)
            return
        }
        let menu = NSMenu()
        for (index, contextAction) in contextActions.enumerated() {
            if contextAction.title == "-" {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: contextAction.title, action: #selector(runContextAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            if let systemImageName = contextAction.systemImageName {
                item.image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: contextAction.title)
                item.image?.isTemplate = true
            }
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func runContextAction(_ sender: NSMenuItem) {
        guard contextActions.indices.contains(sender.tag) else { return }
        contextActions[sender.tag].action()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = droppedURLs(from: sender.draggingPasteboard)
        return urls.isEmpty ? [] : (NSEvent.modifierFlags.contains(.option) ? .copy : .move)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !droppedURLs(from: sender.draggingPasteboard).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        receiveDrop(droppedURLs(from: sender.draggingPasteboard))
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
    }

    private func droppedURLs(from pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL])?.map { $0 as URL } ?? []
    }
}
