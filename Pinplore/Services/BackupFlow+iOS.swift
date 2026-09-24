import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// iOS export/import: files go through the system share sheet (Files app,
/// iCloud Drive, AirDrop) and imports come via fileImporter.
enum BackupFlow {
    /// Encodes all plans and presents the share sheet with the JSON file.
    @MainActor
    static func exportAll(plans: [Plan]) throws -> URL? {
        guard !plans.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pinplore备份-\(formatter.string(from: Date())).json")

        let data = try BackupCodec.export(plans: plans)
        try data.write(to: url, options: [.atomic])
        return url
    }

    /// Presents the mode-choice alert, then runs the import with a picked file.
    @MainActor
    static func importPlans(context: ModelContext, data: Data) async throws -> BackupCodec.Result? {
        let backup = try BackupCodec.decode(data)
        return try await withCheckedThrowingContinuation { c in
            let alert = UIAlertController(
                title: "导入备份",
                message: "备份包含 \(backup.plans.count) 个计划、\(backup.places.count) 个地点（导出于 \(backup.exportedAt.formatted(date: .abbreviated, time: .shortened))）",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "追加合并", style: .default) { _ in
                do {
                    let result = try BackupCodec.import(backup, mode: .merge, context: context)
                    c.resume(returning: result)
                } catch { c.resume(throwing: error) }
            })
            alert.addAction(UIAlertAction(title: "全量替换", style: .destructive) { _ in
                do {
                    let result = try BackupCodec.import(backup, mode: .replace, context: context)
                    c.resume(returning: result)
                } catch { c.resume(throwing: error) }
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
                c.resume(returning: nil)
            })
            // The key window's root must present it; SwiftUI scenes expose it via connected scenes.
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            let root = scene?.keyWindow?.rootViewController
            root?.present(alert, animated: true)
        }
    }
}
