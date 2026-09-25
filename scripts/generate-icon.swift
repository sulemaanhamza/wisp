// Generates AppIcon.icns for Wisp.
// Run with: swift scripts/generate-icon.swift
// Output: scripts/AppIcon.icns (committed to repo, build-app.sh copies it).

import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import Foundation

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let iconsetDir = scriptDir.appendingPathComponent("AppIcon.iconset")
let icnsURL = scriptDir.appendingPathComponent("AppIcon.icns")

try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// Rounded rect with continuous ("squircle") corners, approximating
// Apple's macOS icon shape. Each corner is a quarter superellipse
// spanning 1.528 x radius along each edge (the extent of Apple's
// continuous corner); exponent ~3.1 puts the corner's apex where a
// circular radius would be, and meets the straight edges with zero
// curvature, so there's no visible "kink" like a plain rounded rect.
func squirclePath(in rect: CGRect, radius r: CGFloat) -> CGPath {
    let n: CGFloat = 3.1
    let l = min(r * 1.528, min(rect.width, rect.height) / 2)
    let steps = 90
    let path = CGMutablePath()
    // Corner centres (where the superellipse quadrant is anchored) and
    // the quadrant's start angle, walking counter-clockwise from bottom-right.
    let corners: [(CGPoint, CGFloat)] = [
        (CGPoint(x: rect.maxX - l, y: rect.minY + l), -.pi / 2),
        (CGPoint(x: rect.maxX - l, y: rect.maxY - l), 0),
        (CGPoint(x: rect.minX + l, y: rect.maxY - l), .pi / 2),
        (CGPoint(x: rect.minX + l, y: rect.minY + l), .pi),
    ]
    for (ci, (c, start)) in corners.enumerated() {
        for i in 0...steps {
            let t = start + CGFloat(i) / CGFloat(steps) * .pi / 2
            let ct = cos(t), st = sin(t)
            let p = CGPoint(
                x: c.x + l * copysign(pow(abs(ct), 2 / n), ct),
                y: c.y + l * copysign(pow(abs(st), 2 / n), st)
            )
            if ci == 0 && i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
    }
    path.closeSubpath()
    return path
}

// Bold serif "W" on warm cream — ties to the app's body typography
// (Charter) and the warm-cream palette used in the dark theme.
func makeIcon(pixelSize: Int) -> Data? {
    let size = CGFloat(pixelSize)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // macOS icon grid: 824/1024 tile centred (100px margin at 1024),
    // continuous-corner "squircle" outline, soft shadow beneath.
    let unit = size / 1024
    let tile = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let tilePath = squirclePath(in: tile, radius: 185 * unit)

    // Drop shadow (CG y-up, so negative offset is downward).
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -12 * unit),
        blur: 26 * unit,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28)
    )
    context.addPath(tilePath)
    context.setFillColor(red: 0.95, green: 0.92, blue: 0.86, alpha: 1.0)
    context.fillPath()
    context.restoreGState()

    // Restrained vertical gradient in the warm-cream palette.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.975, green: 0.955, blue: 0.91, alpha: 1.0),  // top
            CGColor(red: 0.92, green: 0.885, blue: 0.815, alpha: 1.0),  // bottom
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: tile.maxY),
        end: CGPoint(x: 0, y: tile.minY),
        options: []
    )

    // Faint inner edge: light highlight, stronger toward the top.
    if pixelSize >= 64 {
        let lineWidth = 2 * unit
        context.addPath(tilePath)
        context.setLineWidth(lineWidth * 2)  // half is clipped away -> inner edge
        context.replacePathWithStrokedPath()
        context.clip()
        let edge = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.55),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
                CGColor(red: 0.45, green: 0.36, blue: 0.25, alpha: 0.12),
            ] as CFArray,
            locations: [0, 0.5, 1]
        )!
        context.drawLinearGradient(
            edge,
            start: CGPoint(x: 0, y: tile.maxY),
            end: CGPoint(x: 0, y: tile.minY),
            options: []
        )
    }
    context.restoreGState()

    // Letter "W": glyph height ~55% of the tile, but capped at 70% of
    // the tile width (W is wide) so it keeps breathing room; optically
    // centred.
    let probeSize: CGFloat = 100
    var font = CTFontCreateWithName("Charter-Bold" as CFString, probeSize, nil)
    let useBold = (CTFontCopyPostScriptName(font) as String) == "Charter-Bold"
    let fontName = useBold ? "Charter-Bold" : "Charter"
    func makeLine(_ f: CTFont) -> CTLine {
        let attrs: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): f,
            .init(kCTForegroundColorAttributeName as String):
                CGColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1.0),
        ]
        let s = NSAttributedString(string: "W", attributes: attrs)
        return CTLineCreateWithAttributedString(s as CFAttributedString)
    }
    font = CTFontCreateWithName(fontName as CFString, probeSize, nil)
    let probeBounds = CTLineGetBoundsWithOptions(makeLine(font), .useGlyphPathBounds)
    let fontSize = probeSize * min(
        tile.height * 0.55 / probeBounds.height,
        tile.width * 0.70 / probeBounds.width
    )
    font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    let line = makeLine(font)

    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let x = tile.midX - bounds.width / 2 - bounds.origin.x
    // Nudge up ~1.5% of the tile: geometric centre reads low.
    let y = tile.midY - bounds.height / 2 - bounds.origin.y + tile.height * 0.015

    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, context)

    guard let cgImage = context.makeImage() else { return nil }

    let mutableData = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        mutableData,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { return nil }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return mutableData as Data
}

let sizeMap: [(pixels: Int, filename: String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (pixels, filename) in sizeMap {
    guard let data = makeIcon(pixelSize: pixels) else {
        print("Failed to render \(filename)")
        exit(1)
    }
    let url = iconsetDir.appendingPathComponent(filename)
    try data.write(to: url)
    print("\(filename)  \(pixels)x\(pixels)")
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = [
    "-c", "icns",
    "-o", icnsURL.path,
    iconsetDir.path,
]
try task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("Wrote \(icnsURL.path)")
    try? FileManager.default.removeItem(at: iconsetDir)
} else {
    print("iconutil failed with status \(task.terminationStatus)")
    exit(1)
}
