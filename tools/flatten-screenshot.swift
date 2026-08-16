import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// App Store Connect rejects any screenshot carrying an alpha channel, and a
// simulator capture always has one. sips cannot drop it (a BMP round-trip
// re-adds it), and PIL is not installable here, so composite onto opaque
// black and write a PNG with no alpha.
let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: flatten <in.png> <out.png>\n".data(using: .utf8)!)
    exit(64)
}
let src = URL(fileURLWithPath: args[1])
let dst = URL(fileURLWithPath: args[2])

guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("cannot read \(src.path)\n".data(using: .utf8)!)
    exit(1)
}

let w = image.width, h = image.height
guard let ctx = CGContext(
    data: nil, width: w, height: h,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { exit(2) }

ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

guard let flat = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        dst as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(3) }
CGImageDestinationAddImage(dest, flat, nil)
guard CGImageDestinationFinalize(dest) else { exit(4) }
print("\(w)x\(h) -> \(dst.lastPathComponent)")
