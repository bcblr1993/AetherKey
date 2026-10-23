import SwiftUI
import AppKit

/// AppKit NSVisualEffectView wrapper with hardware-accelerated layer configuration
public struct VisualEffectBlur: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode
    public let state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        view.layer?.drawsAsynchronously = true
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

/// A restrained material surface that follows the system appearance and accessibility settings.
public struct LiquidGlassContainer<Content: View>: View {
    public let cornerRadius: CGFloat
    public let content: Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(cornerRadius: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .background {
                ZStack {
                    if reduceTransparency {
                        Color(nsColor: .windowBackgroundColor)
                    } else {
                        VisualEffectBlur(material: .popover)
                        Color(nsColor: .windowBackgroundColor).opacity(0.55)
                    }
                    LinearGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.035 : 0.25), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.10), lineWidth: 0.5)
            }
    }
}

/// Single-color reduction of the floating key A mark, shared by the menu and input-source resources.
public enum AetherMenuBarIcon {
    public static func draw(in rect: NSRect, color: NSColor = .black) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let side = min(rect.width, rect.height)
        (AffineTransform(translationByX: rect.midX - side / 2, byY: rect.midY - side / 2) as NSAffineTransform).concat()
        (AffineTransform(scaleByX: side / 100, byY: side / 100) as NSAffineTransform).concat()
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: 19, y: 19))
        outline.line(to: NSPoint(x: 46, y: 80))
        outline.line(to: NSPoint(x: 53, y: 80))
        outline.line(to: NSPoint(x: 81, y: 19))
        outline.lineWidth = 11
        outline.lineCapStyle = .round
        outline.lineJoinStyle = .round
        color.setStroke()
        outline.stroke()
        let bar = NSBezierPath()
        bar.move(to: NSPoint(x: 35, y: 39))
        bar.line(to: NSPoint(x: 66, y: 39))
        bar.lineWidth = 9
        bar.lineCapStyle = .round
        bar.stroke()
    }

    public static func image(size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AetherKey"
        return image
    }
}
