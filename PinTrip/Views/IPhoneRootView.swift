import SwiftData
import SwiftUI

/// iPhone layout: Tab view with 行程 (list) and 地图 tabs, plus a toolbar
/// menu for backup. The Mac keeps its three-column layout.
struct IPhoneRootView: View {
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]
    @State private var selectedPlanID: PersistentIdentifier?
    @State private var selectedPlaceID: PersistentIdentifier?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var preview: PlacePreview?
    @State private var addTargetDay = 1
    @State private var focusedDay: Int?
    @State private var focusRequest: MapCoordinate?
    @State private var showImporter = false
    @State private var importData: Data?
    @State private var shareURL: URL?
    @StateObject private var alertBox = AlertBox.shared
    @Environment(\.modelContext) private var modelContext

    private var selectedPlan: Plan? {
        plans.first { $0.id == selectedPlanID }
    }

    private var selectedPlace: Place? {
        guard let plan = selectedPlan, let placeID = selectedPlaceID else { return nil }
        return plan.places.first { $0.id == placeID }
    }

    var body: some View {
        TabView {
            NavigationStack {
                PlanListiPhone(plans: plans, selection: $selectedPlanID)
            }
            .tabItem { Label("行程", systemImage: "list.bullet") }

            NavigationStack {
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
                .overlay(alignment: .bottom) {
                    if let preview {
                        PreviewCard(
                            preview: preview,
                            dayOptions: selectedPlan?.dayNumbers ?? [],
                            dateForDay: { selectedPlan?.date(forDayIndex: $0 - 1) },
                            selectedDay: selectedPlan?.clampedDay(addTargetDay) ?? 1,
                            onSelectDay: { addTargetDay = $0 },
                            onAdd: { name, category in
                                commitPreview(name: name, category: category, day: addTargetDay)
                            },
                            onCancel: { self.preview = nil }
                        )
                        .padding(12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .navigationTitle(selectedPlan?.name ?? "PinTrip")
            }
            .tabItem { Label("地图", systemImage: "map") }
        }
        .sheet(isPresented: Binding(
            get: { selectedPlace != nil },
            set: { if !$0 { selectedPlaceID = nil } }
        )) {
            if let plan = selectedPlan, let place = selectedPlace {
                NavigationStack {
                    PlaceDetailView(place: place, onRemove: {
                        PlanStore(context: modelContext).remove(place, from: plan)
                        selectedPlaceID = nil
                    }, onDuplicate: { copy in
                        selectedPlaceID = copy.id
                    })
                    .navigationTitle("地点详情")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json]
        ) { result in
            if case .success(let url) = result {
                importData = try? Data(contentsOf: url)
                if let importData {
                    Task { await runImport(data: importData) }
                }
            }
        }
        .alert(item: $alertBox.current) { content in
            Alert(title: Text(content.title), message: Text(content.message))
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinTripOpenImporter)) { _ in
            showImporter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinTripShareExport)) { note in
            if let url = note.object as? URL { shareURL = url }
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

    private func runImport(data: Data) async {
        do {
            if let result = try await BackupFlow.importPlans(context: modelContext, data: data) {
                AlertBox.shared.show(
                    title: "导入完成",
                    message: "计划 \(result.plansImported) 个 · 新建地点 \(result.placesCreated) 个 · 复用地点 \(result.placesReused) 个"
                )
            }
        } catch {
            AlertBox.shared.show(title: "导入失败", message: error.localizedDescription)
        }
    }
}

/// Plan picker for the 行程 tab: selecting a plan shows its day-sectioned places.
struct PlanListiPhone: View {
    let plans: [Plan]
    @Binding var selection: PersistentIdentifier?

    @Environment(\.modelContext) private var context
    @State private var newPlanName = ""
    @State private var isAdding = false
    @State private var planToDelete: Plan?
    @State private var showingDeleteConfirm = false
    @State private var destinationPlan: Plan?
    @State private var datePlan: Plan?
    @State private var showingNewPlanDates = false
    @State private var pendingPlanName = ""

    var body: some View {
        List(selection: $selection) {
            Section("旅游计划") {
                ForEach(plans) { plan in
                    PlanRow(plan: plan)
                        .tag(plan.id as PersistentIdentifier?)
                        .contextMenu {
                            Button("设置目的地城市…") { destinationPlan = plan }
                            Button("修改行程日期…") { datePlan = plan }
                            Divider()
                            Button("删除计划…", role: .destructive) {
                                planToDelete = plan
                                showingDeleteConfirm = true
                            }
                        }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        isAdding = true
                    } label: {
                        Label("新建计划", systemImage: "plus")
                    }
                    Button {
                        Task { await exportAll() }
                    } label: {
                        Label("导出所有计划…", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        // fileImporter toggle lives in parent; post instead
                        NotificationCenter.default.post(name: .pinTripOpenImporter, object: nil)
                    } label: {
                        Label("导入计划…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("新建计划", isPresented: $isAdding) {
            TextField("计划名称", text: $newPlanName)
            Button("下一步") { commitNewPlan() }
            Button("取消", role: .cancel) { newPlanName = "" }
        }
        .confirmationDialog("删除计划", isPresented: $showingDeleteConfirm, presenting: planToDelete) { plan in
            Button("删除「\(plan.name)」", role: .destructive) {
                NotificationCenter.default.post(name: .pinTripDeletePlan, object: plan.id)
                if selection == plan.id { selection = nil }
            }
            Button("取消", role: .cancel) {}
        } message: { plan in
            Text("将同时删除仅属于该计划的 \(plan.places.count) 个地点。与其他计划共享的地点会被保留。")
        }
        .sheet(item: $destinationPlan) { plan in
            PlanDestinationSheet(plan: plan) { name, coordinate in
                plan.setDestination(name: name, coordinate: coordinate)
                try? context.save()
            }
        }
        .sheet(item: $datePlan) { plan in
            DateRangeSheet(mode: .edit, initialStart: plan.startDate, initialEnd: plan.endDate) { start, end in
                _ = PlanStore(context: context).setDateRange(plan, start: start, end: end)
            }
        }
        .sheet(isPresented: $showingNewPlanDates) {
            DateRangeSheet(mode: .create, initialStart: nil, initialEnd: nil) { start, end in
                let plan = PlanStore(context: context).createPlan(name: pendingPlanName)
                if let start, let end {
                    _ = PlanStore(context: context).setDateRange(plan, start: start, end: end)
                }
                selection = plan.id
                pendingPlanName = ""
            }
        }
    }

    private func commitNewPlan() {
        let name = newPlanName.trimmed
        guard !name.isEmpty else { return }
        pendingPlanName = name
        newPlanName = ""
        isAdding = false
        showingNewPlanDates = true
    }

    private func exportAll() {
        do {
            if let url = try BackupFlow.exportAll(plans: plans) {
                NotificationCenter.default.post(name: .pinTripShareExport, object: url)
            }
        } catch {
            AlertBox.shared.show(title: "导出失败", message: error.localizedDescription)
        }
    }
}

/// UIKit share sheet wrapper for exporting the backup JSON.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension Notification.Name {
    static let pinTripOpenImporter = Notification.Name("PinTripOpenImporter")
    static let pinTripShareExport = Notification.Name("PinTripShareExport")
}
