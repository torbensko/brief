import SwiftUI
import AppKit
import Carbon.HIToolbox
import DictationCore

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @State private var draft: AppSettings
    @State private var saveMessage = ""
    @State private var permissionsVersion = 0
    @State private var repositoryPath = ""
    init(controller: AppController) {
        self.controller = controller
        _draft = State(initialValue: controller.settings)
        _repositoryPath = State(initialValue: controller.settings.effectiveRepositoriesPath)
    }
    var body: some View {
        VStack(spacing: 0) {
            TabView {
                general.tabItem { Label("General", systemImage: "slider.horizontal.3") }
                model.tabItem { Label("Model", systemImage: "cpu") }
                vocabulary.tabItem { Label("Recognition", systemImage: "chevron.left.forwardslash.chevron.right") }
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
        .onChange(of: controller.settings) { previous, updated in
            // A background scan must not erase unsaved edits in other settings tabs.
            draft.repositoryVocabulary = updated.repositoryVocabulary
            draft.repositoriesPath = updated.repositoriesPath
            draft.recoveryPolicy = updated.recoveryPolicy
            if updated.modelDirectory != previous.modelDirectory { draft.modelDirectory = updated.modelDirectory }
        }
    }
    private var general: some View {
        Form {
            Section("Delivery") {
                InsertionPermissionNotice(automaticInsertion: draft.automaticInsertion) {
                    InsertionService.requestPermission()
                    openPrivacy("Privacy_Accessibility")
                }
                Text("Automatic insertion needs macOS Accessibility access. Microphone access alone only enables recording.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Insert automatically when the original field is unchanged", isOn: $draft.automaticInsertion)
                Toggle("Use standard paste for insertion (recommended)", isOn: $draft.allowPasteFallback)
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
                Text("Recent dictation is a recovery buffer. By default it keeps the latest entry; change the count or time limit at the top of Recent. Older audio and text are automatically deleted. Recognition stays local.")
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
        Form {
            Section("Recognize your project names") {
                Text("Names like Blint help dictation recognize the projects you talk about.")
                Text("Project names and a small curated coding vocabulary guide recognition together. Refreshed locally when the app opens.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Your repositories") {
                HStack {
                    TextField("Repositories folder", text: $repositoryPath).textFieldStyle(.roundedBorder)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true; panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            repositoryPath = url.path
                            controller.scanRepositories(path: repositoryPath)
                        }
                    }.disabled(controller.scanningRepositories)
                }
                HStack {
                    Button("Scan repositories") { controller.scanRepositories(path: repositoryPath) }
                        .disabled(controller.scanningRepositories || repositoryPath.trimmingCharacters(in: .whitespaces).isEmpty)
                    if controller.scanningRepositories { ProgressView().controlSize(.small) }
                    Text(controller.repositoryScanMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text("Finds the main name of each project. Duplicate worktrees are combined. Results are saved automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let catalog = controller.settings.repositoryVocabulary {
                Section("Your project dictionary") {
                    Text("\(catalog.names.count) project names")
                        .font(.headline)
                    Text("Last scanned \(catalog.scannedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(catalog.names.joined(separator: ", ")).textSelection(.enabled)
                    if !catalog.warnings.isEmpty {
                        DisclosureGroup("Scan notes (\(catalog.warnings.count))") {
                            Text(catalog.warnings.joined(separator: "\n")).font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
            Section("Coding disambiguation") {
                Text("Helps recognize terms such as JSON in coding speech. These are spelling hints, not automatic replacements for names like Jason.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Project types: " + (controller.settings.repositoryVocabulary?.projectTypes.joined(separator: ", ") ?? "Scanning…"))
                    .font(.caption)
                DisclosureGroup("Recognition hints") {
                    Text(CodingVocabulary.terms(for: controller.settings.repositoryVocabulary?.projectTypes ?? []).joined(separator: ", "))
                        .font(.caption).textSelection(.enabled)
                }
            }
            Section("Optional extra spellings") {
                Text("Optional: add a name or spelling the scan missed.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $draft.globalTerms).font(.body.monospaced()).frame(minHeight: 65)
                if !draft.profiles.isEmpty {
                    Text("Your earlier profile terms are also included across all recordings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped)
    }
    private var shortcuts: some View {
        Form {
            Section("Global shortcuts") {
                Picker("Recording gesture", selection: Binding(get: { draft.effectiveRecordingMode }, set: { draft.recordingMode = $0 })) {
                    Text("Hold to dictate").tag(RecordingMode.hold)
                    Text("Press to start / press to stop").tag(RecordingMode.toggle)
                }
                shortcutRow("Dictate", binding: $draft.recordShortcut)
                shortcutRow("Insert pending transcript", binding: $draft.insertShortcut)
                shortcutRow("Open history", binding: $draft.historyShortcut)
                Text("Click a shortcut, then press the new combination. Include Control, Option or Command. Press Escape to cancel. Shortcuts take effect after Save settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Behaviour") {
                Text("Hold mode records while the shortcut is held; release to finish. Toggle mode starts and stops with separate presses. Pauses never stop recording. A waveform is shown while you speak; only the completed recording is transcribed.")
                Text("When focus changes, the transcription is saved rather than pasted into an unexpected destination. Select your intended field and use Insert pending transcript.")
                Text("Hold mode starts on key press. Toggle and other shortcuts act on release; holding a key never repeats the action.")
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
