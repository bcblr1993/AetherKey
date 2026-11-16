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
    
    public var onCandidateAction: ((Int, CandidateAction) -> Void)?
    public var isCandidatePinned: ((Int) -> Bool)?
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
            onCandidateAction: state.onCandidateAction,
            isCandidatePinned: state.isCandidatePinned,
            viewportWidth: state.viewportWidth
        )
        .transaction { $0.animation = nil }
    }
}

/// IMK hosts may return denormal placeholder rectangles or (0, 0) placeholders instead of an actual caret.
enum CandidateCaretGeometry {
    static func isUsable(_ rect: NSRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && !(rect.origin.x == 0 && rect.origin.y == 0)
            && abs(rect.origin.x) < 100_000 && abs(rect.origin.y) < 100_000
            && rect.width >= 0 && rect.width < 10_000
            && rect.height >= 1 && rect.height <= 512
    }

    static func effectiveWindowLevel(for clientWindowLevel: CGWindowLevel?) -> NSWindow.Level {
        let baseLevel = NSWindow.Level.popUpMenu.rawValue
        guard let clientWindowLevel, Int(clientWindowLevel) >= baseLevel else {
            return .popUpMenu
        }
        let maxLevel = Int(CGWindowLevelForKey(.maximumWindow)) - 1
        return NSWindow.Level(rawValue: min(maxLevel, Int(clientWindowLevel) + 1))
    }
}

/// Anchor to the composition start on the current line; only re-anchor on line wraps or screen changes.
struct CandidatePanelPlacement {
    private(set) var anchor: NSRect?
    private(set) var isAbove: Bool?

    mutating func reset() {
        anchor = nil
        isAbove = nil
    }

    mutating func frame(caret: NSRect, size: NSSize, screen: NSRect) -> NSRect {
        if let previous = anchor {
            let lineChanged = abs(caret.minY - previous.minY) >= max(12, previous.height * 0.6)
            let screenChanged = !screen.insetBy(dx: -32, dy: -32).contains(previous.origin)
            if lineChanged || screenChanged {
                anchor = caret
                isAbove = nil
            }
        } else {
            anchor = caret
        }
        let anchorCaret = anchor ?? caret
        let margin: CGFloat = 8
        let gap: CGFloat = 7
        let width = min(size.width, max(1, screen.width - margin * 2))
        let height = min(size.height, max(1, screen.height - margin * 2))
        if isAbove == nil {
            // Reserve room for two rows at the start, avoiding a side flip on expansion.
            let reservedHeight = max(height, 119)
            let spaceBelow = anchorCaret.minY - screen.minY - gap - margin
            let spaceAbove = screen.maxY - anchorCaret.maxY - gap - margin
            isAbove = spaceBelow < reservedHeight && spaceAbove > spaceBelow
        }
        let y = isAbove == true ? anchorCaret.maxY + gap : anchorCaret.minY - height - gap
        return NSRect(
            x: min(max(anchorCaret.minX, screen.minX + margin), screen.maxX - width - margin),
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
    private var sessionMinWidth: CGFloat = 0
    private var lastMeasuredViewMode: CandidateViewMode? = nil
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

    static func targetScreen(for caretRect: NSRect) -> NSScreen? {
        let probe = NSRect(
            x: caretRect.origin.x,
            y: caretRect.origin.y,
            width: max(1, caretRect.width),
            height: max(1, caretRect.height)
        )
        if let containing = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).intersects(probe) }) {
            return containing
        }
        if !NSScreen.screens.isEmpty {
            return NSScreen.screens.min(by: { lhs, rhs in
                squaredDistance(from: caretRect.origin, to: lhs.frame) < squaredDistance(from: caretRect.origin, to: rhs.frame)
            })
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private static func squaredDistance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = point.x < rect.minX ? rect.minX - point.x : (point.x > rect.maxX ? point.x - rect.maxX : 0)
        let dy = point.y < rect.minY ? rect.minY - point.y : (point.y > rect.maxY ? point.y - rect.maxY : 0)
        return dx * dx + dy * dy
    }

    /// Resets the locked line anchor and width floor (e.g. after partial prefix commit).
    public func resetAnchor() {
        placement.reset()
        sessionMinWidth = 0
        lastMeasuredViewMode = nil
    }

    /// Measure the mounted content synchronously, then place it without a window resize animation.
    public func updatePosition(caretRect: NSRect) {
        let targetScreen = Self.targetScreen(for: caretRect)
        let screen = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        if lastMeasuredViewMode != state.viewMode {
            sessionMinWidth = 0
            lastMeasuredViewMode = state.viewMode
        }
        let maximum = max(1, min(640, screen.width - 26))
        // Fit the actual candidate content, keeping width monotonic within the same composition session & view mode.
        let measuredWidth = CandidatePanelMetrics.contentWidth(
            candidates: state.candidates, viewMode: state.viewMode,
            pinyin: state.displayPinyin.isEmpty ? state.inputString : state.displayPinyin,
            mode: state.mode, currentPage: state.currentPage, totalPages: state.totalPages,
            maximum: maximum
        )
        let width = min(maximum, max(sessionMinWidth, measuredWidth))
        sessionMinWidth = width
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
    public func show(caretRect: NSRect, clientWindowLevel: CGWindowLevel? = nil) {
        StatusHUDHolder.shared.hideImmediately()
        let desiredLevel = CandidateCaretGeometry.effectiveWindowLevel(for: clientWindowLevel)
        if self.level != desiredLevel { self.level = desiredLevel }
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
        resetAnchor()
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

/// Observable state backing the lightweight mode/punctuation switch HUD capsule.
@MainActor
public final class StatusHUDState: ObservableObject {
    @Published public var badge: String = "中"
    @Published public var title: String = "中文输入"
    @Published public var isAccent: Bool = true
    @Published public var showCount: Int = 0

    public init() {}
}

@MainActor
public enum StatusHUDHolder {
    public static let shared = StatusHUDPanel()
}

struct StatusHUDView: View {
    @ObservedObject var state: StatusHUDState

    var body: some View {
        LiquidGlassContainer(cornerRadius: 10) {
            HStack(spacing: 6) {
                Text(state.badge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(state.isAccent ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22, minHeight: 20)
                    .background(
                        (state.isAccent ? Color.accentColor : Color.primary).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                Text(state.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.88))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .fixedSize()
        }
        .fixedSize()
        .transaction { $0.animation = nil }
    }
}

/// Non-activating floating status capsule shown briefly beside the caret on mode/punctuation switches.
public final class StatusHUDPanel: NSPanel, @unchecked Sendable {
    public let state = StatusHUDState()
    private var hostingView: NSHostingView<StatusHUDView>!
    private var generation = 0
    private var hideWorkItem: DispatchWorkItem?
    private var fadeTimer: DispatchSourceTimer?

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 110, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        setupPanel()
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    private func setupPanel() {
        isFloatingPanel = true
        level = .popUpMenu
        ignoresMouseEvents = true
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let root = StatusHUDView(state: state)
        hostingView = NSHostingView(rootView: root)
        hostingView.wantsLayer = true
        hostingView.layer?.drawsAsynchronously = true
        contentView = hostingView
    }

    public func show(badge: String, title: String, isAccent: Bool = true, anchorRect: NSRect?, clientWindowLevel: CGWindowLevel? = nil) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        fadeTimer?.cancel()
        fadeTimer = nil
        generation += 1
        let currentGeneration = generation

        let desiredLevel = CandidateCaretGeometry.effectiveWindowLevel(for: clientWindowLevel)
        if self.level != desiredLevel { self.level = desiredLevel }

        state.badge = badge
        state.title = title
        state.isAccent = isAccent
        state.showCount += 1

        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let mouse = NSEvent.mouseLocation
        let caret = (anchorRect.flatMap { CandidateCaretGeometry.isUsable($0) ? $0 : nil })
            ?? NSRect(x: mouse.x, y: mouse.y, width: 0, height: 22)
        let screen = CandidatePanel.targetScreen(for: caret)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let margin: CGFloat = 8
        let gap: CGFloat = 7
        let showAbove = (caret.minY - screen.minY - gap - margin) < size.height
            && (screen.maxY - caret.maxY - gap - margin) > (caret.minY - screen.minY - gap - margin)
        let rawY = showAbove ? caret.maxY + gap : caret.minY - size.height - gap
        let frameRect = NSRect(
            x: min(max(caret.minX, screen.minX + margin), screen.maxX - size.width - margin),
            y: min(max(rawY, screen.minY + margin), screen.maxY - size.height - margin),
            width: size.width,
            height: size.height
        )
        if frame != frameRect { setFrame(frameRect, display: true, animate: false) }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !isVisible { alphaValue = reduceMotion ? 1 : 0 }
        orderFrontRegardless()
        fade(to: 1, duration: reduceMotion ? 0 : 0.09, generation: currentGeneration)

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            let dur = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
            self.fade(to: 0, duration: dur, generation: currentGeneration) { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.orderOut(nil)
                self.alphaValue = 1
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
    }

    public func hideImmediately() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        fadeTimer?.cancel()
        fadeTimer = nil
        generation += 1
        if isVisible {
            orderOut(nil)
            alphaValue = 1
        }
    }

    private func fade(to target: CGFloat, duration: TimeInterval, generation expectedGen: Int, completion: (() -> Void)? = nil) {
        fadeTimer?.cancel()
        fadeTimer = nil
        guard duration > 0 else {
            alphaValue = target
            completion?()
            return
        }
        let initialAlpha = alphaValue
        let start = CACurrentMediaTime()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        fadeTimer = timer
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            guard let self, self.generation == expectedGen else { return }
            let progress = min(1, (CACurrentMediaTime() - start) / duration)
            let eased = 1 - pow(1 - progress, 3)
            self.alphaValue = initialAlpha + (target - initialAlpha) * eased
            if progress >= 1 {
                self.fadeTimer?.cancel()
                self.fadeTimer = nil
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
