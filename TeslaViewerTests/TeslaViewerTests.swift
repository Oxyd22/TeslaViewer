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
