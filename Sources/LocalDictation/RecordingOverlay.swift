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
                    Button("Recent") { controller.showHistory?() }.controlSize(.small)
                    Button { controller.hideOverlay?() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
            }
            PanelDragHandle().frame(height: 10).help("Drag to move this panel")
            if controller.phase == .recording {
                HStack(alignment: .center, spacing: 4) {
                    ForEach(Array(controller.levels.enumerated()), id: \.offset) { _, level in
                        Capsule().fill(.tint).frame(width: 10, height: max(3, CGFloat(level) * 28))
                    }
                }.frame(height: 30).frame(maxWidth: .infinity)
                Text("\(controller.recordingFinishHint) · microphone active")
                    .font(.caption).foregroundStyle(.secondary)
            } else if controller.phase == .idle, let latest = controller.latestTranscript {
                Text(latest.text).font(.callout).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("Copy last text", systemImage: "doc.on.doc") { controller.copy(latest) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Spacer()
                    Text(controller.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            } else {
                Text(controller.message).font(.callout).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(18).frame(width: 446, height: 192, alignment: .topLeading)
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

// A dedicated grip keeps dragging separate from transcript buttons and never takes focus.
private struct PanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> PanelGrip { PanelGrip() }
    func updateNSView(_ nsView: PanelGrip, context: Context) {}
}
private final class PanelGrip: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 24, y: bounds.midY - 2, width: 48, height: 4), xRadius: 2, yRadius: 2).fill()
    }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
        if let window { window.saveFrame(usingName: "DictationFloatingPanel") }
    }
}
