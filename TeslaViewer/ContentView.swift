//
//  ContentView.swift
//  TeslaViewer
//
//  Haupt-View mit NavigationSplitView: Sidebar + Detail.
//

import SwiftUI

// MARK: - Fokussierte Aktion (für die Menüleiste)

private struct OpenFolderActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openFolderAction: (() -> Void)? {
        get { self[OpenFolderActionKey.self] }
        set { self[OpenFolderActionKey.self] = newValue }
    }
}

// MARK: - Haupt-View

struct ContentView: View {
    @State private var folderStore = FolderStore()
    @State private var events: [SentryEvent] = []
    @State private var selectedEvent: SentryEvent?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var skippedEncrypted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                events: events,
                selectedEvent: $selectedEvent,
                isLoading: isLoading,
                hasLoaded: hasLoaded,
                skippedEncrypted: skippedEncrypted
            )
            .frame(minWidth: 260)
        } detail: {
            if let event = selectedEvent {
                VideoGridView(event: event)
                    .id(event.id)
            } else {
                PlaceholderView(hasEvents: !events.isEmpty)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    loadFolder()
                } label: {
                    Label("Ordner öffnen", systemImage: "folder.badge.plus")
                }
            }
            ToolbarItem {
                Button {
                    revealSelectedInFinder()
                } label: {
                    Label("Im Finder zeigen", systemImage: "folder")
                }
                .disabled(selectedEvent == nil)
            }
        }
        .task {
            if let url = folderStore.currentURL {
                await load(from: url)
            }
        }
        .focusedSceneValue(\.openFolderAction, loadFolder)
    }

    private func loadFolder() {
        guard let url = folderStore.chooseFolder() else { return }
        Task { await load(from: url) }
    }

    private func revealSelectedInFinder() {
        guard let event = selectedEvent else { return }
        NSWorkspace.shared.activateFileViewerSelecting([event.folderURL])
    }

    private func load(from url: URL) async {
        isLoading = true
        hasLoaded = false
        events = []
        selectedEvent = nil

        let result = await EventLoader.scan(root: url)
        events = result.events
        skippedEncrypted = result.skippedEncrypted
        selectedEvent = result.events.first
        isLoading = false
        hasLoaded = true
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    let events: [SentryEvent]
    @Binding var selectedEvent: SentryEvent?
    let isLoading: Bool
    let hasLoaded: Bool
    let skippedEncrypted: Bool

    private static let sourceOrder: [ClipSource] = [.sentry, .saved]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Lade Ereignisse…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.isEmpty {
                ContentUnavailableView(
                    hasLoaded ? "Keine Ereignisse gefunden" : "Kein Ordner geladen",
                    systemImage: hasLoaded ? "questionmark.folder.fill" : "car.fill",
                    description: hasLoaded ? nil : Text("Öffne einen TeslaCam-Ordner, um Ereignisse zu sehen.")
                )
            } else {
                List(selection: $selectedEvent) {
                    ForEach(Self.sourceOrder, id: \.self) { source in
                        let sourceEvents = events.filter { $0.source == source }
                        if !sourceEvents.isEmpty {
                            Section(source.displayName) {
                                ForEach(Self.groupedByDay(sourceEvents)) { group in
                                    Text(group.day)
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                    ForEach(group.events) { event in
                                        EventRowView(event: event).tag(event)
                                    }
                                }
                            }
                        }
                    }

                    if skippedEncrypted {
                        Text("Verschlüsselte Clips werden übersprungen.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private struct DayGroup: Identifiable {
        let day: String
        let events: [SentryEvent]
        var id: String { day }
    }

    private static func groupedByDay(_ events: [SentryEvent]) -> [DayGroup] {
        var groups: [DayGroup] = []
        for event in events {
            let day = event.displayDay
            if let last = groups.last, last.day == day {
                groups[groups.count - 1] = DayGroup(day: day, events: last.events + [event])
            } else {
                groups.append(DayGroup(day: day, events: [event]))
            }
        }
        return groups
    }
}

// MARK: - Event-Zeile

struct EventRowView: View {
    let event: SentryEvent
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
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
                let data = try? await Task.detached { try Data(contentsOf: url) }.value
                guard let data else { return }
                thumbnail = NSImage(data: data)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayTime)
                    .font(.caption).fontWeight(.semibold)
                    .lineLimit(1)

                if let city = event.city {
                    Text(city)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Label(event.reasonInfo.display, systemImage: event.reasonInfo.systemIcon)
                    .font(.caption2)
                    .foregroundStyle(event.reasonInfo.severityColor)
                    .lineLimit(1)

                Text("\(event.clips.count) Clip\(event.clips.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Platzhalter

struct PlaceholderView: View {
    let hasEvents: Bool

    var body: some View {
        ContentUnavailableView(
            hasEvents ? "Ereignis aus der Liste wählen" : "TeslaCam-Ordner öffnen",
            systemImage: hasEvents ? "car.rear.fill" : "folder.badge.plus"
        )
    }
}

// MARK: - Previews

#Preview("Sidebar mit Events") {
    SidebarView(
        events: SentryEvent.previewList,
        selectedEvent: .constant(nil),
        isLoading: false,
        hasLoaded: true,
        skippedEncrypted: true
    )
    .frame(width: 280, height: 500)
}

#Preview("Sidebar leer") {
    SidebarView(
        events: [],
        selectedEvent: .constant(nil),
        isLoading: false,
        hasLoaded: false,
        skippedEncrypted: false
    )
    .frame(width: 280, height: 400)
}

#Preview("Sidebar keine Ergebnisse") {
    SidebarView(
        events: [],
        selectedEvent: .constant(nil),
        isLoading: false,
        hasLoaded: true,
        skippedEncrypted: false
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
