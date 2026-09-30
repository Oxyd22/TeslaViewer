# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TeslaViewer is a macOS app for viewing Tesla Dashcam and Sentry Mode recordings. It reads the TeslaCam folder structure from a USB drive or local path and plays all 6 camera feeds synchronized in a 3×2 grid.

## Build & Test Commands

This is a pure **Swift Package** (no `.xcodeproj`). Use the SwiftPM CLI:

- **Build**: `swift build`
- **Run all tests**: `swift test`
- **Run a specific test**: `swift test --filter TeslaViewerTests.testLoadEvents`
- **Run the app (dev)**: `swift run TeslaViewer` — startet das Programm direkt (ohne App-Bundle)
- **Distributierbares .app bauen**: `./bundle.sh` → erzeugt `TeslaViewer.app` (Release, ad-hoc signiert)

## Architecture

The app is split into focused files under `Sources/TeslaViewer/`:

| Datei | Inhalt |
|-------|--------|
| `Models.swift` | `ClipSource`, `EventReason`, `SentryClip`, `SentryEvent` (inkl. GPS) + Preview-Beispieldaten |
| `EventLoader.swift` | `EventLoader` — Filesystem-Scanner und Parser (alle drei Quellen) |
| `VideoPlayerManager.swift` | `VideoPlayerManager` — `@MainActor @Observable`, verwaltet alle AVPlayer + durchgehende Timeline |
| `ClipExporter.swift` | `ClipExporter` — Finder, Einzelkamera-Kopie, 6-Kamera-Grid-Export (AVMutableVideoComposition) |
| `VideoGridView.swift` | `VideoGridView`, `MapPopover`, `ExportOverlay`, `CameraCell`, `PlayerView` (NSViewRepresentable) |
| `ContentView.swift` | `ContentView`, `SidebarView` (mit Quellen-Umschalter), `EventRowView`, `PlaceholderView` |
| `TeslaViewerApp.swift` | App-Entry-Point, `AppDelegate` (Aktivierungs-Policy), WindowGroup-Konfiguration |

### Data Flow

```
TeslaViewerApp → ContentView → SidebarView + VideoGridView
                                              ↑
                               VideoPlayerManager (@Observable)
```

### Key Types

- **`ClipSource`** (enum) — Die drei Quell-Ordner: `.sentry` (`SentryClips`), `.saved` (`SavedClips`), `.recent` (`RecentClips`). Liefert `folderName`, `displayName`, `systemIcon`.

- **`EventLoader`** (enum, static methods) — Scans the filesystem. `loadAll(from:)` lädt alle drei Quellen; `resolveBase(_:)` akzeptiert USB-Root (mit `TeslaCam`), den `TeslaCam`-Ordner selbst oder direkt einen Quell-Ordner. Parst Event-Ordner `YYYY-MM-DD_HH-mm-ss` mit `event.json` (inkl. GPS `est_lat`/`est_lon`). `RecentClips` ist ein flacher Ordner ohne `event.json` → alle Minuten-Segmente werden zu **einem** synthetischen Ereignis gebündelt. Gruppiert MP4s per Timestamp-Prefix zu `SentryClip`.

- **`SentryEvent`** — One trigger event (one folder). All properties are `let` (immutable). Contains metadata (`city`, `reason`, `thumbnailURL`) and an array of `SentryClip` objects sorted chronologically.

- **`SentryClip`** — One group of simultaneous MP4 files (one per camera). All properties are `let`. Camera names are the key in `cameraURLs: [String: URL]`.

- **`EventReason`** — Wraps the raw reason string from `event.json` and maps it to localized German display strings and SF Symbols.

- **`VideoPlayerManager`** (`@MainActor @Observable`) — Owns all `AVPlayer` instances for the current clip. Tracks time via a periodic observer on the "front" camera player (fallback: first available). Handles clip navigation, seek, and play/pause across all cameras simultaneously. **Durchgehende Timeline:** lädt die Dauer aller Segmente asynchron (`loadAllDurations`), bildet kumulierte Startzeiten (`clipStarts`/`totalDuration`) und stellt `globalTime` + `seekToGlobal(_:)` bereit, das bei Bedarf das Segment wechselt.

- **`ClipExporter`** (enum) — `revealInFinder`, `copyCamera` (verlustfreie Einzelkamera-Kopie) und `exportGrid` (rechnet die 6 Kameras eines Clips per `AVMutableComposition` + `AVMutableVideoComposition` in ein 3×2-Raster und exportiert eine MP4). **Wichtig:** Alle Spuren werden auf die gemeinsame Mindestlänge getrimmt (sonst `AVErrorInvalidVideoComposition -11841`), und die Quell-`AVURLAsset`s müssen bis zum `insertTimeRange` festgehalten werden (sonst wird die `AVAssetTrack` ungültig).

- **`VideoGridView`** — Detail view. Renders a fixed 3×2 camera layout using SwiftUI `Grid`. Supports keyboard shortcuts (Space, arrow keys).

- **`CameraCell`** — Single camera tile. Shows `PlayerView` if a player exists, otherwise shows a "no signal" placeholder.

- **`PlayerView`** (`NSViewRepresentable`) — Wraps `AVPlayerView` with `controlsStyle = .none` and `videoGravity = .resizeAspect`.

### File Naming Convention (Tesla)

MP4 filenames follow: `YYYY-MM-DD_HH-mm-ss-<cameraname>.mp4`
The timestamp prefix is always exactly 19 characters; the camera name starts at character 20 (after a `-` separator).

Camera name keys used throughout the app: `front`, `back`, `left_repeater`, `right_repeater`, `left_pillar`, `right_pillar`.

## Tests

Unit tests use Swift's `Testing` framework (`@Test` macros, `#expect`).
Tests are in `Tests/TeslaViewerTests/TeslaViewerTests.swift` and cover `EventLoader`, `EventReason`, date parsing, and `VideoPlayerManager` initialization. The test target does `@testable import TeslaViewer` against the executable target.
UI tests (`XCUITest`) were removed in the SwiftPM-Umbau — XCUITest requires an Xcode project.

## Notes

- The app is **macOS-only**. Uses `NSOpenPanel`, `NSSavePanel`, `NSViewRepresentable`, `AVPlayerView`, MapKit (`Map`/`MKMapItem`), `NSWorkspace`, and `Color(NSColor.windowBackgroundColor)`.
- UI strings **and source code comments** are in **German** (this is intentional — the app targets German-speaking users). New UI text and comments should also be in German.
- Uses `@Observable` (not `ObservableObject`/Combine). Prefer async/await for new async work.
- `Item.swift` (SwiftData scaffold) is unused and can be ignored.
- Minimum window size is 1000×680 pt (enforced in `TeslaViewerApp`).
- Preview-Beispieldaten sind in `Models.swift` als `SentryEvent.preview` / `.previewList` verfügbar.
- `TeslaViewerApp` setzt via `AppDelegate` die Aktivierungs-Policy auf `.regular` — nötig, weil ein SwiftPM-Executable sonst ohne Vordergrund-Fenster startet (kein App-Bundle/Info.plist).
- **Asset-Hinweis**: Bei `swift run` werden `AppIcon`/`AccentColor` aus `Assets.xcassets` **nicht** automatisch angewendet (SwiftUI lädt sie nur aus dem Main-Bundle eines echten `.app`). Der AppIcon-Satz enthält ohnehin noch keine Bilddateien.
