import SwiftData
import SwiftUI

@main
struct PinTripApp: App {
    @State private var modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([Plan.self, Place.self])
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("导出所有计划…") {
                    exportTask = Task { await runExport() }
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("导入计划…") {
                    importTask = Task { await runImport() }
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
    }

    @State private var exportTask: Task<Void, Never>?
    @State private var importTask: Task<Void, Never>?

    @MainActor
    private func runExport() async {
        let context = modelContainer.mainContext
        let plans = (try? context.fetch(FetchDescriptor<Plan>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        guard !plans.isEmpty else { return }
        if let url = try? await BackupFlow.exportAll(plans: plans) {
            let alert = NSAlert()
            alert.messageText = "导出成功"
            alert.informativeText = "已保存到 \(url.lastPathComponent)"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    @MainActor
    private func runImport() async {
        let context = modelContainer.mainContext
        if let result = try? await BackupFlow.importPlans(context: context) {
            let alert = NSAlert()
            alert.messageText = "导入完成"
            alert.informativeText = "计划 \(result.plansImported) 个 · 新建地点 \(result.placesCreated) 个 · 复用地点 \(result.placesReused) 个"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
}
