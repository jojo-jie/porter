import AppKit
import Foundation

struct IconSize {
    let pointSize: Int
    let scale: Int

    var pixelSize: Int { pointSize * scale }
    var filename: String {
        scale == 1
            ? "icon_\(pointSize)x\(pointSize).png"
            : "icon_\(pointSize)x\(pointSize)@\(scale)x.png"
    }
}

let sizes = [
    IconSize(pointSize: 16, scale: 1),
    IconSize(pointSize: 16, scale: 2),
    IconSize(pointSize: 32, scale: 1),
    IconSize(pointSize: 32, scale: 2),
    IconSize(pointSize: 128, scale: 1),
    IconSize(pointSize: 128, scale: 2),
    IconSize(pointSize: 256, scale: 1),
    IconSize(pointSize: 256, scale: 2),
    IconSize(pointSize: 512, scale: 1),
    IconSize(pointSize: 512, scale: 2)
]

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift Scripts/render-icon.swift <output.iconset>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func strokedPath(points: [CGPoint], color: NSColor, width: CGFloat, lineCap: NSBezierPath.LineCapStyle = .round, lineJoin: NSBezierPath.LineJoinStyle = .round) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    path.lineWidth = width
    path.lineCapStyle = lineCap
    path.lineJoinStyle = lineJoin
    color.setStroke()
    path.stroke()
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    context.scaleBy(x: size / 1024, y: size / 1024)

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()

    let background = roundedRect(CGRect(x: 80, y: 80, width: 864, height: 864), radius: 196)
    color(248, 247, 242).setFill()
    background.fill()
    color(0, 0, 0, 0.08).setStroke()
    background.lineWidth = 12
    background.stroke()

    let panel = roundedRect(CGRect(x: 222, y: 306, width: 580, height: 412), radius: 74)
    color(40, 40, 39).setFill()
    panel.fill()

    color(204, 120, 92).setFill()
    NSBezierPath(ovalIn: CGRect(x: 298, y: 372, width: 52, height: 52)).fill()
    color(242, 232, 217).setFill()
    NSBezierPath(ovalIn: CGRect(x: 378, y: 372, width: 52, height: 52)).fill()

    let accent = color(204, 120, 92)
    strokedPath(
        points: [
            CGPoint(x: 328, y: 548),
            CGPoint(x: 496, y: 548),
            CGPoint(x: 544, y: 500),
            CGPoint(x: 544, y: 458),
            CGPoint(x: 704, y: 458)
        ],
        color: accent,
        width: 72
    )
    strokedPath(
        points: [
            CGPoint(x: 646, y: 382),
            CGPoint(x: 722, y: 458),
            CGPoint(x: 646, y: 534)
        ],
        color: accent,
        width: 72
    )
    strokedPath(
        points: [
            CGPoint(x: 334, y: 622),
            CGPoint(x: 484, y: 622)
        ],
        color: color(248, 247, 242),
        width: 42
    )

    image.unlockFocus()
    return image
}

for iconSize in sizes {
    let image = drawIcon(size: CGFloat(iconSize.pixelSize))
    guard let tiff = image.tiffRepresentation,
          let representation = NSBitmapImageRep(data: tiff),
          let png = representation.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(iconSize.filename)\n", stderr)
        exit(1)
    }
    try png.write(to: outputURL.appendingPathComponent(iconSize.filename))
}
