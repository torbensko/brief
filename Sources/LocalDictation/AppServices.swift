import AppKit
import Combine
import ServiceManagement
import Sparkle

@MainActor
final class AppServices: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppServices()
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticChecks = true
    @Published private(set) var automaticDownloads = true
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginNeedsApproval = false
    @Published var serviceError: String?
    private var updaterController: SPUStandardUpdaterController?
    private var isBusy: () -> Bool = { false }
    var isInstalled: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
    func start(isBusy: @escaping () -> Bool) {
        self.isBusy = isBusy
        refreshLoginStatus()
        guard isInstalled, updaterController == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        updaterController = controller
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main)
            .assign(to: &$automaticChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).receive(on: RunLoop.main)
            .assign(to: &$automaticDownloads)
    }
    func checkForUpdates() { updaterController?.checkForUpdates(nil) }
    func setAutomaticChecks(_ enabled: Bool) { updaterController?.updater.automaticallyChecksForUpdates = enabled }
    func setAutomaticDownloads(_ enabled: Bool) { updaterController?.updater.automaticallyDownloadsUpdates = enabled }
    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }
    func setStartAtLogin(_ enabled: Bool) {
        guard isInstalled else { serviceError = "Move Brief to Applications before enabling Start at login."; return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            serviceError = nil
        } catch { serviceError = error.localizedDescription }
        refreshLoginStatus()
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard isBusy() else { return false }
        Task { @MainActor in
            while isBusy() { try? await Task.sleep(for: .seconds(1)) }
            installHandler()
        }
        return true
    }
}
