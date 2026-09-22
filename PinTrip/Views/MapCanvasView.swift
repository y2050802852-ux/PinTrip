import MapKit
import SwiftData
import SwiftUI

struct MapCanvasView: View {
    let plan: Plan?
    @Binding var selectedPlaceID: PersistentIdentifier?
    @Binding var cameraPosition: MapCameraPosition

    /// Restricts the map to a single day when set; nil shows the whole plan.
    @Binding var focusedDay: Int?
    @Binding var preview: PlacePreview?

    /// Called after the user confirms adding the previewed place.
    let onCommitPreview: (String, PlaceCategory, Int) -> Void

    /// Day the add button targets, owned by ContentView so the list and card agree.
    @Binding var addTargetDay: Int

    /// When set, the map flies to this coordinate (double-click on a list row).
    @Binding var focusRequest: MapCoordinate?

    @Environment(\.modelContext) private var context

    private var places: [Place] {
        guard let plan else { return [] }
        let visible = focusedDay.map { day in plan.orderedPlaces.filter { $0.day == day } }
            ?? plan.orderedPlaces
        return visible
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, selection: $selectedPlaceID) {
                ForEach(places) { place in
                    Marker(place.name, systemImage: place.category.symbolName, coordinate: place.coordinate)
                        .tint(place.category.tint)
                        .tag(place.id as PersistentIdentifier?)
                }

                // Preview marker: distinct color and lower opacity so it reads
                // as "not yet in the itinerary".
                if let preview {
                    Marker(preview.needsName ? "新位置" : preview.name, coordinate: preview.coordinate)
                        .tint(Color.accentColor.opacity(0.55))
                }
            }
            .mapStyle(.standard)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .overlay {
                RightClickCapture { point in
                    guard let coordinate = proxy.convert(point, from: .local) else { return }
                    preview = PlacePreview(
                        name: "",
                        subtitle: "地图落点",
                        coordinate: coordinate,
                        source: .manualDrop
                    )
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 10) {
                if let preview, let plan {
                    PreviewCard(
                        preview: preview,
                        dayOptions: plan.dayNumbers,
                        dateForDay: { plan.date(forDayIndex: $0 - 1) },
                        selectedDay: plan.clampedDay(addTargetDay),
                        onSelectDay: { addTargetDay = $0 },
                        onAdd: { name, category in
                            onCommitPreview(name, category, plan.clampedDay(addTargetDay))
                        },
                        onCancel: { self.preview = nil }
                    )
                    .padding(14)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if focusedDay != nil {
                    Button {
                        focusedDay = nil
                    } label: {
                        Label("显示全部地点", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .padding(.trailing, 14)
                    .padding(.bottom, 4)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let plan, plan.destinationName == nil {
                Text("未设置目的地城市 · 搜索结果不受地域限制")
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
        .animation(.easeOut(duration: 0.18), value: preview?.id)
        // Focus the map on the previewed coordinate as soon as it appears.
        .onChange(of: preview?.id) { _, _ in
            guard let coordinate = preview?.coordinate else { return }
            cameraPosition = .camera(
                MapCamera(centerCoordinate: coordinate, distance: 4_000)
            )
        }
        // Double-clicking a place row in the list flies the map to it, closer
        // than a preview since the place is already confirmed.
        .onChange(of: focusRequest) { _, request in
            guard let request else { return }
            cameraPosition = .camera(
                MapCamera(centerCoordinate: request.clCoordinate, distance: 1_000)
            )
            focusRequest = nil
        }
    }
}
