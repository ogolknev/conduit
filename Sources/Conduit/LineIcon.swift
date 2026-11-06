import SwiftUI

/// One outline weight for navigation and feature icons, matching Android's 24-unit grid.
struct LineIcon: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            context.translateBy(x: (size.width - 24 * scale) / 2, y: (size.height - 24 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            var path = Path()
            func line(_ a: CGPoint, _ b: CGPoint) { path.move(to: a); path.addLine(to: b) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat) {
                path.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: radius, height: radius))
            }
            switch name {
            case "square.grid.2x2":
                for x in [3.0, 14.0] { for y in [3.0, 14.0] { rect(x,y,7,7,1.5) } }
            case "slider.horizontal.3":
                for y in [5.0,12.0,19.0] {
                    let x = y == 12 ? 15.0 : 8.0
                    line(CGPoint(x:3,y:y),CGPoint(x:x-2.5,y:y)); line(CGPoint(x:x+2.5,y:y),CGPoint(x:21,y:y)); rect(x-2.5,y-2.5,5,5,2.5)
                }
            case "phone":
                rect(6,2,12,20,2.5); line(CGPoint(x:10,y:5),CGPoint(x:14,y:5)); line(CGPoint(x:10,y:19),CGPoint(x:14,y:19))
            case "doc.on.clipboard":
                path.move(to:CGPoint(x:8,y:5)); path.addLine(to:CGPoint(x:6,y:5)); path.addQuadCurve(to:CGPoint(x:4,y:7),control:CGPoint(x:4,y:5))
                path.addLine(to:CGPoint(x:4,y:20)); path.addQuadCurve(to:CGPoint(x:6,y:22),control:CGPoint(x:4,y:22))
                path.addLine(to:CGPoint(x:18,y:22)); path.addQuadCurve(to:CGPoint(x:20,y:20),control:CGPoint(x:20,y:22))
                path.addLine(to:CGPoint(x:20,y:7)); path.addQuadCurve(to:CGPoint(x:18,y:5),control:CGPoint(x:20,y:5)); path.addLine(to:CGPoint(x:16,y:5))
                rect(8,2,8,6,1.5); line(CGPoint(x:8,y:12),CGPoint(x:16,y:12)); line(CGPoint(x:8,y:16),CGPoint(x:14,y:16))
            case "bell":
                path.move(to: CGPoint(x:5,y:17)); path.addLine(to:CGPoint(x:7,y:14)); path.addLine(to:CGPoint(x:7,y:9))
                path.addCurve(to:CGPoint(x:17,y:9),control1:CGPoint(x:7,y:2),control2:CGPoint(x:17,y:2))
                path.addLine(to:CGPoint(x:17,y:14)); path.addLine(to:CGPoint(x:19,y:17)); path.closeSubpath()
                path.move(to:CGPoint(x:10,y:20)); path.addQuadCurve(to:CGPoint(x:14,y:20),control:CGPoint(x:12,y:23))
            case "upload":
                rect(5,2,14,20,2); line(CGPoint(x:12,y:17),CGPoint(x:12,y:8)); line(CGPoint(x:8,y:12),CGPoint(x:12,y:8)); line(CGPoint(x:16,y:12),CGPoint(x:12,y:8))
            case "download":
                path.move(to:CGPoint(x:3,y:14)); path.addLine(to:CGPoint(x:3,y:21)); path.addLine(to:CGPoint(x:21,y:21)); path.addLine(to:CGPoint(x:21,y:14))
                line(CGPoint(x:12,y:3),CGPoint(x:12,y:15)); line(CGPoint(x:8,y:11),CGPoint(x:12,y:15)); line(CGPoint(x:16,y:11),CGPoint(x:12,y:15))
            default:
                path.move(to:CGPoint(x:3,y:8)); path.addLine(to:CGPoint(x:3,y:20)); path.addLine(to:CGPoint(x:21,y:20)); path.addLine(to:CGPoint(x:21,y:7)); path.addLine(to:CGPoint(x:12,y:7)); path.addLine(to:CGPoint(x:10,y:4)); path.addLine(to:CGPoint(x:3,y:4)); path.closeSubpath()
            }
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.5 / scale, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
}
