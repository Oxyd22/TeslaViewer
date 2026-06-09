# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TeslaViewer is a macOS app for viewing Tesla Dashcam and Sentry Mode recordings. It reads the TeslaCam folder structure from a USB drive or local path and plays all 6 camera feeds synchronized in a 3×2 grid.

## Build & Test Commands

Use the Xcode MCP tools for all build/test operations:

- **Build**: Use `BuildProject` MCP tool
- **Run all tests**: Use `RunAllTests` MCP tool
- **Run specific test**: Use `RunSomeTests` MCP tool with `targetName: "TeslaViewerTests"` and the test identifier
- **Quick diagnostics**: Use `XcodeRefreshCodeIssuesInFile` for fast compiler feedback without a full build

## Architecture

The app is split into focused files under `TeslaViewer/TeslaViewer/`:

| Datei | Inhalt |
|-------|--------|
| `Models.swift` | `EventReason`, `SentryClip`, `SentryEvent` + Preview-Beispieldaten |
| `EventLoader.swift` | `EventLoader` — Filesystem-Scanner und Parser |
| `VideoPlayerManager.swift` | `VideoPlayerManager` — `@MainActor @Observable`, verwaltet alle AVPlayer |
| `VideoGridView.swift` | `VideoGridView`, `CameraCell`, `PlayerView` (NSViewRepresentable) |
| `ContentView.swift` | `ContentView`, `SidebarView`, `EventRowView`, `PlaceholderView` |
| `TeslaViewerApp.swift` | App-Entry-Point, WindowGroup-Konfiguration |

### Data Flow

```
TeslaViewerApp → ContentView → SidebarView + VideoGridView
                                              ↑
                               VideoPlayerManager (@Observable)
```

### Key Types

- **`EventLoader`** (enum, static methods) — Scans the filesystem. Accepts a TeslaCam root folder, a SentryClips folder, or any subfolder. Parses event folders named `YYYY-MM-DD_HH-mm-ss`, reads `event.json` for metadata, and groups MP4 files by timestamp prefix into `SentryClip` objects.

- **`SentryEvent`** — One trigger event (one folder). All properties are `let` (immutable). Contains metadata (`city`, `reason`, `thumbnailURL`) and an array of `SentryClip` objects sorted chronologically.

- **`SentryClip`** — One group of simultaneous MP4 files (one per camera). All properties are `let`. Camera names are the key in `cameraURLs: [String: URL]`.

- **`EventReason`** — Wraps the raw reason string from `event.json` and maps it to localized German display strings and SF Symbols.

- **`VideoPlayerManager`** (`@MainActor @Observable`) — Owns all `AVPlayer` instances for the current clip. Tracks time via a periodic observer on the "front" camera player (fallback: first available). Handles clip navigation, seek, and play/pause across all cameras simultaneously.

- **`VideoGridView`** — Detail view. Renders a fixed 3×2 camera layout using SwiftUI `Grid`. Supports keyboard shortcuts (Space, arrow keys).

- **`CameraCell`** — Single camera tile. Shows `PlayerView` if a player exists, otherwise shows a "no signal" placeholder.

- **`PlayerView`** (`NSViewRepresentable`) — Wraps `AVPlayerView` with `controlsStyle = .none` and `videoGravity = .resizeAspect`.

### File Naming Convention (Tesla)

MP4 filenames follow: `YYYY-MM-DD_HH-mm-ss-<cameraname>.mp4`
The timestamp prefix is always exactly 19 characters; the camera name starts at character 20 (after a `-` separator).

Camera name keys used throughout the app: `front`, `back`, `left_repeater`, `right_repeater`, `left_pillar`, `right_pillar`.

## Tests

Unit tests use Swift's `Testing` framework (`@Test` macros, `#expect`).
UI tests use `XCUITest` framework.
Tests are in `TeslaViewerTests/TeslaViewerTests.swift` and cover `EventLoader`, `EventReason`, date parsing, and `VideoPlayerManager` initialization.

## Notes

- The app is **macOS-only**. Uses `NSOpenPanel`, `NSViewRepresentable`, `AVPlayerView`, and `Color(NSColor.windowBackgroundColor)`.
- UI strings **and source code comments** are in **German** (this is intentional — the app targets German-speaking users). New UI text and comments should also be in German.
- Uses `@Observable` (not `ObservableObject`/Combine). Prefer async/await for new async work.
- `Item.swift` (SwiftData scaffold) is unused and can be ignored.
- Minimum window size is 1000×680 pt (enforced in `TeslaViewerApp`).
- Preview-Beispieldaten sind in `Models.swift` als `SentryEvent.preview` / `.previewList` verfügbar.
