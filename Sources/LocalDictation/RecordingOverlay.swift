import SwiftUI
import AppKit

struct RecordingOverlay: View {
    @ObservedObject var controller: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: controller.phase == .recording ? "mic.fill" : "waveform")
                    .foregroundStyle(controller.phase == .recording ? Color.red : Color.accentColor)
                Text(controller.phase == .recording ? "Recording" : "LocalDictation").font(.headline)
                Spacer()
                if controller.phase == .recording {
                    Text(duration(controller.elapsed)).font(.body.monospacedDigit())
                    Button("Stop") { controller.toggleRecording() }.buttonStyle(.borderedProminent).controlSize(.small)
                    Menu { Button("Stop and keep audio only") { controller.stopAndKeepAudio() } }
                        label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20)
                } else if controller.phase == .transcribing {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { controller.cancelProcessing() }.controlSize(.small)
                } else if controller.phase == .idle {
                    Button("History") { controller.showHistory?() }.controlSize(.small)
                    Button { controller.hideOverlay?() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
            }
            if controller.phase == .recording {
                HStack(alignment: .center, spacing: 4) {
                    ForEach(Array(controller.levels.enumerated()), id: \.offset) { _, level in
                        Capsule().fill(.tint).frame(width: 10, height: max(3, CGFloat(level) * 28))
                    }
                }.frame(height: 30).frame(maxWidth: .infinity)
                Text("\(controller.settings.recordShortcut.display) to finish · audio is being saved")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(controller.message).font(.callout).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(18).frame(width: 446, height: 144, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
    }
}

final class RecordingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
