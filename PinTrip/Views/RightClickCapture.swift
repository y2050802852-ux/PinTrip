#if os(macOS)
import AppKit
import SwiftUI

/// Captures right-clicks on macOS and reports the position in the receiver's
/// own coordinate space (flipped, matching SwiftUI's top-left origin).
///
/// Plain left clicks are intentionally NOT intercepted: SwiftUI Map needs
/// them for marker selection and deselection. Long-press detection is handled
/// separately by `LongPressMonitor` at the event-monitor level.
struct RightClickCapture: NSViewRepresentable {
    let onRightClick: (CGPoint) -> Void
    /// Lets the long-press monitor reuse this view's coordinate conversion.
    var onViewResolved: ((RightClickCaptureView) -> Void)? = nil

    func makeNSView(context: Context) -> RightClickCaptureView {
        let view = RightClickCaptureView()
        view.onRightClick = onRightClick
        onViewResolved?(view)
        return view
    }

    func updateNSView(_ nsView: RightClickCaptureView, context: Context) {
        nsView.onRightClick = onRightClick
    }
}

final class RightClickCaptureView: NSView {
    var onRightClick: ((CGPoint) -> Void)?

    override var acceptsFirstResponder: Bool { false }

    /// Flipped so y grows downward, matching SwiftUI coordinate spaces.
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Claim ONLY right-clicks; everything else passes through to the map.
        guard let event = NSApp.currentEvent, event.type == .rightMouseDown else { return nil }
        return self
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(convert(event.locationInWindow, from: nil))
    }

    /// Converts a window-coordinate point (bottom-left origin, as delivered by
    /// NSEvent.locationInWindow) into this view's flipped local coordinates.
    func localPoint(fromWindow windowPoint: CGPoint) -> CGPoint {
        convert(windowPoint, from: nil)
    }
}

/// Detects a press-and-hold (~0.5s, minimal movement) anywhere and reports it,
/// without swallowing short clicks or drags. Implemented as a local NSEvent
/// monitor so Map interaction (marker selection, pan, zoom) stays untouched.
@MainActor
final class LongPressMonitor {
    private var monitor: Any?
    private var pressStart: CGPoint?
    private var pressWorkItem: DispatchWorkItem?
    private let onLongPress: (CGPoint) -> Void

    init(onLongPress: @escaping (CGPoint) -> Void) {
        self.onLongPress = onLongPress
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
            return event // always pass through
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        self.monitor = nil
        pressWorkItem?.cancel()
        pressStart = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            pressStart = event.locationInWindow
            let work = DispatchWorkItem { [weak self] in
                guard let self, let start = self.pressStart else { return }
                self.pressStart = nil
                self.onLongPress(start)
            }
            pressWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)

        case .leftMouseDragged:
            if let start = pressStart,
               hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 8 {
                pressWorkItem?.cancel()
                pressStart = nil
            }

        case .leftMouseUp:
            pressWorkItem?.cancel()
            pressStart = nil

        default:
            break
        }
    }
}
#endif
