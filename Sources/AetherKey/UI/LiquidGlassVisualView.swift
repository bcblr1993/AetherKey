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

/// AetherKey brand: a solid rounded keycap with a transparent capital A.
public enum AetherMenuBarIcon {
    public static func draw(in rect: NSRect, color: NSColor = .black) {
    NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
    let t = NSAffineTransform(); t.translateX(by:rect.minX,yBy:rect.minY); t.scaleX(by:rect.width/24,yBy:rect.height/24); t.concat()
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 20, height: 20), xRadius: 5, yRadius: 5).fill()
    let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 17, nil)
    var character: UniChar = 65
    var glyph: CGGlyph = 0
    if CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
       let letter = CTFontCreatePathForGlyph(font, glyph, nil) {
        let bounds = letter.boundingBoxOfPath
        var placement = CGAffineTransform(translationX: 12 - bounds.midX, y: 12 - bounds.midY)
        if let centered = letter.copy(using: &placement) {
            context.setBlendMode(.destinationOut)
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
