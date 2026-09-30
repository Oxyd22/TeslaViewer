//
//  ContentView.swift
//  TeslaViewer
//
//  Haupt-View mit NavigationSplitView: Sidebar + Detail.
//

import SwiftUI

// MARK: - Haupt-View

struct ContentView: View {
    @State private var allEvents: [SentryEvent] = []
    @State private var source: ClipSource = .sentry
    @State private var selectedEvent: SentryEvent?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var securityScopedURL: URL?

    /// Ereignisse der aktuell gewählten Quelle.
    private var events: [SentryEvent] {
        allEvents.filter { $0.source == source }
    }

    /// Anzahl Ereignisse je Quelle (für den Umschalter).
    private var sourceCounts: [ClipSource: Int] {
        Dictionary(grouping: allEvents, by: \.source).mapValues(\.count)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                events: events,
                source: $source,
                sourceCounts: sourceCounts,
                selectedEvent: $selectedEvent,
                isLoading: isLoading,
                hasLoaded: hasLoaded,
                onSelectFolder: loadFolder
            )
            .frame(minWidth: 240)
        } detail: {
            if let event = selectedEvent {
                VideoGridView(event: event)
                    .id(event.id)
            } else {
                PlaceholderView(hasEvents: !events.isEmpty)
            }
        }
        .onChange(of: source) {
            // Beim Quellenwechsel das erste Ereignis der neuen Quelle wählen.
            selectedEvent = events.first
        }
        .onDisappear {
            securityScopedURL?.stopAccessingSecurityScopedResource()
        }
    }

    private func loadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "TeslaCam-Ordner, USB-Stick oder einen Clips-Ordner auswählen"
        panel.prompt = "Öffnen"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        securityScopedURL?.stopAccessingSecurityScopedResource()
        let granted = url.startAccessingSecurityScopedResource()
        securityScopedURL = granted ? url : nil
        isLoading = true
        hasLoaded = false
        allEvents = []
        selectedEvent = nil

        Task.detached(priority: .userInitiated) {
            let loaded = EventLoader.loadAll(from: url)
            await MainActor.run {
                self.allEvents = loaded
                // Erste Quelle mit Inhalt vorwählen (bevorzugt Sentry).
                let firstSource = ClipSource.allCases.first { source in
                    loaded.contains { $0.source == source }
                } ?? .sentry
                self.source = firstSource
                self.selectedEvent = loaded.first { $0.source == firstSource }
                self.isLoading = false
                self.hasLoaded = true
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    let events: [SentryEvent]
    @Binding var source: ClipSource
    let sourceCounts: [ClipSource: Int]
    @Binding var selectedEvent: SentryEvent?
    let isLoading: Bool
    let hasLoaded: Bool
    let onSelectFolder: () -> Void

    /// Quellen, die tatsächlich Ereignisse enthalten.
    private var availableSources: [ClipSource] {
        ClipSource.allCases.filter { (sourceCounts[$0] ?? 0) > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onSelectFolder) {
                    Label("Öffnen", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                if !events.isEmpty {
                    Text("\(events.count) Ereignisse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)

            // Quellen-Umschalter (nur wenn mehr als eine Quelle Inhalt hat)
            if availableSources.count > 1 {
                Picker("Quelle", selection: $source) {
                    ForEach(availableSources) { src in
                        Label("\(src.displayName) (\(sourceCounts[src] ?? 0))", systemImage: src.systemIcon)
                            .tag(src)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Lade Ereignisse…")
                Spacer()
            } else if events.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: hasLoaded ? "questionmark.folder.fill" : "car.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(hasLoaded ? "Keine Ereignisse gefunden" : "Kein Ordner geladen")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(events, selection: $selectedEvent) { event in
                    EventRowView(event: event).tag(event)
                }
                .listStyle(.sidebar)
            }
        }
    }
}

// MARK: - Event-Zeile

struct EventRowView: View {
    let event: SentryEvent
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 62, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 62, height: 40)
                        .overlay(
                            Image(systemName: "video")
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .task(id: event.thumbnailURL) {
                guard let url = event.thumbnailURL else { return }
                thumbnail = await Task.detached {
                    NSImage(contentsOf: url)
                }.value
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayDate)
                    .font(.caption).fontWeight(.semibold)
                    .lineLimit(1)

                if let city = event.city {
                    Text(city)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Label(event.reasonInfo.display, systemImage: event.reasonInfo.systemIcon)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)

                Text("\(event.clips.count) Clip\(event.clips.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Platzhalter

struct PlaceholderView: View {
    let hasEvents: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasEvents ? "car.rear.fill" : "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(hasEvents ? "Ereignis aus der Liste wählen" : "TeslaCam-Ordner öffnen")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Previews

#Preview("Sidebar mit Events") {
    SidebarView(
        events: SentryEvent.previewList,
        source: .constant(.sentry),
        sourceCounts: [.sentry: 2, .saved: 1],
        selectedEvent: .constant(nil),
        isLoading: false,
        hasLoaded: true,
        onSelectFolder: {}
    )
    .frame(width: 280, height: 500)
}

#Preview("Sidebar leer") {
    SidebarView(
        events: [],
        source: .constant(.sentry),
        sourceCounts: [:],
        selectedEvent: .constant(nil),
        isLoading: false,
        hasLoaded: false,
        onSelectFolder: {}
    )
    .frame(width: 280, height: 400)
}

#Preview("Sidebar keine Ergebnisse") {
    SidebarView(
        events: [],
        source: .constant(.sentry),
        sourceCounts: [:],
        selectedEvent: .constant(nil),
        isLoading: false,
        hasLoaded: true,
        onSelectFolder: {}
    )
    .frame(width: 280, height: 400)
}

#Preview("Event-Zeile") {
    EventRowView(event: .preview)
        .frame(width: 260)
        .padding()
}

#Preview("Platzhalter") {
    PlaceholderView(hasEvents: false)
        .frame(width: 500, height: 400)
}
