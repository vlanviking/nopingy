import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let width = CGFloat(pixels)
        let rect = NSRect(x: width * 0.07, y: width * 0.07, width: width * 0.86, height: width * 0.86)
        let panel = NSBezierPath(roundedRect: rect, xRadius: width * 0.19, yRadius: width * 0.19)
        NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.14, alpha: 1).setFill(); panel.fill()
        NSColor(calibratedRed: 0.22, green: 0.79, blue: 0.56, alpha: 1).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: width * 0.19, y: width * 0.19, width: width * 0.62, height: width * 0.62))
        ring.lineWidth = width * 0.022; NSColor(calibratedRed: 0.22, green: 0.79, blue: 0.56, alpha: 0.23).setStroke(); ring.stroke()
        let path = NSBezierPath()
        let points: [(CGFloat, CGFloat)] = [(0.20, 0.50), (0.33, 0.50), (0.41, 0.70), (0.50, 0.30), (0.59, 0.61), (0.67, 0.50), (0.80, 0.50)]
        path.move(to: NSPoint(x: points[0].0 * width, y: points[0].1 * width))
        for point in points.dropFirst() { path.line(to: NSPoint(x: point.0 * width, y: point.1 * width)) }
        path.lineWidth = width * 0.042; path.lineCapStyle = .round; path.lineJoinStyle = .round
        NSColor(calibratedRed: 0.22, green: 0.79, blue: 0.56, alpha: 1).setStroke(); path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
