import SwiftData
import SwiftUI

/// One day's contents and its single drop target.
///
/// Registering a `dropDestination` per row made SwiftUI hit-test dozens of
/// targets on every mouse move, and each hover mutated shared `@State`, which
/// invalidated the whole list and re-registered them again. A drag then took
/// seconds to settle and the next drag was unresponsive.
///
/// This view instead owns ONE drop target for the whole day and computes the
/// insertion index from the drop location, keeping the target count equal to
/// the number of days regardless of how many places exist.
struct DayDropArea: View {
    let plan: Plan
    let items: [Place]
    @Binding var selectedPlaceID: PersistentIdentifier?
    @Binding var isTargeted: Bool
    @Binding var dropTargetIndex: Int?
    let handleDrop: ([PlaceDragPayload], Int) -> Bool

    /// Tells the app to fly the map to this place (double-click).
    let onFocusPlace: (Place) -> Void

    /// Duplicates a place within the plan.
    let onDuplicatePlace: (Place) -> Void

    @Environment(\.modelContext) private var context

    /// Place being renamed via the context menu.
    @State private var renamingPlace: Place?

    /// Row height is fixed explicitly so `insertionIndex` can map a drop's y
    /// coordinate to a slot; keep the two in sync.
    private static let rowHeight: CGFloat = 44

    /// Index where a drop at the given y would land, based on row heights.
    private func insertionIndex(for location: CGPoint) -> Int {
        guard !items.isEmpty, Self.rowHeight > 0 else { return 0 }
        let raw = Int(floor(location.y / Self.rowHeight))
        return min(max(raw, 0), items.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                Text("拖动地点到这里")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, place in
                    insertIndicator(index: index)
                    row(for: place)
                        .frame(height: Self.rowHeight)
                }
                insertIndicator(index: items.count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
        )
        // Single drop target per day: receives either the drop action or the
        // hover updates, never a per-row fan-out.
        .dropDestination(for: PlaceDragPayload.self) { payloads, location in
            let index = insertionIndex(for: location)
            return handleDrop(payloads, index)
        } isTargeted: { targeted in
            isTargeted = targeted
            if !targeted { dropTargetIndex = nil }
        }
        // Hover position drives the indicator without extra @State churn.
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                guard isTargeted else { return }
                dropTargetIndex = insertionIndex(for: location)
            case .ended:
                dropTargetIndex = nil
            }
        }
        .sheet(item: $renamingPlace) { place in
            RenameSheet(place: place)
        }
    }

    private func row(for place: Place) -> some View {
        let isSelected = selectedPlaceID == place.id
        return PlaceRow(plan: plan, place: place)
            // The outer List row is the whole day, so List's native selection
            // highlight never applies; draw our own.
            .background(
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .frame(width: 3)
                    Color(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
                }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                // Clicking the selected row again toggles the inspector off.
                selectedPlaceID = (selectedPlaceID == place.id) ? nil : place.id
            }
            .onTapGesture(count: 2) {
                selectedPlaceID = place.id
                onFocusPlace(place)
            }
            .draggable(PlaceDragPayload(placeID: place.id))
            .contextMenu {
                Button("复制地点") { onDuplicatePlace(place) }
                Button("重命名…") { renamingPlace = place }
                Divider()
                Button("从本计划移除", role: .destructive) {
                    PlanStore(context: context).remove(place, from: plan)
                }
            }
    }

    @ViewBuilder
    private func insertIndicator(index: Int) -> some View {
        let active = isTargeted && dropTargetIndex == index
        Rectangle()
            .fill(active ? Color.accentColor : Color.clear)
            .frame(height: active ? 2 : 0)
    }
}
