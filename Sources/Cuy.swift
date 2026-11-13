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

// MARK: - Activities

/// What the cuy is doing at this moment, each with its own frames.
enum CuyActivity: Equatable {
    case sit, loaf, groom, nibble, yawn, walk, run, popcorn, sleep

    var framesPerSecond: Double {
        switch self {
        case .sit: return 5
        case .loaf, .sleep: return 3
        case .groom, .nibble: return 6
        case .yawn: return 5
        case .walk: return 8
        case .run: return 14
        case .popcorn: return 12
        }
    }

    /// Plays through once and is done, rather than looping.
    var playsOnce: Bool { self == .yawn || self == .popcorn }

    /// How long one play-through takes.
    var once: TimeInterval { Double(CuyArt.frames(for: self).count) / framesPerSecond }
}

/// The calm things it does when nothing's going on, how often each comes up,
/// and for how long. Plain logic, so Tools/test-cuy.sh can check it.
enum CuyRest {
    static let choices: [(activity: CuyActivity, weight: Double, seconds: ClosedRange<Double>)] = [
        (.sit, 3, 8...14), (.loaf, 2, 10...18), (.groom, 2, 3...5), (.nibble, 2, 5...8), (.yawn, 1, 1.4...1.4),
    ]

    /// The next rest, never the same one twice running. `roll` and `length`
    /// are 0..<1.
    static func next(after current: CuyActivity, roll: Double, length: Double) -> (CuyActivity, TimeInterval) {
        let options = choices.filter { $0.activity != current }
        let total = options.reduce(0) { $0 + $1.weight }
        var pick = roll * total
        for option in options {
            pick -= option.weight
            if pick < 0 {
                let range = option.seconds
                let seconds = option.activity.playsOnce ? option.activity.once
                    : range.lowerBound + (range.upperBound - range.lowerBound) * length
                return (option.activity, seconds)
            }
        }
        return (.sit, 10)
    }
}

/// The cuy in its room: where it is, which way it faces, and what it's
/// doing — decided a step at a time. Plain logic, given its random numbers
/// from outside, so Tools/test-cuy.sh can check it without a screen.
struct CuyRoomBrain {
    let width: CGFloat
    /// Where its house's door and its food bowl are, across the room.
    let house: CGFloat
    let bowl: CGFloat
    /// How close to the walls it can go: half its own width.
    let margin: CGFloat

    private(set) var x: CGFloat
    private(set) var facingRight = true
    private(set) var activity: CuyActivity = .sit
    private var until: TimeInterval = 0
    private var target: CGFloat?
    private var goingToEat = false

    init(width: CGFloat, house: CGFloat, bowl: CGFloat, margin: CGFloat) {
        self.width = width
        self.house = house
        self.bowl = bowl
        self.margin = margin
        self.x = width / 2
    }

    static let trot: CGFloat = 34          // points a second
    static let stroll: CGFloat = 26        // on the way to bed

    /// A click in the room: it popcorns.
    mutating func poke(now: TimeInterval) {
        activity = .popcorn
        until = now + CuyActivity.popcorn.once
        target = nil
    }

    mutating func step(mood: CuyMood, now: TimeInterval, dt: TimeInterval, roll: () -> Double) {
        let lo = margin, hi = width - margin
        if activity == .popcorn && now < until { return }      // let the jump finish

        switch mood {
        case .running(let pace):
            // Zoomies: laps from wall to wall, faster the busier memory is.
            activity = .run
            target = nil
            let speed = 90 + 90 * CGFloat(pace)
            x += (facingRight ? 1 : -1) * speed * CGFloat(dt)
            if x >= hi { x = hi; facingRight = false }
            if x <= lo { x = lo; facingRight = true }

        case .sleeping:
            // Off to bed by its house's door, then asleep.
            if abs(x - house) > 1 {
                activity = .walk
                facingRight = house > x
                x += (facingRight ? 1 : -1) * min(Self.stroll * CGFloat(dt), abs(house - x))
            } else {
                activity = .sleep
            }

        case .standby:
            if let goal = target {
                activity = .walk
                facingRight = goal > x
                x += (facingRight ? 1 : -1) * min(Self.trot * CGFloat(dt), abs(goal - x))
                if abs(goal - x) < 0.5 {
                    x = goal
                    target = nil
                    if goingToEat {
                        // At the bowl: eat for a while, facing it.
                        goingToEat = false
                        facingRight = true
                        activity = .nibble
                        until = now + 6 + 3 * roll()
                    } else if roll() < 0.12 {
                        activity = .popcorn
                        until = now + CuyActivity.popcorn.once
                    } else {
                        let (rest, seconds) = CuyRest.next(after: activity, roll: roll(), length: roll())
                        activity = rest
                        until = now + seconds
                    }
                }
            } else if now >= until || activity == .run || activity == .sleep {
                // Somewhere new: the bowl now and then, otherwise anywhere at
                // least a little way off.
                if roll() < 0.3 {
                    goingToEat = true
                    target = max(lo, min(hi, bowl - margin))
                } else {
                    var spot = lo + (hi - lo) * CGFloat(roll())
                    if abs(spot - x) < 30 { spot = x < width / 2 ? min(hi, x + 60) : max(lo, x - 60) }
                    target = spot
                }
            }
        }
    }
}

// MARK: - Watching the Mac

/// Keeps the cuy's mood current: checks the hour and the memory every five
/// seconds, while the cuy is switched on.
final class CuyWatcher: ObservableObject {
    static let shared = CuyWatcher()

    @Published private(set) var mood: CuyMood = .standby
    /// What the cuy in the bubble is doing: its mood's activity, or — when
    /// nothing's going on — one of its resting ones, changing every so often.
    @Published private(set) var bubbleActivity: CuyActivity = .sit
    private var restUntil = Date.distantPast
    private var ticks = 0
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
        // Once a second: the resting rotation. Every fifth: the hour and memory.
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.ticks += 1
            if self.ticks % 5 == 0 { self.check() }
            self.updateBubble()
        }
        tick.tolerance = 0.3
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
        updateBubble()
    }

    private func updateBubble() {
        let next: CuyActivity
        switch mood {
        case .sleeping: next = .sleep
        case .running: next = .run
        case .standby:
            let resting = [CuyActivity.sit, .loaf, .groom, .nibble, .yawn].contains(bubbleActivity)
            guard !resting || Date() >= restUntil else { return }
            let (rest, seconds) = CuyRest.next(after: bubbleActivity, roll: .random(in: 0..<1),
                                               length: .random(in: 0...1))
            restUntil = Date().addingTimeInterval(seconds)
            next = rest
        }
        if next != bubbleActivity { bubbleActivity = next }
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
    static let walking: [CGImage] = (0..<4).map { walkingFrame($0) }
    static let loafing: [CGImage] = (0..<10).map { loafFrame($0) }
    static let grooming: [CGImage] = (0..<6).map { groomFrame($0) }
    static let nibbling: [CGImage] = (0..<8).map { nibbleFrame($0) }
    static let yawning: [CGImage] = (0..<7).map { yawnFrame($0) }
    static let popcorning: [CGImage] = (0..<7).map { popcornFrame($0) }

    static func frames(for mood: CuyMood) -> [CGImage] {
        switch mood {
        case .standby: return standby
        case .sleeping: return sleeping
        case .running: return running
        }
    }

    static func frames(for activity: CuyActivity) -> [CGImage] {
        switch activity {
        case .sit: return standby
        case .loaf: return loafing
        case .groom: return grooming
        case .nibble: return nibbling
        case .yawn: return yawning
        case .walk: return walking
        case .run: return running
        case .popcorn: return popcorning
        case .sleep: return sleeping
        }
    }

    // A classic coat: cream, with a ginger saddle over the back and a ginger
    // patch on the head; soft pink ears, nose and feet; a black eye.
    private static let body = CGColor(srgbRed: 0.97, green: 0.94, blue: 0.89, alpha: 1)
    private static let ginger = CGColor(srgbRed: 0.86, green: 0.55, blue: 0.29, alpha: 1)
    private static let ear = CGColor(srgbRed: 0.88, green: 0.62, blue: 0.58, alpha: 1)
    private static let feet = CGColor(srgbRed: 0.95, green: 0.78, blue: 0.74, alpha: 1)
    private static let eye = CGColor(gray: 0, alpha: 1)
    private static let nose = CGColor(srgbRed: 0.93, green: 0.52, blue: 0.6, alpha: 1)

    /// The body: cream, with the ginger saddle over its back half.
    private static func bodyShape(_ c: CGContext, _ rect: CGRect) {
        fill(c, body, ellipse: rect)
        c.saveGState()
        c.addEllipse(in: rect)
        c.clip()
        c.setFillColor(ginger)
        c.fillEllipse(in: CGRect(x: rect.minX - rect.width * 0.15, y: rect.minY + rect.height * 0.3,
                                 width: rect.width * 0.7, height: rect.height * 1.1))
        c.restoreGState()
    }

    /// The head: cream, with a ginger patch over the top and back, around
    /// where the ear sits.
    private static func headShape(_ c: CGContext, _ rect: CGRect) {
        fill(c, body, ellipse: rect)
        c.saveGState()
        c.addEllipse(in: rect)
        c.clip()
        c.setFillColor(ginger)
        c.fillEllipse(in: CGRect(x: rect.minX - rect.width * 0.25, y: rect.minY + rect.height * 0.5,
                                 width: rect.width * 0.8, height: rect.height * 0.9))
        c.restoreGState()
    }

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
            bodyShape(c, CGRect(x: 2.5, y: 3, width: 19, height: 11 + breath))
            headShape(c, CGRect(x: 15, y: 5, width: 10.5, height: 9.5 + breath * 0.5))
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
            bodyShape(c, CGRect(x: 3, y: 3.4 + bob, width: 19.5, height: 10.4))
            headShape(c, CGRect(x: 15.5, y: 5.2 + bob, width: 10.5, height: 9))
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
            bodyShape(c, CGRect(x: 2, y: 1.8, width: 21, height: 9 + breath))
            headShape(c, CGRect(x: 15, y: 2.4, width: 10, height: 8 + breath * 0.5))
            fill(c, ear, ellipse: CGRect(x: 15.8, y: 9.2 + breath * 0.5, width: 4.4, height: 2.6))
            eyeClosed(c, at: CGPoint(x: 21, y: 6.6 + breath * 0.3))
            fill(c, nose, ellipse: CGRect(x: 24.2, y: 5.3, width: 1.2, height: 1))
            for offset in [0, 6] {
                let t = CGFloat((i + offset) % 12) / 12         // 0 → 1 as it rises
                z(c, at: CGPoint(x: 21.5 + t * 3, y: 11 + t * 6.5), size: 2.4 + t * 1.2, alpha: 1 - t)
            }
        }
    }

    // Trotting: like running, but gentler — a small bob, a shorter stride,
    // the ear up, no speed lines.
    private static func walkingFrame(_ i: Int) -> CGImage {
        let bob: CGFloat = i % 2 == 0 ? 0 : 0.5
        let back: [CGFloat] = [5, 6.5, 7.5, 6.5]
        let front: [CGFloat] = [18, 16.5, 15.5, 16.5]
        let lift: [CGFloat] = [1.4, 2, 1.4, 2]
        return draw { c in
            fill(c, feet, roundedRect: CGRect(x: back[i], y: lift[i], width: 3.2, height: 2.4))
            fill(c, feet, roundedRect: CGRect(x: front[i], y: lift[(i + 1) % 4], width: 3.2, height: 2.4))
            bodyShape(c, CGRect(x: 2.8, y: 3.2 + bob, width: 19.2, height: 10.8))
            headShape(c, CGRect(x: 15.2, y: 5.2 + bob, width: 10.5, height: 9.3))
            fill(c, ear, ellipse: CGRect(x: 16.2, y: 12.5 + bob, width: 4.4, height: 3))
            eyeOpen(c, at: CGPoint(x: 21.1, y: 10.4 + bob), closed: false)
            fill(c, nose, ellipse: CGRect(x: 24.5, y: 8.2 + bob, width: 1.3, height: 1.1))
        }
    }

    // Loafing: lying down, relaxed, eyes half shut — a slow breath, and one
    // long blink.
    private static func loafFrame(_ i: Int) -> CGImage {
        let breath = CGFloat(0.5 + 0.5 * sin(Double(i) / 10 * 2 * .pi)) * 0.5
        return draw { c in
            bodyShape(c, CGRect(x: 2.2, y: 2, width: 20.5, height: 10 + breath))
            headShape(c, CGRect(x: 15, y: 3.2, width: 10.2, height: 9 + breath * 0.5))
            fill(c, ear, ellipse: CGRect(x: 16, y: 10.5 + breath * 0.5, width: 4.4, height: 2.8))
            if i == 6 || i == 7 {
                eyeClosed(c, at: CGPoint(x: 21, y: 7.8))
            } else {
                // Half shut: a flattened eye.
                c.setFillColor(eye)
                c.fillEllipse(in: CGRect(x: 19.9, y: 7.6, width: 2.2, height: 1.1))
            }
            fill(c, nose, ellipse: CGRect(x: 24.3, y: 6.3, width: 1.2, height: 1))
        }
    }

    // Grooming: sitting up a touch, a front paw rubbing at its face, eyes
    // closed with contentment while it does.
    private static func groomFrame(_ i: Int) -> CGImage {
        let paw: [CGPoint] = [CGPoint(x: 22.2, y: 6.2), CGPoint(x: 22.8, y: 8), CGPoint(x: 23.4, y: 9.4),
                              CGPoint(x: 22.8, y: 8), CGPoint(x: 23.4, y: 9.4), CGPoint(x: 22.2, y: 6.2)]
        let tilt: CGFloat = (i == 2 || i == 4) ? -0.5 : 0
        return draw { c in
            fill(c, feet, roundedRect: CGRect(x: 6, y: 1.6, width: 3.2, height: 2.6))
            bodyShape(c, CGRect(x: 2.5, y: 3, width: 18.5, height: 12))
            headShape(c, CGRect(x: 14.5, y: 6 + tilt, width: 10.5, height: 9.5))
            fill(c, ear, ellipse: CGRect(x: 15.6, y: 13.4 + tilt, width: 4.4, height: 3))
            if i == 0 || i == 5 {
                eyeOpen(c, at: CGPoint(x: 20.6, y: 11.2 + tilt), closed: false)
            } else {
                eyeClosed(c, at: CGPoint(x: 20.6, y: 11.2 + tilt))
            }
            fill(c, nose, ellipse: CGRect(x: 23.9, y: 9 + tilt, width: 1.3, height: 1.1))
            // The paw, in front of the face.
            fill(c, feet, roundedRect: CGRect(x: paw[i].x - 1.5, y: paw[i].y - 1.2, width: 3, height: 2.6))
        }
    }

    // Nibbling: head down, chewing a strand of hay that gets shorter as it
    // goes, the jaw bobbing.
    private static func nibbleFrame(_ i: Int) -> CGImage {
        let chew: CGFloat = i % 2 == 0 ? 0 : 0.5
        let strand = max(0, 5 - CGFloat(i) * 0.6)
        return draw { c in
            fill(c, feet, roundedRect: CGRect(x: 6, y: 1.6, width: 3.2, height: 2.6))
            fill(c, feet, roundedRect: CGRect(x: 16.5, y: 1.6, width: 3.2, height: 2.6))
            bodyShape(c, CGRect(x: 2.5, y: 3, width: 19, height: 11))
            headShape(c, CGRect(x: 15.5, y: 3.2 + chew * 0.4, width: 10.5, height: 9))
            fill(c, ear, ellipse: CGRect(x: 16.6, y: 10.6, width: 4.4, height: 3))
            eyeOpen(c, at: CGPoint(x: 21.4, y: 8.4), closed: false)
            fill(c, nose, ellipse: CGRect(x: 24.9, y: 5.6 + chew, width: 1.3, height: 1.1))
            if strand > 0 {
                line(c, gray: 0.6, from: CGPoint(x: 25.2, y: 4.6 + chew), to: CGPoint(x: 25.2 + strand * 0.5, y: 4.6 - strand * 0.7 + chew),
                     width: 0.7)
            }
        }
    }

    // Yawning: head tips up, eyes close, the mouth opens wide and shuts.
    private static func yawnFrame(_ i: Int) -> CGImage {
        let open: [CGFloat] = [0, 0.6, 1.3, 1.6, 1.3, 0.6, 0]
        let lift: [CGFloat] = [0, 0.4, 0.8, 1, 0.8, 0.4, 0]
        return draw { c in
            fill(c, feet, roundedRect: CGRect(x: 6, y: 1.6, width: 3.2, height: 2.6))
            fill(c, feet, roundedRect: CGRect(x: 17, y: 1.6, width: 3.2, height: 2.6))
            bodyShape(c, CGRect(x: 2.5, y: 3, width: 19, height: 11))
            headShape(c, CGRect(x: 15, y: 5 + lift[i], width: 10.5, height: 9.5))
            fill(c, ear, ellipse: CGRect(x: 16.2, y: 12.4 + lift[i], width: 4.4, height: 3))
            if open[i] > 0.5 {
                eyeClosed(c, at: CGPoint(x: 21, y: 10.6 + lift[i]))
            } else {
                eyeOpen(c, at: CGPoint(x: 21, y: 10.4 + lift[i]), closed: false)
            }
            fill(c, nose, ellipse: CGRect(x: 24.3, y: 8.4 + lift[i], width: 1.3, height: 1.1))
            if open[i] > 0 {
                c.setFillColor(eye)
                c.fillEllipse(in: CGRect(x: 22.4, y: 6.6 + lift[i] - open[i] / 2, width: 2, height: open[i]))
            }
        }
    }

    // Popcorning: the happy jump — a hop straight up with a little twist,
    // feet kicked out, landing back where it started.
    private static func popcornFrame(_ i: Int) -> CGImage {
        let hop: [CGFloat] = [0, 2.5, 4.5, 5.2, 4.2, 2, 0]
        let twist: [CGFloat] = [0, -0.12, -0.2, 0.05, 0.18, 0.08, 0]
        return draw { c in
            c.saveGState()
            c.translateBy(x: 14, y: 8 + hop[i])
            c.rotate(by: twist[i])
            c.translateBy(x: -14, y: -8)
            let kick: CGFloat = hop[i] > 1 ? 1 : 0
            fill(c, feet, roundedRect: CGRect(x: 5 - kick, y: 1.6 - kick * 0.5, width: 3.2, height: 2.4))
            fill(c, feet, roundedRect: CGRect(x: 17 + kick, y: 1.6 - kick * 0.5, width: 3.2, height: 2.4))
            bodyShape(c, CGRect(x: 2.5, y: 3, width: 19, height: 11))
            headShape(c, CGRect(x: 15, y: 5, width: 10.5, height: 9.5))
            fill(c, ear, ellipse: CGRect(x: 16.2, y: 12.8 + kick * 0.4, width: 4.4, height: 3))
            eyeOpen(c, at: CGPoint(x: 21, y: 10.4), closed: false)
            fill(c, nose, ellipse: CGRect(x: 24.3, y: 8.1, width: 1.3, height: 1.1))
            c.restoreGState()
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
    let activity: CuyActivity
    /// Frames a second, when not the activity's own — running speeds up.
    var framesPerSecond: Double?
    let isVisible: Bool

    /// Set by the preview tool, whose renderer can't see layers.
    static var drawForSnapshot = false

    func makeNSView(context: Context) -> CuyNSView { CuyNSView() }

    func updateNSView(_ view: CuyNSView, context: Context) {
        view.configure(activity: activity, framesPerSecond: framesPerSecond ?? activity.framesPerSecond,
                       isVisible: isVisible)
    }

    static func dismantleNSView(_ view: CuyNSView, coordinator: ()) { view.stopFlipping() }
}

final class CuyNSView: NSView {
    private let picture = CALayer()
    private var frames: [CGImage] = []
    private var index = 0
    private var timer: Timer?
    private var activity: CuyActivity?
    private var framesPerSecond: Double = 5
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

    func configure(activity: CuyActivity, framesPerSecond: Double, isVisible: Bool) {
        if activity != self.activity || abs(framesPerSecond - self.framesPerSecond) > 0.5 {
            if activity != self.activity { index = 0 }
            self.activity = activity
            self.framesPerSecond = framesPerSecond
            frames = CuyArt.frames(for: activity)
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
        if wanted, timer == nil {
            let flip = Timer(timeInterval: 1 / framesPerSecond, repeats: true) { [weak self] _ in
                self?.advance()
            }
            flip.tolerance = 0.2 / framesPerSecond
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
        // A yawn plays once and holds its last frame until the next rest.
        if activity?.playsOnce == true && index == frames.count - 1 { return }
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

    static let width = NotchGeometry.cuyBubbleWidth
    static let gap = NotchGeometry.cuyBubbleGap

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(bottomLeadingRadius: 11, bottomTrailingRadius: 11, style: .continuous)
                .fill(Color.black)
            Group {
                if CuyView.drawForSnapshot {
                    Image(decorative: CuyArt.frames(for: watcher.bubbleActivity)[0], scale: 3)
                } else {
                    CuyView(activity: watcher.bubbleActivity,
                            framesPerSecond: watcher.bubbleActivity == .run ? watcher.mood.framesPerSecond : nil,
                            isVisible: isVisible)
                }
            }
            .frame(width: CuyArt.size.width, height: CuyArt.size.height)
            .offset(y: 3)
        }
        .frame(width: Self.width, height: height)
    }
}

// MARK: - The room

/// The cuy's room: what opens when you rest the cursor on its bubble. A
/// floor, a hidey-house on the left, a food bowl on the right, a little hay —
/// drawn once, in the same plain shapes as everything else on the notch —
/// and the cuy wandering about in it.
enum CuyRoom {
    static let size = CGSize(width: 340, height: 74)
    static let floor: CGFloat = 16              // up from the bottom
    static let cuyScale: CGFloat = 1.6          // the cuy, drawn a little bigger here
    static let house: CGFloat = 62              // where the house's door is, across
    static let bowl: CGFloat = 292

    static var cuySize: CGSize {
        CGSize(width: CuyArt.size.width * cuyScale, height: CuyArt.size.height * cuyScale)
    }

    static let furnishings: CGImage = {
        let scale: CGFloat = 3
        let c = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.scaleBy(x: scale, y: scale)
        c.setLineCap(.round)

        // The floor: one quiet line.
        c.setStrokeColor(CGColor(gray: 0.22, alpha: 1))
        c.setLineWidth(1)
        c.move(to: CGPoint(x: 6, y: floor))
        c.addLine(to: CGPoint(x: size.width - 6, y: floor))
        c.strokePath()

        // The house: a dome with an arched door, a step darker inside.
        let dome = CGRect(x: 18, y: floor, width: 64, height: 48)
        // Clipped at the floor first, then the shape added — clipping clears
        // the shape being built, so the other way round drew nothing.
        c.saveGState()
        c.clip(to: CGRect(x: 0, y: floor, width: size.width, height: size.height))
        c.setFillColor(CGColor(srgbRed: 0.42, green: 0.3, blue: 0.2, alpha: 1))
        c.addPath(CGPath(roundedRect: CGRect(x: dome.minX, y: dome.minY - dome.height * 0.4,
                                             width: dome.width, height: dome.height * 1.4),
                         cornerWidth: dome.width / 2, cornerHeight: dome.height * 0.7, transform: nil))
        c.fillPath()
        c.restoreGState()
        c.setFillColor(CGColor(gray: 0.04, alpha: 1))
        c.addPath(CGPath(roundedRect: CGRect(x: dome.midX - 13, y: floor, width: 26, height: 34),
                         cornerWidth: 13, cornerHeight: 13, transform: nil))
        c.fillPath()

        // The bowl, with food in it.
        c.setFillColor(CGColor(srgbRed: 0.85, green: 0.58, blue: 0.62, alpha: 1))
        c.fill(CGRect(x: bowl - 2, y: floor, width: 30, height: 9))
        c.setFillColor(CGColor(srgbRed: 0.55, green: 0.75, blue: 0.4, alpha: 1))
        for (dx, dy) in [(3.0, 9.0), (8.0, 10.0), (13.0, 9.0), (18.0, 10.5), (23.0, 9.0)] {
            c.fillEllipse(in: CGRect(x: bowl - 2 + dx, y: floor + dy, width: 3.5, height: 2.6))
        }

        // A small heap of hay in the middle of the room.
        c.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.76, blue: 0.45, alpha: 1))
        c.setLineWidth(1)
        for (x1, y1, x2, y2) in [(176.0, 0.0, 186.0, 7.0), (180.0, 0.0, 172.0, 6.0), (183.0, 0.0, 192.0, 5.0),
                                 (186.0, 0.0, 181.0, 8.0), (189.0, 0.0, 197.0, 4.0)] {
            c.move(to: CGPoint(x: x1, y: floor + y1))
            c.addLine(to: CGPoint(x: x2, y: floor + y2))
        }
        c.strokePath()
        return c.makeImage()!
    }()
}

/// The room on screen: the furnishings on one layer, the cuy on another,
/// moved and flipped through its frames about fifteen times a second while
/// the room is open, and not at all otherwise. A click makes it popcorn.
struct CuyRoomView: NSViewRepresentable {
    let isOpen: Bool

    func makeNSView(context: Context) -> CuyRoomNSView { CuyRoomNSView() }
    func updateNSView(_ view: CuyRoomNSView, context: Context) { view.setOpen(isOpen) }
    static func dismantleNSView(_ view: CuyRoomNSView, coordinator: ()) { view.setOpen(false) }
}

final class CuyRoomNSView: NSView {
    private let furnishings = CALayer()
    private let cuy = CALayer()
    private var brain = CuyRoomBrain(width: CuyRoom.size.width, house: CuyRoom.house,
                                     bowl: CuyRoom.bowl, margin: CuyRoom.cuySize.width / 2)
    private var timer: Timer?
    private var lastStep = Date()
    private var shownActivity: CuyActivity?
    private var phase: Double = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        furnishings.contents = CuyRoom.furnishings
        furnishings.contentsScale = 3
        furnishings.contentsGravity = .resize
        cuy.contentsScale = 3
        cuy.contentsGravity = .resizeAspect
        cuy.anchorPoint = CGPoint(x: 0.5, y: 0)
        for layer in [furnishings, cuy] {
            layer.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "transform": NSNull()]
            self.layer?.addSublayer(layer)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        brain.poke(now: Date().timeIntervalSinceReferenceDate)
        draw()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        furnishings.frame = bounds
        cuy.bounds = CGRect(origin: .zero, size: CuyRoom.cuySize)
        CATransaction.commit()
        draw()
    }

    func setOpen(_ open: Bool) {
        if open, timer == nil {
            lastStep = Date()
            let tick = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in self?.step() }
            tick.tolerance = 0.02
            RunLoop.main.add(tick, forMode: .common)
            timer = tick
            draw()
        } else if !open {
            timer?.invalidate()
            timer = nil
        }
    }

    private func step() {
        let now = Date()
        let dt = min(0.2, now.timeIntervalSince(lastStep))
        lastStep = now
        brain.step(mood: CuyWatcher.shared.mood, now: now.timeIntervalSinceReferenceDate, dt: dt) {
            Double.random(in: 0..<1)
        }
        if brain.activity != shownActivity {
            shownActivity = brain.activity
            phase = 0
        } else {
            var fps = brain.activity.framesPerSecond
            if brain.activity == .run { fps = CuyWatcher.shared.mood.framesPerSecond }
            phase += dt * fps
        }
        draw()
    }

    private func draw() {
        let frames = CuyArt.frames(for: brain.activity)
        guard !frames.isEmpty else { return }
        let index = brain.activity.playsOnce ? min(Int(phase), frames.count - 1) : Int(phase) % frames.count
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cuy.contents = frames[index]
        cuy.position = CGPoint(x: brain.x, y: CuyRoom.floor - 2)
        // The art faces right; facing left is the same picture, mirrored.
        cuy.transform = CATransform3DMakeScale(brain.facingRight ? 1 : -1, 1, 1)
        CATransaction.commit()
    }
}

/// What the panel shows when it opens as the cuy's room.
struct CuyRoomPanel: View {
    let geometry: NotchGeometry
    let isOpen: Bool

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.panelContentTop)
            Group {
                if CuyView.drawForSnapshot {
                    // The preview tool can't draw layers: a still of the room.
                    ZStack(alignment: .bottomLeading) {
                        Image(decorative: CuyRoom.furnishings, scale: 3)
                        Image(decorative: CuyArt.frames(for: .walk)[0], scale: 3 / CuyRoom.cuyScale)
                            .offset(x: 140, y: -(CuyRoom.floor - 2))
                    }
                } else {
                    CuyRoomView(isOpen: isOpen)
                }
            }
            .frame(width: CuyRoom.size.width, height: CuyRoom.size.height)
            Spacer(minLength: 0)
        }
        .frame(width: NotchGeometry.panelWidth, height: geometry.cuyRoomFrame.height, alignment: .top)
    }
}
