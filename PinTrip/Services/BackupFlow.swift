import SwiftData
import SwiftUI

/// File → Export All Plans / Import Plans menu actions.
enum BackupFlow {
    /// Opens a save panel defaulting to iCloud Drive and writes the backup.
    @MainActor
    static func exportAll(plans: [Plan]) async throws -> URL? {
        guard !plans.isEmpty else { return nil }

        let panel = NSSavePanel()
        panel.title = "导出所有旅游计划"
        panel.message = "备份文件包含全部计划与地点，可存入 iCloud Drive 或任意位置"
        panel.nameFieldStringValue = suggestedFileName()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        // iCloud Drive as the default location when available.
        let iCloudDocs = iCloudDriveURL()
        if let iCloudDocs {
            panel.directoryURL = iCloudDocs
        }

        let response = await panel.beginSheetModal(for: NSApp.mainWindow ?? NSApp.windows[0])
        guard response == .OK, let url = panel.url else { return nil }

        let data = try BackupCodec.export(plans: plans)
        try data.write(to: url, options: [.atomic])
        return url
    }

    /// Opens an open panel, decodes the file, asks merge vs replace, imports.
    @MainActor
    static func importPlans(context: ModelContext) async throws -> BackupCodec.Result? {
        let panel = NSOpenPanel()
        panel.title = "导入旅游计划"
        panel.message = "选择之前导出的 PinTrip 备份 JSON 文件"
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let iCloudDocs = iCloudDriveURL() {
            panel.directoryURL = iCloudDocs
        }

        let response = await panel.beginSheetModal(for: NSApp.mainWindow ?? NSApp.windows[0])
        guard response == .OK, let url = panel.url else { return nil }

        let data = try Data(contentsOf: url)
        let backup = try BackupCodec.decode(data)

        let mode = await askMode(backup: backup)
        guard let mode else { return nil }
        return try BackupCodec.import(backup, mode: mode, context: context)
    }

    private static func iCloudDriveURL() -> URL? {
        let url = try? FileManager.default.url(
            for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        .appendingPathComponent("Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func suggestedFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "PinTrip备份-\(formatter.string(from: Date())).json"
    }

    /// Merge/replace confirmation with a summary of what the file contains.
    @MainActor
    private static func askMode(backup: PlanBackup) async -> BackupCodec.Mode? {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "导入备份"
            alert.informativeText = """
                备份包含 \(backup.plans.count) 个计划、\(backup.places.count) 个地点
                （导出于 \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened))）

                追加合并：保留现有数据，计划以副本加入，相同地点复用不重复。
                全量替换：清空本地全部数据后按文件恢复。
                """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "追加合并")
            alert.addButton(withTitle: "全量替换")
            alert.addButton(withTitle: "取消")

            let window = NSApp.mainWindow ?? NSApp.windows[0]
            alert.beginSheetModal(for: window) { response in
                switch response {
                case .alertFirstButtonReturn:
                    continuation.resume(returning: BackupCodec.Mode.merge)
                case .alertSecondButtonReturn:
                    continuation.resume(returning: BackupCodec.Mode.replace)
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
