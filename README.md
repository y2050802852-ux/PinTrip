<div align="center">

<img src="assets/app-icon.png" width="120" height="120" alt="Pinplore icon"/>

# 📍 Pinplore

**Native macOS travel pinning & day-by-day trip planning**

Search a place → pin it → plan it day by day → see the whole trip on one map

[![Download](https://img.shields.io/badge/⬇_Download-v1.0.0_DMG-blue?style=for-the-badge&logo=apple)](https://github.com/y2050802852-ux/Pinplore/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS_15+-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI_+_SwiftData-orange?logo=swift)
![License](https://img.shields.io/badge/license-MIT-green)
![Deps](https://img.shields.io/badge/dependencies-zero-brightgreen)

*Pure native · No API keys · No third-party dependencies · Data stays local*

**[English](README.md)** | [简体中文](README.zh-CN.md)

</div>

---

## 📸 Screenshots

<div align="center">
<img src="assets/screenshot-main.png" width="900" alt="Pinplore main window"/>
<p><sub>Nanjing trip: day-sectioned itinerary with categories, ratings and visited checkmarks — all pins live on the map. Dark mode.</sub></p>
</div>

---

## ✨ Features

### 🗺️ Map & Pinning
- **As-you-type search** — `MKLocalSearchCompleter` suggestions appear while typing; the map first *previews* the place and only pins it after you confirm
- **Precise drop** — **right-click** or **press-and-hold (0.5 s)** anywhere on the map to drop a preview pin; name it, pick a category, choose the day
- **Locate me** — one tap requests GPS, marks your position and flies the camera there (a live authorization status label makes permission issues obvious)
- **Category colors** — sights 🔵 food 🟠 lodging 🟢 transport ⚪ other 🟣
- **Double-click focus** — double-click a row in the list and the map flies to that place

### 📅 Day-by-Day Itinerary
- Pick a **start/end date** when creating a plan; Day 1…N sections are derived automatically
- **Drag between days** — hold a place and drop it on any day; intra-day drags reorder, cross-day drags reschedule. A blue insert line shows exactly where it lands
- Empty days are listed up front ("drag places here"), so you can plan the whole window immediately
- "Focus this day" mode: list and map show only that day
- Shrinking the date range moves out-of-range places to the new last day — **nothing is ever lost**

### 🧩 Place Details
- Notes, category, day, star rating, visited ✓, external link
- **Duplicate** a place (hotels/restaurants you visit twice) — an independent copy right after the original
- **Rename** in the inspector or via the row's context menu

### ☁️ Backup & Restore (JSON)
- **⌘E export** — every plan plus the de-duplicated set of places into one JSON, defaulting to `~/Documents/Trip Plan/`
- **⌘I import** with two modes:
  - **Merge** — keeps everything you have; plans arrive as copies, places with matching IDs are re-used, never duplicated
  - **Replace** — wipe local data and restore exactly from the file (device switch / rollback)
- Drop the file into iCloud Drive / any cloud sync folder and it's "in the cloud"
- The format carries a `schemaVersion` for forward compatibility

### 🛡️ Data Safety
- Delete-plan confirmation plus a **5-second undo** (snapshot-based restore; shared places are never lost)
- Many-to-many model: one place can belong to several plans; deleting a plan only removes places *exclusively* owned by it

---

## 🚀 Getting Started

### Install (end users)

1. Grab `Pinplore.dmg` from [**Releases**](https://github.com/y2050802852-ux/Pinplore/releases/latest)
2. Open it and drag **Pinplore.app** into `Applications`
3. First launch showing "unidentified developer"? **Right-click the app → Open** (ad-hoc signing is not notarized — expected)

> Requires macOS 15 (Sequoia) or later, Apple Silicon

### Build from source

```bash
git clone https://github.com/y2050802852-ux/Pinplore.git
cd Pinplore
open Pinplore.xcodeproj    # Xcode 26+, just ⌘R
```

---

## 🏗️ How It's Built

| Layer | Choice | Notes |
|---|---|---|
| UI | SwiftUI `NavigationSplitView` three-column | plans \| day-sectioned places \| map |
| Map | MapKit for SwiftUI (`Map` / `Marker` / `MapSelection`) | same engine as search — coordinates always agree |
| Search | `MKLocalSearch` + `MKLocalSearchCompleter` | no key, native autocomplete |
| Storage | SwiftData many-to-many (`@Relationship(inverse:)`) | hand-managed delete rules + snapshot undo |
| Days | **Computed** from `startDate/endDate`, no Day entity | date changes auto-adjust, no migrations |
| Precise drops | AppKit `NSViewRepresentable` (flipped) overlay | SwiftUI Map exposes no right-click coordinate |
| Location | `CLLocationManager`, event-driven auth + continuous updates | avoids single-shot transient failures |
| Backup | Value snapshots + stable `backupID: UUID` | many-to-many survives a round trip |

### Three gotchas worth documenting (for future travelers)

**1. SwiftData property defaults are evaluated ONCE per model**

```swift
// ❌ WRONG: every instance shares one UUID (evaluated once per model!)
var backupID: UUID = UUID()

// ✅ RIGHT: assign per instance in init()
init() { self.backupID = UUID() }
```

This once collapsed a backup of 8 places into 1 (the exporter de-duplicates by ID).

**2. On macOS 26, setting `MKLocalSearch.Request.region` always fails**

```
Error Domain=MKErrorDomain Code=4 (MKErrorPlacemarkNotFound)
```

Regardless of the region value (even `.world`) or whether the request is built from a completion. Mitigation: bias by query text instead. See `PlaceSearchService.biasCity`.

**3. AppKit vs SwiftUI coordinate flip**

AppKit `NSView` measures from the bottom-left; SwiftUI `.local` measures from the top-left. Map right-click drops used to land vertically mirrored. Fix: the overlay view declares `isFlipped = true`.

---

## 📁 Project Layout

```
Pinplore/
├── Models/
│   ├── Plan.swift               # plan: date range, destination, many-to-many
│   ├── Place.swift              # place: coordinate, category, day, rating…
│   ├── PlacePreview.swift       # candidate place pending confirmation
│   ├── PlaceDragPayload.swift   # drag payload (PersistentIdentifier directly)
│   ├── PlaceSelection.swift     # MapSelectable wrapper, empty-map tap deselects
│   ├── MapCoordinate.swift      # Equatable wrapper for CLLocationCoordinate2D
│   └── DeletionSnapshot.swift   # deletion snapshots (undo rebuild)
├── Services/
│   ├── PlaceSearchService.swift # autocomplete + resolve (region-bug workaround)
│   ├── PlanStore.swift          # CRUD / cascade / duplicate / undo-restore
│   ├── BackupCodec.swift        # JSON encode/decode, merge & replace import
│   ├── BackupFlow.swift         # macOS save/open panels
│   ├── UserLocationService.swift# event-driven auth + continuous location
│   └── UndoController.swift     # 5-second undo window
├── Views/                       # three-column shell, map canvas, preview card, inspector…
└── PinploreApp.swift             # entry + launch-time backupID self-heal
```

---

## 🧪 Quality

- 30+ logic tests: cascade deletes / shared-place retention / undo rebuild, day-index math, drag insertion indices, backup round trip / merge de-dup, UUID uniqueness self-heal
- Every reported bug was reproduced and fixed test-first (e.g. "backup collapsed 8 places into 1", "cross-day drags dead")
- All core logic runs against in-memory SwiftData, no UI needed

## 🗺️ Roadmap

- [ ] Universal iOS app (WIP on branch [`ios-port`](https://github.com/y2050802852-ux/Pinplore/tree/ios-port): Tab layout, share-sheet export, file-importer)
- [ ] Per-day route lines (straight polyline)
- [ ] Real navigation routes (MKDirections / OSRM)
- [ ] Photo attachments (`photoPath` already reserved in the schema)
- [ ] iCloud CloudKit sync (needs a paid developer account; export/import works as the manual path today)

## 📄 License

MIT

<div align="center">

**SwiftData + MapKit + SwiftUI · ~1,600 lines of Swift · zero third-party dependencies**

</div>
