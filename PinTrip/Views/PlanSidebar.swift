import SwiftData
import SwiftUI

struct PlanSidebar: View {
    let plans: [Plan]
    @Binding var selection: PersistentIdentifier?

    @Environment(\.modelContext) private var context
    @State private var newPlanName = ""
    @State private var isAdding = false
    @State private var planToDelete: Plan?
    @State private var showingDeleteConfirm = false
    @State private var destinationPlan: Plan?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("旅游计划") {
                    ForEach(plans) { plan in
                        PlanRow(plan: plan)
                            .tag(plan.id as PersistentIdentifier?)
                            .contextMenu {
                                Button("设置目的地城市…") {
                                    destinationPlan = plan
                                }
                                Divider()
                                Button("删除计划…", role: .destructive) {
                                    planToDelete = plan
                                    showingDeleteConfirm = true
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            if isAdding {
                HStack {
                    TextField("计划名称", text: $newPlanName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commitNewPlan)
                    Button("添加") { commitNewPlan() }
                        .disabled(newPlanName.trimmed.isEmpty)
                    Button {
                        isAdding = false
                        newPlanName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(8)
            } else {
                Button {
                    isAdding = true
                } label: {
                    Label("新建计划", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
        }
        .frame(minWidth: 200)
        .confirmationDialog(
            "删除计划",
            isPresented: $showingDeleteConfirm,
            presenting: planToDelete
        ) { plan in
            Button("删除「\(plan.name)」", role: .destructive) {
                NotificationCenter.default.post(
                    name: .pinTripDeletePlan,
                    object: plan.id
                )
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
    }

    private func commitNewPlan() {
        let name = newPlanName.trimmed
        guard !name.isEmpty else { return }
        let plan = PlanStore(context: context).createPlan(name: name)
        selection = plan.id
        newPlanName = ""
        isAdding = false
    }
}

private struct PlanRow: View {
    let plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(plan.name)
                .font(.body)
            HStack(spacing: 4) {
                if let destination = plan.destinationName {
                    Text(destination)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("\(plan.places.count) 个地点")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Notification.Name {
    static let pinTripDeletePlan = Notification.Name("PinTripDeletePlan")
}
