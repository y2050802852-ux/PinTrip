import AppKit
import SwiftUI

/// Captures right-clicks and long-presses on macOS and reports the position
/// in the receiver's own coordinate space.
///
/// The view is FLIPPED (`isFlipped = true`) so its origin matches SwiftUI's
/// top-left coordinate space — `MapProxy.convert(_:from:)` resolves `.local`
/// against top-left geometry. The earlier non-flipped version reported
/// bottom-left coordinates, which landed the pin vertically mirrored from
/// where the user clicked.
struct RightClickCapture: NSViewRepresentable {
    /// Called with the point in the view's (top-left origin) coordinates.
    let onPoint: (CGPoint) -> Void

    func makeNSView(context: Context) -> PointCaptureView {
        let view = PointCaptureView()
        view.onPoint = onPoint
        return view
    }

    func updateNSView(_ nsView: PointCaptureView, context: Context) {
        nsView.onPoint = onPoint
    }
}

final class PointCaptureView: NSView {
    var onPoint: ((CGPoint) -> Void)?

    override var acceptsFirstResponder: Bool { false }

    /// Flipped so y grows downward, matching SwiftUI coordinate spaces.
    override var isFlipped: Bool { true }

    // MARK: - Right click

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Transparent to normal interaction so panning/zooming still work;
        // only right-clicks and long-presses are intercepted.
        guard let event = NSApp.currentEvent,
              event.type == .rightMouseDown || event.type == .leftMouseDown
        else { return nil }
        return self
    }

    override func rightMouseDown(with event: NSEvent) {
        onPoint?(convert(event.locationInWindow, from: nil))
    }

    // MARK: - Long press (left button held ~0.5s without moving)

    private var longPressWorkItem: DispatchWorkItem?

    override func mouseDown(with event: NSEvent) {
        pendingStart = convert(event.locationInWindow, from: nil)
        let item = DispatchWorkItem { [weak self] in
            guard let self, let start = self.pendingStart else { return }
            self.onPoint?(start)
        }
        longPressWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    override func mouseUp(with event: NSEvent) {
        cancelLongPress()
    }

    override func mouseDragged(with event: NSEvent) {
        // Movement cancels: this is a pan, not a long press.
        if let start = pendingStart {
            let current = convert(event.locationInWindow, from: nil)
            if hypot(current.x - start.x, current.y - start.y) > 8 {
                cancelLongPress()
            }
        }
    }

    private var pendingStart: CGPoint?

    private func cancelLongPress() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        pendingStart = nil
    }
}
