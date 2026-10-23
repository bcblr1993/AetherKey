import AppKit

/// Compile with LiquidGlassVisualView.swift to export the production vector geometry.
@MainActor
private final class MarkView: NSView {
    override func draw(_ dirtyRect: NSRect) { AetherMenuBarIcon.draw(in: bounds) }
}

@main
struct ExportMenuBarIcon {
    @MainActor
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
        let resources = root.appendingPathComponent("Resources")
        let output = root.appendingPathComponent(".build/brand-preview")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let mark = MarkView(frame: NSRect(x: 0, y: 0, width: 22, height: 18))
        try mark.dataWithPDF(inside: mark.bounds).write(to: resources.appendingPathComponent("menubar.pdf"))
        let image = NSImage(size: NSSize(width: 22, height: 18))
        for scale in [1, 2] {
            let pixels = 22 * scale
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: 18 * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = NSSize(width: 22, height: 18)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSGraphicsContext.current!.imageInterpolation = .high
            AetherMenuBarIcon.draw(in: NSRect(x: 0, y: 0, width: 22, height: 18))
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
            let png = bitmap.representation(using: .png, properties: [:])!
            try png.write(to: output.appendingPathComponent("menubar-\(pixels).png"))
            if scale == 2 { try png.write(to: resources.appendingPathComponent("icon.png")) }
        }
        try image.tiffRepresentation!.write(to: resources.appendingPathComponent("icon.tiff"))

        // A comparison sheet drawn at Retina resolution, using the production path.
        let preview = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 600,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        preview.size = NSSize(width: 640, height: 300)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: preview)
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 640, height: 300).fill()
        ("AetherKey · 浮光键" as NSString).draw(at: NSPoint(x: 28, y: 256), withAttributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.black])
        ("菜单栏图标  /  同一品牌轮廓，适配明暗外观" as NSString).draw(at: NSPoint(x: 28, y: 230), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
        for (index, dark) in [false, true].enumerated() {
            let x = CGFloat(28 + index * 304)
            (dark ? NSColor(calibratedWhite: 0.15, alpha: 1) : NSColor.white).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 26, width: 280, height: 176), xRadius: 16, yRadius: 16).fill()
            let ink: NSColor = dark ? .white : .black
            AetherMenuBarIcon.draw(in: NSRect(x: x + 30, y: 82, width: 88, height: 88), color: ink)
            AetherMenuBarIcon.draw(in: NSRect(x: x + 168, y: 115, width: 16, height: 16), color: ink)
            AetherMenuBarIcon.draw(in: NSRect(x: x + 218, y: 113, width: 20, height: 20), color: ink)
            ("放大轮廓          16 pt     20 pt" as NSString).draw(at: NSPoint(x: x + 30, y: 48), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: ink.withAlphaComponent(0.6)])
        }
        NSGraphicsContext.restoreGraphicsState()
        try preview.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("menubar-design.png"))
    }
}
