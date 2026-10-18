import Foundation
import Testing
@testable import DictationCore

@Suite("Recording gestures") struct RecordingGestureTests {
    @Test func holdStartsOnPressAndStopsOnRelease() {
        var gesture = RecordingGesture()
        #expect(gesture.handle(down: true, mode: .hold, idle: true, preparing: false, recording: false) == .start)
        #expect(gesture.ownsRecording)
        #expect(gesture.handle(down: true, mode: .hold, idle: false, preparing: false, recording: true) == .none)
        #expect(gesture.handle(down: false, mode: .hold, idle: false, preparing: false, recording: true) == .stop)
        #expect(!gesture.ownsRecording)
    }
    @Test func releaseWhilePermissionOrStorageIsPreparingCancelsStart() {
        var gesture = RecordingGesture()
        _ = gesture.handle(down: true, mode: .hold, idle: true, preparing: false, recording: false)
        #expect(gesture.handle(down: false, mode: .hold, idle: false, preparing: true, recording: false) == .cancelPreparation)
        #expect(!gesture.ownsRecording)
    }
    @Test func busyPressDoesNotStartLaterOrStopMenuRecording() {
        var gesture = RecordingGesture()
        #expect(gesture.handle(down: true, mode: .hold, idle: false, preparing: false, recording: false) == .none)
        #expect(gesture.handle(down: false, mode: .hold, idle: true, preparing: false, recording: false) == .none)
        #expect(gesture.handle(down: true, mode: .hold, idle: false, preparing: false, recording: true) == .none)
        #expect(gesture.handle(down: false, mode: .hold, idle: false, preparing: false, recording: true) == .none)
    }
    @Test func toggleFiresOnceOnRelease() {
        var gesture = RecordingGesture()
        #expect(gesture.handle(down: true, mode: .toggle, idle: true, preparing: false, recording: false) == .none)
        #expect(gesture.handle(down: true, mode: .toggle, idle: true, preparing: false, recording: false) == .none)
        #expect(gesture.handle(down: false, mode: .toggle, idle: true, preparing: false, recording: false) == .toggle)
        #expect(gesture.handle(down: false, mode: .toggle, idle: true, preparing: false, recording: false) == .none)
    }
    @Test func manualStopBeforeReleaseDoesNotRestart() {
        var gesture = RecordingGesture()
        _ = gesture.handle(down: true, mode: .hold, idle: true, preparing: false, recording: false)
        #expect(gesture.handle(down: false, mode: .hold, idle: true, preparing: false, recording: false) == .none)
    }
    @Test func legacySettingsDefaultToHoldAndTogglePersists() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        let old = try encoder.encode(AppSettings())
        #expect(try decoder.decode(AppSettings.self, from: old).effectiveRecordingMode == .hold)
        var settings = AppSettings(); settings.recordingMode = .toggle
        #expect(try decoder.decode(AppSettings.self, from: encoder.encode(settings)).effectiveRecordingMode == .toggle)
    }
}
