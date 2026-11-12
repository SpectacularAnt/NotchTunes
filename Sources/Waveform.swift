import AppKit
import SwiftUI

/// The little moving bars the Dynamic Island shows beside a song that's
/// playing: six thin capsules, tallest in the middle, each rising and falling
/// on its own, tinted with a colour from the album cover.
///
/// When NotchTunes can hear the music (see AudioTap.swift), the bars follow it
/// the way the island's do: a mirrored glyph, bass in the middle and treble at
/// the edges, pulsing together with the beat. When it can't — permission turned down, or protected audio that comes through
/// silent — they move on a pattern of their own instead, which is what the
/// iPhone's mostly do anyway.
///
/// **Why the bars aren't drawn by SwiftUI.** Measured with the same `top`
/// figures Gauge shows, NotchTunes sat at about 15% of a core while music
/// played, nearly all of it redrawing these bars: every frame went through
/// SwiftUI's whole render pass, and its background rendering kept starting and
/// stopping threads. Drawing them as six separate shapes was worst — the whole
/// notch window was re-measured each frame — and a Canvas helped less than
/// hoped. So they're six plain Core Animation layers, the same thing macOS's
/// own animations are made of, and moving them is just changing six heights.
struct Waveform: View {
    let isPlaying: Bool
    let color: Color
    /// How tall the bars can grow. Their width and spacing follow from it.
    var height: CGFloat = 14
    /// Redraws a second. The notch's bars are tiny and 30 is plenty; the
    /// visualizer's are huge, and 60 keeps them smooth.
    var framesPerSecond: Double = 30
    /// Whether anyone can see these bars right now. When not, they stop
    /// redrawing altogether — the open panel's bars, for instance, are still
    /// there while the panel is closed, just invisible.
    var isVisible: Bool = true

    /// Set by the preview tool. Its renderer can only draw SwiftUI, not
    /// layers, so it gets a still drawing of the same bars instead.
    static var drawForSnapshot = false

    var body: some View {
        let metrics = BarMetrics(height: height)
        Group {
            if Self.drawForSnapshot {
                Canvas { canvas, size in
                    let t = Date().timeIntervalSinceReferenceDate
                    for i in 0..<BarMetrics.count {
                        let h = isPlaying ? metrics.movingHeight(i, at: t, live: nil) : metrics.barWidth
                        canvas.fill(Path(roundedRect: metrics.rect(i, height: h, in: size),
                                         cornerRadius: metrics.barWidth / 2), with: .color(color))
                    }
                }
            } else {
                BarsLayerView(isPlaying: isPlaying, color: NSColor(color), metrics: metrics,
                              framesPerSecond: framesPerSecond, isVisible: isVisible)
            }
        }
        .frame(width: metrics.totalWidth, height: height)
    }
}

/// Sizes and motion for one set of bars.
private struct BarMetrics: Equatable {
    let height: CGFloat

    static let count = 6

    /// How tall each bar is allowed to get, left to right, in the pattern.
    /// Tallest towards the middle, as Apple's are.
    static let reach: [CGFloat] = [0.45, 0.72, 0.95, 1.0, 0.82, 0.58]

    /// Each bar's two speeds and starting points. Two waves of different
    /// speeds added together never quite repeat, which is what keeps the
    /// movement looking alive rather than like a loop.
    static let motion: [(f1: Double, f2: Double, p1: Double, p2: Double)] = [
        (1.9, 3.7, 0.0, 1.3), (2.3, 3.1, 2.1, 0.4), (1.6, 4.3, 4.0, 2.6),
        (2.1, 3.4, 1.1, 5.0), (1.8, 4.0, 3.3, 0.9), (2.5, 2.9, 5.2, 3.8),
    ]

    var barWidth: CGFloat { max(1.5, (height * 0.15).rounded(.toNearestOrEven)) }
    var gap: CGFloat { barWidth * 0.8 }
    var totalWidth: CGFloat { barWidth * CGFloat(Self.count) + gap * CGFloat(Self.count - 1) }

    func rect(_ i: Int, height h: CGFloat, in size: CGSize) -> CGRect {
        CGRect(x: CGFloat(i) * (barWidth + gap), y: (size.height - h) / 2, width: barWidth, height: h)
    }

    /// A bar's height while music plays.
    func movingHeight(_ i: Int, at t: TimeInterval, live: [Float]?) -> CGFloat {
        // The real music, when it can be heard, already shaped like the
        // island's glyph (see BandAnalyser.islandBars).
        if let live {
            return max(barWidth, height * CGFloat(live[i]))
        }

        // Otherwise their own pattern.
        let m = Self.motion[i]
        let wave = 0.5 + 0.25 * sin(2 * .pi * m.f1 * t + m.p1)
                       + 0.25 * sin(2 * .pi * m.f2 * t + m.p2)
        let level = 0.25 + 0.75 * wave           // never quite flat while playing
        return max(barWidth, height * Self.reach[i] * CGFloat(level))
    }

    static func == (a: BarMetrics, b: BarMetrics) -> Bool { a.height == b.height }
}

/// Puts the layer-drawn bars into a SwiftUI layout.
private struct BarsLayerView: NSViewRepresentable {
    let isPlaying: Bool
    let color: NSColor
    let metrics: BarMetrics
    let framesPerSecond: Double
    let isVisible: Bool

    func makeNSView(context: Context) -> BarsNSView { BarsNSView() }

    func updateNSView(_ view: BarsNSView, context: Context) {
        view.configure(isPlaying: isPlaying, color: color, metrics: metrics,
                       framesPerSecond: framesPerSecond, isVisible: isVisible)
    }

    static func dismantleNSView(_ view: BarsNSView, coordinator: ()) {
        view.stopTicking()
    }
}

/// Six layers and a timer. Each tick sets six heights inside one Core
/// Animation transaction with animation switched off, which is about the
/// cheapest drawing a Mac can do. The timer only runs while the bars are both
/// moving and visible.
private final class BarsNSView: NSView {

    private var bars: [CALayer] = []
    private var timer: Timer?

    private var isPlaying = false
    private var isVisible = true
    private var color = NSColor.white
    private var metrics = BarMetrics(height: 14)
    private var framesPerSecond: Double = 30

    /// When play or pause last changed, for the settle into dots (or up out
    /// of them), which takes a quarter of a second.
    private var changedAt = Date.distantPast
    private static let settle: TimeInterval = 0.25

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<BarMetrics.count {
            let bar = CALayer()
            bar.actions = ["bounds": NSNull(), "position": NSNull(), "backgroundColor": NSNull()]
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func configure(isPlaying: Bool, color: NSColor, metrics: BarMetrics,
                   framesPerSecond: Double, isVisible: Bool) {
        if isPlaying != self.isPlaying { changedAt = Date() }
        self.isPlaying = isPlaying
        self.color = color
        self.metrics = metrics
        self.framesPerSecond = framesPerSecond
        self.isVisible = isVisible
        draw()
        updateTicking()
    }

    override func layout() {
        super.layout()
        draw()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTicking()
    }

    private var isSettling: Bool { Date().timeIntervalSince(changedAt) < Self.settle + 0.05 }

    private func updateTicking() {
        let wanted = window != nil && isVisible && (isPlaying || isSettling)
        if wanted, timer == nil || timer?.timeInterval != 1 / framesPerSecond {
            timer?.invalidate()
            let fresh = Timer(timeInterval: 1 / framesPerSecond, repeats: true) { [weak self] _ in
                self?.draw()
                self?.updateTicking()
            }
            // Slack lets macOS line the ticks up with other work, rather than
            // waking up just for these.
            fresh.tolerance = 0.2 / framesPerSecond
            RunLoop.main.add(fresh, forMode: .common)
            timer = fresh
        } else if !wanted {
            stopTicking()
        }
    }

    func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    private func draw() {
        let now = Date()
        let linear = min(1, max(0, now.timeIntervalSince(changedAt) / Self.settle))
        // Eased out: quick to start, gentle as it lands.
        let progress = 1 - (1 - linear) * (1 - linear)
        let blend = CGFloat(isPlaying ? progress : 1 - progress)
        let live = AudioLevels.shared.current()
        let t = now.timeIntervalSinceReferenceDate
        let dot = metrics.barWidth

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            let moving = metrics.movingHeight(i, at: t, live: live)
            let h = dot + (moving - dot) * blend
            bar.frame = metrics.rect(i, height: h, in: bounds.size)
            bar.cornerRadius = dot / 2
            bar.backgroundColor = color.cgColor
        }
        CATransaction.commit()
    }
}

/// Picks colours out of an album cover: one for the bars, and a pair for the
/// visualizer's background.
enum ArtworkTint {

    static let fallback = Color.white.opacity(0.85)

    /// For the bars: the cover's colour, lifted until it shows up on black.
    static func color(for image: NSImage) -> Color {
        guard let main = Pixels(image)?.mainColors().first else { return fallback }
        return Color(nsColor: NSColor(deviceHue: main.hueComponent,
                                      saturation: min(main.saturationComponent, 0.75),
                                      brightness: max(main.brightnessComponent, 0.78),
                                      alpha: 1))
    }

    /// The fallback backdrop: a plain dark grey.
    static let fallbackBackdrop = [Color(white: 0.16), Color(white: 0.08)]

    /// For the visualizer: two colours to fade between, top to bottom — the
    /// cover's main colour, then its second one. Kept in a middle range of
    /// brightness, so a white cover doesn't make white text unreadable and a
    /// black one doesn't vanish into nothing.
    static func backdrop(for image: NSImage) -> [Color] {
        guard let colors = Pixels(image)?.mainColors(), let top = colors.first else { return fallbackBackdrop }
        let bottom = colors.count > 1 ? colors[1] : top

        func settle(_ c: NSColor, darker: CGFloat) -> Color {
            Color(nsColor: NSColor(deviceHue: c.hueComponent,
                                   saturation: min(c.saturationComponent * 1.1, 0.85),
                                   brightness: min(max(c.brightnessComponent, 0.3), 0.58) - darker,
                                   alpha: 1))
        }
        // The bottom a little darker, so the gradient has somewhere to go even
        // when the cover is all one colour.
        return [settle(top, darker: 0), settle(bottom, darker: 0.1)]
    }

    /// The cover shrunk to a small square of pixels, which is plenty for
    /// working out its colours and far quicker than looking at all of them.
    private struct Pixels {
        static let side = 12
        let rep: NSBitmapImageRep

        init?(_ image: NSImage) {
            let side = Pixels.side
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
            NSGraphicsContext.restoreGraphicsState()
            self.rep = rep
        }

        /// The cover's main colours, most prominent first — at most two.
        ///
        /// Averaging every pixel would be simpler, but it muddies: an orange
        /// flower on green leaves averages to mustard, a colour that isn't in
        /// the picture at all. So pixels are sorted into hue families first,
        /// and each family averaged on its own. Colourful, bright pixels count
        /// for more, so a vivid detail isn't drowned out by a dull background;
        /// greys and near-blacks go in a family of their own.
        func mainColors() -> [NSColor] {
            let families = 12
            var sums = Array(repeating: (r: 0.0, g: 0.0, b: 0.0, weight: 0.0), count: families + 1)

            for x in 0..<Pixels.side {
                for y in 0..<Pixels.side {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let sat = Double(c.saturationComponent), bright = Double(c.brightnessComponent)
                    let isNeutral = sat < 0.18 || bright < 0.12
                    let family = isNeutral ? families : min(Int(Double(c.hueComponent) * Double(families)), families - 1)
                    let weight = (sat + 0.15) * (bright + 0.1)
                    sums[family].r += Double(c.redComponent) * weight
                    sums[family].g += Double(c.greenComponent) * weight
                    sums[family].b += Double(c.blueComponent) * weight
                    sums[family].weight += weight
                }
            }

            return sums.filter { $0.weight > 0 }
                .sorted { $0.weight > $1.weight }
                .prefix(2)
                .map { NSColor(deviceRed: $0.r / $0.weight, green: $0.g / $0.weight,
                               blue: $0.b / $0.weight, alpha: 1) }
        }
    }
}
