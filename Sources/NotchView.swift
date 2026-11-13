import SwiftUI

/// A rectangle with square corners along the top and rounded ones underneath,
/// whose corner radius can be animated.
///
/// The top is square because it sits flush against the top edge of the screen,
/// continuing the real notch. `Animatable` is what lets the radius grow along
/// with the shape instead of jumping at the start of the animation.
private struct NotchShape: Shape, Animatable {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                              control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                              control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
        }
    }
}

/// The notch in both of its states.
///
/// There is **one** black shape, and expanding grows it from the size of the bar
/// to the size of the panel. That is what makes it look like the notch itself
/// stretching, rather than one view fading into another: the black is never
/// interrupted, it just changes size.
///
/// Collapsed it reaches a square out either side of the notch — artwork on the
/// left, playing-or-paused on the right. Expanded it carries the controls.
struct NotchView: View {
    @ObservedObject var model: NowPlayingModel
    let geometry: NotchGeometry
    let control: PlayerControl

    @ObservedObject private var settings = Settings.shared

    private var expanded: Bool { model.isExpanded }
    private var dropping: Bool { model.isDropTarget }
    private var room: Bool { model.isCuyRoom }

    /// Whether the bar itself has anything to show. With nothing playing and
    /// nothing in the clipboard, the notch is only up for the cuy, and the bar
    /// stays out of the way.
    private var barHasContent: Bool { model.track != nil || !model.shelf.isEmpty }
    /// Grown below the notch, any way.
    private var open: Bool { expanded || dropping || room }

    /// The size the black grows to: the drop area while something's being
    /// dragged in, otherwise the panel — taller while the clipboard has
    /// something in it, and only the clipboard if nothing's playing.
    private var panel: NSRect {
        dropping ? geometry.dropFrame
            : room ? geometry.cuyRoomFrame
            : geometry.panelFrame(player: model.track != nil, shelf: !model.shelf.isEmpty)
    }

    /// Slightly bouncy, and quick enough not to feel like waiting. The damping
    /// is what allows a small overshoot at the end — `NotchGeometry.overshootRoom`
    /// is the space it needs.
    private static let grow = Animation.spring(response: 0.34, dampingFraction: 0.78)

    var body: some View {
        let cuyShown = settings.cuyEnabled && model.isOnScreen && !open

        return ZStack(alignment: .top) {
            // The cuy's bubble, beside the bar on the left. Steps aside while
            // the panel or the drop area is open, and comes back after.
            CuyBubble(height: geometry.barFrame.height, isVisible: cuyShown)
                .offset(x: -(geometry.barFrame.width / 2 + CuyBubble.gap + CuyBubble.width / 2))
                .opacity(cuyShown ? 1 : 0)
                .scaleEffect(cuyShown ? 1 : 0.6, anchor: .top)
                .animation(cuyShown ? .spring(response: 0.4, dampingFraction: 0.75).delay(0.1)
                                    : .easeIn(duration: 0.12),
                           value: cuyShown)
                .allowsHitTesting(false)

            NotchShape(bottomRadius: open ? NotchGeometry.panelCornerRadius : 11)
                .fill(Color.black)
                .frame(width: open ? panel.width : geometry.barFrame.width,
                       height: open ? panel.height : geometry.barFrame.height)
                .opacity(open || barHasContent ? 1 : 0)
                // Springs on opening and closing, and on growing or shrinking
                // while open — the clipboard arriving, or being cleared.
                .animation(NotchView.grow, value: open)
                .animation(NotchView.grow, value: panel.height)

            // Leaves quickly on the way out, and comes back only once the shape
            // has shrunk back down, so it never shows against the wrong size.
            barContents
                .opacity(open || !barHasContent ? 0 : 1)
                .animation(open ? .easeOut(duration: 0.1)
                                : .easeIn(duration: 0.14).delay(0.12),
                           value: open)

            // The cuy's room, when it's the cuy's bubble you rested on.
            CuyRoomPanel(geometry: geometry, isOpen: room)
                .opacity(room ? 1 : 0)
                .animation(room ? .easeOut(duration: 0.22).delay(0.1) : .easeIn(duration: 0.1), value: room)
                .allowsHitTesting(room)

            // The open area that appears while something's dragged towards
            // the notch.
            DropArea(model: model, geometry: geometry)
                .opacity(dropping ? 1 : 0)
                .animation(dropping ? .easeOut(duration: 0.18).delay(0.06)
                                    : .easeIn(duration: 0.1),
                           value: dropping)
                .allowsHitTesting(dropping)

            // Arrives just after the shape starts growing, drifting down a few
            // points, as though it were coming out from behind the notch.
            ControlPanel(model: model, control: control, geometry: geometry)
                .opacity(expanded ? 1 : 0)
                .offset(y: expanded ? 0 : -10)
                .animation(expanded ? .easeOut(duration: 0.22).delay(0.08)
                                    : .easeIn(duration: 0.1),
                           value: expanded)
                .allowsHitTesting(expanded)
        }
        .frame(width: geometry.windowFrame.width,
               height: geometry.windowFrame.height,
               alignment: .top)
    }

    // MARK: - Collapsed: what sits either side of the notch

    private var barContents: some View {
        HStack(spacing: 0) {
            artworkSide
            // Nothing is drawn here — this is where the notch itself sits.
            Color.clear.frame(width: geometry.notch.width)
            statusSide
        }
        .frame(width: geometry.barFrame.width, height: geometry.barFrame.height)
        .allowsHitTesting(false)
    }

    /// The album art, inset slightly so it doesn't touch the edges of the bar.
    private var artworkSide: some View {
        let inner = geometry.sideWidth - NotchGeometry.contentInset * 2

        return ZStack {
            if let image = model.track?.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.14)
                // With nothing playing, the bar is only up because the
                // clipboard has something in it, so it says so.
                Image(systemName: model.track == nil ? "tray.full.fill" : "music.note")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(width: inner, height: inner)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(width: geometry.sideWidth, height: geometry.barFrame.height)
    }

    /// Playing or paused, the way the Dynamic Island shows it: bars moving to
    /// the music, tinted from the cover, that settle into dots when it stops.
    @ViewBuilder
    private var statusSide: some View {
        if model.track == nil {
            // Nothing playing: how many things are in the clipboard instead.
            Text("\(model.shelf.count)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: geometry.sideWidth, height: geometry.barFrame.height)
        } else {
            playingBars
        }
    }

    private var playingBars: some View {
        Waveform(isPlaying: model.track?.isPlaying ?? false,
                 color: model.accent,
                 height: 12,
                 // Only while the bar is what's showing: not while the panel
                 // covers it, and not while the whole notch is hidden.
                 isVisible: model.isOnScreen && !expanded)
            .opacity((model.track?.isPlaying ?? false) ? 1 : 0.6)
            .frame(width: geometry.sideWidth, height: geometry.barFrame.height)
    }
}

// MARK: - Expanded: the controls

/// Lets each bar report where it was laid out, so the hover check has real
/// frames to test against instead of a second copy of the layout maths.
private struct BarFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The same for the transport buttons. Kept apart from the bars because the
/// bars' frames also decide which one shows its knob, and a button never should.
private struct ButtonFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// A thin bar you drag that fills from one end, with a knob that appears as the
/// cursor comes near — the way Control Center's sound and brightness bars behave.
///
/// The knob is only there when you're about to use it, so at rest the bar stays
/// a clean line. It also stays up for the whole of a drag, even if the cursor
/// wanders off the bar, so it doesn't vanish mid-adjustment.
///
/// There is no knob to catch when idle: clicking anywhere jumps to that value.
/// What's drawn is thin, but what the mouse can hit is much thicker.
private struct FillBar: View {
    enum Direction { case up, right }

    let direction: Direction
    let fraction: Double                 // 0...1
    /// Identifies this bar to the hover check and the log line.
    let name: String
    /// Whether the cursor is over it. Worked out from the polled cursor
    /// position rather than `.onHover`, which never fires for this window.
    let isHovered: Bool
    var trackOpacity: Double = 0.2
    /// Grey rather than white, as the Dynamic Island's scrubber is.
    var fillOpacity: Double = 0.6

    let onDrag: (Double) -> Void
    let onRelease: () -> Void

    @State private var dragging = false

    var body: some View {
        let showKnob = isHovered || dragging || forceKnobsVisible
        let thickness = NotchGeometry.barThickness
        let knob = NotchGeometry.knobLength          // along the bar
        let knobAcross = NotchGeometry.knobThickness

        return GeometryReader { geo in
            let length = direction == .up ? geo.size.height : geo.size.width
            let filled = max(0, min(1, fraction))

            // The fill never shrinks below one bar-thickness, so it stays a
            // capsule rather than collapsing to a sliver.
            let fillLength = max(thickness, length * filled)

            // The knob rides the fill's *drawn* edge, not the raw fraction. Near
            // zero those two disagree — the fill has been held at its minimum
            // while the fraction keeps falling — and the knob drifts behind the
            // edge it is meant to mark.
            let centre = min(max(fillLength, knob / 2), length - knob / 2)

            ZStack(alignment: direction == .up ? .bottom : .leading) {
                Capsule().fill(Color.white.opacity(trackOpacity))

                Capsule()
                    .fill(Color.white.opacity(fillOpacity))
                    .frame(width: direction == .right ? fillLength : nil,
                           height: direction == .up ? fillLength : nil)
            }
            // The thin bar, centred inside the much thicker area the mouse sees.
            .frame(width: direction == .right ? geo.size.width : thickness,
                   height: direction == .up ? geo.size.height : thickness)
            // The knob goes in an overlay, NOT in the stack above. A ZStack
            // takes the size of its largest child, so a knob wider than the
            // track would stretch the track out to match it — which is exactly
            // what happened, and made a 4pt bar draw 14pt thick. An overlay
            // doesn't affect the size of what it sits on.
            .overlay(alignment: direction == .up ? .bottom : .leading) {
                Capsule()
                    .fill(Color.white)
                    // Lying along the bar: wide on the scrubber, tall on the
                    // volume.
                    .frame(width: direction == .right ? knob : knobAcross,
                           height: direction == .up ? knob : knobAcross)
                    // Against the light fill the knob would otherwise vanish;
                    // the shadow is what gives it an edge.
                    .shadow(color: .black.opacity(0.55), radius: 2.5)
                    .offset(x: direction == .right ? centre - knob / 2 : 0,
                            y: direction == .up ? -(centre - knob / 2) : 0)
                    // Fades in and out where it is, as macOS's sliders' knobs
                    // do — no growing out of the bar.
                    .opacity(showKnob ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: showKnob)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .background(
                GeometryReader { inner in
                    Color.clear.preference(key: BarFramesKey.self,
                                           value: [name: inner.frame(in: .global)])
                }
            )
            .gesture(
                // minimumDistance 0 so a plain click counts, rather than needing
                // a drag before anything happens.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        let p = direction == .up
                            ? 1 - value.location.y / geo.size.height
                            : value.location.x / geo.size.width
                        onDrag(max(0, min(1, p)))
                    }
                    .onEnded { _ in
                        dragging = false
                        onRelease()
                    }
            )
        }
    }
}

/// The expanded panel, laid out like the Dynamic Island's music view: artwork
/// and the song at the top, the scrubber under it, transport buttons below —
/// with the volume standing vertically down the right-hand edge.
///
/// The black behind all of this belongs to the shape in `NotchView`, so that it
/// can be one continuous thing that grows.
private struct ControlPanel: View {
    @ObservedObject var model: NowPlayingModel
    let control: PlayerControl
    let geometry: NotchGeometry

    /// While you drag, and for a moment after you let go, the control shows your
    /// value instead of the polled one. Without this the poll would drag it back
    /// out from under your finger.
    @State private var heldPosition: Double?
    @State private var heldVolume: Double?
    @State private var lastSentVolume: Int?

    var body: some View {
        let holding = model.holdProgress != nil

        let hasPlayer = model.track != nil
        let hasShelf = !model.shelf.isEmpty

        return VStack(spacing: 0) {
            if hasPlayer {
                HStack(spacing: 14) {
                    player
                    volume.frame(width: NotchGeometry.barHitThickness)
                }
                .frame(height: NotchGeometry.controlsHeight)
            }
            if hasShelf {
                ShelfSection(model: model, showsDivider: hasPlayer)
                    .frame(height: NotchGeometry.shelfHeight, alignment: .top)
                    // Fades in a beat behind the black growing to make room,
                    // and out quickly before it shrinks back.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.1)),
                        removal: .opacity.animation(.easeIn(duration: 0.08))))
            }
        }
        .padding(.horizontal, NotchGeometry.panelPadding)
        // Clear of the notch: the black starts at the top of the screen, but the
        // notch is physically in the way of that first stretch.
        .padding(.top, geometry.panelContentTop)
        .padding(.bottom, NotchGeometry.panelBottomPadding)
        // Mid-hold the controls fall back, so the hint reads as the one thing
        // happening.
        .opacity(holding ? 0.15 : 1)
        .animation(.easeOut(duration: 0.15), value: holding)
        .frame(width: NotchGeometry.panelWidth,
               height: geometry.panelFrame(player: hasPlayer, shelf: hasShelf).height,
               alignment: .top)
        .overlay {
            // Centred in the part of the panel below the notch, not the whole
            // panel, which would put it too high.
            VStack(spacing: 0) {
                Color.clear.frame(height: geometry.panelContentTop)
                holdHint.frame(maxWidth: .infinity, maxHeight: .infinity)
                Color.clear.frame(height: NotchGeometry.panelBottomPadding)
            }
            .opacity(holding ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: holding)
            .allowsHitTesting(false)
        }
        .onPreferenceChange(BarFramesKey.self) { frames in
            // Not @Published, so this doesn't start a layout loop.
            model.barFrames = frames
        }
        .onPreferenceChange(ButtonFramesKey.self) { frames in
            model.buttonFrames = frames
        }
    }

    /// What appears once a press on the panel has become a hold: what's about to
    /// happen and how far along it is. It only shows once you're already doing
    /// it, so otherwise the way out stays a secret.
    private var holdHint: some View {
        let progress = model.holdProgress ?? 0
        let width: CGFloat = 150

        return VStack(spacing: 10) {
            Image(systemName: "power")
                .font(.system(size: 20, weight: .semibold))
            Text("Keep holding to quit")
                .font(.system(size: 11, weight: .semibold))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(NotchGeometry.barThickness, width * progress))
            }
            .frame(width: width, height: NotchGeometry.barThickness)
            // Progress arrives with each tick of the cursor poll, about 60ms
            // apart; this smooths the steps between them.
            .animation(.linear(duration: 0.06), value: progress)
        }
        .foregroundStyle(.white)
    }

    // MARK: Left — the player

    /// Laid out as the Dynamic Island lays out its music: the cover and song
    /// along the top with the moving bars at the far end, the scrubber across
    /// the middle, and the buttons along the bottom.
    private var player: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.track?.title ?? "Nothing playing")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(model.track?.artist ?? "")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 9)
                Spacer(minLength: 8)
                Waveform(isPlaying: model.track?.isPlaying ?? false,
                         color: model.accent,
                         height: 18,
                         // The panel's bars exist while it's closed, just
                         // invisible; they only need to move while it's open.
                         isVisible: model.isExpanded)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)
            scrubber
            Spacer(minLength: 0)
            transport
        }
    }

    private var artwork: some View {
        ZStack {
            if let image = model.track?.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.12)
                Image(systemName: "music.note")
                    .font(.system(size: 19))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    /// Elapsed on the left, time left on the right, the way a phone shows it.
    /// Seeking only happens when you let go — a track lurching about while you
    /// drag would be unusable.
    private var scrubber: some View {
        let duration = max(model.track?.duration ?? 1, 1)
        let shown = min(heldPosition ?? model.track?.position ?? 0, duration)

        return HStack(spacing: 10) {
            // Fixed widths, so the bar doesn't twitch as the digits change.
            Text(Self.clock(shown))
                .frame(width: 34, alignment: .leading)

            FillBar(direction: .right,
                    fraction: shown / duration,
                    name: "scrubber",
                    isHovered: model.hoveredBar == "scrubber",
                    onDrag: { heldPosition = $0 * duration },
                    onRelease: {
                        guard let target = heldPosition else { return }
                        control.seek(to: target)
                        releaseHold { heldPosition = nil }
                    })
                .frame(height: NotchGeometry.barHitThickness)

            Text("-" + Self.clock(duration - shown))
                .frame(width: 34, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.5))
    }

    /// Previous, play and next in the middle, with repeat and AirPlay
    /// mirroring each other at the two ends — the Dynamic Island's row, with
    /// repeat where it has nothing.
    private var transport: some View {
        let isPlaying = model.track?.isPlaying ?? false
        let isPodcast = model.track?.source == "Podcasts"
        let position = model.track?.position ?? 0

        return HStack(spacing: 0) {
            repeatButton
            Spacer(minLength: 0)
            HStack(spacing: 30) {
                if isPodcast {
                    // Podcasts skip by time rather than by episode, as Apple's
                    // own podcast player does.
                    button("gobackward.15", name: "previous", size: 19) { control.skip(by: -15, from: position) }
                } else {
                    button("backward.fill", name: "previous", size: 19) { control.previousTrack() }
                }
                // A button shows what it is about to do: pause while playing.
                button(isPlaying ? "pause.fill" : "play.fill", name: "playpause", size: 26) {
                    control.togglePlayPause()
                    // Flip the glyph now rather than waiting for the music app to be
                    // asked again.
                    model.notePlayPauseClicked()
                }
                if isPodcast {
                    button("goforward.30", name: "next", size: 19) { control.skip(by: 30, from: position) }
                } else {
                    button("forward.fill", name: "next", size: 19) { control.nextTrack() }
                }
            }
            Spacer(minLength: 0)
            airPlayButton
        }
    }

    /// Off, repeat everything, repeat this song — in that order, as Music and
    /// the iPhone cycle through them. Lit when it's doing anything.
    private var repeatButton: some View {
        let mode = model.track?.repeatMode ?? "off"
        let isSpotify = model.track?.source == "Spotify"
        // Podcasts has no repeat to switch.
        let available = model.track?.source != "Podcasts"

        return button(mode == "one" ? "repeat.1" : "repeat", name: "repeat", size: 15,
                      tint: mode == "off" ? .white.opacity(0.45) : .white,
                      lit: mode != "off") {
            guard available else { return }
            // Spotify has no "repeat this song", so it only goes on and off.
            let next: String
            switch mode {
            case "off": next = "all"
            case "all": next = isSpotify ? "off" : "one"
            default: next = "off"
            }
            control.setRepeat(next)
            model.noteRepeatSet(next)
        }
        .opacity(available ? 1 : 0.3)
    }

    /// Where the sound is going. The AirPlay glyph while it's this Mac, turning
    /// into the device's own glyph — a HomePod, headphones — once it's
    /// somewhere else, as the iPhone's does.
    private var airPlayButton: some View {
        let route = model.airPlayRoute
        // Spotify can't be told where to play from outside, so there's
        // nothing to offer.
        let available = model.track?.source == "Music"

        return button(PlayerControl.symbol(forKind: route), name: "airplay", size: 16,
                      tint: route == nil ? .white.opacity(0.45) : .white) {
            guard available else { return }
            model.onAirPlayTapped?()
        }
        .opacity(available ? 1 : 0.3)
    }

    /// `name` stays the same whatever the glyph shows, so play/pause is one
    /// button to the hold-to-quit check rather than two.
    ///
    /// `lit` puts a soft square behind the glyph, the way the iPhone marks a
    /// mode that's switched on.
    private func button(_ symbol: String, name: String, size: CGFloat,
                        tint: Color = .white, lit: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                // One flat colour: some device glyphs, the HomePod's among
                // them, otherwise draw in two tones and come out murky.
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                // A glyph on its own is a small thing to hit, so the button is
                // bigger than what it draws.
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(lit ? 0.16 : 0))
                )
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.12), value: lit)
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { g in
                Color.clear.preference(key: ButtonFramesKey.self,
                                       value: [name: g.frame(in: .global)])
            }
        )
    }

    // MARK: Right — the volume

    /// Volume *does* apply as you drag, because hearing it change is the whole
    /// point of a volume control.
    private var volume: some View {
        let level = heldVolume ?? model.track?.volume ?? 50

        return VStack(spacing: 6) {
            FillBar(direction: .up,
                       fraction: level / 100,
                       name: "volume",
                       isHovered: model.hoveredBar == "volume",
                       onDrag: { fraction in
                           let newValue = fraction * 100
                           heldVolume = newValue
                           // Only send when the whole number changes, so one drag
                           // is a hundred commands at most rather than thousands.
                           let step = Int(newValue.rounded())
                           if step != lastSentVolume {
                               lastSentVolume = step
                               control.setVolume(newValue)
                           }
                       },
                       onRelease: { releaseHold { heldVolume = nil } })

            // Outside the bar rather than inside it: at low volume the dot sits
            // right where the glyph used to be.
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: Helpers

    /// Keeps your value on screen briefly after you let go, so it does not jump
    /// backwards before the next poll catches up.
    private func releaseHold(_ clear: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: clear)
    }

    private static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - The clipboard

/// Things dropped on the notch, in a row under the player, with Clear.
///
/// Each tile can be dragged back out to wherever you want it — it stays here
/// too. The whole section counts as a control, so pressing on a tile to drag
/// it is never mistaken for the start of a hold-to-quit.
private struct ShelfSection: View {
    @ObservedObject var model: NowPlayingModel
    let showsDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsDivider {
                // Set well below the player, with room either side of the
                // line, so the clipboard reads as its own section rather than
                // crowding the buttons above it.
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }

            HStack {
                Text("CLIPBOARD")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                        model.clearShelf()
                    }
                } label: {
                    Text("Clear")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if isRenderingPreview {
                tiles
            } else {
                ScrollView(.horizontal, showsIndicators: false) { tiles }
            }
        }
        .padding(.top, showsDivider ? 0 : 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { g in
                Color.clear.preference(key: ButtonFramesKey.self,
                                       value: ["shelf": g.frame(in: .global)])
            }
        )
    }
}

extension ShelfSection {
    var tiles: some View {
        HStack(spacing: 10) {
            ForEach(model.shelf) { item in
                ShelfTile(item: item)
            }
        }
    }
}

/// One kept thing: its icon or picture, and its name.
private struct ShelfTile: View {
    let item: ShelfItem

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                    Image(systemName: item.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(width: 38, height: 38)

            Text(item.name)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 58)
        }
        .frame(width: 58)
        .contentShape(Rectangle())
        .help(item.name)
        .modifier(DraggableOut(enabled: !isRenderingPreview, item: item))
    }
}

// MARK: - The drop area

/// What the notch opens into while something's being dragged towards it: an
/// outlined space to let go over, which brightens once you're above it.
private struct DropArea: View {
    @ObservedObject var model: NowPlayingModel
    let geometry: NotchGeometry

    @State private var targeted = false

    var body: some View {
        let frame = geometry.dropFrame

        return VStack(spacing: 0) {
            Color.clear.frame(height: geometry.panelContentTop)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(targeted ? 0.08 : 0.03))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(targeted ? 0.7 : 0.3),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(targeted ? 1 : 0.75))
                    Text(targeted ? "Let go to keep it here" : "Drop here to keep it")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, NotchGeometry.panelPadding)
            .padding(.bottom, 16)
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .modifier(AcceptsDrops(enabled: !isRenderingPreview, targeted: $targeted) { providers in
            Shelf.load(providers) { items in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                    model.keep(items)
                }
            }
        })
        .animation(.easeOut(duration: 0.12), value: targeted)
    }
}

/// Lets a tile be dragged back out — except in the preview tool, whose
/// renderer can't draw a view that does.
private struct DraggableOut: ViewModifier {
    let enabled: Bool
    let item: ShelfItem

    func body(content: Content) -> some View {
        if enabled {
            content.onDrag { item.dragProvider() }
        } else {
            content
        }
    }
}

/// Takes drops — except in the preview tool, whose renderer can't draw a view
/// that does.
private struct AcceptsDrops: ViewModifier {
    let enabled: Bool
    @Binding var targeted: Bool
    let perform: ([NSItemProvider]) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: Shelf.acceptedTypes, isTargeted: $targeted) { providers in
                perform(providers)
                return true
            }
        } else {
            content
        }
    }
}
