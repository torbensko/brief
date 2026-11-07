import SwiftUI
import AppKit
import ApplicationServices
import QuartzCore
import DictationCore

struct RecordingOverlay<Model: RecordingPresentation>: View {
    @ObservedObject var controller: Model
    @State private var contentHeight: CGFloat = 148
    var appIcon: NSImage? = nil
    var insertionPermissionGranted: Bool? = nil
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(nsImage: appIcon ?? NSApp.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                Text("Brief").font(.headline)
                    .overlay { PanelDragHandle().accessibilityHidden(true) }
                    .help("Drag to move this panel")
                if controller.batch.isGrouped {
                    Text("\(controller.batch.items.count) recordings").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if controller.canStartRecording {
                    Button("Record") { controller.toggleRecording() }.controlSize(.small)
                }
                Button { controller.showHistory?() } label: {
                    Image(systemName: "clock.arrow.circlepath").frame(width: 24, height: 24)
                }.buttonStyle(.plain).help("Recent dictation").accessibilityLabel("Recent dictation")
                Button { controller.hideOverlay?() } label: { Image(systemName: "xmark").frame(width: 20, height: 20) }
                    .modifier(PanelButtonStyle()).buttonBorderShape(.circle)
                    .help("Close").accessibilityLabel("Close dictation panel")
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 10) {
                        if controller.batch.items.isEmpty {
                            if let latest = controller.latestTranscript {
                                RecordingCell(controller: controller, id: latest.id, number: nil,
                                              stage: .complete, status: latest.deliveryNote ?? "Text ready")
                            } else {
                                Text(controller.message).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            ForEach(Array(controller.batch.items.enumerated()), id: \.element.id) { index, item in
                                RecordingCell(controller: controller, id: item.id,
                                              number: controller.batch.isGrouped ? index + 1 : nil,
                                              stage: item.stage, status: item.message)
                                    .id(item.id)
                            }
                        }
                    }.background(GeometryReader { geometry in
                        Color.clear.preference(key: RecordingContentHeightKey.self, value: geometry.size.height)
                    })
                }
                .frame(height: min(contentHeight, max(180, (NSScreen.main?.visibleFrame.height ?? 800) - 220)))
                .onChange(of: controller.batch.items.count) { _, _ in
                    if let id = controller.batch.items.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .onPreferenceChange(RecordingContentHeightKey.self) { if $0 > 0 { contentHeight = $0 } }
            if controller.batch.isGrouped {
                HStack {
                    Text("Copy all combines these recordings").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy all") { controller.copyGroup() }
                        .disabled(controller.batch.clipboardText.isEmpty).controlSize(.small)
                }
            }
            InsertionPermissionNotice(automaticInsertion: controller.settings.automaticInsertion,
                                      trustedOverride: insertionPermissionGranted) {
                controller.showSettings?()
            }
        }.padding(18).frame(width: 446, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: PanelHeightKey.self, value: geometry.size.height)
            })
            .onPreferenceChange(PanelHeightKey.self, perform: onHeightChange)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct RecordingCell<Model: RecordingPresentation>: View {
    @ObservedObject var controller: Model
    let id: UUID
    let number: Int?
    let stage: RecordingBatch.Stage
    let status: String
    @State private var showChanges = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var session: DictationSession? { controller.sessions.first { $0.id == id } }
    private var text: String {
        stage == .cleaning ? (session?.attempts.last?.text ?? "") : (session?.text ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                DictationProgress(stage: stage)
                    .overlay { PanelDragHandle().accessibilityHidden(true) }
                    .help("Drag to move this panel")
                Spacer(minLength: 0)
                if stage == .recording {
                    Text(duration(controller.elapsed)).font(.caption.monospacedDigit())
                    Button("Stop") { controller.toggleRecording() }.buttonStyle(.borderedProminent)
                    Menu { Button("Stop and keep audio only") { controller.stopAndKeepAudio() } }
                        label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 18)
                } else if stage == .cleaning {
                    Button("Use original") { controller.skipCleanup(id) }.help("Finish cleanup using the original now")
                } else if stage == .transcribing || stage == .queued {
                    Button("Cancel") { controller.cancelProcessing(id) }
                } else if stage == .complete, session?.cleanup?.changed == true, session?.editedText == nil {
                    Toggle(showChanges ? "Edits on" : "Edits off", isOn: $showChanges).toggleStyle(.button)
                        .help("Highlight wording changes or show the clean text")
                }
            }.controlSize(.small).frame(height: 24)
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if stage != .recording, !text.isEmpty {
                        ScrollView(.vertical) {
                            Group {
                                if stage == .complete, showChanges, let cleanup = session?.cleanup,
                                   cleanup.changed, session?.editedText == nil { CleanupComparison(cleanup: cleanup) }
                                else { Text(text) }
                            }.font(.callout).fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else { Color.clear }
                }.frame(height: bodyHeight, alignment: .top)
                    .clipped()
                HStack(alignment: .top, spacing: 8) {
                    Text(displayStatus).font(.caption).foregroundStyle(stage == .failed ? .orange :
                        (session?.delivery == .confirmed ? .green : .secondary))
                        .lineLimit(2).help(displayStatus)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if stage == .cleaning {
                        Button("Copy original") { controller.copyCleanupOriginal(id) }
                    } else if !text.isEmpty, let session {
                        Button("Copy text") { controller.copy(session) }
                        if session.cleanup?.changed == true {
                            Button("Copy original") { controller.copyOriginal(session) }
                        }
                    }
                }.buttonStyle(.bordered).controlSize(.small).frame(height: 32, alignment: .top)
            }
            // The footer stays reserved so the cell keeps its height between stages; the
            // top padding evens the gaps to the stage strip (8pt) and the cell edge (10pt).
            .overlay {
                if stage == .recording {
                    LevelMeter(levels: controller.levels).padding(.top, 2)
                }
            }
        }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: bodyHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(number.map { "Recording \($0)" } ?? "Recording")
    }
    private var displayStatus: String {
        switch stage {
        case .preparing, .recording, .saving, .queued, .transcribing: return ""
        case .cleaning:
            let detail = status.replacingOccurrences(of: "Tidying wording · ", with: "")
            return detail.prefix(1).uppercased() + detail.dropFirst()
        case .complete, .failed:
            return [session?.cleanup?.note, status].compactMap { $0 }.joined(separator: " ")
        }
    }
    private var transcriptHeight: CGFloat {
        let display: String
        if stage == .complete, showChanges, let cleanup = session?.cleanup,
           cleanup.changed, session?.editedText == nil {
            display = TranscriptDiff.parts(original: cleanup.original, revised: cleanup.text).map(\.text).joined()
        } else { display = text }
        let bounds = (display as NSString).boundingRect(
            with: NSSize(width: 380, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.preferredFont(forTextStyle: .callout)])
        return min(120, max(20, ceil(bounds.height) + 4))
    }
    // A fixed 148-point cell throughout capture/analysis. Only a settled result
    // may expand, with a scrollable original still available during cleanup.
    private var bodyHeight: CGFloat { stage.isActive ? 56 : max(56, transcriptHeight) }
}
private struct RecordingContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Microphone activity. Bars grow evenly from the centre line, and silence rests as a row of dots.
private struct LevelMeter: View {
    let levels: [Float]
    private let barWidth: CGFloat = 6
    private let maxHeight: CGFloat = 44
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule().fill(Color.accentColor)
                    .frame(width: barWidth, height: max(barWidth, CGFloat(level) * maxHeight))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A recessed track of stages, in the same quiet greys as the cell around it. Only the current
/// stage takes colour: accent while processing, a red tint while recording. Passed stages are ticked.
/// Reaching Complete does not imply successful insertion; delivery is reported separately.
struct DictationProgress: View {
    let stage: RecordingBatch.Stage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let titles = ["Record", "Transcribe", "Clean", "Complete"]
    private let symbols = ["mic.fill", "text.bubble", "sparkles", "flag.checkered"]
    private var active: Int? {
        switch stage {
        case .preparing, .recording: return 0
        case .saving, .queued, .transcribing: return 1
        case .cleaning: return 2
        case .complete: return 3
        case .failed: return nil
        }
    }
    private var isProcessing: Bool {
        [.preparing, .saving, .transcribing, .cleaning].contains(stage)
    }
    private func isPassed(_ index: Int) -> Bool { index < (active ?? 0) }
    private func labelStyle(for index: Int) -> AnyShapeStyle {
        guard index == active else {
            return isPassed(index) ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
        }
        return isProcessing ? AnyShapeStyle(.white) : AnyShapeStyle(.primary)
    }
    private func iconStyle(for index: Int) -> AnyShapeStyle {
        if isPassed(index) { return AnyShapeStyle(Color.accentColor) }
        guard index == active else { return AnyShapeStyle(.tertiary) }
        switch stage {
        case .recording: return AnyShapeStyle(.red)
        case .complete: return AnyShapeStyle(Color.accentColor)
        default: return AnyShapeStyle(.secondary)
        }
    }
    private func highlight(for index: Int) -> AnyShapeStyle {
        guard index == active else { return AnyShapeStyle(.clear) }
        if isProcessing { return AnyShapeStyle(Color.accentColor) }
        switch stage {
        case .recording: return AnyShapeStyle(Color.red.opacity(0.16))
        case .complete: return AnyShapeStyle(Color.accentColor.opacity(0.16))
        default: return AnyShapeStyle(Color.primary.opacity(0.1))
        }
    }
    var body: some View {
        HStack(spacing: 1) {
            ForEach(titles.indices, id: \.self) { index in
                let current = index == active
                let recording = current && stage == .recording
                HStack(spacing: 4) {
                    Group {
                        if current && isProcessing {
                            StageSpinner()
                        } else {
                            Image(systemName: isPassed(index) ? "checkmark" :
                                (current && stage == .queued ? "clock" : symbols[index]))
                                .font(.system(size: 10, weight: isPassed(index) ? .bold : .medium))
                                .foregroundStyle(iconStyle(for: index))
                                .symbolEffect(.pulse, options: .repeating, isActive: recording && !reduceMotion)
                        }
                    }.frame(width: 11, height: 11).accessibilityHidden(true)
                    Text(titles[index]).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(labelStyle(for: index)).fixedSize()
                }
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(highlight(for: index), in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(titles[index])
                .accessibilityValue(current ? (stage == .queued ? "Waiting" : "Current stage") :
                    (isPassed(index) ? "Passed" : "Upcoming"))
            }
        }
        .padding(2)
        .background(.primary.opacity(0.07), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: stage)
    }
}

/// A white activity glyph with exactly the same footprint as the stage icons.
private struct StageSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let period = 0.85
    // Driven by the clock, as a repeating implicit animation would also catch layout changes.
    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 1.3)
                Circle().trim(from: 0, to: 0.7)
                    .stroke(.white, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    .rotationEffect(.degrees(reduceMotion ? 0 : turn * 360))
            }.padding(1)
        }
    }
}

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
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
        let target = NSRect(x: top.x, y: top.y - height, width: 446, height: height)
        guard target != frame else { return }
        if isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(target, display: true)
            }
        } else { setFrame(target, display: true) }
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
    var trustedOverride: Bool? = nil
    var openSettings: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            if automaticInsertion && !(trustedOverride ?? AXIsProcessTrusted()) {
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
