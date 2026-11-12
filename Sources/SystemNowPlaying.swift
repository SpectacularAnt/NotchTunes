import AppKit

/// What macOS's own Now Playing service says is playing — used for Podcasts,
/// which has no scripting of its own the way Music and Spotify do.
///
/// **How, and why it might break.** The service (the private MediaRemote
/// framework, the same one Control Center's Now Playing uses) has been
/// closed to outside apps since macOS 15.4. It still answers Apple's own
/// programs, and perl is one of them that will load a library it's handed.
/// So NotchTunes runs `/usr/bin/perl` with a small helper library
/// (Helper/NowPlayingHelper.m) that asks the service and prints what it hears
/// as lines of JSON. This leans on Apple leaving that door open: a macOS
/// update could close it, and then Podcasts simply stops showing — Music and
/// Spotify don't go through here at all, so they're unaffected.
///
/// The helper is told whenever anything changes, so there's no polling: it
/// sits waiting, and NotchTunes reads its lines as they come.
final class SystemNowPlaying {
    static let shared = SystemNowPlaying()

    /// The apps this is used for. Music and Spotify have a proper connection
    /// already, which is kept.
    static let bundleIDs: [String: String] = ["com.apple.podcasts": "Podcasts"]

    /// Called on the main thread when something changes.
    var onChange: (() -> Void)?

    private struct Report {
        let bundleID: String
        let isPlaying: Bool
        let title: String
        let artist: String
        let album: String
        let id: String
        let duration: Double
        let elapsed: Double
        let rate: Double
        let timestamp: Date
    }

    private let lock = NSLock()
    private var report: Report?
    private var artwork: NSImage?
    private var artworkFor = ""

    private var process: Process?
    private var restarts = 0

    private var helper: (script: String, library: String)? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let script = resources.appendingPathComponent("NowPlayingHelper.pl").path
        let library = resources.appendingPathComponent("NowPlayingHelper.dylib").path
        guard FileManager.default.fileExists(atPath: script),
              FileManager.default.fileExists(atPath: library) else { return nil }
        return (script, library)
    }

    // MARK: Listening

    /// Starts the helper, if Podcasts is on this Mac at all.
    func start() {
        guard process == nil, let helper,
              Self.bundleIDs.keys.contains(where: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
        else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [helper.script, helper.library, "stream"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        var pending = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                self?.consume(Data(line))
            }
        }

        // If it stops, start it again — a few times, not for ever, in case a
        // macOS update has broken it for good.
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.process = nil
                guard self.restarts < 5 else {
                    logLine("now playing helper: gave up after repeated stops")
                    return
                }
                self.restarts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.start() }
            }
        }

        do {
            try task.run()
            process = task
            logLine("now playing helper: started")
        } catch {
            logLine("now playing helper: couldn't start — \(error)")
        }
    }

    private func consume(_ line: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if let error = json["error"] as? String {
            logLine("now playing helper: \(error)")
            return
        }

        func number(_ key: String) -> Double { (json[key] as? NSNumber)?.doubleValue ?? 0 }
        func text(_ key: String) -> String { json[key] as? String ?? "" }

        let fresh = Report(bundleID: text("bundle"),
                           isPlaying: (json["playing"] as? NSNumber)?.boolValue ?? false,
                           title: text("title"), artist: text("artist"), album: text("album"),
                           id: text("id"),
                           duration: number("duration"), elapsed: number("elapsed"),
                           rate: number("rate"),
                           timestamp: Date(timeIntervalSince1970: number("timestamp")))

        lock.lock()
        report = fresh
        let identity = "\(fresh.title)|\(fresh.album)"
        if let encoded = json["artwork"] as? String,
           let data = Data(base64Encoded: encoded), let image = NSImage(data: data) {
            artwork = image
            artworkFor = identity
        } else if artworkFor != identity {
            artwork = nil        // a different episode, and no picture for it yet
        }
        lock.unlock()

        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    // MARK: Reading

    /// The episode playing in Podcasts, as a Track — or nil if it isn't
    /// Podcasts that's playing, or Podcasts isn't open. `volume` is filled in
    /// by the caller, since Podcasts' own volume can't be reached.
    func track(volume: @autoclosure () -> Double) -> Track? {
        lock.lock()
        defer { lock.unlock() }
        guard let report, let name = Self.bundleIDs[report.bundleID],
              !report.title.isEmpty,
              !NSRunningApplication.runningApplications(withBundleIdentifier: report.bundleID).isEmpty
        else { return nil }

        // The service gives the position as it was at a moment, and how fast
        // it was moving; the rest is arithmetic.
        var position = report.elapsed
        if report.isPlaying && report.timestamp.timeIntervalSince1970 > 0 {
            position += Date().timeIntervalSince(report.timestamp) * max(report.rate, 0)
        }
        if report.duration > 0 { position = min(position, report.duration) }

        return Track(title: report.title,
                     artist: report.artist.isEmpty ? report.album : report.artist,
                     album: report.album,
                     isPlaying: report.isPlaying && report.rate > 0,
                     source: name,
                     position: max(0, position),
                     duration: report.duration,
                     volume: volume(),
                     trackID: report.id.isEmpty ? "\(report.title)|\(report.album)" : report.id,
                     artwork: artwork,
                     repeatMode: "off")
    }

    // MARK: Commands

    /// Sends one command: "toggle", "next", "previous", or "seek:<seconds>".
    /// Each is a short-lived helper of its own, so it can't hold anything up.
    func send(_ command: String, completion: (() -> Void)? = nil) {
        guard let helper else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [helper.script, helper.library, "send", command]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { _ in DispatchQueue.main.async { completion?() } }
        try? task.run()
    }
}
