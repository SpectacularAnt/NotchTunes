import AppKit
import IOKit.ps
import IOKit.pwr_mgt
import SwiftUI

/// Study Mode: as few distractions as a Mac allows.
///
/// A black strip covers the whole menu bar — every menu, every icon — with
/// only a small clock in the top-right corner, a low-battery warning once the
/// battery falls below a level you choose, and the time left if a timer is
/// running. The music notch carries on working on top of it.
///
/// Optionally, the Dock is kept from appearing too (Settings). The way out is
/// the End button at the left of the strip — the menu bar comes back and
/// NotchTunes keeps running — or the timer, if one was set. Pressing and
/// holding the strip quits NotchTunes, as holding the panel does.
final class StudyController: ObservableObject {

    @Published private(set) var isActive = false
    /// When the timer runs out, or nil for "until I end it".
    // Settable from outside only so the preview tool can show them.
    @Published var endsAt: Date?
    /// How far through a hold on the strip you are, or nil.
    @Published var holdProgress: Double?
    @Published var battery: Battery?

    /// Whether the black is stretched across the whole menu bar, or tucked in
    /// at the notch. Drives the opening and closing animation.
    @Published var stripOpen = false

    /// The stretch: the same kind of spring as the notch's own panel, a touch
    /// slower for the longer distance.
    static let stretch = Animation.spring(response: 0.5, dampingFraction: 0.86)

    /// Told whenever Study Mode starts or ends.
    var onChange: ((Bool) -> Void)?

    struct Battery: Equatable {
        let percent: Int
        let charging: Bool
    }

    private var strip: NSPanel?
    private var ticker: Timer?
    private var holdDetector = HoldToQuitDetector()

    // MARK: Starting and ending

    /// `minutes` nil means it runs until you end it.
    func start(minutes: Int?) {
        endsAt = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
        guard !isActive else {
            logLine("study mode: timer reset")
            return
        }
        guard let geometry = NotchGeometry.current() else { return }

        isActive = true
        StayAwake.set("Study Mode", on: true)
        readBattery()
        showStrip(on: geometry)
        updateDock()

        // Once a second, for the time left. Everything else it shows changes
        // far less often, and is checked along the way.
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        tick.tolerance = 0.2
        RunLoop.main.add(tick, forMode: .common)
        ticker = tick

        logLine("study mode: on" + (minutes.map { " for \($0) minutes" } ?? ""))
        onChange?(true)
    }

    func end() {
        guard isActive else { return }
        isActive = false
        StayAwake.set("Study Mode", on: false)
        endsAt = nil
        holdProgress = nil
        ticker?.invalidate()
        ticker = nil
        // Shrink back into the notch, then go.
        let closing = strip
        strip = nil
        withAnimation(Self.stretch) { stripOpen = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { closing?.orderOut(nil) }
        updateDock()
        logLine("study mode: off")
        onChange?(false)
    }

    private var tickCount = 0

    private func tick() {
        tickCount += 1
        if let endsAt, Date() >= endsAt {
            // Time's up: a gentle sound, and the menu bar comes back.
            NSSound(named: "Glass")?.play()
            end()
            return
        }
        if tickCount % 30 == 0 { readBattery() }
        // The Dock setting can be changed mid-session.
        updateDock()
        // A safety net for anything that moves the strip without saying so.
        pinStrip()
    }

    // MARK: The strip

    /// Where the strip belongs: across the very top of the notched screen.
    static func stripFrame(for geometry: NotchGeometry) -> NSRect {
        let screen = geometry.screen
        let height = geometry.notch.height.rounded()
        return NSRect(x: screen.frame.minX, y: screen.frame.maxY - height,
                      width: screen.frame.width, height: height)
    }

    /// Puts the strip back across the top of the screen if anything has moved
    /// it.
    ///
    /// Something did: going full screen with Study Mode on, macOS moved the
    /// strip about three-quarters of the way down the screen while it built
    /// the full-screen app's own desktop, and nothing ever moved it back. So
    /// it's checked whenever the desktop or the screens change, and once a
    /// second in case anything else does.
    private func pinStrip() {
        guard let strip, let geometry = NotchGeometry.current() else { return }
        let wanted = Self.stripFrame(for: geometry)
        guard strip.frame != wanted else { return }
        logLine("study mode: strip was at \(strip.frame), putting it back at \(wanted)")
        if strip.frame.size != wanted.size {
            // A different screen size: redraw for it, as well as moving.
            strip.contentView = FirstClickHostingView(rootView: StudyStripView(
                study: self, notch: geometry.notch, screen: geometry.screen.frame))
        }
        strip.setFrame(wanted, display: true)
        strip.orderFrontRegardless()
    }

    /// Re-pins straight away, and again once a desktop-switching animation
    /// has had time to finish, since macOS may move things during it.
    @objc private func surroundingsChanged() {
        pinStrip()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.pinStrip() }
    }

    private var watchingSurroundings = false

    private func watchSurroundings() {
        guard !watchingSurroundings else { return }
        watchingSurroundings = true
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(surroundingsChanged),
                              name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(surroundingsChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
    }

    private func showStrip(on geometry: NotchGeometry) {
        let screen = geometry.screen
        let frame = Self.stripFrame(for: geometry)
        watchSurroundings()

        let panel = CoveringPanel(contentRect: frame,
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        // Above the menu bar and its icons — one above the level the icons use,
        // so none can end up drawn over it. The music notch sits one level
        // higher still, so it stays on top of the strip.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        // Clear, so the black can grow out of the notch: what's drawn is a
        // shape inside the window, not the window itself.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // Takes the clicks, so the menus underneath can't be opened.
        panel.ignoresMouseEvents = false
        // Every desktop, full-screen apps' included: wherever you go, the
        // menu bar stays covered.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = FirstClickHostingView(rootView: StudyStripView(study: self, notch: geometry.notch,
                                                                   screen: screen.frame))
        panel.setFrame(frame, display: true)
        stripOpen = false
        panel.orderFrontRegardless()
        strip = panel

        // A turn later, once it's drawn tucked in at the notch, stretch it out.
        DispatchQueue.main.async { withAnimation(Self.stretch) { self.stripOpen = true } }
    }

    // MARK: Holding to end

    /// Where the End button is, in the strip's own coordinates (counted down
    /// from its top), as the view reports it. A press there is a click on
    /// End, never the start of a hold.
    var endButtonFrame: CGRect = .zero

    /// Fed from the cursor poll. Pressing and holding anywhere on the strip
    /// quits NotchTunes, after the hold-to-quit time — the same gesture as on
    /// the panel, and switched on and off by the same setting.
    func updateHold(cursor: NSPoint, buttonDown: Bool, time: TimeInterval) {
        guard isActive, let strip else { return }
        holdDetector.enabled = Settings.shared.holdToQuit
        holdDetector.duration = Settings.shared.holdToQuitSeconds
        holdDetector.panelFrame = strip.frame        // screen coordinates, like the cursor
        let button = endButtonFrame
        holdDetector.controlFrames = button.isEmpty ? [] : [CGRect(x: strip.frame.minX + button.minX,
                                                                    y: strip.frame.maxY - button.maxY,
                                                                    width: button.width, height: button.height)
                                                                .insetBy(dx: -4, dy: -4)]

        let outcome = holdDetector.feed(.init(time: time, point: cursor,
                                              buttonDown: buttonDown, panelExpanded: true))
        switch outcome {
        case .quit:
            // Quitting ends Study Mode with it, and puts the Dock back first
            // (AppController.applicationWillTerminate).
            logLine("study mode: held to quit")
            NSApp.terminate(nil)
        case .holding(let elapsed, let progress):
            let visible: Double? = elapsed >= 0.25 ? progress : nil
            if holdProgress != visible { holdProgress = visible }
        case .idle:
            if holdProgress != nil { holdProgress = nil }
        }
    }

    // MARK: The Dock

    private var dockKeptAway = false

    /// Keeps the Dock from appearing, or lets it back, to match the setting.
    private func updateDock() {
        let wanted = isActive && Settings.shared.studyBlocksDock
        guard wanted != dockKeptAway else { return }
        dockKeptAway = wanted
        if wanted { DockSuppressor.keepAway() } else { DockSuppressor.restore() }
    }

    // MARK: The battery

    private func readBattery() {
        battery = Self.readBattery()
    }

    /// The internal battery's charge and whether it's charging, or nil on a
    /// Mac without one. Read from IOKit's power-source list, which needs no
    /// permission.
    static func readBattery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let details = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  details[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = details[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = details[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            let charging = (details[kIOPSIsChargingKey] as? Bool ?? false)
                || details[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return Battery(percent: min(100, current * 100 / maximum), charging: charging)
        }
        return nil
    }
}

/// Takes the very first click, so End works with a single click even though
/// the strip never becomes the active window.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A panel that never takes keyboard focus: the strip and the Dock cover are
/// only ever there to sit on top of things.
private final class CoveringPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// MARK: - What the strip shows

/// Black, edge to edge. On the left: End, and — only while you're holding to
/// quit — what's about to happen and how far along. On the right, set in a
/// little from the corner: the low-battery warning when it's due, the time
/// left when a timer's running, and the clock.
///
/// Not private, so Tools/preview-panel.sh can draw it.
struct StudyStripView: View {
    @ObservedObject var study: StudyController
    @ObservedObject private var settings = Settings.shared
    let notch: NSRect
    let screen: NSRect

    var body: some View {
        let height = notch.height.rounded()
        let open = study.stripOpen
        // Where it starts from: the music notch's own bar — the notch and a
        // square either side — so it looks like that bar stretching out.
        let barWidth = notch.width + height * 2
        let barX = notch.midX - screen.minX - barWidth / 2

        return ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(bottomLeadingRadius: open ? 0 : 11,
                                   bottomTrailingRadius: open ? 0 : 11,
                                   style: .continuous)
                .fill(Color.black)
                .frame(width: open ? screen.width : barWidth, height: height)
                .offset(x: open ? 0 : barX)
                .animation(StudyController.stretch, value: open)

            // Arrives once the black has nearly reached the edges, and leaves
            // first on the way back.
            contents
                .opacity(open ? 1 : 0)
                .animation(open ? .easeOut(duration: 0.25).delay(0.25) : .easeIn(duration: 0.1), value: open)
                .allowsHitTesting(open)
        }
        .frame(width: screen.width, height: height, alignment: .topLeading)
    }

    private var contents: some View {
        // Once a second: the clock and the countdown. A few words in a small
        // window — this costs next to nothing.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 0) {
                HStack(spacing: 14) {
                    endButton
                    holdHint
                }
                .frame(width: max(0, notch.minX - screen.minX - 24), alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    batteryWarning
                    countdown(at: context.date)
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                // In from the corner a little, clear of the screen's rounded
                // edge.
                .padding(.trailing, 26)
            }
            .padding(.horizontal, 16)
            .onPreferenceChange(EndButtonFrameKey.self) { study.endButtonFrame = $0 }
        }
        .frame(width: screen.width, height: notch.height.rounded())
    }

    /// Ends Study Mode and brings the menu bar back; NotchTunes keeps
    /// running.
    private var endButton: some View {
        Button { study.end() } label: {
            Text("End")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 11)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.16)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("End Study Mode")
        .background(
            GeometryReader { g in
                Color.clear.preference(key: EndButtonFrameKey.self, value: g.frame(in: .global))
            }
        )
    }

    @ViewBuilder
    private var holdHint: some View {
        if let progress = study.holdProgress {
            HStack(spacing: 10) {
                Text("Keep holding to quit NotchTunes")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(Color.white)
                        .frame(width: max(5, 90 * progress))
                }
                .frame(width: 90, height: 5)
                .animation(.linear(duration: 0.06), value: progress)
            }
        }
    }

    /// Only once the battery is at or below the level set in Settings.
    @ViewBuilder
    private var batteryWarning: some View {
        if let battery = study.battery, battery.percent <= Int(settings.studyBatteryThreshold) {
            HStack(spacing: 4) {
                Image(systemName: battery.charging ? "battery.100percent.bolt" : Self.symbol(for: battery.percent))
                    .symbolRenderingMode(.monochrome)
                Text("\(battery.percent)%")
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: .medium))
            // Red only when it's really low and not charging, as macOS does.
            .foregroundStyle(battery.percent <= 10 && !battery.charging ? Color.red : Color.white.opacity(0.85))
        }
    }

    private static func symbol(for percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    @ViewBuilder
    private func countdown(at now: Date) -> some View {
        if let endsAt = study.endsAt {
            let left = max(0, Int(endsAt.timeIntervalSince(now).rounded(.up)))
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text(left >= 3600
                     ? String(format: "%d:%02d:%02d", left / 3600, left / 60 % 60, left % 60)
                     : String(format: "%d:%02d", left / 60, left % 60))
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
        }
    }
}

// MARK: - Keeping the Dock away

/// Stops the Dock from appearing during Study Mode, and puts it back after.
///
/// macOS has no switch for another app to turn the Dock off, but the Dock's
/// own settings get most of the way: a Dock set to hide itself waits a moment
/// before sliding in, and that wait can be set to a thousand seconds — long
/// enough that it never comes. So Study Mode turns hiding on with that wait,
/// and afterwards puts back exactly what was there before.
///
/// The catch: the Dock only notices new settings when it restarts, so it
/// blinks for a second when Study Mode starts and ends. And since this
/// changes a real setting, the original values are saved first, and put back
/// when Study Mode ends, when NotchTunes quits, and — in case it ever closed
/// unexpectedly mid-session — the next time it starts.
enum DockSuppressor {

    /// What the Dock's two settings were before. Nil means the setting
    /// wasn't there at all, which is different from being false or zero, and
    /// is put back by removing it again.
    struct Original: Equatable {
        var autohide: Bool?
        var delay: Double?
    }

    private static let savedKey = "dockOriginalSettings"
    private static let dock = "com.apple.dock" as CFString

    static func keepAway() {
        guard UserDefaults.standard.dictionary(forKey: savedKey) == nil else { return }   // already away
        let original = Original(
            autohide: CFPreferencesCopyAppValue("autohide" as CFString, dock) as? Bool,
            delay: (CFPreferencesCopyAppValue("autohide-delay" as CFString, dock) as? NSNumber)?.doubleValue)
        save(original)
        run(commandsToKeepAway())
        logLine("study mode: Dock kept away")
    }

    /// `waiting` runs the commands before returning — needed when NotchTunes
    /// is quitting, or it would be gone before they ran.
    static func restore(waiting: Bool = false) {
        guard let original = saved() else { return }
        run(commandsToRestore(original), waiting: waiting)
        UserDefaults.standard.removeObject(forKey: savedKey)
        logLine("study mode: Dock back")
    }

    /// At launch: if settings are still saved, NotchTunes closed while the
    /// Dock was away. Put it back.
    static func restoreIfLeftAway() {
        if saved() != nil {
            logLine("study mode: putting back a Dock left away last time")
            restore()
        }
    }

    // MARK: The commands — plain lists, so they can be tested without running

    static func commandsToKeepAway() -> [[String]] {
        [["/usr/bin/defaults", "write", "com.apple.dock", "autohide", "-bool", "true"],
         ["/usr/bin/defaults", "write", "com.apple.dock", "autohide-delay", "-float", "1000"],
         ["/usr/bin/killall", "Dock"]]
    }

    static func commandsToRestore(_ original: Original) -> [[String]] {
        var commands: [[String]] = []
        if let hide = original.autohide {
            commands.append(["/usr/bin/defaults", "write", "com.apple.dock", "autohide", "-bool", hide ? "true" : "false"])
        } else {
            commands.append(["/usr/bin/defaults", "delete", "com.apple.dock", "autohide"])
        }
        if let delay = original.delay {
            commands.append(["/usr/bin/defaults", "write", "com.apple.dock", "autohide-delay", "-float", String(delay)])
        } else {
            commands.append(["/usr/bin/defaults", "delete", "com.apple.dock", "autohide-delay"])
        }
        commands.append(["/usr/bin/killall", "Dock"])
        return commands
    }

    // MARK: Saving the originals

    static func encode(_ original: Original) -> [String: Any] {
        var dictionary: [String: Any] = [:]
        if let hide = original.autohide { dictionary["autohide"] = hide }
        if let delay = original.delay { dictionary["delay"] = delay }
        dictionary["saved"] = true      // so an empty original still counts as saved
        return dictionary
    }

    static func decode(_ dictionary: [String: Any]) -> Original {
        Original(autohide: dictionary["autohide"] as? Bool, delay: (dictionary["delay"] as? NSNumber)?.doubleValue)
    }

    private static func save(_ original: Original) {
        UserDefaults.standard.set(encode(original), forKey: savedKey)
    }

    private static func saved() -> Original? {
        UserDefaults.standard.dictionary(forKey: savedKey).map(decode)
    }

    /// Runs each command in turn, waiting for each. They take a moment, so
    /// it's off the main thread.
    private static func run(_ commands: [[String]], waiting: Bool = false) {
        let work = {
            for command in commands {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command[0])
                process.arguments = Array(command.dropFirst())
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
            }
        }
        if waiting { work() } else { DispatchQueue.global(qos: .userInitiated).async(execute: work) }
    }
}

/// Where the End button was laid out, so a press on it isn't taken for a hold.
private struct EndButtonFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

// MARK: - Staying awake

/// Keeps the Mac from sleeping, dimming, starting the screensaver or locking
/// from being left idle — while Study Mode is on, and while the visualizer is
/// playing.
///
/// This is macOS's own "keep the display awake" request — a power assertion,
/// the same thing video players and `caffeinate -d` use. It needs no
/// permission and changes no setting. Each part of NotchTunes that wants it
/// says so by name, and the one request is held for as long as any of them
/// still wants it — so ending Study Mode doesn't let the screen sleep under a
/// visualizer that's still playing, or the other way round. If NotchTunes
/// quits or crashes, macOS drops it on its own. Closing the lid, or locking on
/// purpose, still works as usual.
enum StayAwake {
    private static var assertion: IOPMAssertionID = 0
    private static var held = false
    private static var wanting: Set<String> = []

    /// `reason` is who's asking: "Study Mode", "Visualizer".
    static func set(_ reason: String, on: Bool) {
        let before = wanting
        if on { wanting.insert(reason) } else { wanting.remove(reason) }
        guard wanting != before else { return }
        update()
    }

    static var isHeld: Bool { held }

    private static func update() {
        if !wanting.isEmpty && !held {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "NotchTunes is keeping the display awake" as CFString,
                &assertion)
            held = result == kIOReturnSuccess
            logLine(held ? "keeping the Mac awake for \(wanting.sorted())" : "couldn't keep the Mac awake (\(result))")
        } else if wanting.isEmpty && held {
            IOPMAssertionRelease(assertion)
            held = false
            logLine("the Mac may sleep again")
        }
    }
}
