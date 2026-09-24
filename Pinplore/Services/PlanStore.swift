import SwiftData
import SwiftUI

/// Deletion semantics for the many-to-many Plan <-> Place relationship.
///
/// Deleting a plan removes the plan and unlinks every place it contained.
/// A place left with no remaining plan is an orphan and is deleted too;
/// a place still referenced by another plan survives untouched.
@MainActor
struct PlanStore {
    let context: ModelContext

    @discardableResult
    func createPlan(name: String) -> Plan {
        let plan = Plan(name: name)
        context.insert(plan)
        try? context.save()
        return plan
    }

    func rename(_ plan: Plan, to name: String) {
        plan.name = name
        try? context.save()
    }

    /// Deletes `plan`, cascading to exclusively-owned places.
    /// Every affected place is snapshotted first so it can be rebuilt verbatim.
    @discardableResult
    func delete(_ plan: Plan) -> PlanDeletion {
        let deletion = PlanDeletion(plan: plan)
        for place in plan.places {
            place.plans.removeAll { $0.id == plan.id }
            if place.plans.isEmpty {
                context.delete(place)
            }
        }
        context.delete(plan)
        try? context.save()
        return deletion
    }

    /// Rebuilds the plan from a snapshot, recreating places that were deleted.
    func restore(_ deletion: PlanDeletion) -> Plan {
        let plan = Plan(name: deletion.name)
        plan.createdAt = deletion.createdAt
        plan.destinationName = deletion.destinationName
        plan.destinationLatitude = deletion.destinationLatitude
        plan.destinationLongitude = deletion.destinationLongitude
        plan.searchRadius = deletion.searchRadius
        plan.startDate = deletion.startDate
        plan.endDate = deletion.endDate
        context.insert(plan)

        // Places shared with other plans survived deletion; re-link those
        // instead of recreating duplicates.
        let wantedIDs = Set(deletion.places.map(\.id))
        var survivorByID: [PersistentIdentifier: Place] = [:]
        if !wantedIDs.isEmpty {
            let survivors = (try? context.fetch(FetchDescriptor<Place>())) ?? []
            for place in survivors where wantedIDs.contains(place.id) {
                survivorByID[place.id] = place
            }
        }

        for snapshot in deletion.places {
            if let existing = survivorByID[snapshot.id] {
                if !existing.plans.contains(where: { $0.id == plan.id }) {
                    existing.plans.append(plan)
                }
            } else {
                let place = snapshot.makePlace()
                context.insert(place)
                place.plans = [plan]
            }
        }

        try? context.save()
        return plan
    }

    /// Applies a new itinerary window. Places scheduled on days that no longer
    /// exist are moved to the new last day rather than being lost.
    /// Returns how many places were moved.
    func setDateRange(_ plan: Plan, start: Date?, end: Date?) -> Int {
        plan.startDate = start
        plan.endDate = end

        var moved = 0
        let lastDay = plan.dayCount
        for place in plan.places where place.day > lastDay {
            place.day = lastDay
            moved += 1
        }
        try? context.save()
        return moved
    }

    func add(_ place: Place, to plan: Plan) {
        if !place.plans.contains(where: { $0.id == plan.id }) {
            place.plans.append(plan)
        }
        if !plan.places.contains(where: { $0.id == place.id }) {
            plan.places.append(place)
        }
        try? context.save()
    }

    func remove(_ place: Place, from plan: Plan) {
        place.plans.removeAll { $0.id == plan.id }
        plan.places.removeAll { $0.id == place.id }
        if place.plans.isEmpty {
            context.delete(place)
        }
        try? context.save()
    }

    /// Duplicates `place` within `plan`: a new record right after the
    /// original (same day), named with a "(副本)" suffix.
    ///
    /// The copy is independent — editing its notes/rating/day never touches
    /// the original — which is the point over referencing the same record
    /// twice. It joins only the given plan.
    @discardableResult
    func duplicate(_ place: Place, in plan: Plan) -> Place {
        let copy = Place(
            name: place.name + "（副本）",
            coordinate: place.coordinate,
            category: place.category
        )
        copy.notes = place.notes
        copy.rating = place.rating
        copy.visited = false          // a new visit, not the original's history
        copy.linkURL = place.linkURL
        copy.photoPath = place.photoPath
        copy.day = place.day

        // Slot directly after the original within its day.
        let daySiblings = plan.places
            .filter { $0.day == place.day }
            .sorted { $0.sortOrder < $1.sortOrder }
        let originalIndex = daySiblings.firstIndex { $0.id == place.id }
            ?? daySiblings.count
        copy.sortOrder = originalIndex + 1

        context.insert(copy)
        add(copy, to: plan)

        // Shift siblings after the original to keep order contiguous.
        for (offset, sibling) in daySiblings.enumerated() where offset > originalIndex {
            sibling.sortOrder += 1
        }
        try? context.save()
        return copy
    }
}
