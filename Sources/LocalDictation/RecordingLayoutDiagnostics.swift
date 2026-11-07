import AppKit
import DictationCore
import SwiftUI

/// Measures and renders the actual native cells using synthetic text and private storage.
@MainActor enum RecordingLayoutDiagnostics {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Brief-layout-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = AppSettings()
        settings.automaticInsertion = false
        try SettingsFile.save(settings, to: root.appendingPathComponent("settings.json"))
        let controller = try AppController(storageRoot: root)
        let original = "The the preview should keep every recording in its own cell. " +
            "Keep the stages at the top left while the timer and buttons stay on the right. " +
            "A new recording can start while earlier audio is transcribing or cleaning up. " +
            "Once the result is ready, the panel can expand smoothly to show the complete text."
        let session = DictationSession(sampleRate: 16000, profileName: "Layout preview", vocabulary: "")
        try await controller.store.create(session)
        try await controller.store.appendAttempt(TranscriptAttempt(text: original, model: "Synthetic preview",
            vocabulary: "", processingSeconds: 0, audioSeconds: 0, generationTokens: 0), to: session.id)
        _ = try await controller.store.update(session.id) {
            $0.cleanup = TranscriptCleanup(original: original, text: original.replacingOccurrences(of: "The the", with: "The"), model: "Synthetic preview")
        }
        await controller.refreshHistory()
        var heights: [RecordingBatch.Stage: CGFloat] = [:]
        for stage in [RecordingBatch.Stage.preparing, .recording, .saving, .queued, .transcribing, .cleaning, .complete] {
            let hasText = stage == .cleaning || stage == .complete
            let status = stage == .cleaning ? "Tidying wording · original on clipboard" : "Copied to clipboard · press ⌘V to paste"
            let view = NSHostingView(rootView: RecordingCell(controller: controller,
                id: hasText ? session.id : UUID(), number: nil, stage: stage, status: status).frame(width: 410).background(Color(nsColor: .windowBackgroundColor)))
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 410, height: 300),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            window.setContentSize(view.fittingSize)
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(100))
            view.layoutSubtreeIfNeeded()
            heights[stage] = view.bounds.height
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw DictationError.message("Could not render recording cell")
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let path = "/tmp/brief-layout-\(stage.rawValue).png"
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            window.orderOut(nil); window.contentView = nil
        }
        guard let activeHeight = heights[.recording],
              heights.filter({ $0.key.isActive }).allSatisfy({ abs($0.value - activeHeight) < 0.5 }),
              let completedHeight = heights[.complete], completedHeight > activeHeight else {
            throw DictationError.message("Recording cells changed height before completion: \(heights)")
        }
        print("Native recording layout passed: all unfinished states \(Int(activeHeight))pt; long completed text \(Int(completedHeight))pt. Renders: /tmp/brief-layout-<stage>.png")
        try await checkExpansion(controller, sessionID: session.id)
    }

    private static func checkExpansion(_ controller: AppController, sessionID: UUID) async throws {
        guard let session = controller.sessions.first(where: { $0.id == sessionID }),
              let attempt = session.attempts.last else { throw DictationError.message("Missing layout fixture") }
        controller.beginCleanupPresentation(session)
        let panel = RecordingPanel(contentRect: NSRect(x: 0, y: 0, width: 446, height: 222),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.restorePosition()
        panel.isOpaque = false; panel.backgroundColor = .clear
        var heightEvents: [CGFloat] = []
        let content = FirstMouseHostingView(rootView: RecordingOverlay(controller: controller) { [weak panel] height in
            heightEvents.append(height)
            panel?.resizeToContent(height)
        })
        content.sizingOptions = []
        content.autoresizingMask = [.width, .height]
        content.frame = NSRect(origin: .zero, size: panel.contentLayoutRect.size)
        panel.contentView = content
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil); panel.contentView = nil }
        try await Task.sleep(for: .milliseconds(300))
        let start = panel.frame.height
        try await controller.finishTranscriptDelivery(session, attempt: attempt, automaticInsertion: false)
        var samples: [CGFloat] = []
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(25))
            samples.append(panel.frame.height)
        }
        let end = panel.frame.height
        guard end > start else { throw DictationError.message("Completed text did not expand the panel: \(start) → \(end); height changes \(heightEvents); content frame \(content.frame)") }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            guard samples.contains(where: { $0 > start + 0.5 && $0 < end - 0.5 }) else {
                throw DictationError.message("Completed text jumped from \(start) to \(end) without animating: \(samples)")
            }
        }
        print("Native panel expansion passed: \(Int(start)) → \(Int(end))pt, with intermediate animated frames (or Reduce Motion).")
    }
}
