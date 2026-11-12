import Foundation

// Tests for HoldToQuitDetector. Pure logic against synthetic samples: no window,
// no mouse, nothing on screen. Run with Tools/test-hold-to-quit.sh.

typealias Sample = HoldToQuitDetector.Sample

// The panel and its controls, in window coordinates counted down from the top —
// roughly where they really are, though only their relationships matter here.
let panel = CGRect(x: 16, y: 0, width: 360, height: 194)
let volumeBar = CGRect(x: 340, y: 42, width: 20, height: 130)
let playButton = CGRect(x: 162, y: 148, width: 34, height: 26)
let emptySpot = CGPoint(x: 260, y: 70)       // beside the song title
let outside = CGPoint(x: 5, y: 300)

/// The mouse watcher's real tick.
let tick: TimeInterval = 0.06

func detector(enabled: Bool = true, duration: TimeInterval = 2) -> HoldToQuitDetector {
    var d = HoldToQuitDetector()
    d.enabled = enabled
    d.duration = duration
    d.panelFrame = panel
    d.controlFrames = [volumeBar, playButton]
    return d
}

/// Feeds `seconds` of samples and reports when it quit, if it did.
func simulate(_ d: HoldToQuitDetector, seconds: TimeInterval,
              _ state: (TimeInterval) -> (point: CGPoint, down: Bool, expanded: Bool))
              -> (quitAt: TimeInterval?, progressAt1s: Double?) {
    var d = d
    var t: TimeInterval = 0
    var quitAt: TimeInterval?
    var progressAt1s: Double?
    while t <= seconds && quitAt == nil {
        let s = state(t)
        switch d.feed(Sample(time: t, point: s.point, buttonDown: s.down, panelExpanded: s.expanded)) {
        case .quit: quitAt = t
        case .holding(_, let p) where abs(t - 1.0) < tick / 2: progressAt1s = p
        default: break
        }
        t += tick
    }
    return (quitAt, progressAt1s)
}

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String) {
    print("  \(ok ? "PASS" : "FAIL")  \(name)  — \(detail)")
    if !ok { failures += 1 }
}
func when(_ t: TimeInterval?) -> String { t.map { String(format: "quit at %.2fs", $0) } ?? "never quit" }

print("Hold to quit\n")

// --- The thing working at all. If this fails every "never quit" below means
//     nothing, so it goes first.
var r = simulate(detector(), seconds: 4) { _ in (emptySpot, true, true) }
check("holding empty space quits", r.quitAt != nil && abs(r.quitAt! - 2.0) < tick * 1.5, when(r.quitAt))

r = simulate(detector(), seconds: 4) { t in (emptySpot, t < 2.5, true) }
check("progress is about half at the halfway mark",
      r.progressAt1s.map { abs($0 - 0.5) < 0.05 } ?? false,
      r.progressAt1s.map { String(format: "%.2f at 1.0s", $0) } ?? "no progress reported")

r = simulate(detector(duration: 4), seconds: 6) { _ in (emptySpot, true, true) }
check("a longer setting waits longer", r.quitAt != nil && abs(r.quitAt! - 4.0) < tick * 1.5,
      when(r.quitAt) + " with a 4s setting")

r = simulate(detector(), seconds: 4) { t in
    // A real hand isn't perfectly still: a 5pt tremble, inside the slop.
    (CGPoint(x: emptySpot.x + 5 * sin(t * 9), y: emptySpot.y), true, true)
}
check("a little wobble still counts", r.quitAt != nil, when(r.quitAt))

// --- Ordinary use must never quit.
r = simulate(detector(), seconds: 4) { t in (emptySpot, t < 1.0, true) }
check("letting go early does nothing", r.quitAt == nil, when(r.quitAt))

r = simulate(detector(), seconds: 4) { _ in
    (CGPoint(x: volumeBar.midX, y: volumeBar.midY), true, true)
}
check("holding the volume bar does nothing", r.quitAt == nil, when(r.quitAt))

r = simulate(detector(), seconds: 4) { t in
    // Pressing on the volume bar and dragging it down, off the bar and across
    // empty panel — the drag that matters most not to quit.
    (CGPoint(x: volumeBar.midX - CGFloat(t) * 40, y: volumeBar.midY), true, true)
}
check("dragging volume across empty space does nothing", r.quitAt == nil, when(r.quitAt))

r = simulate(detector(), seconds: 4) { _ in
    (CGPoint(x: playButton.midX, y: playButton.midY), true, true)
}
check("holding play/pause does nothing", r.quitAt == nil, when(r.quitAt))

r = simulate(detector(), seconds: 4) { _ in (outside, true, true) }
check("holding outside the panel does nothing", r.quitAt == nil, when(r.quitAt))

r = simulate(detector(), seconds: 4) { t in
    // Pressed outside, then dragged in and held still on empty space.
    (t < 0.5 ? outside : emptySpot, true, true)
}
check("a press dragged in from outside does nothing", r.quitAt == nil, when(r.quitAt))

r = simulate(detector(), seconds: 5) { t in
    // Moves 30pt away at 0.5s — that's a drag — then comes back and sits still.
    let point = (t > 0.5 && t < 1.0) ? CGPoint(x: emptySpot.x + 30, y: emptySpot.y) : emptySpot
    return (point, true, true)
}
check("a cancelled hold doesn't restart without letting go", r.quitAt == nil, when(r.quitAt))

r = simulate(detector(), seconds: 5) { t in
    (emptySpot, t < 1.0 || t > 1.3, true)       // let go briefly, then press again
}
check("letting go and pressing again starts over", r.quitAt != nil && r.quitAt! > 3.0,
      when(r.quitAt) + " (the second press began at ~1.3s)")

r = simulate(detector(enabled: false), seconds: 4) { _ in (emptySpot, true, true) }
check("switched off in settings does nothing", r.quitAt == nil, when(r.quitAt))

r = simulate(detector(), seconds: 4) { t in (emptySpot, true, t > 0.5) }
check("a press made before the panel opened does nothing", r.quitAt == nil, when(r.quitAt))

r = simulate(detector(), seconds: 4) { t in (emptySpot, true, t < 1.0) }
check("the panel closing mid-hold cancels it", r.quitAt == nil, when(r.quitAt))

print(failures == 0 ? "\nAll passed." : "\n\(failures) failed.")
exit(failures == 0 ? 0 : 1)
