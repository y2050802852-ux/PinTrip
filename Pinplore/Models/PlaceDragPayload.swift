import CoreTransferable
import Foundation
import SwiftData

/// Drag payload for moving a place between days or within a day.
///
/// `PersistentIdentifier` is `Codable` and `Sendable`, so it travels directly
/// in the pasteboard — no hashing or string parsing that could collide.
struct PlaceDragPayload: Transferable, Codable, Sendable {
    let placeID: PersistentIdentifier

    init(placeID: PersistentIdentifier) {
        self.placeID = placeID
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}
