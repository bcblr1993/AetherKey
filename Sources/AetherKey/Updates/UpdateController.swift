import AppKit
import Combine
import Sparkle

/// Updates only the installed input-method bundle; dictionaries live outside it.
@MainActor
public final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    public static let shared = UpdateController()
    public static let checkInterval: TimeInterval = 6 * 60 * 60
    public static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.3" }
    public enum State { case notChecked, checking, current, available, failed }
    private var controller: SPUStandardUpdaterController?
    private var cancellables = Set<AnyCancellable>()
    @Published public private(set) var canCheckForUpdates = false
    @Published public private(set) var state: State = .notChecked
    @Published public private(set) var availableVersion: String?
    @Published public private(set) var lastCheckedAt: Date?
    @Published public private(set) var nextCheckAt: Date?
    @Published public var automaticallyChecksForUpdates = true {
        didSet {
            controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            if !automaticallyChecksForUpdates { nextCheckAt = nil }
        }
    }

    public func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.updateCheckInterval = Self.checkInterval
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        lastCheckedAt = controller.updater.lastUpdateCheckDate
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)
        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.lastCheckedAt = $0 }
            .store(in: &cancellables)
    }

    @objc public func checkForUpdates() {
        start()
        guard canCheckForUpdates else { return }
        state = .checking
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        state = .available
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableVersion = nil
        state = .current
    }

    public func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        nextCheckAt = Date().addingTimeInterval(delay)
    }

    public func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if error != nil, state != .available, state != .current { state = .failed }
    }
}
