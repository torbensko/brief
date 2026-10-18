import SwiftUI
import AppKit
import Carbon.HIToolbox
import DictationCore

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @State private var draft: AppSettings
    @State private var saveMessage = ""
    @State private var permissionsVersion = 0
    @State private var editingProfile: UUID?
    init(controller: AppController) {
        self.controller = controller
        _draft = State(initialValue: controller.settings)
        _editingProfile = State(initialValue: controller.settings.selectedProfileID)
    }
    var body: some View {
        VStack(spacing: 0) {
            TabView {
                general.tabItem { Label("General", systemImage: "slider.horizontal.3") }
                model.tabItem { Label("Model", systemImage: "cpu") }
                vocabulary.tabItem { Label("Vocabulary", systemImage: "text.book.closed") }
                shortcuts.tabItem { Label("Shortcuts", systemImage: "keyboard") }
            }.padding(12)
            Divider()
            HStack {
                Text(saveMessage.isEmpty ? "\(controller.modelLoaded ? "Model loaded" : "Model not loaded") · no cloud transcription" : saveMessage)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                Spacer()
                Button("Revert") { draft = controller.settings; saveMessage = "" }
                Button("Save settings") {
                    do { try controller.apply(draft); saveMessage = "Settings saved." }
                    catch { saveMessage = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(controller.isBusy)
            }.padding(16)
            if let error = controller.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding([.horizontal, .bottom], 16)
            }
        }.frame(width: 670, height: 650)
        .onChange(of: controller.settings) { _, updated in draft = updated }
    }
    private var general: some View {
        Form {
            Section("Delivery") {
                Toggle("Insert automatically when the original field is unchanged", isOn: $draft.automaticInsertion)
                Toggle("Use clipboard paste when direct insertion is unavailable", isOn: $draft.allowPasteFallback)
                Text("Paste fallback leaves the transcript on your clipboard. It never presses Return. Delivery is recorded as requested, not confirmed.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Allow insertion into recognised terminal applications", isOn: $draft.allowTerminalApps)
                Text("Keep this off unless needed. An embedded terminal inside another app cannot always be identified; use manual-only delivery in that workflow.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Permissions") {
                HStack {
                    Label(AudioRecorder.microphoneGranted ? "Microphone enabled" : "Microphone permission needed", systemImage: "mic")
                    Spacer()
                    Button("Grant") { Task { _ = await AudioRecorder.requestPermission(); permissionsVersion += 1 } }
                    Button("Open settings") { openPrivacy("Privacy_Microphone") }
                }
                HStack {
                    Label(InsertionService.trusted ? "Accessibility enabled" : "Accessibility permission needed for insertion", systemImage: "accessibility")
                    Spacer()
                    Button("Grant") { InsertionService.requestPermission(); permissionsVersion += 1 }
                    Button("Open settings") { openPrivacy("Privacy_Accessibility") }
                }
                Button("Refresh permission status") { permissionsVersion += 1 }
            }.id(permissionsVersion)
            Section("Local storage") {
                Text("Audio and transcripts are retained until you explicitly delete them. Nothing is uploaded for recognition. Model downloads are the only built-in network operation.")
                Text(controller.root.path).font(.caption.monospaced()).textSelection(.enabled)
                Button("Open storage folder") { NSWorkspace.shared.open(controller.root) }
                Text("Files are not encrypted by this app. macOS backups and other software with access to your account may copy them. Use FileVault and manage your backups accordingly.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var model: some View {
        Form {
            Section("Qwen3-ASR · 1.7B · BF16") {
                Text("Full-weight local speech recognition. Download once, then use offline without an API key or subscription.")
                Text("The model stays loaded in a separate helper process between recordings. There is no live transcription or automatic rewriting.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Download model from Hugging Face") { controller.downloadModel() }.disabled(controller.isBusy)
                if controller.phase == .downloading {
                    ProgressView().controlSize(.small)
                    Text(controller.downloadMessage).font(.caption).textSelection(.enabled)
                    Button("Cancel download") { controller.cancelProcessing() }
                }
            }
            Section("Local model folder") {
                TextField("Path to downloaded model files", text: $draft.modelDirectory)
                    .font(.caption.monospaced()).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Choose folder…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        guard panel.runModal() == .OK, let url = panel.url else { return }
                        do { try ModelDirectory.validate(url); draft.modelDirectory = url.path; saveMessage = "Save settings to use this folder." }
                        catch { saveMessage = error.localizedDescription }
                    }
                    Button("Load saved model") { controller.warmModel() }.disabled(controller.isBusy || !controller.modelAvailable)
                    Button("Unload") { controller.unloadModel() }.disabled(controller.isBusy)
                }
                if controller.phase == .loading {
                    HStack { ProgressView().controlSize(.small); Text("Loading local weights…"); Button("Cancel") { controller.cancelProcessing() } }
                }
            }
            Section("Recognition") {
                Picker("Language", selection: $draft.language) {
                    Text("English").tag("English")
                    Text("Automatic detection").tag("")
                    Text("Danish").tag("Danish")
                }
                Stepper("Output token budget: \(draft.tokenBudgetMultiplier)×", value: $draft.tokenBudgetMultiplier, in: 1...4)
                Text("Start at 1×. Increase only when a recording is flagged as hitting its output limit. This does not make a model inherently more accurate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var vocabulary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recognition vocabulary").font(.title3.bold())
            Text("One term or exact spelling per line. These terms are sent to the local recogniser as context, not used as search-and-replace rules.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Picker("Active profile", selection: $draft.selectedProfileID) {
                    Text("General only").tag(nil as UUID?)
                    ForEach(draft.profiles) { profile in Text(profile.name).tag(Optional(profile.id)) }
                }
                Button("Add profile") {
                    let profile = VocabularyProfile(name: "New project", terms: "")
                    draft.profiles.append(profile); editingProfile = profile.id; draft.selectedProfileID = profile.id
                }
            }
            HSplitView {
                VStack(alignment: .leading) {
                    Text("General coding terms").font(.headline)
                    TextEditor(text: $draft.globalTerms).font(.body.monospaced())
                        .border(.quaternary).frame(minHeight: 190)
                }.frame(minWidth: 230)
                VStack(alignment: .leading) {
                    Picker("Edit profile", selection: $editingProfile) {
                        Text("Choose a profile").tag(nil as UUID?)
                        ForEach(draft.profiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if let index = draft.profiles.firstIndex(where: { $0.id == editingProfile }) {
                        TextField("Project name", text: $draft.profiles[index].name).textFieldStyle(.roundedBorder)
                        TextEditor(text: $draft.profiles[index].terms).font(.body.monospaced()).border(.quaternary)
                        Button("Remove this profile") {
                            let id = draft.profiles[index].id
                            draft.profiles.remove(at: index)
                            if draft.selectedProfileID == id { draft.selectedProfileID = nil }
                            editingProfile = nil
                        }
                    } else { Text("Select or add a profile.").foregroundStyle(.secondary); Spacer() }
                }.frame(minWidth: 260).padding(.leading, 12)
            }
            Text("Context preview").font(.caption.bold())
            ScrollView { Text(draft.vocabularyContext.isEmpty ? "No custom vocabulary" : draft.vocabularyContext)
                .font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(height: 70)
            Spacer(minLength: 0)
        }.padding(16)
    }
    private var shortcuts: some View {
        Form {
            Section("Global shortcuts") {
                shortcutRow("Start / stop recording", binding: $draft.recordShortcut)
                shortcutRow("Insert pending transcript", binding: $draft.insertShortcut)
                shortcutRow("Open history", binding: $draft.historyShortcut)
                Text("Click a shortcut, then press the new combination. Include Control, Option or Command. Press Escape to cancel. Shortcuts take effect after Save settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Behaviour") {
                Text("Recording toggles on and off. Pauses never stop it. A waveform is shown while you speak; only the completed recording is transcribed.")
                Text("When focus changes, the transcription is saved rather than pasted into an unexpected destination. Select your intended field and use Insert pending transcript.")
                Text("Shortcuts trigger on key release to avoid repeated toggles while a key is held.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func shortcutRow(_ title: String, binding: Binding<HotKeyBinding>) -> some View {
        HStack { Text(title); Spacer(); ShortcutRecorder(binding: binding).frame(width: 180, height: 30) }
    }
    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var binding: HotKeyBinding
    func makeNSView(context: Context) -> CaptureButton {
        let button = CaptureButton()
        button.onCapture = { value in binding = value }
        button.title = binding.display
        return button
    }
    func updateNSView(_ view: CaptureButton, context: Context) {
        view.onCapture = { value in binding = value }
        view.savedTitle = binding.display
        if !view.armed { view.title = binding.display }
    }
}

private final class CaptureButton: NSButton {
    var onCapture: ((HotKeyBinding) -> Void)?
    var armed = false
    var savedTitle = ""
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded; target = self; action = #selector(arm)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func arm() { armed = true; title = "Press shortcut…"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard armed else { super.keyDown(with: event); return }
        if event.keyCode == 53 { armed = false; title = savedTitle; window?.makeFirstResponder(nil); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.control, .option, .command]).isEmpty else { NSSound.beep(); return }
        var modifiers: UInt32 = 0
        var label = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
        let names: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        label += names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        let result = HotKeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers, display: label)
        armed = false; title = label; savedTitle = label; onCapture?(result); window?.makeFirstResponder(nil)
    }
}
