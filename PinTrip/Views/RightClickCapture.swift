import AppKit
import SwiftUI

/// Captures right-clicks on macOS and reports the click position in the
/// receiver's own coordinate space.
///
/// SwiftUI's `contextMenu` on macOS does not provide the click location, and
/// `MapKit for SwiftUI` has no `contextMenu(point:)` modifier on macOS, so the
/// drop-a-pin gesture is handled with an AppKit overlay instead.
struct RightClickCapture: NSViewRepresentable {
    let onRightClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> RightClickCaptureView {
        let view = RightClickCaptureView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickCaptureView, context: Context) {
        nsView.onRightClick = onRightClick
    }
}

final class RightClickCaptureView: NSView {
    var onRightClick: ((CGPoint) -> Void)?

    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Transparent to normal interaction so panning and zooming still work;
        // only right-clicks are intercepted.
        guard let event = NSApp.currentEvent,
              event.type == .rightMouseDown
        else { return nil }
        return self
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onRightClick?(point)
    }
}
