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
            Self.healDuplicateBackupIDs(container: modelContainer)
        } catch {
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }

    /// One-time repair for rows created while `backupID` used a schema-level
    /// default: SwiftData evaluated `UUID()` once, so every row stored the
    /// same value and backups collapsed to a single place. Re-assign a unique
    /// ID to any row whose backupID is shared by more than one record.
    @MainActor
    private static func healDuplicateBackupIDs(container: ModelContainer) {
        let context = ModelContext(container)
        do {
            let places = try context.fetch(FetchDescriptor<Place>())
            var seen = Set<UUID>()
            for place in places where !seen.insert(place.backupID).inserted {
                place.backupID = UUID()
            }
            let plans = try context.fetch(FetchDescriptor<Plan>())
            var seenPlans = Set<UUID>()
            for plan in plans where !seenPlans.insert(plan.backupID).inserted {
                plan.backupID = UUID()
            }
            try context.save()
        } catch {
            // Non-fatal: worst case a later export collapses duplicates again.
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
