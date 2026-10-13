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
        view.appearance = NSAppearance(named: .darkAqua)
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

/// AetherNative Liquid Glass Container with razor-thin 0.5pt specular gradient border and dark glass backing.
public struct LiquidGlassContainer<Content: View>: View {
    public let cornerRadius: CGFloat
    public let content: Content

    public init(cornerRadius: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .background(
                ZStack {
                    // Deep dark visual effect glass base
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                    
                    // Dark ambient overlay (45% pure black)
                    Color.black.opacity(0.48)
                    
                    // Subtle ambient specular gradient
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color.clear,
                            Color.black.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                // 0.5pt razor gradient subtle glow border
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.36), location: 0.0),  // Top-left highlight
                                .init(color: Color.white.opacity(0.16), location: 0.25),
                                .init(color: Color.white.opacity(0.04), location: 0.65),
                                .init(color: Color.white.opacity(0.12), location: 1.0)   // Bottom-right subtle bounce
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            // Low-frequency diffuse shadow for floating depth
            .shadow(color: Color.black.opacity(0.55), radius: 24, x: 0, y: 12)
            .shadow(color: Color.black.opacity(0.20), radius: 4, x: 0, y: 2)
    }
}

/// AetherNative Subtle Glow Capsule for highlighted candidate selection
public struct SubtleGlowCapsule: View {
    public var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.13),
                        Color.white.opacity(0.07)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.32),
                                Color.white.opacity(0.10)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            // Soft diffuse micro-glow shadow
            .shadow(color: Color.white.opacity(0.09), radius: 6, x: 0, y: 1)
    }
}
