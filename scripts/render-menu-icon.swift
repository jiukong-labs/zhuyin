import AppKit

// Renders the input-menu icon from the application artwork.
//
// The artwork sits in the middle of an opaque black backdrop. At menu-bar
// size that backdrop would shrink the mark to about ten points inside a
// black square, so the backdrop connected to the image edges
// is cleared, the mark is cropped to a centered square, and 16 px and 32 px
// PNGs are written for `tiffutil -cathidpicheck`.
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

/// Channels at or below this level count as backdrop. The mark's own dark
/// tile is lighter, so the clearing stops at the tile's edge.
let backdropLevel: UInt8 = 12

let width = source.width
let height = source.height
let bytesPerRow = width * 4
var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

pixels.withUnsafeMutableBytes { buffer in
    let context = CGContext(
        data: buffer.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
}

func isBackdrop(_ index: Int) -> Bool {
    let offset = index * 4
    return pixels[offset + 3] > 0
        && pixels[offset] <= backdropLevel
        && pixels[offset + 1] <= backdropLevel
        && pixels[offset + 2] <= backdropLevel
}

// Clear only backdrop reachable from the edges, so dark detail inside the
// mark stays opaque.
var pending: [Int] = []
var visited = [Bool](repeating: false, count: width * height)
for x in 0 ..< width {
    pending.append(x)
    pending.append((height - 1) * width + x)
}
for y in 0 ..< height {
    pending.append(y * width)
    pending.append(y * width + width - 1)
}
while let index = pending.popLast() {
    guard !visited[index], isBackdrop(index) else {
        continue
    }
    visited[index] = true
    pixels.replaceSubrange(index * 4 ..< index * 4 + 4, with: [0, 0, 0, 0])
    let x = index % width
    let y = index / width
    if x > 0 { pending.append(index - 1) }
    if x < width - 1 { pending.append(index + 1) }
    if y > 0 { pending.append(index - width) }
    if y < height - 1 { pending.append(index + width) }
}

var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0 ..< height {
    for x in 0 ..< width where pixels[(y * width + x) * 4 + 3] > 0 {
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
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
let cleared = pixels.withUnsafeMutableBytes { buffer in
    CGContext(
        data: buffer.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!.makeImage()!
}

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
        cleared,
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
