import AppKit
import SwiftUI
import QuartzCore

/// Observable state model powering CandidatePanel UI.
public final class CandidateState: ObservableObject, @unchecked Sendable {
    @Published public var inputString: String = ""
    @Published public var displayPinyin: String = ""
    @Published public var mode: InputMode = .chinese
    @Published public var viewMode: CandidateViewMode = .paging
    @Published public var candidates: [Candidate] = []
    @Published public var selectedIndex: Int = 0
    @Published public var currentPage: Int = 1
    @Published public var totalPages: Int = 1
    @Published public var isVisible: Bool = false
    @Published public var viewportWidth: CGFloat? = nil
    
    public var onSelectCandidate: ((Int) -> Void)?
    public var onToggleViewMode: (() -> Void)?
    public var onPageDelta: ((Int) -> Void)?
    
    public init() {}
}

/// Keep the view mounted so measuring the next frame never sees an empty transition.
public struct CandidatePanelRootView: View {
    @ObservedObject public var state: CandidateState

    public init(state: CandidateState) { self.state = state }

    public var body: some View {
        CandidateListView(
            inputString: state.inputString,
            displayPinyin: state.displayPinyin,
            mode: state.mode,
            viewMode: state.viewMode,
            candidates: state.candidates,
            selectedIndex: state.selectedIndex,
            currentPage: state.currentPage,
            totalPages: state.totalPages,
            onSelectCandidate: state.onSelectCandidate,
            onToggleViewMode: state.onToggleViewMode,
            onPageDelta: state.onPageDelta,
            viewportWidth: state.viewportWidth
        )
        .transaction { $0.animation = nil }
    }
}

/// IMK hosts may return denormal placeholder rectangles instead of an actual caret.
enum CandidateCaretGeometry {
    static func isUsable(_ rect: NSRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && abs(rect.origin.x) < 100_000 && abs(rect.origin.y) < 100_000
            && rect.width >= 0 && rect.width < 10_000
            && rect.height >= 1 && rect.height <= 512
    }
}

/// Follow the insertion caret while retaining the chosen side on the same line.
struct CandidatePanelPlacement {
    private(set) var anchor: NSRect?
    private(set) var isAbove: Bool?

    mutating func frame(caret: NSRect, size: NSSize, screen: NSRect) -> NSRect {
        // Never lock coordinates: every valid host caret update moves the popup.
        // Keep the chosen side on the same line, rather than locking its coordinates.
        if let previous = anchor {
            if abs(caret.minY - previous.minY) >= max(12, previous.height * 0.6) {
                isAbove = nil
            }
            anchor = caret
        } else {
            anchor = caret
        }
        let caret = anchor ?? caret
        let margin: CGFloat = 8
        let gap: CGFloat = 7
        let width = min(size.width, max(1, screen.width - margin * 2))
        let height = min(size.height, max(1, screen.height - margin * 2))
        if isAbove == nil {
            // Reserve room for two rows at the start, avoiding a side flip on expansion.
            let reservedHeight = max(height, 119)
            let spaceBelow = caret.minY - screen.minY - gap - margin
            let spaceAbove = screen.maxY - caret.maxY - gap - margin
            isAbove = spaceBelow < reservedHeight && spaceAbove > spaceBelow
        }
        let y = isAbove == true ? caret.maxY + gap : caret.minY - height - gap
        return NSRect(
            x: min(max(caret.minX, screen.minX + margin), screen.maxX - width - margin),
            y: min(max(y, screen.minY + margin), screen.maxY - height - margin),
            width: width, height: height
        )
    }
}

/// High-performance floating candidate panel conforming to system IME non-activating guidelines.
public final class CandidatePanel: NSPanel, @unchecked Sendable {
    public let state = CandidateState()
    private var hostingView: NSHostingView<CandidatePanelRootView>!
    private var placement = CandidatePanelPlacement()
    private var presentationGeneration = 0
    private var fadeTimer: DispatchSourceTimer?
    private var fadeCompletion: (() -> Void)?

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        
        setupPanel()
    }

    public override var canBecomeKey: Bool {
        return false
    }

    public override var canBecomeMain: Bool {
        return false
    }
    
    private func setupPanel() {
        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.isMovableByWindowBackground = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.animationBehavior = .none
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        
        let root = CandidatePanelRootView(state: state)
        self.hostingView = NSHostingView(rootView: root)
        self.hostingView.wantsLayer = true
        self.hostingView.layer?.drawsAsynchronously = true
        self.contentView = hostingView
    }

    /// Measure the mounted content synchronously, then place it without a window resize animation.
    public func updatePosition(caretRect: NSRect) {
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(caretRect.origin) })
            ?? NSScreen.main ?? NSScreen.screens.first
        let screen = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        // Fit the actual candidate content; position still comes from the accepted caret path.
        let width = CandidatePanelMetrics.contentWidth(
            candidates: state.candidates, viewMode: state.viewMode,
            pinyin: state.displayPinyin.isEmpty ? state.inputString : state.displayPinyin,
            mode: state.mode, currentPage: state.currentPage, totalPages: state.totalPages,
            maximum: max(1, min(640, screen.width - 26))
        )
        if state.viewportWidth != width { state.viewportWidth = width }
        hostingView.layoutSubtreeIfNeeded()
        let size = NSSize(width: width + CandidatePanelMetrics.outerPadding * 2,
                          height: CandidatePanelMetrics.height(for: state.viewMode))
        let target = placement.frame(caret: caretRect, size: size, screen: screen)
        if frame != target { setFrame(target, display: true, animate: false) }
        CandidateGeometryDiagnostics.record([
            "stage": "panel", "caret": NSStringFromRect(caretRect),
            "frame": NSStringFromRect(target), "screen": NSStringFromRect(screen)
        ])
    }

    /// Fade only on a new presentation; typing and page changes update in place.
    public func show(caretRect: NSRect) {
        let wasVisible = state.isVisible
        state.isVisible = true
        updatePosition(caretRect: caretRect)
        guard !wasVisible else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Continue from the current opacity if a new composition interrupts dismissal.
        if !isVisible { alphaValue = reduceMotion ? 1 : 0 }
        orderFrontRegardless()
        fade(to: 1, duration: reduceMotion ? 0 : 0.13)
    }

    public func dismiss() {
        guard state.isVisible else { return }
        state.isVisible = false
        placement = CandidatePanelPlacement()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        fade(to: 0, duration: reduceMotion ? 0 : 0.08) { [weak self] in
            guard let self, !self.state.isVisible else { return }
            self.orderOut(nil)
            self.alphaValue = 1
        }
    }

    // Explicitly cancel the previous fade. Overlapping NSWindow animator proxies can
    // otherwise finish an old fade-out after a new composition has already appeared.
    private func fade(to target: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil) {
        fadeTimer?.cancel()
        fadeTimer = nil
        fadeCompletion = completion
        presentationGeneration += 1
        guard duration > 0 else {
            alphaValue = target
            fadeCompletion = nil
            completion?()
            return
        }
        let generation = presentationGeneration
        let initialAlpha = alphaValue
        let start = CACurrentMediaTime()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        fadeTimer = timer
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            let progress = min(1, (CACurrentMediaTime() - start) / duration)
            let eased = 1 - pow(1 - progress, 3)
            self.alphaValue = initialAlpha + (target - initialAlpha) * eased
            if progress >= 1 {
                self.fadeTimer?.cancel()
                self.fadeTimer = nil
                let completion = self.fadeCompletion
                self.fadeCompletion = nil
                completion?()
            }
        }
        timer.resume()
    }
}

/// Opt-in, bounded coordinate-only tracing for diagnosing host input-client differences.
/// No input strings, candidate text, document contents, or window titles are recorded.
enum CandidateGeometryDiagnostics {
    static var enabled: Bool {
        NSClassFromString("XCTestCase") == nil
            && ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil
            && UserDefaults.standard.string(forKey: "AetherKeyGeometryLog") != nil
    }

    static func record(_ values: [String: String]) {
        guard enabled, let path = UserDefaults.standard.string(forKey: "AetherKeyGeometryLog") else { return }
        let url = URL(fileURLWithPath: path)
        var values = values
        values["time"] = String(Date().timeIntervalSince1970)
        guard var data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return }
        data.append(10)
        do {
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            let size = try file.seekToEnd()
            if size > 131072 { try file.truncate(atOffset: 0); try file.seek(toOffset: 0) }
            try file.write(contentsOf: data)
        } catch { /* Diagnostics must never interrupt text input. */ }
    }
}
