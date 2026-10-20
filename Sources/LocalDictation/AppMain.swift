import AppKit
import SwiftUI
import DictationCore

@main
struct LocalDictationApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--recognition-context") {
            do {
                let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                let settings = try SettingsFile.load(from: root.appendingPathComponent("LocalDictation/settings.json"))
                print(settings.vocabularyContext)
            } catch { fputs("Could not read recognition context: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: AppController?
    private var statusItem: NSStatusItem?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var overlay: RecordingPanel?
    private var overlayPresentation = 0
    private var terminating = false
    private var previewRoot: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let preview = CommandLine.arguments.contains("--preview-recovery") || CommandLine.arguments.contains("--preview-card")
            if preview { previewRoot = FileManager.default.temporaryDirectory.appendingPathComponent("LocalDictation-preview-" + UUID().uuidString) }
            let controller = try AppController(storageRoot: previewRoot)
            self.controller = controller
            installMainMenu()
            controller.showHistory = { [weak self] in self?.showHistory() }
            controller.showSettings = { [weak self] in self?.showSettings() }
            controller.showOverlay = { [weak self] in self?.showOverlay() }
            controller.fadeOverlay = { [weak self] in self?.fadeOverlay() }
            controller.hideOverlay = { [weak self] in self?.overlay?.orderOut(nil) }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Brief")
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
            Task {
                if preview {
                    var session = DictationSession(sampleRate: 16_000, profileName: "Preview", vocabulary: "Blint, JSON")
                    session.audioDeleted = true
                    try? await controller.store.create(session)
                    try? await controller.store.appendAttempt(TranscriptAttempt(text: "In Blint, let the agent save the specification as a JSON document. Do not delete the existing file.", model: "UI preview — not a recognition result", vocabulary: "Blint, JSON", processingSeconds: 0, audioSeconds: 0, generationTokens: 0), to: session.id)
                    await controller.refreshHistory()
                    if !CommandLine.arguments.contains("--preview-card") { self.showHistory() }
                    // Keep the synthetic preview visible for layout and drag inspection.
                    self.showOverlay()
                } else {
                    await controller.bootstrap()
                    if CommandLine.arguments.contains("--show-settings") { self.showSettings() }
                }
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func installMainMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Brief")
        let quitItem = NSMenuItem(title: "Quit Brief", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [
            ("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")
        ] {
            edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        editItem.submenu = edit
        main.addItem(editItem)
        let windowItem = NSMenuItem()
        let windows = NSMenu(title: "Window")
        let history = NSMenuItem(title: "Recent dictation", action: #selector(showHistory), keyEquivalent: "h")
        history.keyEquivalentModifierMask = [.command, .shift]
        history.target = self
        windows.addItem(history)
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        windows.addItem(settings)
        windows.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windows
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let controller else { return }
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector?, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        add(AppVersion.display, nil, enabled: false)
        add(controller.message, nil, enabled: false)
        add(controller.modelLoaded ? "Model loaded" : "Model not loaded", nil, enabled: false)
        menu.addItem(.separator())
        add(controller.phase == .recording ? "Stop recording" : "Record", #selector(record),
            enabled: !controller.isBusy || controller.phase == .recording)
        add("Insert pending", #selector(insert), enabled: !controller.isBusy && controller.pendingSession != nil)
        add("Recent dictation", #selector(showHistory))
        add("Show last text", #selector(showLatest), enabled: controller.latestTranscript != nil)
        add("Settings…", #selector(showSettings))
        add("View latest release…", #selector(showReleases))
        menu.addItem(.separator())
        add("Quit Brief", #selector(quit))
    }

    @objc private func record() { controller?.toggleRecording() }
    @objc private func insert() { controller?.insertPending() }
    @objc private func showLatest() { controller?.showLatestTranscript() }
    @objc private func showReleases() {
        NSWorkspace.shared.open(URL(string: "https://github.com/torbensko/brief/releases/latest")!)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showHistory() {
        guard let controller else { return }
        if historyWindow == nil {
            historyWindow = window(title: "Brief — Recent", content: HistoryView(controller: controller))
        }
        activate(historyWindow)
    }
    @objc private func showSettings() {
        guard let controller else { return }
        if settingsWindow == nil {
            settingsWindow = window(title: "Brief — Settings", content: SettingsView(controller: controller))
        }
        activate(settingsWindow)
    }
    private func window<V: View>(title: String, content: V) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
    private func activate(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    private func showOverlay() {
        guard let controller else { return }
        if overlay == nil {
            let panel = RecordingPanel(contentRect: NSRect(x: 0, y: 0, width: 482, height: 228),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.restorePosition()
            panel.contentView = FirstMouseHostingView(rootView: RecordingOverlay(controller: controller) { [weak panel] height in
                panel?.resizeToContent(height)
            })
            panel.title = "Latest dictation"
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            overlay = panel
        }
        if let overlay {
            overlayPresentation += 1
            overlay.alphaValue = 1
            overlay.resizeToContent(overlay.frame.height)
            overlay.orderFrontRegardless()
        }
    }
    private func fadeOverlay() {
        guard let overlay else { return }
        let presentation = overlayPresentation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            overlay.animator().alphaValue = 0
        } completionHandler: { [weak self, weak overlay] in
            guard let self, self.overlayPresentation == presentation else { return }
            overlay?.orderOut(nil)
            overlay?.alphaValue = 1
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating, let controller else { return .terminateNow }
        terminating = true
        Task {
            await controller.shutdown()
            if let previewRoot { try? FileManager.default.removeItem(at: previewRoot) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
