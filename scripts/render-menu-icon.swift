import AppKit

// Renders the 久空 input mode's menu icon from the application artwork.
//
// macOS draws input-mode icons as templates: only the alpha channel counts,
// tinted for the menu bar. The artwork's mark is white line work on a dark
// tile on a black backdrop, so its alpha would be a solid square. Each pixel's
// brightest channel becomes the alpha of black ink instead, which keeps the
// white line work and the orange drop and clears the tile and backdrop. The
// result is cropped to a centered square and written as 16 px and 32 px
// PNGs for `tiffutil -cathidpicheck`.
//
// Usage: swift render-menu-icon.swift <artwork.png> <output-directory>

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let artwork = NSImage(contentsOfFile: arguments[1]),
      let source = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(
        Data("usage: render-menu-icon.swift <artwork.png> <output-directory>\n".utf8)
    )
    exit(2)
}
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)

/// The tile is about 25 at its brightest and the line work about 250, so
/// brightness between these levels ramps the ink in for smooth edges.
let clearLevel = 64.0
let solidLevel = 140.0

let width = source.width
let height = source.height
let bytesPerRow = width * 4
var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

func makeContext(_ buffer: UnsafeMutableRawBufferPointer) -> CGContext {
    CGContext(
        data: buffer.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!
}

pixels.withUnsafeMutableBytes { buffer in
    makeContext(buffer).draw(
        source,
        in: CGRect(x: 0, y: 0, width: width, height: height)
    )
}

var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0 ..< height {
    for x in 0 ..< width {
        let offset = (y * width + x) * 4
        let brightness = Double(max(pixels[offset], pixels[offset + 1], pixels[offset + 2]))
        let coverage = min(1, max(0, (brightness - clearLevel) / (solidLevel - clearLevel)))
        let alpha = UInt8((coverage * Double(pixels[offset + 3])).rounded())
        // Premultiplied black ink: only the alpha carries the mark.
        pixels.replaceSubrange(offset ..< offset + 4, with: [0, 0, 0, alpha])
        if alpha > 0 {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
}
guard maxX >= minX, maxY >= minY else {
    FileHandle.standardError.write(Data("The artwork has no visible mark.\n".utf8))
    exit(1)
}

let side = max(maxX - minX + 1, maxY - minY + 1)
let crop = CGRect(
    x: minX - (side - (maxX - minX + 1)) / 2,
    y: minY - (side - (maxY - minY + 1)) / 2,
    width: side,
    height: side
)
let ink = pixels.withUnsafeMutableBytes { makeContext($0).makeImage()! }

func writeIcon(pixelSize: Int, dotsPerInch: Int, name: String) {
    let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!
    context.interpolationQuality = .high
    // The bitmap's origin is top-left; Core Graphics draws from bottom-left.
    let scale = CGFloat(pixelSize) / CGFloat(side)
    context.draw(
        ink,
        in: CGRect(
            x: -crop.minX * scale,
            y: -(CGFloat(height) - crop.maxY) * scale,
            width: CGFloat(width) * scale,
            height: CGFloat(height) * scale
        )
    )
    let url = outputDirectory.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        "public.png" as CFString,
        1,
        nil
    )!
    CGImageDestinationAddImage(
        destination,
        context.makeImage()!,
        [
            kCGImagePropertyDPIWidth: dotsPerInch,
            kCGImagePropertyDPIHeight: dotsPerInch,
        ] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("Could not write \(url.path).\n".utf8))
        exit(1)
    }
}

writeIcon(pixelSize: 16, dotsPerInch: 72, name: "menu-icon.png")
writeIcon(pixelSize: 32, dotsPerInch: 144, name: "menu-icon@2x.png")
