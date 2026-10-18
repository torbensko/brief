import SwiftUI
import DictationCore

struct HistoryView: View {
    @ObservedObject var controller: AppController
    @State private var search = ""
    @State private var pendingOnly = false
    private var filtered: [DictationSession] {
        controller.sessions.filter { session in
            (!pendingOnly || session.delivery == .pending) &&
            (search.isEmpty || session.text.localizedCaseInsensitiveContains(search)
             || session.profileName.localizedCaseInsensitiveContains(search)
             || (session.targetApplication ?? "").localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill").font(.system(size: 30)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LocalDictation").font(.title2.bold())
                    Text("Recent dictation · recover text that missed its destination").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(controller.phase == .recording ? "Stop recording" : "Record", systemImage: controller.phase == .recording ? "stop.fill" : "mic.fill") {
                    controller.toggleRecording()
                }.disabled(controller.isBusy && controller.phase != .recording)
                Button("Settings", systemImage: "gearshape") { controller.showSettings?() }
                    .labelStyle(.iconOnly).help("Settings")
            }.padding(20)
            HStack {
                Text("Keep")
                Picker("Retention", selection: Binding(get: { controller.settings.effectiveRecoveryPolicy.mode }, set: {
                    controller.setRecoveryPolicy(RecoveryPolicy(mode: $0, value: $0 == .count ? 1 : 5))
                })) {
                    Text("last entries").tag(RecoveryPolicy.Mode.count)
                    Text("for minutes").tag(RecoveryPolicy.Mode.minutes)
                }.labelsHidden().frame(width: 140)
                Stepper(value: Binding(get: { controller.settings.effectiveRecoveryPolicy.value }, set: {
                    controller.setRecoveryPolicy(RecoveryPolicy(mode: controller.settings.effectiveRecoveryPolicy.mode, value: $0))
                }), in: 1...100) { Text("\(controller.settings.effectiveRecoveryPolicy.value)").monospacedDigit() }.frame(width: 85)
                Spacer()
                Text("Older audio and text are automatically deleted.").font(.caption).foregroundStyle(.secondary)
            }.frame(height: 36).padding(.horizontal, 20).padding(.bottom, 12).layoutPriority(1).disabled(controller.isBusy)
            Divider()
            if let error = controller.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { controller.errorMessage = nil }
                }.padding(12).background(.quaternary)
            }
            HSplitView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Search transcripts or projects", text: $search).textFieldStyle(.roundedBorder)
                    Toggle("Pending only", isOn: $pendingOnly).toggleStyle(.checkbox)
                    List(selection: $controller.selectedSessionID) {
                        ForEach(filtered) { session in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(session.createdAt, format: .dateTime.day().month().hour().minute()).font(.caption.weight(.medium))
                                    Spacer()
                                    if session.delivery == .pending { Image(systemName: "tray.and.arrow.down").help("Pending") }
                                }
                                Text(session.text.isEmpty ? session.state.label : session.text)
                                    .font(.callout).lineLimit(3)
                                Text("\(session.profileName) · \(duration(session.duration))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5).tag(session.id)
                        }
                    }.listStyle(.sidebar)
                    Text("\(filtered.count) recent entries · stored locally")
                        .font(.caption).foregroundStyle(.secondary)
                    if !controller.historyWarnings.isEmpty {
                        Text("Some history entries could not be read. Their files have not been changed.")
                            .font(.caption).foregroundStyle(.orange)
                        Button("Show history folder") {
                            NSWorkspace.shared.open(controller.root.appendingPathComponent("Sessions"))
                        }
                    }
                }.padding(14).frame(minWidth: 230, idealWidth: 270, maxWidth: 340)
                if let session = controller.sessions.first(where: { $0.id == controller.selectedSessionID }) {
                    TranscriptDetail(controller: controller, session: session).id(session.id)
                        .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("Your latest dictation, recoverable", systemImage: "tray")
                    } description: {
                        Text("Record with \(controller.settings.recordShortcut.display).\nRecent audio and transcripts stay here briefly, even when insertion fails.")
                    }.frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                Circle().fill(controller.phase == .recording ? Color.red : Color.secondary).frame(width: 7, height: 7)
                Text(controller.message).font(.caption).lineLimit(2)
                Spacer()
                if controller.phase == .transcribing || controller.phase == .loading {
                    Button("Cancel processing") { controller.cancelProcessing() }.controlSize(.small)
                }
                Text(controller.settings.insertShortcut.display + " inserts pending")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }.padding(12)
        }.frame(minWidth: 820, minHeight: 680)
    }
}

private struct TranscriptDetail: View {
    @ObservedObject var controller: AppController
    let session: DictationSession
    @State private var draft: String
    @State private var showDelete = false
    @State private var deleteAudioOnly = false
    @State private var term = ""
    @State private var editError: String?
    init(controller: AppController, session: DictationSession) {
        self.controller = controller; self.session = session
        _draft = State(initialValue: session.text)
    }
    private var dirty: Bool { draft != session.text }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.createdAt, format: .dateTime.weekday().day().month().hour().minute()).font(.headline)
                    Text("\(session.profileName) · \(duration(session.duration))\(session.targetApplication.map { " · " + $0 } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Show files in Finder") { controller.reveal(session) }
                    Button("Archive pending transcript") { controller.archive(session.id) }
                    Divider()
                    Button("Delete audio only…", role: .destructive) { deleteAudioOnly = true; showDelete = true }
                        .disabled(session.audioDeleted || controller.isBusy)
                    Button("Delete recording and transcript…", role: .destructive) { deleteAudioOnly = false; showDelete = true }
                        .disabled(controller.isBusy)
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24)
            }
            HStack {
                badge(session.state.label)
                badge(session.delivery.label)
                if session.editedText != nil { badge("Edited") }
            }
            if let deliveryNote = session.deliveryNote { Text(deliveryNote).font(.callout).textSelection(.enabled) }
            if let note = session.note { Text(note).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            if let editError { Text(editError).font(.callout).foregroundStyle(.red) }
            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10).background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .disabled(controller.isBusy || session.attempts.isEmpty)
                .frame(minHeight: 140)
            HStack {
                Button("Save edits") {
                    Task {
                        do { try await controller.saveEdit(session.id, text: draft); editError = nil }
                        catch { editError = error.localizedDescription }
                    }
                }.disabled(!dirty || controller.isBusy).keyboardShortcut("s", modifiers: .command)
                if dirty { Text("Unsaved edits").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") { controller.copy(session) }
                    .disabled(dirty || !session.canInsert || controller.isBusy)
                Button("Use for next insertion", systemImage: "arrow.up.right.square") { controller.stage(session.id) }
                    .disabled(dirty || !session.canInsert || controller.isBusy)
            }
            HStack {
                Button("Play audio", systemImage: "play.fill") { controller.play(session) }
                    .disabled(session.audioDeleted || session.frameCount == 0 || controller.isBusy)
                Button("Stop") { controller.stopPlayback() }
                Button("Export WAV") { controller.exportAudio(session) }
                    .disabled(session.audioDeleted || session.frameCount == 0 || controller.isBusy)
                Spacer()
                Menu("Retranscribe") {
                    Button("With the recording’s original vocabulary") { controller.retry(session, useCurrentVocabulary: false) }
                    Button("With the current coding vocabulary") { controller.retry(session, useCurrentVocabulary: true) }
                }.disabled(session.audioDeleted || session.frameCount == 0 || controller.isBusy || dirty)
            }.controlSize(.small)
            Divider()
            HStack {
                TextField("Add a spelling, e.g. Blint", text: $term).textFieldStyle(.roundedBorder)
                Button("Add to vocabulary") {
                    do {
                        var settings = controller.settings
                        let word = term.trimmingCharacters(in: .whitespacesAndNewlines)
                        settings.globalTerms += "\n" + word
                        try controller.apply(settings); term = ""; editError = nil
                    } catch { editError = error.localizedDescription }
                }.disabled(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.isBusy)
            }
            Text("This adds recognition context for future runs; it does not replace words in existing transcripts.")
                .font(.caption).foregroundStyle(.secondary)
            if !session.attempts.isEmpty {
                DisclosureGroup("Original recognition attempts (\(session.attempts.count))") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(session.attempts.reversed()) { attempt in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(attempt.createdAt, format: .dateTime.hour().minute().second()).font(.caption.bold())
                                    Text(attempt.text).font(.callout).textSelection(.enabled)
                                    Text(attempt.model).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                    Text(String(format: "%.1fs processing · %d output tokens", attempt.processingSeconds, attempt.generationTokens))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Button("Use this text in editor") { draft = attempt.text }.controlSize(.small)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 160)
                }
            }
        }.padding(20)
        .onChange(of: session.text) { old, new in if draft == old { draft = new } }
        .alert(deleteAudioOnly ? "Delete saved audio?" : "Delete this recording?", isPresented: $showDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { controller.delete(session, audioOnly: deleteAudioOnly) }
        } message: {
            Text(deleteAudioOnly ? "The transcript will remain, but replay and retranscription will no longer be available."
                                 : "The audio and all transcript versions will be permanently removed from this app’s storage.")
        }
    }
    private func badge(_ title: String) -> some View {
        Text(title).font(.caption2.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

func duration(_ seconds: Double) -> String {
    let value = max(0, Int(seconds.isFinite ? seconds : 0))
    return String(format: "%d:%02d", value / 60, value % 60)
}
