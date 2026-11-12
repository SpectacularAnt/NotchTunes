import AppKit

/// Sends playback commands back to whichever app is currently playing.
///
/// Music and Spotify both understand this same small vocabulary, so the only
/// thing that changes between them is the name in the `tell` line.
final class PlayerControl {

    /// The app to send commands to. The reader sets this each time it finds a
    /// song, so the buttons always act on whatever is actually playing.
    var activeApp: String?

    /// Called on the main thread once a command has been sent, so the display
    /// can read back the result without waiting for the next poll.
    var onCommandFinished: (() -> Void)?

    private let queue = DispatchQueue(label: "NotchTunes.control")

    /// Podcasts is reached through macOS's Now Playing service rather than
    /// AppleScript — see SystemNowPlaying.swift.
    private var isPodcasts: Bool { activeApp == "Podcasts" }

    private func sendToPodcasts(_ command: String) {
        SystemNowPlaying.shared.send(command) { [weak self] in self?.onCommandFinished?() }
    }

    func togglePlayPause() {
        if isPodcasts { sendToPodcasts("toggle"); return }
        run("playpause")
    }

    func previousTrack() {
        if isPodcasts { sendToPodcasts("previous"); return }
        run("previous track")
    }

    func nextTrack() {
        if isPodcasts { sendToPodcasts("next"); return }
        run("next track")
    }

    /// `value` is 0...100, matching what the music apps use. For Podcasts,
    /// whose own volume can't be reached, it's the Mac's volume instead.
    func setVolume(_ value: Double) {
        if isPodcasts {
            runRaw("set volume output volume \(clampedInt(value, max: 100))")
            return
        }
        run("set sound volume to \(clampedInt(value, max: 100))")
    }

    /// Jumps forwards or back by some seconds — Podcasts' 15 back, 30 on.
    func skip(by seconds: Double, from position: Double) {
        seek(to: max(0, position + seconds))
    }

    /// `seconds` from the start of the track.
    func seek(to seconds: Double) {
        if isPodcasts { sendToPodcasts("seek:\(clampedInt(seconds, max: 86_400))"); return }
        run("set player position to \(clampedInt(seconds, max: 86_400))")
    }

    /// `mode` is "off", "one" or "all". Spotify has no "repeat one", and
    /// only knows on and off.
    func setRepeat(_ mode: String) {
        if isPodcasts { return }      // Podcasts has no repeat
        if activeApp == "Spotify" {
            run("set repeating to \(mode == "off" ? "false" : "true")")
        } else {
            run("set song repeat to \(mode)")
        }
    }

    // MARK: AirPlay

    /// One place Music can send its sound.
    struct AirPlayDevice {
        let name: String
        let kind: String        // "computer", "HomePod", "Bluetooth device"…
        let isSelected: Bool
    }

    /// Asks Music which AirPlay devices are around right now. Only Music has
    /// these: Spotify's scripting knows nothing about AirPlay. Answers on the
    /// main thread, with an empty list if Music isn't the one playing.
    func airPlayDevices(completion: @escaping ([AirPlayDevice]) -> Void) {
        guard activeApp == "Music" else { completion([]); return }

        let source = """
        tell application "Music"
            set out to ""
            try
                repeat with d in (every AirPlay device whose available is true)
                    set out to out & (name of d) & tab & ((kind of d) as text) & tab & ((selected of d) as text) & linefeed
                end repeat
            end try
            return out
        end tell
        """

        queue.async {
            var error: NSDictionary?
            let text = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue ?? ""
            let devices = text.split(separator: "\n").compactMap { line -> AirPlayDevice? in
                let parts = line.components(separatedBy: "\t")
                guard parts.count == 3 else { return nil }
                return AirPlayDevice(name: parts[0], kind: parts[1], isSelected: parts[2] == "true")
            }
            DispatchQueue.main.async { completion(devices) }
        }
    }

    /// Sends the sound to one device, and only that one — what tapping a
    /// device in the iPhone's AirPlay list does.
    func selectAirPlay(_ name: String) {
        guard activeApp == "Music" else { return }
        let quoted = "\"" + name.replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        run("set current AirPlay devices to {AirPlay device \(quoted)}")
    }

    /// Which way the sound is going, boiled down for the AirPlay button: nil
    /// for this Mac, "multiple" for more than one device, or the kind of the
    /// one device it's going to.
    static func route(of devices: [AirPlayDevice]) -> String? {
        let chosen = devices.filter(\.isSelected)
        if chosen.count > 1 { return "multiple" }
        guard let only = chosen.first, only.kind != "computer" else { return nil }
        return only.kind
    }

    /// The glyph for a kind of device, or for a route as `route(of:)` gives it.
    /// Nil is this Mac's own speakers, shown as the AirPlay glyph itself.
    static func symbol(forKind kind: String?) -> String {
        switch kind {
        case nil: return "airplayaudio"
        case "computer": return "laptopcomputer"
        case "HomePod": return "homepod.fill"
        case "Apple TV": return "appletv.fill"
        case "Bluetooth device": return "headphones"
        case "multiple": return "hifispeaker.2.fill"
        default: return "hifispeaker.fill"
        }
    }

    private func clampedInt(_ value: Double, max upper: Int) -> Int {
        guard value.isFinite else { return 0 }
        return min(Swift.max(Int(value.rounded()), 0), upper)
    }

    /// A script on its own, not addressed to any app — for AppleScript's
    /// built-in commands, like the Mac's volume.
    private func runRaw(_ source: String) {
        queue.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.async { self.onCommandFinished?() }
        }
    }

    private func run(_ command: String) {
        // Demo mode has no real app behind it, so there is nothing to command.
        guard let app = activeApp, app == "Music" || app == "Spotify" else { return }

        let source = """
        tell application "\(app)"
            try
                \(command)
            end try
        end tell
        """

        // Not cached, unlike the reader's scripts: every volume value makes a
        // different script, so a cache here would grow forever. Commands only
        // happen when you touch a control, so compiling each time is fine.
        queue.async {
            guard let script = NSAppleScript(source: source) else { return }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error {
                NSLog("NotchTunes: command failed %@", error)
            }
            DispatchQueue.main.async { self.onCommandFinished?() }
        }
    }
}
