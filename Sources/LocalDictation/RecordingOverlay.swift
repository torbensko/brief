import SwiftUI
import AppKit
import DictationCore

struct RecordingOverlay: View {
    @ObservedObject var controller: AppController
    @State private var showChanges = true
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                Text("Brief").font(.headline)
                if controller.phase == .recording {
                    Label("Recording", systemImage: "mic.fill")
                        .font(.caption).foregroundStyle(.red)
                }
                Spacer()
                if controller.phase == .recording {
                    Text(duration(controller.elapsed)).font(.body.monospacedDigit())
                    Button("Stop") { controller.toggleRecording() }.buttonStyle(.borderedProminent).controlSize(.small)
                    Menu { Button("Stop and keep audio only") { controller.stopAndKeepAudio() } }
                        label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20)
                } else if controller.phase == .transcribing {
                    ProgressView().controlSize(.small)
                    if controller.tidyingWording {
                        Button("Use original now") { controller.skipCleanup() }.controlSize(.small)
                    } else {
                        Button("Cancel") { controller.cancelProcessing() }.controlSize(.small)
                    }
                } else if controller.phase == .idle {
                    Button { controller.showHistory?() } label: {
                        Image(systemName: "clock.arrow.circlepath").frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain).help("Recent dictation")
                    .accessibilityLabel("Recent dictation")
                    Button { controller.hideOverlay?() } label: { Image(systemName: "xmark").frame(width: 20, height: 20) }
                        .modifier(PanelButtonStyle()).buttonBorderShape(.circle).help("Close")
                        .accessibilityLabel("Close dictation panel")
                }
            }
            PanelDragHandle().frame(width: 410, height: 24).help("Drag to move this panel")
            if controller.phase == .recording {
                HStack(alignment: .center, spacing: 4) {
                    ForEach(Array(controller.levels.enumerated()), id: \.offset) { _, level in
                        Capsule().fill(.tint).frame(width: 10, height: max(3, CGFloat(level) * 28))
                    }
                }.frame(height: 30).frame(maxWidth: .infinity)
                Text("\(controller.recordingFinishHint) · microphone active")
                    .font(.caption).foregroundStyle(.secondary)
            } else if controller.phase == .idle, controller.deliveryConfirmed, controller.latestTranscript?.cleanup?.changed != true {
                Label(controller.message, systemImage: "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if controller.phase == .idle, controller.noSpeechDetected {
                Text(controller.message).font(.callout)
            } else if controller.phase == .idle, let latest = controller.latestTranscript {
                if latest.cleanup?.changed == true, latest.editedText == nil {
                    Label("Wording tidied", systemImage: "wand.and.stars")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ScrollView(.vertical) {
                    Group {
                        if showChanges, let cleanup = latest.cleanup, cleanup.changed, latest.editedText == nil {
                            CleanupComparison(cleanup: cleanup)
                        } else { Text(latest.text) }
                    }.font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: transcriptHeight(showChanges ? (latest.cleanup?.original ?? latest.text) + " " : latest.text))
                if let cleanup = latest.cleanup {
                    if cleanup.changed {
                        HStack {
                            Toggle("Show edits", isOn: $showChanges).toggleStyle(.checkbox)
                            Text("Added · removed (struck through)").foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy original") { controller.copyOriginal(latest) }.buttonStyle(.plain)
                        }.font(.caption)
                    } else {
                        Text(cleanup.note ?? "Wording checked · no changes").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let note = latest.deliveryNote {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Copy last text", systemImage: "doc.on.doc") { controller.copy(latest) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Spacer()
                    if controller.message != latest.deliveryNote {
                        Text(controller.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            } else {
                Text(controller.message).font(.callout).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            }
            InsertionPermissionNotice(automaticInsertion: controller.settings.automaticInsertion) {
                controller.showSettings?()
            }
        }.padding(18).frame(width: 446, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: PanelHeightKey.self, value: geometry.size.height)
            })
            .onPreferenceChange(PanelHeightKey.self, perform: onHeightChange)
            .onChange(of: controller.latestTranscript?.cleanup?.createdAt) { _, _ in
                // Each new result starts with its edits visible in the floating panel.
                showChanges = true
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
    }
    private func transcriptHeight(_ text: String) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.preferredFont(forTextStyle: .callout)])
        return min(120, max(20, ceil(bounds.height) + 4))
    }
}

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

final class RecordingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    private var anchor: NSPoint?
    private let anchorKey = "BriefPanelTopLeft"
    func restorePosition() {
        let saved = UserDefaults.standard.array(forKey: anchorKey) as? [Double]
        if let saved, saved.count == 2 { anchor = NSPoint(x: saved[0], y: saved[1]) }
        if anchor == nil, let screen = NSScreen.main {
            anchor = NSPoint(x: screen.visibleFrame.midX - 223, y: screen.visibleFrame.maxY - 24)
        }
        resizeToContent(frame.height)
    }
    func resizeToContent(_ height: CGFloat) {
        guard height > 0, var top = anchor else { return }
        let screen = NSScreen.screens.first { $0.visibleFrame.contains(NSPoint(x: top.x + 223, y: top.y - 1)) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            top.x = max(visible.minX, min(top.x, visible.maxX - 446))
            top.y = min(visible.maxY, max(top.y, visible.minY + height))
        }
        // Clamping a taller card must not change the user's saved anchor.
        setFrame(NSRect(x: top.x, y: top.y - height, width: 446, height: height), display: true)
    }
    func rememberDraggedPosition() {
        anchor = NSPoint(x: frame.minX, y: frame.maxY)
        UserDefaults.standard.set([Double(frame.minX), Double(frame.maxY)], forKey: anchorKey)
    }
}

private struct PanelButtonStyle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.buttonStyle(.glass) }
        else { content.buttonStyle(.bordered) }
    }
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
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 24, y: bounds.midY - 2, width: 48, height: 4), xRadius: 2, yRadius: 2).fill()
    }
    override func mouseDown(with event: NSEvent) {
        dragStart = window?.convertPoint(toScreen: event.locationInWindow)
        windowStart = window?.frame.origin
        NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let origin = windowStart else { return }
        guard let now = window?.convertPoint(toScreen: event.locationInWindow) else { return }
        window?.setFrameOrigin(NSPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y))
        (window as? RecordingPanel)?.rememberDraggedPosition()
    }
    override func mouseUp(with event: NSEvent) {
        (window as? RecordingPanel)?.rememberDraggedPosition()
        dragStart = nil; windowStart = nil
        NSCursor.pop()
    }
}

/// Permission status stays visible even after Copy replaces the transient delivery message.
struct InsertionPermissionNotice: View {
    let automaticInsertion: Bool
    var openSettings: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            if automaticInsertion && !InsertionService.trusted {
                HStack {
                    Label("Insertion blocked · Accessibility access needed", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                    Spacer(minLength: 4)
                    Button("Enable insertion", action: openSettings).controlSize(.small)
                }
            }
        }
    }
}
