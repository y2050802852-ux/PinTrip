import Foundation
import SwiftData

/// Codable snapshots for the backup file format.
///
/// The JSON carries a `schemaVersion` so future format changes can be
/// detected instead of silently mis-parsed.

struct PlanBackup: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String
    var plans: [PlanDTO]
    /// Places not linked to any exported plan would be lost data; the codec
    /// exports exactly the union of places referenced by the plans.
    var places: [PlaceDTO]
}

struct PlanDTO: Codable {
    var backupID: UUID
    var name: String
    var createdAt: Date
    var destinationName: String?
    var destinationLatitude: Double?
    var destinationLongitude: Double?
    var searchRadius: Double
    var startDate: Date?
    var endDate: Date?
    /// backupIDs of places belonging to this plan, in display order.
    var placeIDs: [UUID]
}

struct PlaceDTO: Codable {
    var backupID: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var notes: String
    var categoryRaw: String
    var sortOrder: Int
    var day: Int
    var rating: Int
    var visited: Bool
    var linkURL: String
    var photoPath: String
    var createdAt: Date
}

enum BackupCodec {
    static let schemaVersion = 1

    // MARK: - Export

    /// Serializes every plan (and the union of their places) to JSON.
    static func export(plans: [Plan]) throws -> Data {
        // Deduplicate shared places across plans.
        var placeByID: [UUID: Place] = [:]
        var planDTOs: [PlanDTO] = []

        for plan in plans {
            for place in plan.orderedPlaces {
                placeByID[place.backupID] = place
            }
            planDTOs.append(PlanDTO(
                backupID: plan.backupID,
                name: plan.name,
                createdAt: plan.createdAt,
                destinationName: plan.destinationName,
                destinationLatitude: plan.destinationLatitude,
                destinationLongitude: plan.destinationLongitude,
                searchRadius: plan.searchRadius,
                startDate: plan.startDate,
                endDate: plan.endDate,
                placeIDs: plan.orderedPlaces.map(\.backupID)
            ))
        }

        let placeDTOs = placeByID.values.map { place in
            PlaceDTO(
                backupID: place.backupID,
                name: place.name,
                latitude: place.latitude,
                longitude: place.longitude,
                notes: place.notes,
                categoryRaw: place.categoryRaw,
                sortOrder: place.sortOrder,
                day: place.day,
                rating: place.rating,
                visited: place.visited,
                linkURL: place.linkURL,
                photoPath: place.photoPath,
                createdAt: place.createdAt
            )
        }

        let backup = PlanBackup(
            schemaVersion: schemaVersion,
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            plans: planDTOs,
            places: placeDTOs
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    // MARK: - Import

    enum ImportError: LocalizedError {
        case unsupportedSchema(Int)
        case corrupt(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let v):
                return "备份文件格式版本不支持（schema \(v)，当前支持 \(schemaVersion)）"
            case .corrupt(let detail):
                return "备份文件损坏：\(detail)"
            }
        }
    }

    static func decode(_ data: Data) throws -> PlanBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(PlanBackup.self, from: data)
        guard backup.schemaVersion <= schemaVersion else {
            throw ImportError.unsupportedSchema(backup.schemaVersion)
        }
        return backup
    }

    /// Import mode chosen by the user in the confirmation dialog.
    enum Mode {
        /// Keep everything already in the store; re-link places whose
        /// backupID already exists locally, otherwise create them. Plans
        /// always arrive as new copies (never renamed/overwritten).
        case merge
        /// Wipe all local plans and places, then restore exactly the file.
        case replace
    }

    struct Result {
        var plansImported = 0
        var placesCreated = 0
        var placesReused = 0
    }

    /// Restores a decoded backup into the store. Must run on the main actor
    /// (SwiftData context is main-actor bound).
    @MainActor
    static func `import`(_ backup: PlanBackup, mode: Mode, context: ModelContext) throws -> Result {
        var result = Result()

        if mode == .replace {
            // Delete all plans; orphan places go with them via the store's rules.
            let plans = try context.fetch(FetchDescriptor<Plan>())
            for plan in plans {
                context.delete(plan)
            }
            let places = try context.fetch(FetchDescriptor<Place>())
            for place in places where place.plans.isEmpty {
                context.delete(place)
            }
            try context.save()
        }

        // 1. Places: reuse by backupID, else create.
        var placeByBackupID: [UUID: Place] = [:]
        if mode == .merge {
            let existing = try context.fetch(FetchDescriptor<Place>())
            for place in existing {
                placeByBackupID[place.backupID] = place
            }
        }

        var createdPlaces: [UUID: Place] = [:]
        for dto in backup.places {
            if let existing = placeByBackupID[dto.backupID] {
                createdPlaces[dto.backupID] = existing
                result.placesReused += 1
                continue
            }
            let place = Place(
                name: dto.name,
                coordinate: .init(latitude: dto.latitude, longitude: dto.longitude)
            )
            place.backupID = dto.backupID
            place.notes = dto.notes
            place.categoryRaw = dto.categoryRaw
            place.sortOrder = dto.sortOrder
            place.day = dto.day
            place.rating = dto.rating
            place.visited = dto.visited
            place.linkURL = dto.linkURL
            place.photoPath = dto.photoPath
            place.createdAt = dto.createdAt
            context.insert(place)
            createdPlaces[dto.backupID] = place
            result.placesCreated += 1
        }

        // 2. Plans: merge always creates copies; replace creates fresh ones.
        for dto in backup.plans {
            let plan = Plan(name: dto.name)
            plan.backupID = mode == .replace ? dto.backupID : UUID()
            plan.createdAt = dto.createdAt
            plan.destinationName = dto.destinationName
            plan.destinationLatitude = dto.destinationLatitude
            plan.destinationLongitude = dto.destinationLongitude
            plan.searchRadius = dto.searchRadius
            plan.startDate = dto.startDate
            plan.endDate = dto.endDate
            context.insert(plan)

            var seen = Set<UUID>()
            for placeID in dto.placeIDs where !seen.contains(placeID) {
                seen.insert(placeID)
                if let place = createdPlaces[placeID] {
                    place.plans.append(plan)
                    plan.places.append(place)
                }
            }
            result.plansImported += 1
        }

        try context.save()
        return result
    }
}
