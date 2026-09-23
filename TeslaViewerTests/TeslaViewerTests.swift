//
//  TeslaViewerTests.swift
//  TeslaViewerTests
//
//  Created by Daniel Riewe on 23.12.25.
//

import Testing
@testable import TeslaViewer
import Foundation

// MARK: - Fixture-Helfer

/// Baut eine temporäre TeslaCam-Ordnerstruktur mit Platzhalter-MP4s und optionalem
/// event.json auf, wie sie EventLoader.scan(root:) auf einem echten USB-Laufwerk vorfindet.
private struct TeslaCamFixture {
    let rootURL: URL

    static func make() throws -> TeslaCamFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return TeslaCamFixture(rootURL: root)
    }

    @discardableResult
    func makeEventFolder(
        in parent: String,
        timestamp: String,
        cameras: [String] = ["front", "back", "left_pillar", "right_pillar", "left_repeater", "right_repeater"],
        eventJSON: String? = nil
    ) throws -> URL {
        let dir = rootURL.appendingPathComponent(parent).appendingPathComponent(timestamp)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for camera in cameras {
            let fileURL = dir.appendingPathComponent("\(timestamp)-\(camera).mp4")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }
        if let eventJSON {
            let jsonURL = dir.appendingPathComponent("event.json")
            FileManager.default.createFile(atPath: jsonURL.path, contents: Data(eventJSON.utf8))
        }
        return dir
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

struct TeslaViewerTests {

    @Test func testScanFindsBothSources() async throws {
        let fixture = try TeslaCamFixture.make()
        defer { fixture.cleanup() }

        try fixture.makeEventFolder(
            in: "SentryClips", timestamp: "2025-12-23_12-00-00",
            eventJSON: #"{"timestamp":"2025-12-23T12:00:05","city":"Berlin","reason":"sentry_aware_object_detection"}"#
        )
        try fixture.makeEventFolder(
            in: "SavedClips", timestamp: "2025-12-24_09-00-00",
            eventJSON: #"{"timestamp":"2025-12-24T09:00:03","city":"Hamburg","reason":"user_interaction_dashcam_launcher_action_tapped"}"#
        )

        let result = await EventLoader.scan(root: fixture.rootURL)
        #expect(result.events.count == 2)

        let sentryEvent = try #require(result.events.first { $0.source == .sentry })
        #expect(sentryEvent.city == "Berlin")
        #expect(sentryEvent.reason == "sentry_aware_object_detection")
        #expect(sentryEvent.clips.first?.cameraURLs["front"] != nil)
        #expect(sentryEvent.clips.first?.cameraURLs["left_pillar"] != nil)

        let savedEvent = try #require(result.events.first { $0.source == .saved })
        #expect(savedEvent.city == "Hamburg")
    }

    @Test func testScanSkipsEncryptedClips() async throws {
        let fixture = try TeslaCamFixture.make()
        defer { fixture.cleanup() }

        try fixture.makeEventFolder(in: "SentryClips", timestamp: "2025-12-23_12-00-00")
        try FileManager.default.createDirectory(
            at: fixture.rootURL.appendingPathComponent("EncryptedClips"), withIntermediateDirectories: true
        )

        let result = await EventLoader.scan(root: fixture.rootURL)
        #expect(result.skippedEncrypted)
        #expect(result.events.count == 1)
    }

    @Test func testScanAcceptsSingleEventFolderAsRoot() async throws {
        let fixture = try TeslaCamFixture.make()
        defer { fixture.cleanup() }
        let eventDir = try fixture.makeEventFolder(in: "SentryClips", timestamp: "2025-12-23_12-00-00")

        let result = await EventLoader.scan(root: eventDir)
        #expect(result.events.count == 1)
        #expect(result.events.first?.folderURL == eventDir)
    }

    @Test func testTriggerOffsetParsedFromEventJSON() async throws {
        let fixture = try TeslaCamFixture.make()
        defer { fixture.cleanup() }
        try fixture.makeEventFolder(
            in: "SentryClips", timestamp: "2025-12-23_12-00-00",
            eventJSON: #"{"timestamp":"2025-12-23T12:00:57","reason":"sentry_aware_object_detection"}"#
        )

        let result = await EventLoader.scan(root: fixture.rootURL)
        let event = try #require(result.events.first)
        let offset = try #require(event.triggerOffset)
        #expect(abs(offset - 57) < 0.001)
    }

    @Test func testEventIDIsStableAcrossScans() async throws {
        let fixture = try TeslaCamFixture.make()
        defer { fixture.cleanup() }
        try fixture.makeEventFolder(in: "SentryClips", timestamp: "2025-12-23_12-00-00")

        let first = await EventLoader.scan(root: fixture.rootURL)
        let second = await EventLoader.scan(root: fixture.rootURL)
        #expect(first.events.first?.id == second.events.first?.id)
    }

    @Test func testClipGroupingHandlesMissingCamera() async throws {
        let fixture = try TeslaCamFixture.make()
        defer { fixture.cleanup() }
        let eventDir = try fixture.makeEventFolder(
            in: "SentryClips", timestamp: "2025-12-23_12-00-00", cameras: ["front", "back"]
        )
        // Zweiter Clip: nur "front" vorhanden, "back" fehlt in diesem Clip.
        let secondClipFront = eventDir.appendingPathComponent("2025-12-23_12-01-00-front.mp4")
        FileManager.default.createFile(atPath: secondClipFront.path, contents: Data())

        let result = await EventLoader.scan(root: fixture.rootURL)
        let event = try #require(result.events.first)
        #expect(event.clips.count == 2)
        let secondClip = event.clips[1]
        #expect(secondClip.cameraURLs["front"] != nil)
        #expect(secondClip.cameraURLs["back"] == nil)
    }

    @Test func testDateParsingFromFolderName() async throws {
        let fixture = try TeslaCamFixture.make()
        defer { fixture.cleanup() }
        try fixture.makeEventFolder(in: "SentryClips", timestamp: "2025-12-23_12-00-00")

        let result = await EventLoader.scan(root: fixture.rootURL)
        let event = try #require(result.events.first)
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: event.eventTimestamp
        )
        #expect(components.year == 2025)
        #expect(components.month == 12)
        #expect(components.day == 23)
        #expect(components.hour == 12)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test func testEventReasonMapping() throws {
        let objectDetection = EventReason(raw: "sentry_aware_object_detection")
        #expect(objectDetection.display == "Objekt erkannt")
        #expect(objectDetection.systemIcon == "eye.fill")

        let personDetection = EventReason(raw: "sentry_aware_body_cam_object_detection")
        #expect(personDetection.display == "Person erkannt")
        #expect(personDetection.systemIcon == "figure.walk")

        let handlePulled = EventReason(raw: "sentry_locked_handle_pulled")
        #expect(handlePulled.display == "Türgriff gezogen")

        #expect(EventReason(raw: "user_interaction_dashcam_multifunction_selected").display == "Manuell gespeichert")
        #expect(EventReason(raw: "user_interaction_dashcam_launcher_action_tapped").display == "Manuell gespeichert")

        let collision = EventReason(raw: "sentry_aware_collision")
        #expect(collision.display == "Kollision")
        #expect(collision.systemIcon == "exclamationmark.triangle.fill")

        let accel = EventReason(raw: "sentry_aware_accel_0.453139")
        #expect(accel.display == "Erschütterung")
        if case .acceleration(let magnitude) = accel {
            let value = try #require(magnitude)
            #expect(abs(value - 0.453139) < 0.0001)
        } else {
            Issue.record("Erwartete .acceleration-Fall für \"sentry_aware_accel_0.453139\"")
        }

        let empty = EventReason(raw: "")
        #expect(empty.display == "Sentry-Ereignis")
        #expect(empty.systemIcon == "video.fill")

        let unknown = EventReason(raw: "some_unmapped_reason")
        #expect(unknown.display == "Some Unmapped Reason")
    }

    @Test @MainActor func testVideoPlayerManagerInitialState() throws {
        let manager = VideoPlayerManager()
        #expect(manager.players.isEmpty)
        #expect(manager.isPlaying == false)
        #expect(manager.currentTime == 0)
        #expect(manager.duration == 0)
        #expect(manager.isLoading == false)
    }
}
