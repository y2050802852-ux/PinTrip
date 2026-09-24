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
    @State private var locationService = UserLocationService()
    @State private var locationError: String?
    @State private var userLocationShown: MapCoordinate?

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

                // "Locate me" result: shows until the next plan switch.
                if let userLocationShown {
                    Marker("我的位置", systemImage: "location.circle.fill", coordinate: userLocationShown.clCoordinate)
                        .tint(.cyan)
                }
                UserLocationMarker()
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

                // Locate-me: request position, mark it, focus the camera.
                VStack(alignment: .trailing, spacing: 6) {
                    Button {
                        Task { await locateMe() }
                    } label: {
                        Label("定位我的位置", systemImage: locationService.isLocating ? "location.ripple" : "location.fill")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                    .disabled(locationService.isLocating)

                    if locationService.isDenied {
                        Text(LocationError.denied.errorDescription ?? "")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: 260, alignment: .trailing)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    } else if let locationError {
                        Text(locationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: 240, alignment: .trailing)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.trailing, 14)
                .padding(.bottom, 4)
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
        .onChange(of: plan?.id) { _, _ in
            userLocationShown = nil
            locationError = nil
        }
    }

    /// Requests the current position once, marks it, and flies the camera.
    private func locateMe() async {
        locationError = nil
        do {
            let coordinate = try await locationService.locate()
            let coordinateValue = MapCoordinate(coordinate)
            userLocationShown = coordinateValue
            cameraPosition = .camera(
                MapCamera(centerCoordinate: coordinate, distance: 1_000)
            )
        } catch {
            locationError = error.localizedDescription
        }
    }
}

/// Apple's blue pulsing dot for the user's position on SwiftUI Maps.
private struct UserLocationMarker: MapContent {
    var body: some MapContent {
        UserAnnotation()
    }
}
