# TeslaViewer

Eine schlanke macOS-App zum Ansehen von Tesla Dashcam- und Sentry-Mode-Aufnahmen. TeslaViewer liest die `TeslaCam`-Ordnerstruktur von einem USB-Laufwerk oder einem lokalen Pfad und spielt alle 6 Kamera-Feeds eines Ereignisses synchron in einem 3×2-Grid ab.

## Funktionen

- **Durchgehende Zeitleiste** über das gesamte Ereignis (nicht nur pro Clip), mit Teilstrichen an den Clipgrenzen und einer ⚡-Markierung am tatsächlichen Sentry-Auslöse-Zeitpunkt — inklusive „Zum Ereignis springen"
- **Echte Kamera-Synchronisation**: alle 6 Feeds starten exakt zum selben Zeitpunkt, statt jeweils zu starten, sobald ihr eigener Puffer bereit ist
- **Ordner merken**: der zuletzt geöffnete TeslaCam-Ordner wird über einen Security-Scoped Bookmark app-übergreifend gespeichert und beim nächsten Start automatisch geladen
- **Kamera-Fokus**: eine einzelne Kamera per Klick vergrößern, mit sanftem Übergang
- **Im Finder zeigen**: den Ordner eines Ereignisses direkt im Finder öffnen
- Liest sowohl `SentryClips` als auch `SavedClips`; `EncryptedClips` wird erkannt und mit einem Hinweis übersprungen (seit Tesla-Software 2026.20 verschlüsselt, nicht abspielbar)

## Voraussetzungen

- macOS 27 oder neuer
- Xcode 27 oder neuer

## Installation

TeslaViewer wird ohne Apple Developer Program vertrieben, ist also **nicht notarisiert**. macOS blockiert deshalb beim ersten Start mit „Apple kann nicht bestätigen, dass diese App frei von Malware ist" — das ist normal für kostenlose, nicht im App Store vertriebene Apps und kein Zeichen eines Problems.

So startest du die App trotzdem:

1. Lade `TeslaViewer.zip` herunter und entpacke es
2. **Rechtsklick** (oder ctrl+Klick) auf `TeslaViewer.app` → **Öffnen**
3. Im Dialog erneut **Öffnen** bestätigen

Das ist nur beim allerersten Start nötig. Alternativ in System­einstellungen → Datenschutz & Sicherheit ganz unten „Trotzdem öffnen" wählen, oder im Terminal:

```
xattr -cr /Pfad/zu/TeslaViewer.app
```

## Verwendung

1. App starten
2. „Ordner öffnen…" (⌘O) wählen und den `TeslaCam`-Ordner eines USB-Laufwerks oder einen lokalen Pfad auswählen
3. Ein Ereignis aus der Seitenleiste auswählen — die App gruppiert nach Quelle (Sentry-Ereignisse / Gespeicherte Clips) und Tag

### Tastaturbefehle

| Befehl | Kürzel |
|---|---|
| Abspielen / Pause | Leertaste |
| 1 Sekunde zurück / vor | ← / → |
| Zum Ereignis springen | ⌘⏎ |
| Kamera-Fokus beenden | esc |
| Im Finder zeigen | ⌘R |
| Ordner öffnen | ⌘O |

## Architektur

Der Code ist in fokussierte Dateien unter `TeslaViewer/TeslaViewer/` aufgeteilt:

| Datei | Inhalt |
|---|---|
| `Models.swift` | `EventReason`, `SentryEvent`, `SentryClip`, `ClipSource` + Preview-Beispieldaten |
| `EventLoader.swift` | Filesystem-Scanner: parst TeslaCam-Ordnerstrukturen zu `SentryEvent`-Objekten |
| `EventComposition.swift` | Baut pro Kamera eine durchgehende `AVMutableComposition` über alle Clips eines Ereignisses |
| `VideoPlayerManager.swift` | `@MainActor @Observable`, verwaltet alle `AVPlayer` und die synchronisierte Wiedergabe |
| `FolderStore.swift` | Ordnerauswahl und Security-Scoped-Bookmark-Persistenz |
| `VideoGridView.swift` | Kamera-Grid, Zeitleiste, Steuerleiste |
| `ContentView.swift` | Haupt-View mit Seitenleiste und Toolbar |
| `TeslaViewerApp.swift` | App-Entry-Point, Menübefehle |

Details zu Konventionen und Datenformaten stehen in `CLAUDE.md`.

## Build & Tests

Öffne `TeslaViewer.xcodeproj` in Xcode und baue/teste über das übliche Xcode-Schema (⌘B / ⌘U). Unit-Tests nutzen Swift Testing (`TeslaViewerTests`), UI-Tests XCUITest (`TeslaViewerUITests`).
