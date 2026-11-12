import CoreGraphics
import Foundation

/// Decides when pressing and holding the expanded panel should quit the app.
///
/// This is the secret way out for when the menu bar is hidden — an exam app
/// that locks the screen down, say — and the Quit item in it can't be reached.
///
/// It's pure logic on purpose: fed one sample at a time, with no window and no
/// mouse involved, so every rule below can be tested in a bare executable
/// without anything appearing on screen. The window feeds it from the cursor
/// poll that is already running, about sixteen times a second.
struct HoldToQuitDetector {

    /// One reading of where things stand.
    struct Sample {
        /// Seconds, on any clock that only goes forwards.
        let time: TimeInterval
        /// In the panel window's own coordinates, counted down from the top —
        /// the same space the views report their frames in.
        let point: CGPoint
        let buttonDown: Bool
        let panelExpanded: Bool
    }

    enum Outcome: Equatable {
        case idle
        /// `elapsed` is in seconds; `progress` runs from 0 to 1.
        case holding(elapsed: TimeInterval, progress: Double)
        case quit
    }

    var enabled = true
    var duration: TimeInterval = 2

    /// Moving further than this from where the press began cancels it. A hold
    /// stays put; anything that travels is a drag, and a drag never quits.
    var slop: CGFloat = 8

    /// The panel. A press has to begin inside it.
    var panelFrame: CGRect = .zero

    /// The bars and buttons. A press that begins on one of these is using that
    /// control, so holding the volume bar or the play button never quits.
    var controlFrames: [CGRect] = []

    private var start: (time: TimeInterval, point: CGPoint)?
    private var buttonWasDown = false

    mutating func feed(_ sample: Sample) -> Outcome {
        defer { buttonWasDown = sample.buttonDown }

        guard enabled, sample.panelExpanded else {
            start = nil
            return .idle
        }

        // Only the moment the button goes down can begin a hold. A press that
        // started somewhere else and was dragged in doesn't count, and nor does
        // one still held from before the panel opened.
        if sample.buttonDown && !buttonWasDown {
            let onControl = controlFrames.contains { $0.contains(sample.point) }
            start = (panelFrame.contains(sample.point) && !onControl)
                ? (sample.time, sample.point)
                : nil
        }

        guard sample.buttonDown, let began = start else {
            start = nil
            return .idle
        }

        let moved = hypot(sample.point.x - began.point.x, sample.point.y - began.point.y)
        if moved > slop {
            // Cancelled for good until the button is let go and pressed again.
            start = nil
            return .idle
        }

        let elapsed = sample.time - began.time
        if elapsed >= duration {
            start = nil
            return .quit
        }
        return .holding(elapsed: elapsed, progress: elapsed / duration)
    }
}
