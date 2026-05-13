#!/usr/bin/env swift
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("Usage: render-dmg-background.swift <output-png>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let size = NSSize(width: 800, height: 480)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to create bitmap context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1.0).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let arrowColor = NSColor(red: 0.22, green: 0.21, blue: 0.18, alpha: 0.9)
arrowColor.setStroke()

let shaft = NSBezierPath()
shaft.lineWidth = 18
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 365, y: 250))
shaft.line(to: NSPoint(x: 440, y: 250))
shaft.stroke()

let head = NSBezierPath()
head.lineWidth = 18
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.move(to: NSPoint(x: 420, y: 290))
head.line(to: NSPoint(x: 460, y: 250))
head.line(to: NSPoint(x: 420, y: 210))
head.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: outputURL)
} catch {
    fputs("Failed to write PNG: \(error)\n", stderr)
    exit(1)
}
