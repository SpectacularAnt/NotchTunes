import AppKit
import SwiftUI

/// One song, as reported by a music app.
struct Track {
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    let source: String          // "Music" or "Spotify" — also the name commands go to
    let position: Double        // seconds played so far
    let duration: Double        // seconds long
    let volume: Double          // 0...100, the music app's own volume
    let trackID: String         // the music app's own id for this song, if it has one
    var artwork: NSImage?
    /// "off", "one" or "all" — Music's own words for its repeat modes. Spotify
    /// only has on and off, which come through as "all" and "off".
    var repeatMode: String = "off"

    /// Lets us notice when the song genuinely changed, rather than when it has
    /// merely ticked along by a second. The app's own id is the reliable answer;
    /// demo mode hasn't got one, so it falls back to the text.
    var identity: String {
        trackID.isEmpty ? "\(source)|\(title)|\(artist)|\(album)" : "\(source)|\(trackID)"
    }

    /// A copy with a different play state, for flipping the glyph the moment you
    /// click instead of waiting for the music app to confirm.
    func settingPlaying(_ playing: Bool) -> Track {
        Track(title: title, artist: artist, album: album, isPlaying: playing,
              source: source, position: position, duration: duration,
              volume: volume, trackID: trackID, artwork: artwork,
              repeatMode: repeatMode)
    }

    /// The same for the repeat button.
    func settingRepeat(_ mode: String) -> Track {
        var copy = self
        copy.repeatMode = mode
        return copy
    }
}

extension Track: Equatable {
    static func == (a: Track, b: Track) -> Bool {
        a.identity == b.identity
            && a.isPlaying == b.isPlaying
            && a.position == b.position
            && a.duration == b.duration
            && a.volume == b.volume
            && a.repeatMode == b.repeatMode
            && a.artwork === b.artwork     // NSImage is a class, so identity is enough
    }
}

/// What the notch draws. SwiftUI redraws whenever a @Published value changes.
final class NowPlayingModel: ObservableObject {
    @Published var track: Track?

    /// Which of the three states the notch is in. The window decides this; the
    /// view just follows it.
    @Published var isExpanded = false

    /// Whether the notch is on screen at all, bar or panel. The moving bars
    /// stop drawing while it isn't.
    @Published var isOnScreen = false

    /// What's kept in the notch's clipboard, newest first. Empty means the
    /// section doesn't exist and the notch looks just as it did before it.
    @Published var shelf: [ShelfItem] = []

    /// True while something is being dragged towards the notch and the drop
    /// area is open.
    @Published var isDropTarget = false

    /// True while Study Mode is on. Holding the panel then ends Study Mode
    /// rather than quitting.
    @Published var isStudying = false

    /// What a completed hold does while studying. Set by the app controller.
    var onStudyHoldComplete: (() -> Void)?

    /// Adds what was dropped.
    func keep(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        shelf = Shelf.merge(items, into: shelf)
    }

    /// Empties the clipboard — and the pictures saved for it — so the section
    /// disappears.
    func clearShelf() {
        shelf = []
        Shelf.removeSavedImages()
    }

    /// Which bar the cursor is over, by name, or nil.
    ///
    /// SwiftUI's `.onHover` is no use here: it relies on a tracking area that
    /// only fires for an active window, and this panel never becomes active —
    /// it's an accessory app with a non-activating panel. So hovering is worked
    /// out from the cursor position we are already polling.
    @Published var hoveredBar: String?

    /// Where each bar is, in the window's own coordinates, reported by the views
    /// themselves so the layout is only described in one place. Not @Published:
    /// nothing redraws because of it, and publishing it would loop.
    var barFrames: [String: CGRect] = [:]

    /// Where the transport buttons are, the same way — so that holding one of
    /// them is never mistaken for holding the panel to quit.
    var buttonFrames: [String: CGRect] = [:]

    /// How far through a hold-to-quit you are, 0 to 1, or nil when there isn't
    /// one. Drives the "keep holding" hint.
    @Published var holdProgress: Double?

    /// A colour taken from the album cover, for the moving bars — the way the
    /// Dynamic Island tints them to match whatever is playing.
    @Published var accent: Color = ArtworkTint.fallback

    /// Two colours from the cover for the visualizer's background.
    @Published var backdrop: [Color] = ArtworkTint.fallbackBackdrop

    /// Where the sound is going, when it isn't this Mac: the kind of AirPlay
    /// device ("HomePod", "Bluetooth device"…), "multiple", or nil for this
    /// Mac's own speakers. Read when the panel opens.
    @Published var airPlayRoute: String?

    /// What the AirPlay button does. Set by the app controller, which is the
    /// one that can both ask Music for its devices and open the menu.
    var onAirPlayTapped: (() -> Void)?

    /// Set when you click play/pause, so the poll doesn't overwrite your click
    /// with a stale answer before the music app has caught up.
    private var trustClickUntil: Date?
    private var trustRepeat: (mode: String, until: Date)?

    func apply(_ new: Track?) {
        var incoming = new

        // Keep showing what you asked for until the music app agrees, otherwise
        // the glyph flickers back to its old state for a fraction of a second.
        if let until = trustClickUntil, until > Date(),
           let mine = track, let theirs = incoming {
            incoming = theirs.settingPlaying(mine.isPlaying)
        } else if trustClickUntil != nil {
            trustClickUntil = nil
        }

        if let held = trustRepeat, let theirs = incoming {
            if held.until > Date() { incoming = theirs.settingRepeat(held.mode) } else { trustRepeat = nil }
        }

        guard track != incoming else { return }
        if incoming?.artwork !== track?.artwork {
            accent = incoming?.artwork.map(ArtworkTint.color(for:)) ?? ArtworkTint.fallback
            backdrop = incoming?.artwork.map(ArtworkTint.backdrop(for:)) ?? ArtworkTint.fallbackBackdrop
        }
        track = incoming
    }

    /// Shows the new repeat mode straight away, as the play button does.
    func noteRepeatSet(_ mode: String) {
        guard let current = track else { return }
        trustRepeat = (mode, Date().addingTimeInterval(0.8))
        track = current.settingRepeat(mode)
    }

    /// Flips the glyph straight away, so the button feels like it did something.
    func notePlayPauseClicked() {
        guard let current = track else { return }
        trustClickUntil = Date().addingTimeInterval(0.6)
        track = current.settingPlaying(!current.isPlaying)
    }
}

/// Reads the current song out of Music.app, and Spotify if it is installed, by
/// sending them the same Apple Events that AppleScript uses.
///
/// macOS blocks the private framework that the system's own Now Playing widget
/// uses, so asking the apps directly is the approach that actually works. The
/// trade-off: it covers Music and Spotify, but not audio playing in a browser.
final class NowPlayingReader {

    private struct Source {
        let name: String
        let bundleID: String
        /// Returns nine lines: title, artist, album, state, position, duration,
        /// volume, id, repeat.
        let infoScript: String
        /// Returns four lines: state, position, volume, repeat.
        let quickScript: String
        /// Spotify reports track length in milliseconds; Music reports seconds.
        let durationIsMilliseconds: Bool
        let artworkDataScript: String?
        let artworkURLScript: String?
    }

    /// Everything about the song: asked for only when something has changed.
    ///
    /// This used to fetch Music's *whole* record for the song and for the app
    /// in one go — `properties of current track`, sixty-odd fields including
    /// the lyrics — because that was quickest for NotchTunes. Measured with
    /// the same `top` figures Gauge shows, it was expensive for Music: about
    /// 6% of a core on its own, 16% with NotchTunes asking that once a second.
    /// Asking for the nine fields actually used, one by one, takes NotchTunes
    /// a little longer (off the main thread, where it doesn't matter) and costs
    /// Music next to nothing.
    private static let musicInfoScript = """
    tell application "Music"
        try
            set s to player state as text
            if s is "stopped" then return ""
            set t to current track
            return (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & s & linefeed & ((player position) as text) & linefeed & ((duration of t) as text) & linefeed & ((sound volume) as text) & linefeed & ((database ID of t) as text) & linefeed & (song repeat as text)
        on error
            return ""
        end try
    end tell
    """

    /// The quick check, asked several times a second while the panel is
    /// open: only the four things that change without the song changing.
    /// Returns four lines: state, position, volume, repeat.
    private static let musicQuickScript = """
    tell application "Music"
        try
            set s to player state as text
            if s is "stopped" then return ""
            return s & linefeed & ((player position) as text) & linefeed & ((sound volume) as text) & linefeed & (song repeat as text)
        on error
            return ""
        end try
    end tell
    """

    private static let spotifyQuickScript = """
    tell application "Spotify"
        try
            set s to player state as text
            if s is "stopped" then return ""
            return s & linefeed & ((player position) as text) & linefeed & ((sound volume) as text) & linefeed & (repeating as text)
        on error
            return ""
        end try
    end tell
    """

    /// Spotify's dictionary is a different shape, so it keeps the plain form.
    /// It is slower, but it is the version that is known to work.
    private static let spotifyInfoScript = """
    tell application "Spotify"
        try
            set theState to player state as text
            if theState is "stopped" then return ""
            set t to current track
            return (get name of t) & linefeed & (get artist of t) & linefeed & (get album of t) & linefeed & theState & linefeed & ((player position) as text) & linefeed & ((duration of t) as text) & linefeed & ((sound volume) as text) & linefeed & (get id of t) & linefeed & (repeating as text)
        on error
            return ""
        end try
    end tell
    """

    private let sources = [
        Source(name: "Music",
               bundleID: "com.apple.Music",
               infoScript: NowPlayingReader.musicInfoScript,
               quickScript: NowPlayingReader.musicQuickScript,
               durationIsMilliseconds: false,
               artworkDataScript: """
               tell application "Music"
                   try
                       return raw data of artwork 1 of current track
                   on error
                       return ""
                   end try
               end tell
               """,
               artworkURLScript: nil),

        Source(name: "Spotify",
               bundleID: "com.spotify.client",
               infoScript: NowPlayingReader.spotifyInfoScript,
               quickScript: NowPlayingReader.spotifyQuickScript,
               durationIsMilliseconds: true,
               artworkDataScript: nil,
               artworkURLScript: """
               tell application "Spotify"
                   try
                       return artwork url of current track
                   on error
                       return ""
                   end try
               end tell
               """)
    ]

    /// AppleScript is slow and not thread-safe, so every call happens one at a
    /// time on this queue, well away from the screen-drawing work.
    private let queue = DispatchQueue(label: "NotchTunes.nowPlaying")
    private var compiled: [String: NSAppleScript] = [:]

    private var artworkCache: [String: NSImage] = [:]
    /// Counts failures per song. A song whose artwork isn't ready yet should be
    /// tried again on the next poll — but a song that simply hasn't got a cover
    /// shouldn't be asked forever.
    private var artworkFailures: [String: Int] = [:]
    private static let artworkAttemptLimit = 6

    private var isReading = false

    /// Which app played most recently. With both paused, that's the one whose
    /// song stays on the notch — otherwise pausing Spotify would flip it over
    /// to whatever Music last had loaded, which is always something.
    /// Only touched on the reading queue.
    private var lastPlayingSource: String?

    /// The last full answer from each app, by name. A quick check updates
    /// the parts that change between songs and keeps the rest. Only touched
    /// on the reading queue.
    private var known: [String: Track] = [:]

    /// A full read asked for while another read was under way. Not dropped:
    /// it's usually the one that matters, because something just changed.
    private var fullReadWaiting = false

    /// `full` asks for everything about the song; otherwise it's the quick
    /// check of play state, position, volume and repeat.
    func read(full: Bool, completion: @escaping (Track?) -> Void) {
        // If a music app is slow to answer, don't pile more requests on top.
        guard !isReading else {
            if full { fullReadWaiting = true }
            return
        }
        isReading = true

        queue.async { [weak self] in
            guard let self else { return }
            let track = self.readOnQueue(full: full)
            DispatchQueue.main.async {
                self.isReading = false
                completion(track)
                if self.fullReadWaiting {
                    self.fullReadWaiting = false
                    self.read(full: true, completion: completion)
                }
            }
        }
    }

    private func readOnQueue(full: Bool) -> Track? {
        var pausedTracks: [Track] = []

        for source in sources {
            // Never message an app that isn't running: the Apple Event would
            // launch it, and opening Spotify because you glanced at the notch
            // would be a terrible surprise.
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID)
            guard !running.isEmpty else {
                known[source.name] = nil
                continue
            }

            let found = full || known[source.name] == nil
                ? readFull(source)
                : readQuick(source)
            known[source.name] = found
            guard let track = found else { continue }

            if track.isPlaying {                 // something playing always wins
                lastPlayingSource = source.name
                return track
            }
            pausedTracks.append(track)
        }

        // Podcasts, through macOS's own Now Playing service (see
        // SystemNowPlaying.swift). Its volume can't be reached, so the volume
        // bar shows — and sets — the Mac's own.
        if let episode = SystemNowPlaying.shared.track(volume: systemVolume()) {
            if episode.isPlaying {
                lastPlayingSource = episode.source
                return episode
            }
            pausedTracks.append(episode)
        }

        // Nothing playing: the paused song from whichever app played last,
        // falling back to the first one found.
        return pausedTracks.first { $0.source == lastPlayingSource } ?? pausedTracks.first
    }

    /// The Mac's output volume, 0...100. Asked of AppleScript's own built-in
    /// commands, which run inside NotchTunes and need no permission.
    private func systemVolume() -> Double {
        Double(run("output volume of (get volume settings)")?.int32Value ?? 50)
    }

    private func readFull(_ source: Source) -> Track? {
        guard let raw = run(source.infoScript)?.stringValue, !raw.isEmpty else { return nil }
        let lines = raw.components(separatedBy: "\n")
        guard lines.count >= 9 else { return nil }

        let rawDuration = Double(lines[5]) ?? 0
        var track = Track(
            title: lines[0],
            artist: lines[1],
            album: lines[2],
            isPlaying: lines[3].caseInsensitiveCompare("playing") == .orderedSame,
            source: source.name,
            position: Double(lines[4]) ?? 0,
            duration: source.durationIsMilliseconds ? rawDuration / 1000 : rawDuration,
            volume: Double(lines[6]) ?? 50,
            trackID: lines[7],
            artwork: nil,
            repeatMode: Self.repeatMode(lines[8]))
        track.artwork = artwork(for: track, from: source)
        return track
    }

    /// The four quick things, laid over the last full answer. Falls back to a
    /// full read if the answer suggests the song has changed underneath it —
    /// which the apps' own announcements should already have caught, but a
    /// missed one shouldn't leave the wrong song on screen.
    private func readQuick(_ source: Source) -> Track? {
        guard let previous = known[source.name] else { return readFull(source) }
        guard let raw = run(source.quickScript)?.stringValue, !raw.isEmpty else { return nil }
        let lines = raw.components(separatedBy: "\n")
        guard lines.count >= 4 else { return readFull(source) }

        let position = Double(lines[1]) ?? 0
        let jumpedBack = position < previous.position - 3
        let pastTheEnd = previous.duration > 0 && position > previous.duration + 2
        if jumpedBack || pastTheEnd { return readFull(source) }

        return Track(title: previous.title, artist: previous.artist, album: previous.album,
                     isPlaying: lines[0].caseInsensitiveCompare("playing") == .orderedSame,
                     source: previous.source, position: position, duration: previous.duration,
                     volume: Double(lines[2]) ?? previous.volume, trackID: previous.trackID,
                     artwork: previous.artwork, repeatMode: Self.repeatMode(lines[3]))
    }

    /// Music says "off", "one" or "all"; Spotify says "true" or "false".
    private static func repeatMode(_ raw: String) -> String {
        switch raw.lowercased() {
        case "one": return "one"
        case "all", "true": return "all"
        default: return "off"
        }
    }

    /// Artwork is only fetched when the song changes. A *failure* is not cached:
    /// when a track has just changed, the music app often hasn't loaded the cover
    /// yet, and caching that empty answer would leave the square blank for the
    /// whole song.
    private func artwork(for track: Track, from source: Source) -> NSImage? {
        let id = track.identity
        if let cached = artworkCache[id] { return cached }
        guard (artworkFailures[id] ?? 0) < NowPlayingReader.artworkAttemptLimit else { return nil }

        var image: NSImage?
        if let script = source.artworkDataScript,
           let data = run(script)?.data, !data.isEmpty {
            image = NSImage(data: data)
        } else if let script = source.artworkURLScript,
                  let text = run(script)?.stringValue,
                  let url = URL(string: text),
                  let data = try? Data(contentsOf: url) {
            image = NSImage(data: data)
        }

        if let image {
            artworkCache[id] = image
            // Keep the cache from growing without limit over a long listening
            // session. Covers are about a megabyte each.
            if artworkCache.count > 24 {
                artworkCache.removeAll()
                artworkCache[id] = image
            }
        } else {
            artworkFailures[id, default: 0] += 1
        }
        return image
    }

    /// Runs a script, reusing the compiled version next time round.
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let existing = compiled[source] {
            script = existing
        } else {
            guard let fresh = NSAppleScript(source: source) else { return nil }
            compiled[source] = fresh
            script = fresh
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            // Error -1743 means the Automation permission was declined. Everything
            // else is usually the music app being busy, which the next poll fixes.
            NSLog("NotchTunes: AppleScript error %@", error)
            return nil
        }
        return result
    }
}
