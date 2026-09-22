import MapKit
import SwiftData
import SwiftUI

struct MapCanvasView: View {
    let plan: Plan?
    @Binding var selectedPlaceID: PersistentIdentifier?
    @Binding var cameraPosition: MapCameraPosition

    @Environment(\.modelContext) private var context
    @State private var dropCoordinate: CLLocationCoordinate2D?
    @State private var showingDropSheet = false

    private var places: [Place] {
        plan?.orderedPlaces ?? []
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, selection: $selectedPlaceID) {
                ForEach(places) { place in
                    Marker(place.name, systemImage: place.category.symbolName, coordinate: place.coordinate)
                        .tint(place.category.tint)
                        .tag(place.id as PersistentIdentifier?)
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
                    dropCoordinate = coordinate
                    showingDropSheet = true
                }
            }
        }
        .sheet(isPresented: $showingDropSheet) {
            DropPinSheet(coordinate: dropCoordinate) { name, category in
                guard let coordinate = dropCoordinate else { return }
                addPlace(name: name, coordinate: coordinate, category: category)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let plan, plan.destinationName == nil {
                Text("未设置目的地城市 · 搜索结果不受地域限制")
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
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
    }
}
