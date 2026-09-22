import MapKit
import SwiftData
import SwiftUI

struct PlaceListView: View {
    let plan: Plan?
    @Binding var selectedPlaceID: PersistentIdentifier?
    let undoController: UndoController

    @Environment(\.modelContext) private var context
    @State private var searchService = PlaceSearchService()
    @State private var query = ""
    @State private var isResolving = false
    @State private var searchError: String?

    private var places: [Place] {
        plan?.orderedPlaces ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            content
        }
        .frame(minWidth: 280)
        .onChange(of: plan?.id) { _, _ in
            searchService.clear()
            query = ""
            updateSearchRegion()
        }
        .onAppear(perform: updateSearchRegion)
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
                    ForEach(places) { place in
                        PlaceRow(plan: plan, place: place)
                            .tag(place.id as PersistentIdentifier?)
                    }
                    .onMove { from, to in
                        reorder(plan: plan, from: from, to: to)
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
                TextField("搜索地点加入计划", text: $query)
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
                    Task { await resolve(suggestion) }
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
        .overlay {
            if isResolving {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: - Actions

    private func updateSearchRegion() {
        searchService.biasCity = plan?.destinationName
    }

    private func resolve(_ suggestion: PlaceSuggestion) async {
        isResolving = true
        defer { isResolving = false }
        do {
            let coordinate = try await searchService.resolve(suggestion)
            addPlace(name: suggestion.title, coordinate: coordinate, category: .sight)
            query = ""
            searchService.clear()
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
            addPlace(
                name: item.name ?? query,
                coordinate: item.placemark.coordinate,
                category: .sight
            )
            query = ""
            searchService.clear()
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func addPlace(
        name: String,
        coordinate: CLLocationCoordinate2D,
        category: PlaceCategory
    ) {
        guard let plan else { return }
        let place = Place(name: name, coordinate: coordinate, category: category)
        place.sortOrder = plan.places.count
        context.insert(place)
        PlanStore(context: context).add(place, to: plan)
        selectedPlaceID = place.id
        searchError = nil
    }

    private func reorder(plan: Plan, from source: IndexSet, to destination: Int) {
        var ordered = plan.orderedPlaces
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, place) in ordered.enumerated() {
            place.sortOrder = index
        }
        try? context.save()
    }
}
