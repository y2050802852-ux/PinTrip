import SwiftUI

/// Cross-platform modal message. macOS shows NSAlert immediately; iOS stores
/// the pending message and the app scene presents it as a SwiftUI alert.
@MainActor
final class AlertBox: ObservableObject {
    static let shared = AlertBox()

    @Published var current: AlertContent?

    struct AlertContent: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    func show(title: String, message: String) {
        #if os(macOS)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
        #else
        current = AlertContent(title: title, message: message)
        #endif
    }
}
