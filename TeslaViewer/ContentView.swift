//
//  ContentView.swift
//  TeslaViewer
//
//  Haupt-View mit NavigationSplitView: Sidebar + Detail.
//

import SwiftUI

// MARK: - Haupt-View

struct ContentView: View {
    @State private var events: [SentryEvent] = []
    @State private var selectedEvent: SentryEvent?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var securityScopedURL: URL?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                events: events,
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
        .onDisappear {
            securityScopedURL?.stopAccessingSecurityScopedResource()
        }
    }

    private func loadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "TeslaCam-Ordner oder SentryClips-Ordner auswählen"
        panel.prompt = "Öffnen"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        securityScopedURL?.stopAccessingSecurityScopedResource()
        let granted = url.startAccessingSecurityScopedResource()
        securityScopedURL = granted ? url : nil
        isLoading = true
        hasLoaded = false
        events = []
        selectedEvent = nil

        Task.detached(priority: .userInitiated) {
            let loaded = EventLoader.loadEvents(from: url)
            await MainActor.run {
                self.events = loaded
                self.selectedEvent = loaded.first
                self.isLoading = false
                self.hasLoaded = true
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    let events: [SentryEvent]
    @Binding var selectedEvent: SentryEvent?
    let isLoading: Bool
    let hasLoaded: Bool
    let onSelectFolder: () -> Void

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
