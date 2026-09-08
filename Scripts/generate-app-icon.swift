#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let outputDirectory = root.appendingPathComponent("Config", isDirectory: true)
let temporaryDirectory = root.appendingPathComponent(".build/AppIcon.iconset", isDirectory: true)

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try? fileManager.removeItem(at: temporaryDirectory)
try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

func drawIcon(size: Int) throws -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "AudoCaptureIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create graphics context"])
    }
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let canvas = CGFloat(size)
    let inset = canvas * 0.055
    let tile = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let cornerRadius = canvas * 0.225

    let tilePath = NSBezierPath(roundedRect: tile, xRadius: cornerRadius, yRadius: cornerRadius)
    tilePath.addClip()
    let background = NSGradient(colors: [
        NSColor(calibratedRed: 0.075, green: 0.125, blue: 0.255, alpha: 1),
        NSColor(calibratedRed: 0.025, green: 0.055, blue: 0.145, alpha: 1)
    ])!
    background.draw(in: tile, angle: -35)

    // A restrained glow keeps the microphone legible at Finder thumbnail sizes.
    let glowRect = NSRect(x: canvas * 0.18, y: canvas * 0.16, width: canvas * 0.64, height: canvas * 0.64)
    NSColor(calibratedRed: 0.16, green: 0.70, blue: 0.95, alpha: 0.13).setFill()
    NSBezierPath(ovalIn: glowRect).fill()

    let white = NSColor(calibratedWhite: 0.985, alpha: 1)
    let cyan = NSColor(calibratedRed: 0.30, green: 0.86, blue: 0.98, alpha: 1)
    let micWidth = canvas * 0.205
    let micHeight = canvas * 0.405
    let micX = (canvas - micWidth) / 2
    let micY = canvas * 0.335
    let mic = NSBezierPath(roundedRect: NSRect(x: micX, y: micY, width: micWidth, height: micHeight),
                           xRadius: micWidth / 2, yRadius: micWidth / 2)
    white.setFill()
    mic.fill()

    let cradle = NSBezierPath()
    cradle.move(to: NSPoint(x: canvas * 0.295, y: canvas * 0.515))
    cradle.curve(to: NSPoint(x: canvas * 0.705, y: canvas * 0.515),
                 controlPoint1: NSPoint(x: canvas * 0.295, y: canvas * 0.205),
                 controlPoint2: NSPoint(x: canvas * 0.705, y: canvas * 0.205))
    cradle.lineWidth = canvas * 0.065
    cradle.lineCapStyle = .round
    cyan.setStroke()
    cradle.stroke()

    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: canvas / 2, y: canvas * 0.275))
    stem.line(to: NSPoint(x: canvas / 2, y: canvas * 0.19))
    stem.lineWidth = canvas * 0.065
    stem.lineCapStyle = .round
    cyan.setStroke()
    stem.stroke()

    let base = NSBezierPath(roundedRect: NSRect(x: canvas * 0.375, y: canvas * 0.135, width: canvas * 0.25, height: canvas * 0.065),
                            xRadius: canvas * 0.0325, yRadius: canvas * 0.0325)
    cyan.setFill()
    base.fill()

    guard let cgImage = context.makeImage() else {
        throw NSError(domain: "AudoCaptureIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to create CGImage"])
    }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AudoCaptureIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"])
    }
    return png
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_48x48.png", 48),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for item in sizes {
    let data = try drawIcon(size: item.pixels)
    try data.write(to: temporaryDirectory.appendingPathComponent(item.name), options: .atomic)
}

let preview = outputDirectory.appendingPathComponent("AppIcon-preview.png")
try drawIcon(size: 512).write(to: preview, options: .atomic)

func bigEndianBytes(_ value: UInt32) -> [UInt8] {
    [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff)
    ]
}

let icns = outputDirectory.appendingPathComponent("AppIcon.icns")
let icnsEntries: [(type: String, file: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_48x48.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]
var entries = Data()
for entry in icnsEntries {
    let png = try Data(contentsOf: temporaryDirectory.appendingPathComponent(entry.file))
    let typeData = Data(entry.type.utf8)
    guard typeData.count == 4 else {
        throw NSError(domain: "AudoCaptureIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid ICNS entry type"])
    }
    entries.append(typeData)
    entries.append(contentsOf: bigEndianBytes(UInt32(png.count + 8)))
    entries.append(png)
}

var icnsData = Data("icns".utf8)
icnsData.append(contentsOf: bigEndianBytes(UInt32(entries.count + 8)))
icnsData.append(entries)
try icnsData.write(to: icns, options: .atomic)

print("Generated \(icns.path)")
print("Preview: \(preview.path)")
