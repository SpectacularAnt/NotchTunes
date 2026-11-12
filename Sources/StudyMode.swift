import AppKit
import IOKit.ps
import SwiftUI

/// Study Mode: as few distractions as a Mac allows.
///
/// A black strip covers the whole menu bar — every menu, every icon — with
/// only a small clock in the top-right corner, a low-battery warning once the
/// battery falls below a level you choose, and the time left if a timer is
/// running. The music notch carries on working on top of it.
///
/// Optionally, the Dock is blocked too (Settings). And the way out is the same
/// press-and-hold as hold-to-quit, except that here it ends Study Mode instead
/// of quitting — the menu bar comes back, and NotchTunes keeps running.
final class StudyController: ObservableObject {

    @Published private(set) var isActive = false
    /// When the timer runs out, or nil for "until I end it".
    // Settable from outside only so the preview tool can show them.
    @Published var endsAt: Date?
    /// How far through a hold on the strip you are, or nil.
    @Published var holdProgress: Double?
    @Published var battery: Battery?

    /// Told whenever Study Mode starts or ends.
    var onChange: ((Bool) -> Void)?

    struct Battery: Equatable {
        let percent: Int
        let charging: Bool
    }

    private var strip: NSPanel?
    private var dockCover: NSPanel?
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
        readBattery()
        showStrip(on: geometry)
        if Settings.shared.studyBlocksDock { showDockCover() }

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
        endsAt = nil
        holdProgress = nil
        ticker?.invalidate()
        ticker = nil
        strip?.orderOut(nil)
        strip = nil
        dockCover?.orderOut(nil)
        dockCover = nil
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
        if Settings.shared.studyBlocksDock != (dockCover != nil) {
            if Settings.shared.studyBlocksDock { showDockCover() } else { dockCover?.orderOut(nil); dockCover = nil }
        }
    }

    // MARK: The strip

    private func showStrip(on geometry: NotchGeometry) {
        let screen = geometry.screen
        let height = geometry.notch.height.rounded()
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height,
                           width: screen.frame.width, height: height)

        let panel = CoveringPanel(contentRect: frame,
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        // Above the menu bar and its icons — one above the level the icons use,
        // so none can end up drawn over it. The music notch sits one level
        // higher still, so it stays on top of the strip.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        // Takes the clicks, so the menus underneath can't be opened.
        panel.ignoresMouseEvents = false
        // Every desktop, full-screen apps' included: wherever you go, the
        // menu bar stays covered.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: StudyStripView(study: self, notch: geometry.notch,
                                                                   screen: screen.frame))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        strip = panel
    }

    // MARK: Holding to end

    /// Fed from the cursor poll. A press-and-hold anywhere on the strip ends
    /// Study Mode, after the same time hold-to-quit uses. It always works here,
    /// even with hold-to-quit switched off — with the menu bar covered, it's
    /// the way out.
    func updateHold(cursor: NSPoint, buttonDown: Bool, time: TimeInterval) {
        guard isActive, let strip else { return }
        holdDetector.enabled = true
        holdDetector.duration = Settings.shared.holdToQuitSeconds
        holdDetector.panelFrame = strip.frame        // screen coordinates, like the cursor
        holdDetector.controlFrames = []

        let outcome = holdDetector.feed(.init(time: time, point: cursor,
                                              buttonDown: buttonDown, panelExpanded: true))
        switch outcome {
        case .quit:
            logLine("study mode: held to end")
            end()
        case .holding(let elapsed, let progress):
            let visible: Double? = elapsed >= 0.25 ? progress : nil
            if holdProgress != visible { holdProgress = visible }
        case .idle:
            if holdProgress != nil { holdProgress = nil }
        }
    }

    // MARK: The Dock

    /// Blocks the Dock while Study Mode is on, if that's switched on.
    ///
    /// macOS doesn't let another app switch the Dock off, so this covers it
    /// instead, with a window one level above the Dock's own:
    ///  - a Dock that's always shown gets a black band over it, which nothing
    ///    else ever sits under anyway;
    ///  - a Dock that hides itself gets a band that appears when the cursor
    ///    reaches that very edge — which is exactly when the Dock would slide
    ///    in — stays while you're over the Dock's area, and vanishes when you
    ///    move away, so it doesn't sit over your apps the rest of the time.
    private func showDockCover() {
        guard let screen = NSScreen.screens.first else { return }    // the Dock lives on the main display
        let dock = Self.dockArea(on: screen)

        let panel = CoveringPanel(contentRect: dock.frame,
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.setFrame(dock.frame, display: true)
        dockCoverHides = dock.hides
        dockCoverZone = dock.frame
        dockSide = (CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String) ?? "bottom"
        if dock.hides {
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
        }
        panel.orderFrontRegardless()
        dockCover = panel
    }

    private var dockCoverHides = false
    private var dockCoverZone = NSRect.zero
    private var dockCoverShowing = false
    private var leftDockEdgeAt: Date?

    /// For a Dock that hides itself: shows the cover while the cursor is at
    /// that edge, and for a moment after, while the Dock slides away.
    func updateDockCover(cursor: NSPoint) {
        guard isActive, dockCoverHides, let dockCover else { return }
        // It only *starts* at the very edge of the screen — where the Dock is
        // summoned — so working near the bottom of a window doesn't bring it
        // up. Once up, it stays while you're anywhere over the Dock's band.
        let atEdge = dockCoverShowing
            ? dockCoverZone.contains(cursor)
            : dockCoverZone.contains(cursor) && distanceToOuterEdge(cursor) < 3
        if atEdge {
            leftDockEdgeAt = nil
            if !dockCoverShowing {
                dockCoverShowing = true
                dockCover.alphaValue = 1
                dockCover.ignoresMouseEvents = false
            }
        } else if dockCoverShowing {
            if leftDockEdgeAt == nil { leftDockEdgeAt = Date() }
            if let left = leftDockEdgeAt, Date().timeIntervalSince(left) > 0.6 {
                dockCoverShowing = false
                dockCover.alphaValue = 0
                dockCover.ignoresMouseEvents = true
            }
        }
    }

    private var dockSide = "bottom"

    /// How far the cursor is from the screen edge the Dock lives on.
    private func distanceToOuterEdge(_ point: NSPoint) -> CGFloat {
        switch dockSide {
        case "left": return point.x - dockCoverZone.minX
        case "right": return dockCoverZone.maxX - point.x
        default: return point.y - dockCoverZone.minY
        }
    }

    /// Where the Dock is and whether it hides itself, read from the Dock's own
    /// settings — reading them needs no permission, and nothing is changed.
    static func dockArea(on screen: NSScreen) -> (frame: NSRect, hides: Bool) {
        func setting<T>(_ key: String) -> T? {
            CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) as? T
        }
        let side: String = setting("orientation") ?? "bottom"
        let hides: Bool = setting("autohide") ?? false
        let tile = CGFloat((setting("tilesize") as Double?) ?? 48)

        let full = screen.frame, usable = screen.visibleFrame
        // A Dock that's always shown takes its room out of the usable area, so
        // that difference is exactly its size. A hidden one doesn't, so its
        // size is worked out from its icons, with a margin.
        let reserved: CGFloat
        switch side {
        case "left": reserved = usable.minX - full.minX
        case "right": reserved = full.maxX - usable.maxX
        default: reserved = usable.minY - full.minY
        }
        let thickness = (hides || reserved < 4) ? tile + 24 : reserved

        let frame: NSRect
        switch side {
        case "left": frame = NSRect(x: full.minX, y: full.minY, width: thickness, height: full.height)
        case "right": frame = NSRect(x: full.maxX - thickness, y: full.minY, width: thickness, height: full.height)
        default: frame = NSRect(x: full.minX, y: full.minY, width: full.width, height: thickness)
        }
        return (frame, hides || reserved < 4)
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

/// A panel that never takes keyboard focus: the strip and the Dock cover are
/// only ever there to sit on top of things.
private final class CoveringPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// MARK: - What the strip shows

/// Black, edge to edge. On the right: the low-battery warning when it's due,
/// the time left when a timer's running, and the clock. On the left, only
/// while you're holding to leave: what's about to happen, and how far along.
///
/// Not private, so Tools/preview-panel.sh can draw it.
struct StudyStripView: View {
    @ObservedObject var study: StudyController
    @ObservedObject private var settings = Settings.shared
    let notch: NSRect
    let screen: NSRect

    var body: some View {
        // Once a second: the clock and the countdown. A few words in a small
        // window — this costs next to nothing.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 0) {
                holdHint
                    .frame(width: max(0, notch.minX - screen.minX - 24), alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    batteryWarning
                    countdown(at: context.date)
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(width: screen.width, height: notch.height.rounded())
        .background(Color.black)
    }

    @ViewBuilder
    private var holdHint: some View {
        if let progress = study.holdProgress {
            HStack(spacing: 10) {
                Text("Keep holding to end Study Mode")
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
