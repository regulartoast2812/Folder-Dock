import AppKit
import SwiftUI

/// AppKit-backed file dragging that advertises the same operations Finder does.
/// SwiftUI's URL `draggable` currently exposes a copy-only drag to Finder.
struct FinderDragSource<Label: View>: NSViewRepresentable {
    let urls: () -> [URL]
    let primaryAction: () -> Void
    let doubleAction: () -> Void
    let dragEnded: (NSDragOperation) -> Void
    let contextMenuProvider: () -> NSMenu?
    let isEnabled: Bool
    let label: Label

    init(
        urls: @escaping () -> [URL],
        primaryAction: @escaping () -> Void,
        doubleAction: @escaping () -> Void,
        dragEnded: @escaping (NSDragOperation) -> Void = { _ in },
        contextMenu: @escaping () -> NSMenu? = { nil },
        isEnabled: Bool = true,
        @ViewBuilder label: () -> Label
    ) {
        self.urls = urls
        self.primaryAction = primaryAction
        self.doubleAction = doubleAction
        self.dragEnded = dragEnded
        self.contextMenuProvider = contextMenu
        self.isEnabled = isEnabled
        self.label = label()
    }

    func makeNSView(context: Context) -> FinderDragSourceView<Label> {
        let view = FinderDragSourceView(rootView: label)
        configure(view)
        return view
    }

    func updateNSView(_ nsView: FinderDragSourceView<Label>, context: Context) {
        nsView.rootView = label
        configure(nsView)
    }

    private func configure(_ view: FinderDragSourceView<Label>) {
        view.dragURLs = urls
        view.primaryAction = primaryAction
        view.doubleAction = doubleAction
        view.dragEnded = dragEnded
        view.contextMenuProvider = contextMenuProvider
        view.isDragEnabled = isEnabled
    }
}

final class FinderDragSourceView<Content: View>: NSView, NSDraggingSource {
    var dragURLs: () -> [URL] = { [] }
    var primaryAction: () -> Void = {}
    var doubleAction: () -> Void = {}
    var dragEnded: (NSDragOperation) -> Void = { _ in }
    var contextMenuProvider: () -> NSMenu? = { nil }
    var isDragEnabled = true

    private let hostingView: NSHostingView<Content>

    private var mouseDownEvent: NSEvent?
    private var isDragging = false

    var rootView: Content {
        get { hostingView.rootView }
        set { hostingView.rootView = newValue }
    }

    init(rootView: Content) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        let event = NSApp.currentEvent
        let requestsContextMenu = event?.type == .rightMouseDown
            || event?.type == .rightMouseUp
            || (event?.type == .leftMouseDown && event?.modifierFlags.contains(.control) == true)
        if requestsContextMenu || isDragEnabled {
            return self
        }
        return hostingView.hitTest(convert(point, to: hostingView))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider()
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragEnabled,
              !isDragging,
              let mouseDownEvent,
              hypot(
                event.locationInWindow.x - mouseDownEvent.locationInWindow.x,
                event.locationInWindow.y - mouseDownEvent.locationInWindow.y
              ) > 3 else { return }

        let urls = dragURLs()
            .map(\.standardizedFileURL)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !urls.isEmpty else { return }

        isDragging = true
        let dragOrigin = convert(mouseDownEvent.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(index, 5)) * 3
            let frame = NSRect(
                x: dragOrigin.x - 20 + offset,
                y: dragOrigin.y - 20 - offset,
                width: 40,
                height: 40
            )
            item.setDraggingFrame(frame, contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }

        let session = beginDraggingSession(with: items, event: mouseDownEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = urls.count > 1 ? .stack : .none
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard !isDragging else {
            isDragging = false
            return
        }
        if event.clickCount >= 2 {
            doubleAction()
        } else {
            primaryAction()
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        if NSEvent.modifierFlags.contains(.option) {
            return .copy
        }
        // Finder chooses move for same-volume destinations and copy when a
        // destination (such as an importing app or another volume) requires it.
        return [.copy, .move, .link]
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDragging = false
        mouseDownEvent = nil
        dragEnded(operation)
    }
}
