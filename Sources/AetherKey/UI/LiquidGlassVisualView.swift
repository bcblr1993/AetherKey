import SwiftUI
import CoreText
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

/// AetherKey brand: Apple continuous squircle keycap with sculpted Kinetic Ribbon A cutout.
public enum AetherMenuBarIcon {
    /// Pure boolean vector path in top-left 24×24 optical coordinate space.
    public static var vectorPath: CGPath { makeVectorPath() }

    private static func makeVectorPath() -> CGPath {
        let badge = continuousSquircle(in: CGRect(x: 2.0, y: 2.0, width: 20.0, height: 20.0), radius: 5.0)

        let legs = CGMutablePath()
        legs.move(to: CGPoint(x: 6.2, y: 17.8))
        legs.addCurve(
            to: CGPoint(x: 13.5, y: 6.2),
            control1: CGPoint(x: 7.8, y: 12.8),
            control2: CGPoint(x: 10.6, y: 7.0)
        )
        legs.addCurve(
            to: CGPoint(x: 16.9, y: 17.8),
            control1: CGPoint(x: 14.9, y: 5.8),
            control2: CGPoint(x: 16.0, y: 12.2)
        )
        let legsOutline = legs.copy(strokingWithWidth: 2.75, lineCap: .round, lineJoin: .round, miterLimit: 4)

        let waveBar = CGMutablePath()
        waveBar.move(to: CGPoint(x: 6.4, y: 14.55))
        waveBar.addCurve(
            to: CGPoint(x: 18.0, y: 12.35),
            control1: CGPoint(x: 9.8, y: 13.35),
            control2: CGPoint(x: 14.0, y: 14.05)
        )
        let barOutline = waveBar.copy(strokingWithWidth: 2.35, lineCap: .round, lineJoin: .round, miterLimit: 4)

        return badge.subtracting(legsOutline.union(barOutline))
    }

    private static func continuousSquircle(in rect: CGRect, radius: CGFloat) -> CGPath {
        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY
        let r = min(radius, min(rect.width, rect.height) * 0.45)
        let ext = r * 1.28
        let handle = r * 0.56

        let path = CGMutablePath()
        path.move(to: CGPoint(x: minX + ext, y: minY))
        path.addLine(to: CGPoint(x: maxX - ext, y: minY))
        path.addCurve(
            to: CGPoint(x: maxX - r * 0.30, y: minY + r * 0.30),
            control1: CGPoint(x: maxX - ext + handle, y: minY),
            control2: CGPoint(x: maxX - r * 0.52, y: minY + r * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: maxX, y: minY + ext),
            control1: CGPoint(x: maxX - r * 0.08, y: minY + r * 0.52),
            control2: CGPoint(x: maxX, y: minY + ext - handle)
        )
        path.addLine(to: CGPoint(x: maxX, y: maxY - ext))
        path.addCurve(
            to: CGPoint(x: maxX - r * 0.30, y: maxY - r * 0.30),
            control1: CGPoint(x: maxX, y: maxY - ext + handle),
            control2: CGPoint(x: maxX - r * 0.08, y: maxY - r * 0.52)
        )
        path.addCurve(
            to: CGPoint(x: maxX - ext, y: maxY),
            control1: CGPoint(x: maxX - r * 0.52, y: maxY - r * 0.08),
            control2: CGPoint(x: maxX - ext + handle, y: maxY)
        )
        path.addLine(to: CGPoint(x: minX + ext, y: maxY))
        path.addCurve(
            to: CGPoint(x: minX + r * 0.30, y: maxY - r * 0.30),
            control1: CGPoint(x: minX + ext - handle, y: maxY),
            control2: CGPoint(x: minX + r * 0.52, y: maxY - r * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: minX, y: maxY - ext),
            control1: CGPoint(x: minX + r * 0.08, y: maxY - r * 0.52),
            control2: CGPoint(x: minX, y: maxY - ext + handle)
        )
        path.addLine(to: CGPoint(x: minX, y: minY + ext))
        path.addCurve(
            to: CGPoint(x: minX + r * 0.30, y: minY + r * 0.30),
            control1: CGPoint(x: minX, y: minY + ext - handle),
            control2: CGPoint(x: minX + r * 0.08, y: minY + r * 0.52)
        )
        path.addCurve(
            to: CGPoint(x: minX + ext, y: minY),
            control1: CGPoint(x: minX + r * 0.52, y: minY + r * 0.08),
            control2: CGPoint(x: minX + ext - handle, y: minY)
        )
        path.closeSubpath()
        return path
    }

    public static func draw(in rect: NSRect, color: NSColor = .black) {
        guard let graphicsContext = NSGraphicsContext.current else { return }
        let context = graphicsContext.cgContext
        context.saveGState()
        defer { context.restoreGState() }

        if graphicsContext.isFlipped {
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / 24.0, y: rect.height / 24.0)
        } else {
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: rect.width / 24.0, y: -rect.height / 24.0)
        }

        context.setFillColor(color.cgColor)
        context.addPath(vectorPath)
        context.fillPath()
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
