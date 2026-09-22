import MapKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]
    @State private var selectedPlanID: PersistentIdentifier?
    @State private var selectedPlaceID: PersistentIdentifier?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var undoController = UndoController()
    @Environment(\.modelContext) private var modelContext

    private var selectedPlan: Plan? {
        plans.first { $0.id == selectedPlanID }
    }

    private var selectedPlace: Place? {
        guard let plan = selectedPlan,
              let placeID = selectedPlaceID
        else { return nil }
        return plan.places.first { $0.id == placeID }
    }

    var body: some View {
        NavigationSplitView {
            PlanSidebar(plans: plans, selection: $selectedPlanID)
        } content: {
            PlaceListView(
                plan: selectedPlan,
                selectedPlaceID: $selectedPlaceID,
                undoController: undoController
            )
        } detail: {
            MapCanvasView(
                plan: selectedPlan,
                selectedPlaceID: $selectedPlaceID,
                cameraPosition: $cameraPosition
            )
            .inspector(isPresented: Binding(
                get: { selectedPlace != nil },
                set: { if !$0 { selectedPlaceID = nil } }
            )) {
                if let plan = selectedPlan, let place = selectedPlace {
                    PlaceDetailView(place: place) {
                        PlanStore(context: modelContext).remove(place, from: plan)
                        selectedPlaceID = nil
                    }
                    .inspectorColumnWidth(min: 280, ideal: 320)
                }
            }
        }
        .navigationTitle(selectedPlan?.name ?? "PinTrip")
        .onChange(of: selectedPlanID) { _, _ in
            selectedPlaceID = nil
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
