import CoreLocation
import MapKit
import SwiftUI

/// Sets a plan's destination city. Searching a city biases later place
/// searches toward it and sets the map camera when the plan is selected.
struct PlanDestinationSheet: View {
    let plan: Plan
    let onCommit: (String, CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var service = PlaceSearchService()
    @State private var query = ""
    @State private var isResolving = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置目的地城市")
                .font(.headline)
            Text("之后的地点搜索会优先围绕该城市，切换计划时地图也会自动定位到这里。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("搜索城市，如「东京」「大阪」", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _, newValue in
                    service.updateQuery(newValue)
                }
                .onSubmit { Task { await resolveTop() } }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !service.suggestions.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(service.suggestions.prefix(8)) { suggestion in
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
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxHeight: 220)
                .overlay { if isResolving { ProgressView().controlSize(.small) } }
            }

            HStack {
                if plan.destinationName != nil {
                    Button("清除目的地", role: .destructive) {
                        clearDestination()
                    }
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func resolve(_ suggestion: PlaceSuggestion) async {
        isResolving = true
        defer { isResolving = false }
        do {
            let coordinate = try await service.resolve(suggestion)
            commit(suggestion.title, coordinate)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func resolveTop() async {
        guard !query.trimmed.isEmpty else { return }
        isResolving = true
        defer { isResolving = false }
        do {
            let items = try await service.search(query)
            guard let item = items.first else {
                errorText = "未找到该城市"
                return
            }
            commit(item.name ?? query, item.placemark.coordinate)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func commit(_ name: String, _ coordinate: CLLocationCoordinate2D) {
        onCommit(name, coordinate)
        dismiss()
    }

    private func clearDestination() {
        plan.destinationName = nil
        plan.destinationLatitude = nil
        plan.destinationLongitude = nil
        dismiss()
    }
}
