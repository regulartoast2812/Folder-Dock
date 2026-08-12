import AppKit
import SwiftUI

struct CopyablePathLabel: NSViewRepresentable {
    let path: String
    let didCopy: () -> Void

    func makeNSView(context: Context) -> CopyablePathNSView {
        let view = CopyablePathNSView()
        view.update(path: path, didCopy: didCopy)
        return view
    }

    func updateNSView(_ nsView: CopyablePathNSView, context: Context) {
        nsView.update(path: path, didCopy: didCopy)
    }
}

final class CopyablePathNSView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var path = ""
    private var didCopy: () -> Void = {}
    private var isPressed = false
    private var isHovering = false
    private var hoverScrollStarted = false
    private var pathTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 9)
        label.textColor = .labelColor
        label.alphaValue = 0.62
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.alignment = .left
        label.isSelectable = false
        label.isEditable = false
        label.drawsBackground = false
        label.wantsLayer = true
        label.cell?.usesSingleLineMode = true
        label.cell?.lineBreakMode = .byClipping
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 16)
    }

    override func layout() {
        super.layout()
        let textSize = measuredTextSize
        let labelWidth = max(bounds.width, ceil(textSize.width) + 2)
        let labelHeight = min(bounds.height, max(12, ceil(textSize.height)))
        let minimumX = min(0, bounds.width - labelWidth)
        let x = isHovering ? max(min(label.frame.minX, 0), minimumX) : 0
        label.frame = NSRect(
            x: x,
            y: floor((bounds.height - labelHeight) / 2),
            width: labelWidth,
            height: labelHeight
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pathTrackingArea {
            removeTrackingArea(pathTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pathTrackingArea = trackingArea
    }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        copyPath()
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 {
            copyPath()
        } else {
            super.otherMouseUp(with: event)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isHovering else { return }
        isHovering = true
        hoverScrollStarted = false
        layoutSubtreeIfNeeded()
        resetPathPosition()
        perform(#selector(beginHoverScroll), with: nil, afterDelay: 0.35)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        hoverScrollStarted = false
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(beginHoverScroll),
            object: nil
        )
        resetPathPosition()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    func update(path: String, didCopy: @escaping () -> Void) {
        self.didCopy = didCopy
        guard self.path != path else { return }
        self.path = path
        label.stringValue = path
        toolTip = nil
        isHovering = false
        hoverScrollStarted = false
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(beginHoverScroll),
            object: nil
        )
        resetPathPosition()
        label.alphaValue = 0.62
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    private var measuredTextSize: NSSize {
        guard let font = label.font else { return .zero }
        return (path as NSString).size(withAttributes: [.font: font])
    }

    @objc private func beginHoverScroll() {
        guard isHovering, !hoverScrollStarted else { return }
        hoverScrollStarted = true
        layoutSubtreeIfNeeded()
        let overflow = max(0, label.frame.width - bounds.width)
        guard overflow > 1 else { return }

        resetPathPosition()
        label.displayIfNeeded()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = min(max(TimeInterval(overflow / 55), 1.4), 8)
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            label.animator().setFrameOrigin(NSPoint(x: -overflow, y: label.frame.origin.y))
        }
    }

    private func resetPathPosition() {
        label.layer?.removeAllAnimations()
        var frame = label.frame
        frame.origin.x = 0
        label.frame = frame
    }

    private func copyPath() {
        guard !path.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        label.alphaValue = 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.55
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            label.animator().alphaValue = 0.62
        }
        didCopy()
    }
}

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
    let doubleAction: () -> Void
    let middleAction: () -> Void
    let dragURLs: () -> [URL]
    let dragStarted: () -> Void
    let dragEnded: (NSDragOperation) -> Void
    let receiveDrop: ([URL]) -> Bool
    let contextMenuStarted: () -> Void
    let contextActions: [PointerContextAction]
    let label: Label

    init(
        primaryAction: @escaping () -> Void,
        doubleAction: @escaping () -> Void = {},
        middleAction: @escaping () -> Void,
        dragURLs: @escaping () -> [URL] = { [] },
        dragStarted: @escaping () -> Void = {},
        dragEnded: @escaping (NSDragOperation) -> Void = { _ in },
        receiveDrop: @escaping ([URL]) -> Bool = { _ in false },
        contextMenuStarted: @escaping () -> Void = {},
        contextActions: [PointerContextAction] = [],
        @ViewBuilder label: () -> Label
    ) {
        self.primaryAction = primaryAction
        self.doubleAction = doubleAction
        self.middleAction = middleAction
        self.dragURLs = dragURLs
        self.dragStarted = dragStarted
        self.dragEnded = dragEnded
        self.receiveDrop = receiveDrop
        self.contextMenuStarted = contextMenuStarted
        self.contextActions = contextActions
        self.label = label()
    }

    func makeNSView(context: Context) -> PointerButtonView<Label> {
        let view = PointerButtonView(rootView: label)
        view.primaryAction = primaryAction
        view.doubleAction = doubleAction
        view.middleAction = middleAction
        view.dragURLs = dragURLs
        view.dragStarted = dragStarted
        view.dragEnded = dragEnded
        view.receiveDrop = receiveDrop
        view.contextMenuStarted = contextMenuStarted
        view.contextActions = contextActions
        return view
    }

    func updateNSView(_ nsView: PointerButtonView<Label>, context: Context) {
        nsView.rootView = label
        nsView.primaryAction = primaryAction
        nsView.doubleAction = doubleAction
        nsView.middleAction = middleAction
        nsView.dragURLs = dragURLs
        nsView.dragStarted = dragStarted
        nsView.dragEnded = dragEnded
        nsView.receiveDrop = receiveDrop
        nsView.contextMenuStarted = contextMenuStarted
        nsView.contextActions = contextActions
    }
}

final class PointerButtonView<Content: View>: NSView, NSDraggingSource {
    var primaryAction: () -> Void = {}
    var doubleAction: () -> Void = {}
    var middleAction: () -> Void = {}
    var dragURLs: () -> [URL] = { [] }
    var dragStarted: () -> Void = {}
    var dragEnded: (NSDragOperation) -> Void = { _ in }
    var receiveDrop: ([URL]) -> Bool = { _ in false }
    var contextMenuStarted: () -> Void = {}
    var contextActions: [PointerContextAction] = []
    private var mouseDownEvent: NSEvent?
    private var isDraggingFile = false
    private let hostingView: NSHostingView<Content>

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

    override var intrinsicContentSize: NSSize {
        hostingView.intrinsicContentSize
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

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
              let mouseDownEvent,
              hypot(event.locationInWindow.x - mouseDownEvent.locationInWindow.x, event.locationInWindow.y - mouseDownEvent.locationInWindow.y) > 3 else { return }

        var seenPaths = Set<String>()
        let urls = dragURLs()
            .map(\.standardizedFileURL)
            .filter { seenPaths.insert($0.path).inserted }
        guard !urls.isEmpty else { return }

        isDraggingFile = true
        dragStarted()
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
        if !isDraggingFile {
            if event.clickCount >= 2 {
                doubleAction()
            } else {
                primaryAction()
            }
        }
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
        contextMenuStarted()
        let menu = NSMenu()
        // These items dispatch into the closures stored by this view rather than
        // through AppKit's responder chain. Automatic validation therefore has
        // no command target to validate and disables the whole menu.
        menu.autoenablesItems = false
        for (index, contextAction) in contextActions.enumerated() {
            if contextAction.title == "-" {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: contextAction.title, action: #selector(runContextAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.isEnabled = true
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

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        if NSEvent.modifierFlags.contains(.option) {
            return .copy
        }
        return [.copy, .move, .link]
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDraggingFile = false
        mouseDownEvent = nil
        dragEnded(operation)
    }

    private func droppedURLs(from pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL])?.map { $0 as URL } ?? []
    }
}
