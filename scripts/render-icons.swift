import AppKit
import Foundation

// Vector artwork shared with android/res/drawable/ic_conduit.xml.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: Double(size) / 24, y: Double(size) / 24)
        NSColor(srgbRed: 32.0/255, green: 32.0/255, blue: 32.0/255, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 22, height: 22), xRadius: 5, yRadius: 5).fill()
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).setStroke()
        for rect in [NSRect(x: 6, y: 7, width: 4.5, height: 10), NSRect(x: 13.5, y: 7, width: 4.5, height: 10)] {
            let path = NSBezierPath(roundedRect: rect, xRadius: 1.2, yRadius: 1.2); path.lineWidth = 1.25; path.stroke()
        }
        let bridge = NSBezierPath(); bridge.lineWidth = 1.25; bridge.move(to: NSPoint(x: 10.5, y: 12)); bridge.line(to: NSPoint(x: 13.5, y: 12)); bridge.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
    }
}
