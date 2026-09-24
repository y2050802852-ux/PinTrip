import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]
    @State private var selectedPlanID: PersistentIdentifier?
    @State private var selectedPlaceID: PersistentIdentifier?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var undoController = UndoController()

    /// Coordinate the map should fly to (double-click on a place row).
    @State private var focusRequest: MapCoordinate?

    /// Candidate place awaiting confirmation, shared by the list and the map.
    @State private var preview: PlacePreview?
    /// Day the preview card will add to.
    @State private var addTargetDay = 1
    /// When set, the middle list and the map show only this day.
    @State private var focusedDay: Int?

    @Environment(\.modelContext) private var modelContext

    private var selectedPlan: Plan? {
        plans.first { $0.id == selectedPlanID }
    }

    private var selectedPlace: Place? {
        guard let plan = selectedPlan, let placeID = selectedPlaceID else { return nil }
        return plan.places.first { $0.id == placeID }
    }

    var body: some View {
        NavigationSplitView {
            PlanSidebar(plans: plans, selection: $selectedPlanID)
        } content: {
            PlaceListView(
                plan: selectedPlan,
                selectedPlaceID: $selectedPlaceID,
                undoController: undoController,
                focusedDay: $focusedDay,
                preview: $preview,
                focusRequest: $focusRequest
            )
        } detail: {
            MapCanvasView(
                plan: selectedPlan,
                selectedPlaceID: $selectedPlaceID,
                cameraPosition: $cameraPosition,
                focusedDay: $focusedDay,
                preview: $preview,
                onCommitPreview: commitPreview,
                addTargetDay: $addTargetDay,
                focusRequest: $focusRequest
            )
            .inspector(isPresented: Binding(
                get: { selectedPlace != nil },
                set: { if !$0 { selectedPlaceID = nil } }
            )) {
                if let plan = selectedPlan, let place = selectedPlace {
                    PlaceDetailView(place: place, onRemove: {
                        PlanStore(context: modelContext).remove(place, from: plan)
                        selectedPlaceID = nil
                    }, onDuplicate: { copy in
                        selectedPlaceID = copy.id
                    })
                    .inspectorColumnWidth(min: 280, ideal: 320)
                }
            }
        }
        .navigationTitle(selectedPlan?.name ?? "Pinplore")
        .onChange(of: selectedPlanID) { _, _ in
            selectedPlaceID = nil
            preview = nil
            focusedDay = nil
            addTargetDay = 1
            retargetCamera()
        }
        .onAppear(perform: retargetCamera)
        .overlay(alignment: .bottom) {
            if undoController.isShowing {
                UndoBanner(controller: undoController)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: undoController.isShowing)
        .onReceive(NotificationCenter.default.publisher(for: .pinTripDeletePlan)) { note in
            guard let planID = note.object as? PersistentIdentifier,
                  let plan = plans.first(where: { $0.id == planID })
            else { return }
            let deletion = PlanStore(context: modelContext).delete(plan)
            undoController.offerUndo(deletion)
        }
        // Selecting a place makes its day the default target for new additions.
        .onChange(of: selectedPlace?.day) { _, newDay in
            if let newDay { addTargetDay = newDay }
        }
    }

    private func commitPreview(name: String, category: PlaceCategory, day: Int) {
        guard let plan = selectedPlan else { return }
        let place = Place(name: name, coordinate: preview?.coordinate ?? CLLocationCoordinate2D(), category: category)
        place.day = plan.clampedDay(day)
        place.sortOrder = plan.places.filter { $0.day == place.day }.count
        modelContext.insert(place)
        PlanStore(context: modelContext).add(place, to: plan)
        selectedPlaceID = place.id
        preview = nil
    }

    private func retargetCamera() {
        guard let plan = selectedPlan else {
            cameraPosition = .automatic
            return
        }
        if let coordinate = plan.destinationCoordinate {
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: plan.searchRadius * 2,
                longitudinalMeters: plan.searchRadius * 2
            ))
        } else {
            cameraPosition = .automatic
        }
    }
}
