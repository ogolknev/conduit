import AppKit
import Foundation

// Geometry is shared by every Conduit mark through design/brand.json.
struct Brand: Decodable {
    struct Tile: Decodable { let x, y, size, radius: Double }
    struct Glyph: Decodable { let rects: [[Double]]; let radius, stroke: Double; let bridge: [Double] }
    let canvas: Double; let background: String; let tile: Tile; let glyph: Glyph
}
let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("design/brand.json")
let brand = try JSONDecoder().decode(Brand.self, from: Data(contentsOf: source))
let tile = brand.tile; let glyph = brand.glyph
let color = UInt32(brand.background.dropFirst(), radix: 16)!

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
        // macOS legacy icon keyline: 824 px artwork inside a 1024 px canvas.
        let unit=Double(size)*824/1024/tile.size
        let padding=Double(size)*100/1024-unit*tile.x
        context.translateBy(x:padding,y:padding)
        context.scaleBy(x:unit,y:unit)
        NSColor(srgbRed: Double((color >> 16) & 255)/255, green: Double((color >> 8) & 255)/255, blue: Double(color & 255)/255, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: tile.x, y: tile.y, width: tile.size, height: tile.size), xRadius: tile.radius, yRadius: tile.radius).fill()
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).setStroke()
        for values in glyph.rects {
            let rect = NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
            let path = NSBezierPath(roundedRect: rect, xRadius: glyph.radius, yRadius: glyph.radius); path.lineWidth = glyph.stroke; path.lineCapStyle = .round; path.stroke()
        }
        let bridge = NSBezierPath(); bridge.lineWidth = glyph.stroke; bridge.lineCapStyle = .round; bridge.move(to: NSPoint(x: glyph.bridge[0], y: glyph.bridge[1])); bridge.line(to: NSPoint(x: glyph.bridge[2], y: glyph.bridge[3])); bridge.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
    }
}
