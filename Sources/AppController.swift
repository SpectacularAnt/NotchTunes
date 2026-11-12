import AppKit
import SwiftUI

/// Owns the window and the two repeating jobs that drive it: one asks the music
/// apps what is playing, the other watches where the cursor is.
final class AppController: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    private let model = NowPlayingModel()
    private let reader = NowPlayingReader()
    private let control = PlayerControl()
    private let mouse = MouseWatcher()

    // Used to spot the moment playback starts, so the squares can announce it.
    private var lastIdentity: String?
    private var lastWasPlaying = false

    private let launchedAt = Date()
    private let settingsWindow = SettingsWindowController()
    private lazy var visualizer = VisualizerWindowController(model: model)
    private let permissionsWindow = PermissionsWindowController()
    private let updater = Updater()
    private let study = StudyController()

    /// While the panel is open, the scrubber and buttons are checked four
    /// times a second.
    private static let pollInterval: TimeInterval = 0.25

    private var window: NotchWindow!
    private var statusItem: NSStatusItem?
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // If NotchTunes closed while Study Mode was keeping the Dock away, put
        // the Dock back.
        DockSuppressor.restoreIfLeftAway()

        // The clipboard doesn't outlive the app, so pictures saved for it last
        // time are no longer wanted.
        Shelf.removeSavedImages()

        guard let geometry = NotchGeometry.current() else {
            logLine("no screen to measure, giving up")
            NSApp.terminate(nil)
            return
        }

        window = NotchWindow(model: model, control: control, geometry: geometry)
        addMenuBarItem()

        // The first time NotchTunes opens, ask for what it needs up front,
        // with a word on what each is for, rather than leaving macOS's
        // prompts to pop up unexplained later.
        if !isDemoMode { permissionsWindow.showIfFirstLaunch() }

        // A command changes things immediately, so read back immediately rather
        // than waiting up to a quarter second for the next tick.
        // A skip changes the song, so that one reads everything.
        control.onCommandFinished = { [weak self] in self?.refresh(full: true) }

        // Where the sound is going is only worth asking about while the panel
        // is open to show it. Opening it also brings the scrubber up to date
        // straight away rather than at the next tick.
        window.onExpand = { [weak self] in
            self?.refreshAirPlay()
            self?.refresh(full: false)
        }

        // Podcasts comes through macOS's own Now Playing service, whose helper
        // reports every change as it happens.
        SystemNowPlaying.shared.onChange = { [weak self] in self?.refresh(full: false) }
        SystemNowPlaying.shared.start()

        // Music and Spotify both announce to the whole system whenever the
        // song changes or playback starts or stops. Listening for that is how
        // NotchTunes knows about changes without asking for every detail all
        // the time.
        let announcements = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            announcements.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.refresh(full: true)
            }
        }
        // And an app quitting or opening is worth an immediate look too.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard ["com.apple.Music", "com.spotify.client"].contains(app?.bundleIdentifier ?? "") else { return }
                self?.refresh(full: true)
            }
        }
        model.onAirPlayTapped = { [weak self] in self?.showAirPlayMenu() }

        // Study Mode: the panel's hold ends it too, and the panel needs to know
        // it's on to say so.
        study.onChange = { [weak self] on in self?.model.isStudying = on }
        model.onStudyHoldComplete = { [weak self] in self?.study.end() }

        // Ask the music apps what is playing: everything now, then quick checks.
        refresh(full: true)
        let timer = Timer(timeInterval: AppController.pollInterval, repeats: true) { [weak self] _ in
            self?.pollIfDue()
        }
        // .common mode keeps the timer ticking even while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        // Reveal the tabs while the cursor is on the notch, hide them again when
        // it leaves.
        mouse.start(zone: { [weak self] in self?.window.revealZone ?? .zero },
                    onSample: { [weak self] point in
                        let down = NSEvent.pressedMouseButtons & 1 != 0
                        let now = ProcessInfo.processInfo.systemUptime
                        self?.study.updateHold(cursor: point, buttonDown: down, time: now)
                        self?.watchForDrag(at: point)
                        self?.window.updateBarHover(cursor: point)
                        self?.window.updateHoldToQuit(
                            cursor: point,
                            buttonDown: NSEvent.pressedMouseButtons & 1 != 0,
                            time: ProcessInfo.processInfo.systemUptime)
                    },
                    onChange: { [weak self] isOverNotch in
                        self?.window.setCursorIsOnNotch(isOverNotch)
                    })
    }

    // MARK: Dragging towards the notch

    private let dragBoard = NSPasteboard(name: .drag)
    private var buttonWasDown = false
    private var dragCountAtPress = 0
    private var dragStartedInPanel = false

    /// Opens the drop area while something is being dragged near the notch.
    ///
    /// There's no announcement for "a drag has started somewhere on the Mac",
    /// but every drag puts what it's carrying on a shared drag pasteboard, and
    /// that pasteboard's change count ticks over when it does. So: note the
    /// count when the button goes down; if it has moved while the button is
    /// still down, something is being dragged. Reading it needs no permission,
    /// and this runs on the cursor check that's happening anyway.
    private func watchForDrag(at point: NSPoint) {
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0

        if buttonDown && !buttonWasDown {
            dragCountAtPress = dragBoard.changeCount
            // Dragging something *out* of the clipboard starts inside the open
            // panel. That drag shouldn't turn the panel into a drop area.
            dragStartedInPanel = window.expandedPanelOnScreen?.contains(point) ?? false
        }
        buttonWasDown = buttonDown

        let dragging = buttonDown && !dragStartedInPanel && dragBoard.changeCount != dragCountAtPress
        window.setDragApproaching(dragging && window.dragZone.contains(point))
    }

    /// How often to check in, between the apps' own announcements.
    ///
    /// Open, the scrubber needs the position four times a second. Closed,
    /// nothing on screen needs the position at all; the check is just a safety
    /// net in case an announcement went astray. A full read every so often
    /// catches anything the quick checks can't see.
    private static let closedPollInterval: TimeInterval = 2.0
    private static let fullReadInterval: TimeInterval = 15.0
    private var lastPoll = Date.distantPast
    private var lastFullRead = Date.distantPast

    private func pollIfDue() {
        let interval = model.isExpanded ? AppController.pollInterval : AppController.closedPollInterval
        // A little slack, so a tick that arrives a hair early still counts.
        guard Date().timeIntervalSince(lastPoll) >= interval - 0.05 else { return }
        refresh(full: Date().timeIntervalSince(lastFullRead) >= AppController.fullReadInterval)
    }

    private func refresh(full: Bool) {
        lastPoll = Date()
        if full { lastFullRead = lastPoll }
        if isDemoMode {
            handle(AppController.demoTrack(since: launchedAt))
            return
        }

        reader.read(full: full) { [weak self] track in
            self?.handle(track)
        }
    }

    /// Everything that happens once a song has been read. Demo mode comes
    /// through here too, so it exercises exactly the same path.
    private func handle(_ track: Track?) {
        if let track {
            logLine("read \(track.source): \(track.title) — \(track.artist) "
                    + "(playing: \(track.isPlaying), \(Int(track.position))/\(Int(track.duration))s, "
                    + "volume \(Int(track.volume)), artwork: \(track.artwork != nil))")
        } else {
            logLine("nothing playing")
        }

        // Commands have to go to whichever app is actually playing.
        control.activeApp = track?.source

        model.apply(track)

        // Listen to the music while it plays, so the bars can follow it.
        AudioFollower.shared.update(app: track?.source,
                                    isPlaying: track?.isPlaying ?? false,
                                    enabled: Settings.shared.barsFollowMusic && !isDemoMode)
        window.setPlayback(hasTrack: track != nil,
                           isPlaying: track?.isPlaying ?? false)
        announceIfJustStarted(track)

        // Picks up a changed setting without waiting for the song to change.
        window.revalidate()
    }

    /// Updates the AirPlay button's glyph to match where the sound is going.
    private func refreshAirPlay() {
        control.airPlayDevices { [weak self] devices in
            self?.model.airPlayRoute = PlayerControl.route(of: devices)
        }
    }

    /// Lists the AirPlay devices under the button, and switches to the one
    /// you pick.
    private func showAirPlayMenu() {
        control.airPlayDevices { [weak self] devices in
            guard let self else { return }
            self.model.airPlayRoute = PlayerControl.route(of: devices)
            self.window.showAirPlayMenu(devices) { name in
                self.control.selectAirPlay(name)
                // Give Music a moment to switch before asking where it went.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.refreshAirPlay() }
            }
        }
    }

    /// A sample song whose position advances, so the scrubber can be seen moving
    /// without any music playing.
    private static func demoTrack(since start: Date) -> Track {
        let length: Double = 199
        return Track(title: "Rhinestone Eyes", artist: "Gorillaz",
                     album: "Plastic Beach", isPlaying: demoIsPlaying, source: "Demo",
                     position: Date().timeIntervalSince(start)
                         .truncatingRemainder(dividingBy: length),
                     duration: length, volume: 65, trackID: "", artwork: nil)
    }

    /// The window doesn't follow you between desktops on its own — an accessory
    /// app never becomes active, which is the only thing that would move it. So
    /// this is how you bring it across.
    @objc private func moveToThisDesktop() {
        window.moveToActiveSpace()
    }

    @objc private func openVisualizer(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = VisualizerStyle(rawValue: raw) else { return }
        visualizer.show(style)
    }

    /// Ticks the style that's showing, while the visualizer is open.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // Nothing to move while the notch is on every desktop already.
        if item.action == #selector(moveToThisDesktop) {
            return !Settings.shared.allDesktops
        }
        if item.action == #selector(openVisualizer(_:)) {
            let showing = visualizer.currentStyle?.rawValue
            item.state = (showing != nil && showing == item.representedObject as? String) ? .on : .off
        }
        return true
    }

    /// Quitting mid-Study-Mode — at logout, say — puts the Dock back first.
    func applicationWillTerminate(_ notification: Notification) {
        DockSuppressor.restore(waiting: true)
    }

    @objc private func startStudyMode(_ sender: NSMenuItem) {
        study.start(minutes: sender.representedObject as? Int)
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func openPermissions() {
        permissionsWindow.show()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    /// Show the squares briefly when playback starts, or when it moves on to a
    /// different song, so a new track announces itself without you looking.
    private func announceIfJustStarted(_ track: Track?) {
        let isPlaying = track?.isPlaying ?? false
        let startedPlaying = isPlaying && !lastWasPlaying
        let changedSong = isPlaying && track?.identity != lastIdentity

        if startedPlaying || changedSong {
            window.peek()
        }

        lastIdentity = track?.identity
        lastWasPlaying = isPlaying
    }

    /// A small menu bar item, because an app with no Dock icon otherwise has no
    /// way to quit without going to the Terminal.
    private func addMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "music.note",
                                     accessibilityDescription: "NotchTunes")

        let menu = NSMenu()

        let move = NSMenuItem(title: "Move to This Desktop",
                              action: #selector(moveToThisDesktop),
                              keyEquivalent: "")
        move.target = self
        menu.addItem(move)

        // Visualizer ▸ Album Cover / Moving Bars. Choosing one opens the
        // window in that style, or switches it if it's already open.
        let visualizerMenu = NSMenu()
        for style in [VisualizerStyle.cover, .bars] {
            let item = NSMenuItem(title: style.menuTitle,
                                  action: #selector(openVisualizer(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            visualizerMenu.addItem(item)
        }
        let visualizerItem = NSMenuItem(title: "Visualizer", action: nil, keyEquivalent: "")
        visualizerItem.submenu = visualizerMenu
        menu.addItem(visualizerItem)

        // Study Mode ▸ for how long. While it's on the menu bar is covered, so
        // this menu can't be reached then: holding the strip, or the timer, is
        // how it ends.
        let studyMenu = NSMenu()
        let lengths: [(String, Int?)] = [("Until I End It", nil), ("25 Minutes", 25), ("45 Minutes", 45),
                                          ("1 Hour", 60), ("1½ Hours", 90), ("2 Hours", 120)]
        for (title, minutes) in lengths {
            let item = NSMenuItem(title: title, action: #selector(startStudyMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
            studyMenu.addItem(item)
        }
        let studyItem = NSMenuItem(title: "Study Mode", action: nil, keyEquivalent: "")
        studyItem.submenu = studyMenu
        menu.addItem(studyItem)

        let updates = NSMenuItem(title: "Check for Updates…",
                                 action: #selector(checkForUpdates),
                                 keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let permissions = NSMenuItem(title: "Permissions…",
                                     action: #selector(openPermissions),
                                     keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(openSettings),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchTunes",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        logLine("menu bar item ready: "
                + menu.items.map { "\($0.title.isEmpty ? "—" : $0.title)"
                    + ($0.action == nil ? "" : " [wired]") }.joined(separator: ", "))
    }
}
