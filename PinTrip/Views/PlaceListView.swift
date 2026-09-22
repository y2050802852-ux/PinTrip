import MapKit
import SwiftData
import SwiftUI

struct PlaceListView: View {
    let plan: Plan?
    @Binding var selectedPlaceID: PersistentIdentifier?
    let undoController: UndoController

    /// Day whose places are shown exclusively; nil shows the whole trip.
    @Binding var focusedDay: Int?

    /// Set when the user picks a search suggestion or right-clicks the map.
    @Binding var preview: PlacePreview?

    @Environment(\.modelContext) private var context
    @State private var searchService = PlaceSearchService()
    @State private var query = ""
    @State private var isResolving = false
    @State private var searchError: String?

    private var places: [Place] {
        plan?.orderedPlaces ?? []
    }

    private var placesByDay: [(day: Int, places: [Place])] {
        guard let plan else { return [] }
        let days = focusedDay.map { [$0] } ?? plan.dayNumbers
        return days.compactMap { day in
            let items = places.filter { $0.day == day }
            return items.isEmpty ? nil : (day: day, places: items)
        }
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
            if places.isEmpty {
                ContentUnavailableView {
                    Label("还没有地点", systemImage: "mappin.slash")
                } description: {
                    Text("用上方搜索框查找地点，或在地图上右键添加")
                }
            } else {
                List(selection: $selectedPlaceID) {
                    ForEach(placesByDay, id: \.day) { section in
                        Section {
                            ForEach(section.places) { place in
                                PlaceRow(plan: plan, place: place)
                                    .tag(place.id as PersistentIdentifier?)
                            }
                            .onMove { from, to in
                                reorder(day: section.day, from: from, to: to)
                            }
                        } header: {
                            DayHeader(
                                plan: plan,
                                day: section.day,
                                count: section.places.count,
                                isFocused: focusedDay == section.day
                            ) {
                                focusedDay = (focusedDay == section.day) ? nil : section.day
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        } else {
            ContentUnavailableView {
                Label("未选择计划", systemImage: "sidebar.left")
            } description: {
                Text("在左侧选择或新建一个旅游计划")
            }
        }
    }

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

    /// Selecting a suggestion only previews it on the map; nothing is saved
    /// until the user confirms from the preview card.
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

    /// Clears the search field after a preview has been committed elsewhere.
    private func clearAfterCommit() {
        query = ""
        searchService.clear()
    }

    private func reorder(day: Int, from source: IndexSet, to destination: Int) {
        var ordered = places.filter { $0.day == day }
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, place) in ordered.enumerated() {
            place.sortOrder = index
        }
        try? context.save()
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
