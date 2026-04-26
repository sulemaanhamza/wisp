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

    // Warm cream background, full bleed.
    context.setFillColor(red: 0.95, green: 0.92, blue: 0.86, alpha: 1.0)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // Letter "W" centered.
    let fontSize = size * 0.6
    var font = CTFontCreateWithName("Charter-Bold" as CFString, fontSize, nil)
    if CTFontCopyPostScriptName(font) as String != "Charter-Bold" {
        font = CTFontCreateWithName("Charter" as CFString, fontSize, nil)
    }

    let attrs: [NSAttributedString.Key: Any] = [
        .init(kCTFontAttributeName as String): font,
        .init(kCTForegroundColorAttributeName as String):
            CGColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1.0),
    ]
    let attrString = NSAttributedString(string: "W", attributes: attrs)
    let line = CTLineCreateWithAttributedString(attrString as CFAttributedString)

    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let x = (size - bounds.width) / 2 - bounds.origin.x
    let y = (size - bounds.height) / 2 - bounds.origin.y

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
