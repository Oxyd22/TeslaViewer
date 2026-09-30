//
//  TeslaViewerTests.swift
//  TeslaViewerTests
//
//  Created by Daniel Riewe on 23.12.25.
//

import Testing
@testable import TeslaViewer
import Foundation

struct TeslaViewerTests {

    @Test func testLoadEvents() async throws {
        // Create a temporary directory structure mimicking TeslaCam
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestTeslaCam")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sentryClipsDir = tempDir.appendingPathComponent("SentryClips")
        try FileManager.default.createDirectory(at: sentryClipsDir, withIntermediateDirectories: true)

        // Create mock event directory
        let eventDir = sentryClipsDir.appendingPathComponent("2025-12-23_12-00-00")
        try FileManager.default.createDirectory(at: eventDir, withIntermediateDirectories: true)

        // Create mock video files
        let frontVideo = eventDir.appendingPathComponent("2025-12-23_12-00-00-front.mp4")
        let backVideo = eventDir.appendingPathComponent("2025-12-23_12-00-00-back.mp4")
        let leftVideo = eventDir.appendingPathComponent("2025-12-23_12-00-00-left_pillar.mp4")
        let rightVideo = eventDir.appendingPathComponent("2025-12-23_12-00-00-right_pillar.mp4")

        // Create empty files to simulate videos
        FileManager.default.createFile(atPath: frontVideo.path, contents: Data())
        FileManager.default.createFile(atPath: backVideo.path, contents: Data())
        FileManager.default.createFile(atPath: leftVideo.path, contents: Data())
        FileManager.default.createFile(atPath: rightVideo.path, contents: Data())

        // Create event.json
        let eventJson = eventDir.appendingPathComponent("event.json")
        let jsonData = "{\"timestamp\":\"2025-12-23_12-00-00\",\"city\":\"Berlin\",\"reason\":\"sentry_aware_object_detection\"}".data(using: .utf8)!
        FileManager.default.createFile(atPath: eventJson.path, contents: jsonData)

        // Test the loadEvents function using EventLoader
        let events = EventLoader.loadEvents(from: tempDir)

        #expect(events.count == 1)
        #expect(events.first?.city == "Berlin")
        #expect(events.first?.reason == "sentry_aware_object_detection")
        #expect(events.first?.clips.count == 1)
        #expect(await events.first?.clips.first?.cameraURLs["front"] != nil)
        #expect(await events.first?.clips.first?.cameraURLs["back"] != nil)
        #expect(await events.first?.clips.first?.cameraURLs["left_pillar"] != nil)
        #expect(await events.first?.clips.first?.cameraURLs["right_pillar"] != nil)
    }

    @Test func testLoadAllSourcesAndGPS() async throws {
        // TeslaCam-Struktur mit allen drei Quellen aufbauen.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestTeslaCam-\(UUID().uuidString)")
        let fm = FileManager.default
        defer { try? fm.removeItem(at: base) }

        func writeEvent(in parent: URL, folder: String, json: String, cameras: [String]) throws {
            let dir = parent.appendingPathComponent(folder)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for cam in cameras {
                fm.createFile(atPath: dir.appendingPathComponent("\(folder)-\(cam).mp4").path, contents: Data())
            }
            fm.createFile(atPath: dir.appendingPathComponent("event.json").path, contents: json.data(using: .utf8))
        }

        let sentry = base.appendingPathComponent("SentryClips")
        let saved  = base.appendingPathComponent("SavedClips")
        let recent = base.appendingPathComponent("RecentClips")
        try fm.createDirectory(at: recent, withIntermediateDirectories: true)

        // Sentry-Ereignis mit GPS
        try writeEvent(
            in: sentry, folder: "2025-06-19_09-11-47",
            json: "{\"city\":\"Marne-la-Vallée\",\"reason\":\"sentry_aware_object_detection\",\"est_lat\":\"48.8277\",\"est_lon\":\"2.81941\"}",
            cameras: ["front", "back"]
        )
        // Gespeichertes Ereignis
        try writeEvent(
            in: saved, folder: "2026-06-08_21-27-34",
            json: "{\"reason\":\"user_interaction_dashcam_icon_tapped\"}",
            cameras: ["front"]
        )
        // RecentClips: flacher Puffer, zwei Minuten-Segmente, kein event.json
        for minute in ["2026-06-09_07-21-20", "2026-06-09_07-22-20"] {
            for cam in ["front", "back"] {
                fm.createFile(atPath: recent.appendingPathComponent("\(minute)-\(cam).mp4").path, contents: Data())
            }
        }

        let all = EventLoader.loadAll(from: base)

        // Je Quelle ein Ereignis (Recent bündelt seine Segmente zu einem).
        #expect(all.filter { $0.source == .sentry }.count == 1)
        #expect(all.filter { $0.source == .saved }.count == 1)
        #expect(all.filter { $0.source == .recent }.count == 1)

        let sentryEvent = try #require(all.first { $0.source == .sentry })
        #expect(sentryEvent.city == "Marne-la-Vallée")
        #expect(sentryEvent.latitude == 48.8277)
        #expect(sentryEvent.longitude == 2.81941)
        #expect(sentryEvent.coordinate != nil)

        // RecentClips: ein Ereignis mit zwei Clips, ohne GPS.
        let recentEvent = try #require(all.first { $0.source == .recent })
        #expect(recentEvent.clips.count == 2)
        #expect(recentEvent.coordinate == nil)
    }

    @Test func testEventReasonMapping() throws {
        // Test event reason display strings
        let objectDetection = EventReason(raw: "sentry_aware_object_detection")
        #expect(objectDetection.display == "Objekt erkannt")
        #expect(objectDetection.systemIcon == "eye.fill")

        let personDetection = EventReason(raw: "sentry_aware_body_cam_object_detection")
        #expect(personDetection.display == "Person erkannt")
        #expect(personDetection.systemIcon == "figure.walk")

        let collision = EventReason(raw: "sentry_aware_collision")
        #expect(collision.display == "Kollision")
        #expect(collision.systemIcon == "exclamationmark.triangle.fill")

        let empty = EventReason(raw: "")
        #expect(empty.display == "Sentry-Ereignis")
        #expect(empty.systemIcon == "video.fill")
    }

    @Test func testDateParsing() throws {
        // Test date parsing from folder names
        let formatter = EventLoader.dateFormatter
        let dateString = "2025-12-23_12-00-00"
        let date = formatter.date(from: dateString)
        
        #expect(date != nil)
        
        if let parsedDate = date {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsedDate)
            #expect(components.year == 2025)
            #expect(components.month == 12)
            #expect(components.day == 23)
            #expect(components.hour == 12)
            #expect(components.minute == 0)
            #expect(components.second == 0)
        }
    }

    @Test @MainActor func testVideoPlayerManager() throws {
        // Test basic VideoPlayerManager initialization
        let manager = VideoPlayerManager()
        #expect(manager.totalClips == 0)
        #expect(manager.currentClipIndex == 0)
        #expect(manager.isPlaying == false)
        #expect(manager.currentTime == 0)
        #expect(manager.duration == 60)
    }

}
