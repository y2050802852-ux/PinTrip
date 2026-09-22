import SwiftData
import SwiftUI

/// Owns the "plan deleted" toast and holds the snapshot needed to restore it.
/// SwiftData has no undo manager, and cascade deletes are permanent, so the
/// plan and its places are copied out before the delete and rebuilt on undo.
@Observable
final class UndoController {
    private(set) var pending: PlanDeletion?
    private(set) var isShowing = false
    private var dismissalTask: Task<Void, Never>?

    @MainActor
    func offerUndo(_ deletion: PlanDeletion, seconds: Double = 5) {
        pending = deletion
        isShowing = true
        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await MainActor.run { self?.dismiss() }
        }
    }

    @MainActor
    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        pending = nil
        isShowing = false
    }

    var message: String {
        guard let pending else { return "" }
        return "已删除「\(pending.name)」及其 \(pending.placeCount) 个地点"
    }
}
