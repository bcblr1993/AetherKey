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

/// System input-source keycap. The Chinese label remains distinct from Apple's ABC source.
public enum AetherMenuBarIcon {
    public static func draw(in rect: NSRect, color: NSColor = .black) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let side = min(rect.width, rect.height * 1.25)
        (AffineTransform(translationByX: rect.midX - side / 2, byY: rect.midY - side / 2) as NSAffineTransform).concat()
        (AffineTransform(scaleByX: side / 100, byY: side / 100) as NSAffineTransform).concat()
        let keycap = NSBezierPath(roundedRect: NSRect(x: 3, y: 12, width: 94, height: 76),
                                 xRadius: 19, yRadius: 19)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        color.setFill()
        keycap.fill()
        let baseFont = CTFontCreateWithName("PingFangSC-Medium" as CFString, 54, nil)
        let font = CTFontCreateForString(baseFont, "中" as CFString, CFRange(location: 0, length: 1))
        var character: UniChar = 0x4E2D
        var glyph: CGGlyph = 0
        if CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
           let letter = CTFontCreatePathForGlyph(font, glyph, nil) {
            let bounds = letter.boundingBoxOfPath
            var placement = CGAffineTransform(translationX: 50 - bounds.midX, y: 50 - bounds.midY)
            if let centered = letter.copy(using: &placement) {
                context.setBlendMode(.destinationOut)
                context.setFillColor(NSColor.black.cgColor)
                context.addPath(centered)
                context.fillPath()
            }
        }
        context.endTransparencyLayer()
    }

    public static func image(size: CGFloat = 22) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size * 18 / 22), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AetherKey"
        return image
    }
}
