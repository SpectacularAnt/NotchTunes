import AppKit

/// Where the notch is, and where the two tabs that poke out of its sides go.
///
/// All the measuring lives here so the window and the view can never disagree
/// about it.
struct NotchGeometry {

    let screen: NSScreen
    let notch: NSRect

    /// How far the black bar reaches out past each side of the notch. The notch's
    /// own height, so each side is a square.
    var sideWidth: CGFloat { notch.height }

    /// How much smaller the artwork is than the square it sits in, so it doesn't
    /// touch the edges of the bar.
    static let contentInset: CGFloat = 3.5

    /// How much wider than the bar the hover area is, at each side.
    static let revealMargin: CGFloat = 10

    static let panelWidth: CGFloat = 380

    /// How tall the controls part of the panel is — the part below the notch,
    /// with the player in it and no clipboard. The panel itself is this plus
    /// the notch's own height, because its black reaches all the way to the
    /// top of the screen.
    static let panelContentHeight: CGFloat = 170

    /// The player and volume, without the gaps above and below.
    static let controlsHeight: CGFloat = 144

    /// The clipboard section, when something is stored in it: a line, a
    /// heading with Clear, and a row of tiles.
    static let shelfHeight: CGFloat = 112

    /// The part of the drop area below the notch.
    static let dropContentHeight: CGFloat = 112

    /// How thick the drawn part of both bars is — the scrubber and the volume.
    /// They match on purpose.
    ///
    /// Control Center's own track measures 4pt; this is a little heavier than
    /// that by choice.
    static let barThickness: CGFloat = 6

    /// How big the knob is. A fixed size rather than a multiple of the track:
    /// about how big the thing wants to be to read and to grab, whatever the
    /// track beneath it is doing.
    ///
    /// A slightly stretched pill rather than a circle — longer along the bar
    /// than across it — which is the shape macOS's own sliders use, Music's
    /// mini player among them. Across, it's the 14pt Control Center's
    /// round knob measured.
    static let knobThickness: CGFloat = 14
    static let knobLength: CGFloat = 20

    /// How thick each bar is to the mouse. Much bigger than what's drawn, so a
    /// thin bar is still easy to grab.
    static let barHitThickness: CGFloat = 20

    /// The breathing room around the controls. Generous, as the Dynamic
    /// Island's is.
    static let panelPadding: CGFloat = 20

    /// The black bar: the notch plus a square on each side, the full height of
    /// the notch and flush with the top of the screen. Drawn as one solid shape
    /// across the notch, so it reads as the notch itself being wider rather than
    /// as two tabs stuck to its sides.
    ///
    /// Measured down from the top of the screen and rounded to whole points. The
    /// notch is 33.5pt tall on this Mac, and a frame on a half point leaves
    /// SwiftUI centring its layout inside the window — which showed up as a
    /// hairline of wallpaper along the very top edge.
    var barFrame: NSRect {
        let height = notch.height.rounded()
        let width = (notch.width + sideWidth * 2).rounded()
        return NSRect(x: (notch.midX - width / 2).rounded(),
                      y: screen.frame.maxY - height,
                      width: width,
                      height: height)
    }

    /// The expanded panel. Its black runs all the way up to the top of the screen
    /// rather than starting below the notch, so it reads as the notch itself
    /// having grown downwards instead of a separate slab hanging off it. The
    /// controls live in the part below the notch.
    var panelFrame: NSRect { panelFrame(player: true, shelf: false) }

    /// The panel with or without its two parts. The clipboard adds itself
    /// under the player while something is stored; with nothing playing, the
    /// clipboard is all there is.
    func panelFrame(player: Bool, shelf: Bool) -> NSRect {
        let gaps = 8 + NotchGeometry.panelBottomPadding
        let content = gaps + (player ? NotchGeometry.controlsHeight : 0)
                           + (shelf ? NotchGeometry.shelfHeight : 0)
        return frameBelowNotch(content: content)
    }

    /// The cuy's bubble, to the left of the bar.
    static let cuyBubbleWidth: CGFloat = 46
    static let cuyBubbleGap: CGFloat = 6

    /// Where the cuy's bubble is, give or take a few points to the left —
    /// resting the cursor here opens its room.
    var cuyZone: NSRect {
        let width = NotchGeometry.cuyBubbleWidth + NotchGeometry.revealMargin
        return NSRect(x: barFrame.minX - NotchGeometry.cuyBubbleGap - width, y: barFrame.minY,
                      width: width + NotchGeometry.cuyBubbleGap / 2,
                      height: screen.frame.maxY - barFrame.minY)
    }

    /// The cuy's room, when it's open: the room and the gaps around it.
    var cuyRoomFrame: NSRect { frameBelowNotch(content: 8 + 74 + 16) }

    /// The area that opens to take a drop.
    var dropFrame: NSRect { frameBelowNotch(content: NotchGeometry.dropContentHeight) }

    private func frameBelowNotch(content: CGFloat) -> NSRect {
        let height = (content + notch.height).rounded()
        return NSRect(x: (notch.midX - NotchGeometry.panelWidth / 2).rounded(),
                      y: screen.frame.maxY - height,
                      width: NotchGeometry.panelWidth,
                      height: height)
    }

    /// How close something being dragged has to come for the drop area to
    /// open: a generous band across the top of the screen around the notch,
    /// so it opens as you head for it rather than once you've arrived.
    var dragApproachZone: NSRect {
        let width = NotchGeometry.panelWidth + 240
        let depth: CGFloat = 220
        return NSRect(x: notch.midX - width / 2,
                      y: screen.frame.maxY - depth,
                      width: width,
                      height: depth)
    }

    /// The breathing room under the controls.
    static let panelBottomPadding: CGFloat = 18

    /// How round the panel's bottom corners are. Large, like the Dynamic
    /// Island's, which reads as one smooth pill rather than a box.
    static let panelCornerRadius: CGFloat = 34

    /// How far down the panel its controls start: clear of the notch, plus a gap.
    var panelContentTop: CGFloat { notch.height.rounded() + 8 }

    /// Slack around the panel inside the window. The expand animation is a spring
    /// that overshoots a little, and without room to do that it would be clipped
    /// by the edge of the window at the very moment it is meant to look bouncy.
    static let overshootRoom: CGFloat = 16

    /// One window covers both states, so collapsing and expanding is a change of
    /// what is drawn rather than a window resize. Grown at the sides and bottom
    /// to leave the spring somewhere to overshoot; the top stays flush with the
    /// top of the screen, which is the one edge that must not move.
    var windowFrame: NSRect {
        let room = NotchGeometry.overshootRoom
        // Sized for the biggest the panel gets — the player and the clipboard
        // together — so everything else is just a change of what's drawn.
        let base = barFrame.union(panelFrame(player: true, shelf: true)).union(dropFrame)
        return NSRect(x: base.minX - room,
                      y: base.minY - room,
                      width: base.width + room * 2,
                      height: base.height + room)
    }

    /// Where the cursor has to be for the panel to open: the bar itself, give or
    /// take a few points at the sides.
    ///
    /// This stops at the bottom of the menu bar and never reaches below it. That
    /// matters more than it looks: an earlier version reached 64pt further down
    /// to be easier to hit, and it swallowed clicks meant for whatever was
    /// underneath — a browser's tab strip sits exactly there. Opening the panel
    /// makes it take mouse events, so the click lands on the panel instead of
    /// the tab.
    ///
    /// It no longer needs that reach. The bar is on screen the whole time a song
    /// is loaded, so there is something visible to aim at, and the panel can
    /// only open while a song is loaded anyway.
    var revealZone: NSRect {
        let margin = NotchGeometry.revealMargin
        return NSRect(x: barFrame.minX - margin,
                      y: barFrame.minY,
                      width: barFrame.width + margin * 2,
                      height: screen.frame.maxY - barFrame.minY)
    }

    /// Measures the screen that has a notch, falling back to the main screen.
    static func current() -> NotchGeometry? {
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = notched ?? NSScreen.main else { return nil }
        return NotchGeometry(screen: screen, notch: notchRect(on: screen))
    }

    /// macOS hands us the two menu bar areas either side of the notch, so the
    /// gap between them is the notch itself. On a Mac without one we pretend
    /// there is a notch-sized gap in the middle, so the tabs still land sensibly.
    private static func notchRect(on screen: NSScreen) -> NSRect {
        let height = max(screen.safeAreaInsets.top, 24)
        let top = screen.frame.maxY - height

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NSRect(x: left.maxX, y: top, width: right.minX - left.maxX, height: height)
        }

        let assumedWidth: CGFloat = 185
        return NSRect(x: screen.frame.midX - assumedWidth / 2, y: top,
                      width: assumedWidth, height: height)
    }
}
