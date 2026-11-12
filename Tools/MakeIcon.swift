import AppKit

// Draws the NotchTunes app icon and writes an .icns.
//
// Everything is drawn with code rather than pulled from an image file, so the
// icon is sharp at every size and can be adjusted by changing numbers here.
// Run it with Tools/make-icon.sh.

// MARK: - Colours

func rgb(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1).cgColor
}

let graphiteTop = rgb(62, 67, 78)
let graphiteBottom = rgb(13, 14, 18)
let notchBlack = rgb(5, 5, 8)
let barTop = rgb(255, 174, 51)      // warm amber
let barBottom = rgb(255, 45, 88)    // pink

func gradient(_ from: CGColor, _ to: CGColor) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
               colors: [from, to] as CFArray,
               locations: [0, 1])!
}

// MARK: - The drawing

func draw(in cg: CGContext, size: CGFloat) {
    // The artwork fills the whole canvas, edge to edge, with no rounded corners
    // of its own.
    //
    // This matters on macOS 26 and later: the system rounds icons to its own
    // shape. Supplying an icon that already had its own rounded square, with
    // transparent margins around it, made the system treat it as a small image
    // and draw its own dark tile behind it — the result was one rounded square
    // nested inside another. Filling the canvas lets the system simply mask it.
    let box = CGRect(x: 0, y: 0, width: size, height: size)

    // Below this the fine detail turns to mud, so the small sizes get a simpler,
    // chunkier version of the same idea.
    let detailed = size >= 64

    cg.saveGState()

    cg.drawLinearGradient(gradient(graphiteTop, graphiteBottom),
                          start: CGPoint(x: box.midX, y: box.maxY),
                          end: CGPoint(x: box.midX, y: box.minY),
                          options: [])

    if detailed {
        // The notch itself, hanging from the top edge: square across the top,
        // rounded underneath, exactly like the real thing.
        let width = box.width * 0.34
        let height = box.height * 0.115
        let notch = CGRect(x: box.midX - width / 2, y: box.maxY - height,
                           width: width, height: height)
        let r = height * 0.42

        let path = CGMutablePath()
        path.move(to: CGPoint(x: notch.minX, y: notch.maxY))
        path.addLine(to: CGPoint(x: notch.minX, y: notch.minY + r))
        path.addQuadCurve(to: CGPoint(x: notch.minX + r, y: notch.minY),
                          control: CGPoint(x: notch.minX, y: notch.minY))
        path.addLine(to: CGPoint(x: notch.maxX - r, y: notch.minY))
        path.addQuadCurve(to: CGPoint(x: notch.maxX, y: notch.minY + r),
                          control: CGPoint(x: notch.maxX, y: notch.minY))
        path.addLine(to: CGPoint(x: notch.maxX, y: notch.maxY))
        path.closeSubpath()

        cg.addPath(path)
        cg.setFillColor(notchBlack)
        cg.fillPath()
    }

    // Three bars, like the equaliser in the notch itself. Bold on purpose: thin
    // strokes are the first thing to disappear when an icon is shown small.
    let barWidth = box.width * (detailed ? 0.088 : 0.115)
    let gap = box.width * (detailed ? 0.055 : 0.065)
    let scale: CGFloat = detailed ? 1.0 : 1.10
    let heights: [CGFloat] = [0.26, 0.40, 0.31]

    let total = barWidth * 3 + gap * 2
    var x = box.midX - total / 2
    let baseY = box.minY + box.height * (detailed ? 0.26 : 0.27)

    for fraction in heights {
        let bar = CGRect(x: x, y: baseY,
                         width: barWidth,
                         height: box.height * fraction * scale)
        cg.addPath(CGPath(roundedRect: bar,
                          cornerWidth: barWidth / 2,
                          cornerHeight: barWidth / 2,
                          transform: nil))
        x += barWidth + gap
    }

    // One gradient across all three, so they read as a single object.
    cg.saveGState()
    cg.clip()
    cg.drawLinearGradient(gradient(barTop, barBottom),
                          start: CGPoint(x: box.midX, y: baseY + box.height * 0.45),
                          end: CGPoint(x: box.midX, y: baseY),
                          options: [])
    cg.restoreGState()

    cg.restoreGState()
}

// MARK: - Writing the files

func render(size: CGFloat) -> Data {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not make a bitmap at \(pixels)px")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw(in: context.cgContext, size: size)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(pixels)px as PNG")
    }
    return png
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

// The names iconutil expects. A size appears twice when it serves as both a
// 1x and a 2x image.
let wanted: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),     ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),     ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),  ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),  ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),  ("icon_512x512@2x.png", 1024),
]

var cache: [CGFloat: Data] = [:]
for (name, size) in wanted {
    let png = cache[size] ?? render(size: size)
    cache[size] = png
    try png.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
    print("  \(name)  (\(Int(size))px)")
}
