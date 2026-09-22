import MapKit
import SwiftData
import SwiftUI

struct PlaceListView: View {
    let plan: Plan?
    @Binding var selectedPlaceID: PersistentIdentifier?
    let undoController: UndoController

    /// Day whose places are shown exclusively; nil shows every day.
    @Binding var focusedDay: Int?

    /// Set when the user picks a search suggestion or right-clicks the map.
    @Binding var preview: PlacePreview?

    @Environment(\.modelContext) private var context
    @State private var searchService = PlaceSearchService()
    @State private var query = ""
    @State private var isResolving = false
    @State private var searchError: String?

    /// Day currently hovered by a drag, and the row index it would insert at.
    @State private var dropTargetDay: Int?
    @State private var dropTargetIndex: Int?

    private var places: [Place] {
        plan?.orderedPlaces ?? []
    }

    /// Every day is listed, including empty ones, so places can be dragged
    /// into a day before any place exists there.
    private var visibleDays: [Int] {
        guard let plan else { return [] }
        return focusedDay.map { [$0] } ?? plan.dayNumbers
    }

    /// Places grouped by day, computed once per body evaluation.
    ///
    /// Previously each `places(onDay:)` call re-sorted the whole plan, and the
    /// body called it twice per day — quadratic work on every re-render, which
    /// made dragging feel frozen.
    private var groupedByDay: [Int: [Place]] {
        guard plan != nil else { return [:] }
        var result: [Int: [Place]] = [:]
        for day in visibleDays {
            result[day] = []
        }
        for place in places {
            result[place.day, default: []].append(place)
        }
        for key in result.keys {
            result[key]?.sort { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
        }
        return result
    }

    private func places(onDay day: Int, from groups: [Int: [Place]]) -> [Place] {
        groups[day] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            content
        }
        .frame(minWidth: 300)
        .onChange(of: plan?.id) { _, _ in
            searchService.clear()
            query = ""
            preview = nil
            focusedDay = nil
            updateSearchBias()
        }
        .onAppear(perform: updateSearchBias)
        // Search text is cleared once the previewed place is committed.
        .onChange(of: preview) { _, newValue in
            if newValue == nil { clearAfterCommit() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let plan {
            let groups = groupedByDay
            List(selection: $selectedPlaceID) {
                ForEach(visibleDays, id: \.self) { day in
                    Section {
                        DayDropArea(
                            plan: plan,
                            items: places(onDay: day, from: groups),
                            selectedPlaceID: $selectedPlaceID,
                            isTargeted: Binding(
                                get: { dropTargetDay == day },
                                set: { if !$0, dropTargetDay == day { dropTargetDay = nil } }
                            ),
                            dropTargetIndex: $dropTargetIndex,
                            handleDrop: { payloads, index in
                                handleDrop(payloads, day: day, index: index)
                            }
                        )
                    } header: {
                        DayHeader(
                            plan: plan,
                            day: day,
                            count: places(onDay: day, from: groups).count,
                            isFocused: focusedDay == day
                        ) {
                            focusedDay = (focusedDay == day) ? nil : day
                        }
                    }
                }
            }
            .listStyle(.inset)
            .overlay {
                if places.isEmpty {
                    ContentUnavailableView {
                        Label("还没有地点", systemImage: "mappin.slash")
                    } description: {
                        Text("用上方搜索框查找地点，或在地图上右键添加")
                    }
                    .background(.background)
                }
            }
        } else {
            ContentUnavailableView {
                Label("未选择计划", systemImage: "sidebar.left")
            } description: {
                Text("在左侧选择或新建一个旅游计划")
            }
        }
    }

    // MARK: - Drop handling

    // MARK: - Drop handling

    private func handleDrop(_ payloads: [PlaceDragPayload], day: Int, index: Int) -> Bool {
        guard let plan, let payload = payloads.first else { return false }
        guard let place = plan.places.first(where: { $0.id == payload.placeID }) else { return false }

        let sourceDay = place.day
        let groups = groupedByDay
        var target = places(onDay: day, from: groups)
        // Removing the place first keeps the index valid for same-day moves.
        target.removeAll { $0.id == place.id }

        var insertAt = index
        if sourceDay == day,
           let oldIndex = places(onDay: day, from: groups).firstIndex(where: { $0.id == place.id }),
           oldIndex < index {
            insertAt -= 1
        }
        insertAt = min(max(insertAt, 0), target.count)

        place.day = plan.clampedDay(day)
        target.insert(place, at: insertAt)

        for (offset, item) in target.enumerated() {
            item.sortOrder = offset
        }
        // The day the place left must be renumbered too, otherwise it keeps a
        // gap and later inserts land in the wrong slot.
        if sourceDay != day {
            let source = places(onDay: sourceDay, from: groups)
            for (offset, item) in source.enumerated() {
                item.sortOrder = offset
            }
        }
        try? context.save()

        dropTargetDay = nil
        dropTargetIndex = nil
        return true
    }

    // MARK: - Search

    private var searchField: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索地点", text: $query)
                    .textFieldStyle(.plain)
                    .onChange(of: query) { _, newValue in
                        searchService.updateQuery(newValue)
                    }
                    .onSubmit {
                        Task { await resolveTopResult() }
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        searchService.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !searchService.suggestions.isEmpty {
                suggestionList
            }
        }
        .padding(10)
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(searchService.suggestions.prefix(6)) { suggestion in
                Button {
                    Task { await previewSuggestion(suggestion) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title).font(.body)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary.opacity(0.4))
                )
                Divider()
            }
        }
        .overlay { if isResolving { ProgressView().controlSize(.small) } }
    }

    // MARK: - Actions

    private func updateSearchBias() {
        searchService.biasCity = plan?.destinationName
    }

    /// Selecting a suggestion only previews it; nothing is saved until confirmed.
    private func previewSuggestion(_ suggestion: PlaceSuggestion) async {
        isResolving = true
        defer { isResolving = false }
        do {
            let coordinate = try await searchService.resolve(suggestion)
            preview = PlacePreview(
                name: suggestion.title,
                subtitle: suggestion.subtitle,
                coordinate: coordinate,
                source: .search
            )
            searchError = nil
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func resolveTopResult() async {
        guard !query.trimmed.isEmpty else { return }
        isResolving = true
        defer { isResolving = false }
        do {
            let items = try await searchService.search(query)
            guard let item = items.first else {
                searchError = "未找到该地点"
                return
            }
            preview = PlacePreview(
                name: item.name ?? query,
                subtitle: item.placemark.title ?? "",
                coordinate: item.placemark.coordinate,
                source: .search
            )
            searchError = nil
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func clearAfterCommit() {
        query = ""
        searchService.clear()
    }
}

/// Blue outline shown on the day section that a drag is currently over.
private struct DayHighlight: ViewModifier {
    let isTargeted: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                    )
            )
            .animation(.easeOut(duration: 0.12), value: isTargeted)
    }
}

private struct DayHeader: View {
    let plan: Plan
    let day: Int
    let count: Int
    let isFocused: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("第 \(day) 天")
                .font(.headline)
            if let date = plan.date(forDayIndex: day - 1) {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("· \(count) 个")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(isFocused ? "显示全部" : "只看这天") {
                toggle()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(isFocused ? Color.accentColor : .secondary)
        }
        .padding(.vertical, 2)
    }
}
