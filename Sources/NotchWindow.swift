import AppKit
import Combine
import SwiftUI

/// A borderless panel sitting across the notch, in one of four states:
/// invisible, two small squares beside the notch, an expanded control panel
/// hanging below it, or — while something is being dragged towards it — an
/// open area to drop it on.
///
/// It stays one window throughout, sized to cover whichever state is showing.
final class NotchWindow: NSPanel {

    private enum Presentation { case hidden, tabs, expanded, dropTarget }

    private let model: NowPlayingModel
    private let control: PlayerControl
    private var geometry: NotchGeometry
    private let hosting: NSHostingView<NotchView>

    private var hasTrack = false
    private var isPlaying = false
    private var cursorIsOnNotch = false
    private var hoverDelayPassed = false
    private var hoverTimer: Timer?
    private var isPeeking = false
    private var peekTimer: Timer?

    private var shown: Presentation = .hidden

    /// Called each time the panel opens, so anything that's only worth asking
    /// Music about while you're looking — where the sound is going — is fresh.
    var onExpand: (() -> Void)?

    /// True while the AirPlay menu is up. The menu reaches below the panel, and
    /// moving down onto it mustn't close the panel it belongs to.
    private var menuIsOpen = false
    private var airPlayPick: ((String) -> Void)?

    /// Decides when a press-and-hold on the panel means "quit". Kept as its own
    /// type so its rules can be tested without a window — see HoldToQuit.swift.
    private var holdDetector = HoldToQuitDetector()

    /// Something is being dragged and is near the notch.
    private var dragApproaching = false

    private var shelfWatch: AnyCancellable?
    private var desktopsWatch: AnyCancellable?

    /// True while a full-screen app is in front — only tracked while the
    /// notch is on every desktop, since that's when it could end up on top
    /// of one.
    private var fullScreenInFront = false

    private static let oneDesktop: NSWindow.CollectionBehavior = [.moveToActiveSpace, .stationary, .ignoresCycle]
    private static let everyDesktop: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

    init(model: NowPlayingModel, control: PlayerControl, geometry: NotchGeometry) {
        self.model = model
        self.control = control
        self.geometry = geometry
        self.hosting = NSHostingView(
            rootView: NotchView(model: model, geometry: geometry, control: control))

        super.init(contentRect: geometry.windowFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false        // a shadow would give away the transparent middle
        isMovable = false
        hidesOnDeactivate = false

        // Clicks pass through until the controls are actually on screen. See
        // `applyPresentation()`, which is where this gets turned off and on again.
        ignoresMouseEvents = true

        // .statusBar puts us above ordinary windows and above the menu bar.
        // Two above .statusBar, so it stays on top of Study Mode's strip, which
        // sits one above it to cover the menu bar's icons.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)

        // Which desktops it's on: see `applyDesktopBehavior()`. By default,
        // follow the active desktop but stay out of full-screen Spaces.
        //
        // `.canJoinAllSpaces` used to be here, and "all Spaces" includes the one
        // a full-screen app creates — which is how the bar ended up floating
        // over full-screen windows. Without it, macOS keeps the window out of
        // full-screen Spaces on its own, with nothing to detect and nothing to
        // poll.
        //
        // `.moveToActiveSpace` does *not* make it follow you between desktops,
        // despite the name: it only acts when the *application* becomes active,
        // and an accessory app with a non-activating panel never does. So the
        // window stays on the desktop it was launched on, and moving it is a
        // deliberate act — see `moveToActiveSpace()` below, on the menu.
        collectionBehavior = Self.oneDesktop
        applyDesktopBehavior()

        alphaValue = 0
        contentView = hosting
        setFrame(geometry.windowFrame, display: false)
        logLine("notch \(geometry.notch), bar \(geometry.barFrame), panel \(geometry.panelFrame)")

        // Adding to or clearing the clipboard changes what the notch should
        // be: clearing it with nothing playing hides the notch altogether.
        // Waits a turn, because this is told just *before* the change lands.
        shelfWatch = model.$shelf.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyPresentation() }
        }

        // The every-desktop setting takes effect straight away.
        desktopsWatch = Settings.shared.$allDesktops.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyDesktopBehavior() }
        }

        // Switching desktop, or to another app, may have brought a full-screen
        // app to the front.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(self, selector: #selector(frontMayHaveChanged), name: name, object: nil)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(remeasure),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    /// AppKit likes to shove windows down clear of the menu bar. We want to sit
    /// in it, so this says no — without it the bar can end up a point or two
    /// below the top of the screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Keyboard focus only while the controls are on screen, and `.nonactivatingPanel`
    /// means even then the app you were using stays frontmost. The sliders need
    /// this to respond to a drag.
    override var canBecomeKey: Bool { shown == .expanded }
    override var canBecomeMain: Bool { false }

    /// Where the cursor has to be. Once the panel is open the panel itself counts
    /// too, so moving down onto the controls doesn't close it again.
    ///
    /// Measured from the panel rather than the window, because the window carries
    /// extra slack for the spring's overshoot that isn't really part of the panel.
    var revealZone: NSRect {
        switch shown {
        case .expanded: return geometry.revealZone.union(currentPanelFrame.insetBy(dx: -12, dy: -12))
        case .dropTarget: return geometry.revealZone.union(geometry.dropFrame)
        default: return geometry.revealZone
        }
    }

    /// The panel as it's drawn right now: with the player while a song is
    /// loaded, with the clipboard while something is stored in it.
    private var currentPanelFrame: NSRect {
        geometry.panelFrame(player: hasTrack, shelf: !model.shelf.isEmpty)
    }

    /// Where a drag has to be for the drop area to stay open. Once it's open,
    /// the area itself and a margin round it count too, so it doesn't snap
    /// shut as you move down onto it.
    var dragZone: NSRect {
        let zone = geometry.dragApproachZone
        return shown == .dropTarget ? zone.union(geometry.dropFrame.insetBy(dx: -40, dy: -40)) : zone
    }

    /// Where the panel is on screen, for telling whether a drag started from
    /// inside it — dragging an item out of the clipboard mustn't turn the
    /// panel into a drop area under your hand.
    var expandedPanelOnScreen: NSRect? {
        shown == .expanded ? currentPanelFrame : nil
    }

    func setDragApproaching(_ value: Bool) {
        guard value != dragApproaching else { return }
        dragApproaching = value
        logLine(value ? "drag approaching the notch" : "drag gone")
        applyPresentation()
    }

    @objc private func remeasure() {
        guard let fresh = NotchGeometry.current() else { return }
        geometry = fresh
        hosting.rootView = NotchView(model: model, geometry: fresh, control: control)
        setFrame(fresh.windowFrame, display: true)
        logLine("remeasured: notch \(fresh.notch)")
    }

    // MARK: - What is showing

    func setPlayback(hasTrack: Bool, isPlaying: Bool) {
        guard hasTrack != self.hasTrack || isPlaying != self.isPlaying else { return }
        self.hasTrack = hasTrack
        self.isPlaying = isPlaying
        applyPresentation()
    }

    func setCursorIsOnNotch(_ value: Bool) {
        guard value != cursorIsOnNotch else { return }
        cursorIsOnNotch = value

        hoverTimer?.invalidate()
        hoverTimer = nil

        guard value else {
            // Left the notch: the next arrival has to earn its delay again.
            hoverDelayPassed = false
            applyPresentation()
            return
        }

        let delay = Settings.shared.hoverDelay
        logLine("cursor arrived on the notch, hover delay \(delay)s")
        if delay < 0.01 {
            hoverDelayPassed = true
        } else {
            // Wait for the cursor to settle. Leaving early cancels this, so
            // passing over the notch on the way to the menu bar opens nothing.
            hoverDelayPassed = false
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                self?.hoverDelayPassed = true
                self?.applyPresentation()
            }
            RunLoop.main.add(timer, forMode: .common)
            hoverTimer = timer
        }

        applyPresentation()
    }

    /// Works out which bar, if any, the cursor is over, and tells the model.
    ///
    /// The views report their own frames in the window's coordinates, so the
    /// only thing to do here is flip the cursor from screen coordinates (which
    /// count up from the bottom) into the window's (which count down from the
    /// top).
    func updateBarHover(cursor: NSPoint) {
        guard shown == .expanded else {
            if model.hoveredBar != nil { model.hoveredBar = nil }
            return
        }

        let local = CGPoint(x: cursor.x - frame.minX,
                            y: frame.maxY - cursor.y)
        let hit = model.barFrames.first { $0.value.contains(local) }?.key

        if hit != model.hoveredBar {
            logLine("bar hover: \(hit ?? "none")")
            model.hoveredBar = hit
        }
    }

    /// Feeds one cursor sample to the hold-to-quit detector, and acts on what it
    /// decides. Called on every tick of the cursor poll.
    func updateHoldToQuit(cursor: NSPoint, buttonDown: Bool, time: TimeInterval) {
        // While studying, holding always works — it's how Study Mode ends —
        // whatever the hold-to-quit setting says.
        holdDetector.enabled = Settings.shared.holdToQuit || model.isStudying
        holdDetector.duration = Settings.shared.holdToQuitSeconds
        holdDetector.panelFrame = localPanelFrame
        holdDetector.controlFrames = Array(model.barFrames.values) + Array(model.buttonFrames.values)

        let local = CGPoint(x: cursor.x - frame.minX, y: frame.maxY - cursor.y)
        let outcome = holdDetector.feed(.init(time: time,
                                              point: local,
                                              buttonDown: buttonDown,
                                              panelExpanded: shown == .expanded))

        switch outcome {
        case .quit:
            if model.isStudying {
                model.holdProgress = nil
                model.onStudyHoldComplete?()
            } else {
                logLine("held to quit")
                NSApp.terminate(nil)
            }

        case .holding(let elapsed, let progress):
            // An ordinary click on the panel shouldn't flash a hint, so it waits
            // until the press has clearly become a hold.
            let visible: Double? = elapsed >= 0.25 ? progress : nil
            if model.holdProgress != visible { model.holdProgress = visible }

        case .idle:
            if model.holdProgress != nil { model.holdProgress = nil }
        }
    }

    /// The panel in the window's own coordinates, counted down from the top —
    /// the space the cursor sample and the views' frames are both in.
    private var localPanelFrame: CGRect {
        let panel = currentPanelFrame
        return CGRect(x: panel.minX - frame.minX,
                      y: frame.maxY - panel.maxY,
                      width: panel.width,
                      height: panel.height)
    }

    /// Drops the AirPlay menu down from the AirPlay button: every device Music
    /// can play to, with a tick by the one in use.
    ///
    /// A real menu, so it looks and behaves like every other AirPlay list on
    /// the Mac. Dark to match the panel it hangs off.
    func showAirPlayMenu(_ devices: [PlayerControl.AirPlayDevice], onPick: @escaping (String) -> Void) {
        guard shown == .expanded, let button = model.buttonFrames["airplay"] else { return }

        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        if devices.isEmpty {
            let none = NSMenuItem(title: "No AirPlay devices found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(pickAirPlay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.name
            item.state = device.isSelected ? .on : .off
            item.image = NSImage(systemSymbolName: PlayerControl.symbol(forKind: device.kind),
                                 accessibilityDescription: nil)
            menu.addItem(item)
        }

        airPlayPick = onPick
        menuIsOpen = true
        // The button's frame is in the hosting view's own coordinates, which
        // count down from the top — the same way this point is meant.
        menu.popUp(positioning: nil,
                   at: NSPoint(x: button.minX, y: button.maxY + 6),
                   in: hosting)
        // popUp only returns once the menu has closed.
        menuIsOpen = false
        airPlayPick = nil
        applyPresentation()
    }

    @objc private func pickAirPlay(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        logLine("AirPlay: chose \(name)")
        airPlayPick?(name)
    }

    /// Brings the window to whichever desktop is in front right now.
    ///
    /// Allowing every Space for a moment and ordering the window in puts it on
    /// the one you are looking at; taking that permission away again leaves it
    /// there. Going straight to `orderFrontRegardless()` is not enough on its
    /// own, because macOS remembers the Space a window already belongs to.
    ///
    /// Nothing flashes on screen: when the notch is meant to be hidden its alpha
    /// is already zero, so the window being ordered in is invisible.
    // MARK: - Every desktop

    /// On every desktop, or just the one. "Every desktop" in macOS's terms
    /// includes the Spaces that full-screen apps make for themselves, which is
    /// how the bar once ended up floating over a full-screen video — so with
    /// this on, NotchTunes watches for a full-screen app in front and hides
    /// itself while there is one.
    private func applyDesktopBehavior() {
        let every = Settings.shared.allDesktops
        collectionBehavior = every ? Self.everyDesktop : Self.oneDesktop
        logLine(every ? "on every desktop" : "on one desktop")
        frontMayHaveChanged()
        if shown != .hidden { orderFrontRegardless() }
    }

    @objc private func frontMayHaveChanged() {
        guard Settings.shared.allDesktops else {
            if fullScreenInFront { fullScreenInFront = false; applyPresentation() }
            return
        }
        // Wait for the desktop-switching animation to finish, or the windows
        // read are the ones on the way out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let now = Self.fullScreenAppInFront(on: self.geometry.screen)
            guard now != self.fullScreenInFront else { return }
            self.fullScreenInFront = now
            logLine(now ? "full-screen app in front: hiding" : "full-screen app gone")
            self.applyPresentation()
        }
    }

    /// Whether the frontmost app has a window covering the whole of the
    /// notched screen — the menu bar's strip included, which an ordinary
    /// window, even a zoomed one, never does. Only window sizes and owners are
    /// read, which needs no permission.
    static func fullScreenAppInFront(on screen: NSScreen) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return false }

        // Window positions count down from the top of the main display.
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let target = CGRect(x: screen.frame.minX, y: mainHeight - screen.frame.maxY,
                            width: screen.frame.width, height: screen.frame.height)

        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? Int32) == front,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let raw = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw) else { return false }
            return abs(bounds.minX - target.minX) < 2 && abs(bounds.minY - target.minY) < 2
                && abs(bounds.width - target.width) < 2 && abs(bounds.height - target.height) < 2
        }
    }

    func moveToActiveSpace() {
        let settled = collectionBehavior
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        orderFrontRegardless()

        // A turn of the run loop, so the window is actually placed before the
        // permission is withdrawn.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.collectionBehavior = settled
            // Hand visibility back to the state machine.
            if self.shown == .hidden { self.orderOut(nil) }
            logLine("moved to the active desktop")
        }
    }

    /// Re-decide what should be showing. Called on every poll so that changing a
    /// setting takes effect without having to wait for the song to change.
    func revalidate() {
        applyPresentation()
    }

    /// Show the squares for a few seconds on their own, for when a song starts
    /// without you touching anything. How long is up to you in Settings, and
    /// zero turns the announcement off.
    func peek() {
        let seconds = Settings.shared.peekDuration
        guard seconds >= 0.01 else { return }

        isPeeking = true
        peekTimer?.invalidate()

        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            self?.isPeeking = false
            self?.applyPresentation()
        }
        RunLoop.main.add(timer, forMode: .common)
        peekTimer = timer
        applyPresentation()
    }

    /// Cursor on the notch wins over everything. Below that the bar is up for as
    /// long as a song is loaded — paused included — or just after one starts if
    /// you'd rather it only announced itself.
    private var wanted: Presentation {
        // On every desktop, but never over a full-screen app.
        if Settings.shared.allDesktops && fullScreenInFront { return .hidden }
        // A drag on its way in beats everything, song or no song.
        if dragApproaching { return .dropTarget }
        // Otherwise there has to be something to show: a song, or something
        // kept in the clipboard.
        guard hasTrack || !model.shelf.isEmpty else { return .hidden }
        if menuIsOpen { return .expanded }
        if cursorIsOnNotch && hoverDelayPassed { return .expanded }
        if Settings.shared.keepVisible || isPeeking { return .tabs }
        return .hidden
    }

    private func applyPresentation() {
        let next = wanted
        guard next != shown else { return }
        shown = next
        logLine("\(next) (song: \(hasTrack), playing: \(isPlaying), cursor on notch: \(cursorIsOnNotch), peeking: \(isPeeking))")

        model.isExpanded = (next == .expanded)
        model.isDropTarget = (next == .dropTarget)
        model.isOnScreen = (next != .hidden)
        if next == .expanded { onExpand?() }

        // Only take the mouse while the controls are on screen, or while a drop
        // is coming — a window that ignores the mouse can't be dropped on.
        // Every other moment everything passes straight through to the menu
        // bar underneath.
        ignoresMouseEvents = !(next == .expanded || next == .dropTarget)

        if next != .hidden {
            orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = next == .hidden ? 0.2 : 0.16
            animator().alphaValue = next == .hidden ? 0 : 1
        }, completionHandler: { [weak self] in
            guard let self else { return }
            if self.shown == .hidden {
                self.orderOut(nil)
            }
            logLine("settled: \(self.shown), onScreen \(self.isVisible), "
                    + "alpha \(self.alphaValue), frame \(self.frame), level \(self.level.rawValue)")
        })
    }
}
