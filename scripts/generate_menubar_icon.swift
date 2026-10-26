import AppKit
/// Compile with LiquidGlassVisualView.swift. Exports the same geometry used in app UI.
@MainActor private final class MarkView: NSView {
    override func draw(_ dirtyRect: NSRect) { AetherMenuBarIcon.draw(in: bounds) }
}
@main struct ExportMenuBarIcon {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
        let resources = root.appendingPathComponent("Resources")
        let mark = MarkView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        try mark.dataWithPDF(inside: mark.bounds).write(to: resources.appendingPathComponent("menubar.pdf"))
        let image = NSImage(size: NSSize(width: 22, height: 22))
        for scale in [1, 2] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 22 * scale, pixelsHigh: 22 * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = NSSize(width: 22, height: 22)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            AetherMenuBarIcon.draw(in: NSRect(x: 0, y: 0, width: 22, height: 22))
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
            if scale == 2 { try bitmap.representation(using: .png, properties: [:])!.write(to: resources.appendingPathComponent("icon.png")) }
        }
        try image.tiffRepresentation!.write(to: resources.appendingPathComponent("AetherKeyMenu.tiff"))
    }
}
