import AppKit
import Combine
import SwiftUI

// A cuy — a guinea pig — that lives in a little bubble beside the notch.
//
// It has three moods:
//  - standby: sitting, breathing, blinking now and then, twitching an ear;
//  - asleep, at night (11 PM to 7 AM): lying flatter, eye shut, breathing
//    slowly, with small z's drifting up;
//  - running, when the Mac's memory is busy (three-quarters used or more):
//    scurrying in place, faster the fuller memory gets. Busy memory wakes it
//    even at night.
//
// The art is drawn the way the notch draws everything else: plain white
// shapes on black, no outlines, no detail beyond what reads at this size.
// Each mood is a handful of still frames, drawn once and then flipped through
// a few times a second, like a flip-book — the cheapest way to animate
// something that's on screen all day.
//
// Opt-in: Settings ▸ "Keep a cuy on the notch".

// MARK: - Mood

enum CuyMood: Equatable {
    case standby
    case sleeping
    /// `pace` is 0...1: how hard it's running.
    case running(pace: Double)

    /// What the cuy should be doing, from the hour (0–23) and how much of
    /// the Mac's memory is in use (0...1). Plain logic, so
    /// Tools/test-cuy.sh can check it.
    static func now(hour: Int, memoryUsed: Double) -> CuyMood {
        if memoryUsed >= runningFrom {
            return .running(pace: min(1, (memoryUsed - runningFrom) / (1 - runningFrom - 0.05)))
        }
        if hour >= 23 || hour < 7 { return .sleeping }
        return .standby
    }

    /// Memory use at which it starts running.
    static let runningFrom = 0.75

    /// Flips a second.
    var framesPerSecond: Double {
        switch self {
        case .standby: return 5
        case .sleeping: return 3
        case .running(let pace): return 8 + 10 * pace
        }
    }
}

// MARK: - Watching the Mac

/// Keeps the cuy's mood current: checks the hour and the memory every five
/// seconds, while the cuy is switched on.
final class CuyWatcher: ObservableObject {
    static let shared = CuyWatcher()

    @Published private(set) var mood: CuyMood = .standby
    private var timer: Timer?
    private var settingWatch: AnyCancellable?

    private init() {
        settingWatch = Settings.shared.$cuyEnabled.sink { [weak self] on in
            DispatchQueue.main.async { on ? self?.start() : self?.stop() }
        }
    }

    private func start() {
        guard timer == nil else { return }
        check()
        let tick = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.check() }
        tick.tolerance = 1
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let hour = Calendar.current.component(.hour, from: Date())
        let next = CuyMood.now(hour: hour, memoryUsed: Self.memoryUsed())
        if next != mood {
            mood = next
            logLine("cuy: \(next)")
        }
    }

    /// The share of the Mac's memory in use, 0...1, counted the way Activity
    /// Monitor's "Memory Used" is: app memory, wired memory and compressed
    /// memory together. Asking the kernel for these needs no permission.
    static func memoryUsed() -> Double {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = Double(vm_kernel_page_size)
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let used = (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        return max(0, min(1, used / Double(ProcessInfo.processInfo.physicalMemory)))
    }
}

// MARK: - The art

/// The cuy's frames, drawn in code: white shapes on black, in a 28 × 20 point
/// box, facing right. Drawn once each, at three times size for sharpness.
enum CuyArt {

    static let size = CGSize(width: 28, height: 20)

    static let standby: [CGImage] = (0..<20).map { standbyFrame($0) }
    static let running: [CGImage] = (0..<4).map { runningFrame($0) }
    static let sleeping: [CGImage] = (0..<12).map { sleepingFrame($0) }

    static func frames(for mood: CuyMood) -> [CGImage] {
        switch mood {
        case .standby: return standby
        case .sleeping: return sleeping
        case .running: return running
        }
    }

    private static let body = CGColor(gray: 0.93, alpha: 1)
    private static let ear = CGColor(gray: 0.62, alpha: 1)
    private static let feet = CGColor(gray: 0.8, alpha: 1)
    private static let eye = CGColor(gray: 0, alpha: 1)
    private static let nose = CGColor(gray: 0.4, alpha: 1)

    // Sitting: a loaf of a body, the head at the front, a little ear, a dot
    // of an eye, a nose, two feet showing. Breathes over ten frames; blinks
    // twice, twitches an ear and wiggles its nose once in every twenty.
    private static func standbyFrame(_ i: Int) -> CGImage {
        let breath = CGFloat(0.5 + 0.5 * sin(Double(i) / 10 * 2 * .pi)) * 0.6
        let blink = i == 7 || i == 15
        let earUp: CGFloat = (i == 3 || i == 4) ? 0.9 : 0
        let sniff: CGFloat = (i == 11 || i == 12) ? 0.4 : 0
        return draw { c in
            fill(c, feet, roundedRect: CGRect(x: 6, y: 1.6, width: 3.2, height: 2.6))
            fill(c, feet, roundedRect: CGRect(x: 17, y: 1.6, width: 3.2, height: 2.6))
            fill(c, body, ellipse: CGRect(x: 2.5, y: 3, width: 19, height: 11 + breath))
            fill(c, body, ellipse: CGRect(x: 15, y: 5, width: 10.5, height: 9.5 + breath * 0.5))
            fill(c, ear, ellipse: CGRect(x: 16.2, y: 12.4 + earUp + breath * 0.5, width: 4.4, height: 3))
            eyeOpen(c, at: CGPoint(x: 21, y: 10.4 + breath * 0.4), closed: blink)
            fill(c, nose, ellipse: CGRect(x: 24.3, y: 8.1 + sniff, width: 1.3, height: 1.1))
        }
    }

    // Running in place: the body bobs, the ear lies back, the legs swap
    // front and back, and two short lines trail behind.
    private static func runningFrame(_ i: Int) -> CGImage {
        let bob: CGFloat = i % 2 == 0 ? 0 : 1
        let back: [CGFloat] = [3.5, 6, 8, 6]
        let front: [CGFloat] = [19, 16.5, 14.5, 16.5]
        let lift: [CGFloat] = [1.2, 2.2, 1.2, 2.2]
        return draw { c in
            fill(c, feet, roundedRect: CGRect(x: back[i], y: lift[i], width: 3.2, height: 2.4))
            fill(c, feet, roundedRect: CGRect(x: front[i], y: lift[(i + 1) % 4], width: 3.2, height: 2.4))
            fill(c, body, ellipse: CGRect(x: 3, y: 3.4 + bob, width: 19.5, height: 10.4))
            fill(c, body, ellipse: CGRect(x: 15.5, y: 5.2 + bob, width: 10.5, height: 9))
            fill(c, ear, ellipse: CGRect(x: 15.6, y: 11.9 + bob, width: 4.8, height: 2.4))
            eyeOpen(c, at: CGPoint(x: 21.4, y: 10.2 + bob), closed: false)
            fill(c, nose, ellipse: CGRect(x: 24.8, y: 8.2 + bob, width: 1.3, height: 1.1))
            // Speed lines, alternating in length.
            let long: CGFloat = i % 2 == 0 ? 3 : 2
            line(c, gray: 0.55, from: CGPoint(x: 2.2 - long, y: 10 + bob), to: CGPoint(x: 2.2, y: 10 + bob))
            line(c, gray: 0.55, from: CGPoint(x: 2.6 - (5 - long), y: 6.6 + bob), to: CGPoint(x: 2.6, y: 6.6 + bob))
        }
    }

    // Asleep: lying flat, the eye a closed curve, breathing slowly, and a
    // small z rising and fading above the head every twelve frames, with a
    // second one following halfway through.
    private static func sleepingFrame(_ i: Int) -> CGImage {
        let breath = CGFloat(0.5 + 0.5 * sin(Double(i) / 12 * 2 * .pi)) * 0.7
        return draw { c in
            fill(c, body, ellipse: CGRect(x: 2, y: 1.8, width: 21, height: 9 + breath))
            fill(c, body, ellipse: CGRect(x: 15, y: 2.4, width: 10, height: 8 + breath * 0.5))
            fill(c, ear, ellipse: CGRect(x: 15.8, y: 9.2 + breath * 0.5, width: 4.4, height: 2.6))
            eyeClosed(c, at: CGPoint(x: 21, y: 6.6 + breath * 0.3))
            fill(c, nose, ellipse: CGRect(x: 24.2, y: 5.3, width: 1.2, height: 1))
            for offset in [0, 6] {
                let t = CGFloat((i + offset) % 12) / 12         // 0 → 1 as it rises
                z(c, at: CGPoint(x: 21.5 + t * 3, y: 11 + t * 6.5), size: 2.4 + t * 1.2, alpha: 1 - t)
            }
        }
    }

    // MARK: Drawing helpers

    private static func draw(_ paint: (CGContext) -> Void) -> CGImage {
        let scale: CGFloat = 3
        let context = CGContext(data: nil,
                                width: Int(size.width * scale), height: Int(size.height * scale),
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.setShouldAntialias(true)
        paint(context)
        return context.makeImage()!
    }

    private static func fill(_ c: CGContext, _ color: CGColor, ellipse rect: CGRect) {
        c.setFillColor(color)
        c.fillEllipse(in: rect)
    }

    private static func fill(_ c: CGContext, _ color: CGColor, roundedRect rect: CGRect) {
        c.setFillColor(color)
        c.addPath(CGPath(roundedRect: rect, cornerWidth: rect.width / 2.2, cornerHeight: rect.height / 2.2,
                         transform: nil))
        c.fillPath()
    }

    private static func eyeOpen(_ c: CGContext, at p: CGPoint, closed: Bool) {
        if closed {
            line(c, gray: 0, from: CGPoint(x: p.x - 1.1, y: p.y), to: CGPoint(x: p.x + 1.1, y: p.y), width: 0.8)
        } else {
            c.setFillColor(eye)
            c.fillEllipse(in: CGRect(x: p.x - 1.05, y: p.y - 1.05, width: 2.1, height: 2.1))
        }
    }

    private static func eyeClosed(_ c: CGContext, at p: CGPoint) {
        c.setStrokeColor(eye)
        c.setLineWidth(0.8)
        c.setLineCap(.round)
        c.move(to: CGPoint(x: p.x - 1.3, y: p.y + 0.3))
        c.addQuadCurve(to: CGPoint(x: p.x + 1.3, y: p.y + 0.3), control: CGPoint(x: p.x, y: p.y - 0.9))
        c.strokePath()
    }

    private static func line(_ c: CGContext, gray: CGFloat, from a: CGPoint, to b: CGPoint, width: CGFloat = 0.9) {
        c.setStrokeColor(CGColor(gray: gray, alpha: 1))
        c.setLineWidth(width)
        c.setLineCap(.round)
        c.move(to: a)
        c.addLine(to: b)
        c.strokePath()
    }

    /// A small "z", drawn as three strokes.
    private static func z(_ c: CGContext, at p: CGPoint, size s: CGFloat, alpha: CGFloat) {
        c.setStrokeColor(CGColor(gray: 0.9, alpha: alpha))
        c.setLineWidth(0.75)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        c.move(to: CGPoint(x: p.x, y: p.y + s))
        c.addLine(to: CGPoint(x: p.x + s, y: p.y + s))
        c.addLine(to: CGPoint(x: p.x, y: p.y))
        c.addLine(to: CGPoint(x: p.x + s, y: p.y))
        c.strokePath()
    }
}

// MARK: - On screen

/// The cuy, flipping through its frames on a layer. Like the moving bars,
/// it stays off SwiftUI's drawing path: each flip just swaps the picture a
/// layer shows. It only flips while it can be seen.
struct CuyView: NSViewRepresentable {
    let mood: CuyMood
    let isVisible: Bool

    /// Set by the preview tool, whose renderer can't see layers.
    static var drawForSnapshot = false

    func makeNSView(context: Context) -> CuyNSView { CuyNSView() }

    func updateNSView(_ view: CuyNSView, context: Context) {
        view.configure(mood: mood, isVisible: isVisible)
    }

    static func dismantleNSView(_ view: CuyNSView, coordinator: ()) { view.stopFlipping() }
}

final class CuyNSView: NSView {
    private let picture = CALayer()
    private var frames: [CGImage] = []
    private var index = 0
    private var timer: Timer?
    private var mood: CuyMood?
    private var isVisible = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        picture.contentsGravity = .resizeAspect
        picture.contentsScale = 3
        picture.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(picture)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.frame = bounds
        CATransaction.commit()
    }

    func configure(mood: CuyMood, isVisible: Bool) {
        if mood != self.mood {
            self.mood = mood
            frames = CuyArt.frames(for: mood)
            index = 0
            show()
            timer?.invalidate()
            timer = nil
        }
        self.isVisible = isVisible
        updateFlipping()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateFlipping()
    }

    private func updateFlipping() {
        let wanted = window != nil && isVisible && frames.count > 1
        if wanted, timer == nil, let mood {
            let flip = Timer(timeInterval: 1 / mood.framesPerSecond, repeats: true) { [weak self] _ in
                self?.advance()
            }
            flip.tolerance = 0.2 / mood.framesPerSecond
            RunLoop.main.add(flip, forMode: .common)
            timer = flip
        } else if !wanted {
            stopFlipping()
        }
    }

    func stopFlipping() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        guard !frames.isEmpty else { return }
        index = (index + 1) % frames.count
        show()
    }

    private func show() {
        guard !frames.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.contents = frames[index % frames.count]
        CATransaction.commit()
    }
}

/// The cuy's home: a small black bubble to the left of the notch's bar,
/// rounded underneath like the bar, the way the Dynamic Island shows a
/// second, smaller bubble beside the main one.
struct CuyBubble: View {
    @ObservedObject var watcher = CuyWatcher.shared
    let height: CGFloat
    let isVisible: Bool

    static let width: CGFloat = 46
    static let gap: CGFloat = 6

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(bottomLeadingRadius: 11, bottomTrailingRadius: 11, style: .continuous)
                .fill(Color.black)
            Group {
                if CuyView.drawForSnapshot {
                    Image(decorative: CuyArt.frames(for: watcher.mood)[0], scale: 3)
                } else {
                    CuyView(mood: watcher.mood, isVisible: isVisible)
                }
            }
            .frame(width: CuyArt.size.width, height: CuyArt.size.height)
            .offset(y: 3)
        }
        .frame(width: Self.width, height: height)
    }
}
