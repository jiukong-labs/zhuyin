import AppKit

// Renders the 久空 input mode's menu icon from its transparent artwork.
//
// Preserve the source colors and alpha; TISIconIsTemplate is false. Crop the
// transparent margins to a centered square and write 16 px and 32 px PNGs
// for `tiffutil -cathidpicheck`.
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
        let alpha = pixels[offset + 3]
        // Ignore nearly transparent edge residue when centering the artwork.
        if alpha > 2 {
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
let horizontalPadding = CGFloat(side - (maxX - minX + 1)) / 2
let verticalPadding = CGFloat(side - (maxY - minY + 1)) / 2
let crop = CGRect(
    x: CGFloat(minX) - horizontalPadding,
    y: CGFloat(minY) - verticalPadding,
    width: CGFloat(side),
    height: CGFloat(side)
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
