import AppKit
import SwiftUI

/// Observable state model powering CandidatePanel UI.
public final class CandidateState: ObservableObject, @unchecked Sendable {
    @Published public var inputString: String = ""
    @Published public var mode: InputMode = .chinese
    @Published public var candidates: [Candidate] = []
    @Published public var selectedIndex: Int = 0
    @Published public var currentPage: Int = 1
    @Published public var totalPages: Int = 1
    @Published public var isVisible: Bool = false
    
    public init() {}
}

/// Root container view hosting CandidateListView with fast 80ms scale & fade transitions.
public struct CandidatePanelRootView: View {
    @ObservedObject public var state: CandidateState

    public init(state: CandidateState) {
        self.state = state
    }

    public var body: some View {
        ZStack {
            if state.isVisible {
                CandidateListView(
                    inputString: state.inputString,
                    mode: state.mode,
                    candidates: state.candidates,
                    selectedIndex: state.selectedIndex,
                    currentPage: state.currentPage,
                    totalPages: state.totalPages
                )
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.98).combined(with: .opacity),
                        removal: .scale(scale: 0.98).combined(with: .opacity)
                    )
                )
            }
        }
        .animation(.easeOut(duration: 0.08), value: state.isVisible)
    }
}

/// High-performance floating candidate panel conforming to system IME non-activating guidelines.
public final class CandidatePanel: NSPanel, @unchecked Sendable {
    public let state = CandidateState()
    private var hostingView: NSHostingView<CandidatePanelRootView>!
    private var dismissWorkItem: DispatchWorkItem?

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
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        
        let root = CandidatePanelRootView(state: state)
        self.hostingView = NSHostingView(rootView: root)
        self.hostingView.wantsLayer = true
        self.hostingView.layer?.drawsAsynchronously = true
        self.contentView = hostingView
    }

    /// Positions and displays the candidate panel below or above the host caret with boundary clipping.
    public func updatePosition(caretRect: NSRect) {
        // Query required panel size from hosting view
        let fittingSize = hostingView.fittingSize
        let panelWidth = max(fittingSize.width, 160)
        let panelHeight = max(fittingSize.height, 56)
        
        // Find screen enclosing the caret
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(caretRect.origin) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        
        let screenFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        
        // Default: display right below caret line
        var targetX = caretRect.origin.x
        var targetY = caretRect.origin.y - panelHeight - 6
        
        // Boundary check: If panel extends below screen bottom, flip to above caret
        if targetY < screenFrame.minY {
            let caretHeight = caretRect.height > 0 ? caretRect.height : 22
            targetY = caretRect.origin.y + caretHeight + 6
        }
        
        // Boundary check: horizontal clamping
        if targetX + panelWidth > screenFrame.maxX - 10 {
            targetX = screenFrame.maxX - panelWidth - 10
        }
        if targetX < screenFrame.minX + 10 {
            targetX = screenFrame.minX + 10
        }
        
        let newFrame = NSRect(x: targetX, y: targetY, width: panelWidth, height: panelHeight)
        self.setFrame(newFrame, display: true)
    }

    /// Presents panel with 80ms snappy transition.
    public func show(caretRect: NSRect) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        
        updatePosition(caretRect: caretRect)
        state.isVisible = true
        self.orderFrontRegardless()
    }

    /// Hides panel with 80ms fast fade and orders out once transition concludes.
    public func dismiss() {
        state.isVisible = false
        
        dismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.state.isVisible else { return }
            self.orderOut(nil)
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: work)
    }
}
