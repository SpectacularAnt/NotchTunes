import AppKit

/// Checks GitHub for a newer NotchTunes and, if you want it, installs it.
///
/// Each version is published as a GitHub release (Tools/release.sh does that)
/// with the built app attached as NotchTunes.zip. Checking asks GitHub's
/// public API for the latest release and compares its version number with
/// this one's. Installing downloads the zip, checks it really is NotchTunes,
/// then hands over to a few lines of shell that wait for this copy to quit,
/// swap the new one into its place, and open it.
///
/// Nothing is checked or downloaded unless you choose Check for Updates.
final class Updater {

    static let repository = "SpectacularAnt/NotchTunes"
    static let assetName = "NotchTunes.zip"

    private struct Release {
        let version: String
        let notes: String
        let download: URL
    }

    private var isChecking = false

    /// The version this copy is: CFBundleShortVersionString, like "1.1".
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: Checking

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub asks every caller to say who it is. A plain name, nothing more.
        request.setValue("NotchTunes", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let release = data.flatMap(Self.parse)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false

                if let release {
                    if Self.isNewer(release.version, than: Self.currentVersion) {
                        self.offer(release)
                    } else {
                        self.tell("You're up to date",
                                  "NotchTunes \(Self.currentVersion) is the newest version.")
                    }
                } else if status == 404 {
                    // No releases yet — or the repository isn't public.
                    self.tell("No updates published yet",
                              "There isn't a released version of NotchTunes on GitHub to compare with.")
                } else {
                    self.tell("Couldn't check for updates",
                              error?.localizedDescription ?? "GitHub didn't answer as expected. Try again in a little while.")
                }
            }
        }.resume()
    }

    private static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == assetName }),
              let link = asset["browser_download_url"] as? String,
              let url = URL(string: link)
        else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, notes: json["body"] as? String ?? "", download: url)
    }

    /// Compares version numbers part by part, so 1.10 is newer than 1.9.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Asking

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "NotchTunes \(release.version) is available"
        var info = "You have version \(Self.currentVersion)."
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { info += "\n\n" + notes }
        info += "\n\nNotchTunes will quit, update and reopen. macOS may ask for its permissions again afterwards."
        alert.informativeText = info
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            install(release)
        }
    }

    private func tell(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: Installing

    private func install(_ release: Release) {
        URLSession.shared.downloadTask(with: release.download) { [weak self] file, _, error in
            let result: Result<URL, UpdateError>
            if let file {
                result = Self.unpack(file, expecting: release.version)
            } else {
                result = .failure(.download(error?.localizedDescription ?? "The download didn't finish."))
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let newApp): self?.swap(in: newApp)
                case .failure(let problem): self?.tell("Couldn't update NotchTunes", problem.message)
                }
            }
        }.resume()
    }

    enum UpdateError: Error {
        case download(String)
        case contents(String)

        var message: String {
            switch self {
            case .download(let why): return why
            case .contents(let why): return why
            }
        }
    }

    /// Unzips the download into a fresh folder and makes sure what came out
    /// is NotchTunes, at the version promised, before anything is replaced.
    private static func unpack(_ zip: URL, expecting version: String) -> Result<URL, UpdateError> {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTunes-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return .failure(.contents("Couldn't make a folder for the download."))
        }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, folder.path]
        do { try unzip.run() } catch { return .failure(.contents("Couldn't unzip the download.")) }
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { return .failure(.contents("The download wasn't a readable zip.")) }

        let app = folder.appendingPathComponent("NotchTunes.app")
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.infoDictionary?["CFBundleShortVersionString"] as? String == version
        else {
            return .failure(.contents("The download didn't contain NotchTunes \(version)."))
        }
        return .success(app)
    }

    /// Quits, and leaves a few lines of shell to put the new copy where this
    /// one is and open it. The swap has to wait until this copy has quit:
    /// replacing a running app's files under it is asking for trouble.
    private func swap(in newApp: URL) {
        let here = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier

        // The installer deletes this copy before putting the new one in its
        // place, so it must only ever be pointed at an installed NotchTunes.
        guard Bundle.main.bundleURL.lastPathComponent == "NotchTunes.app",
              Bundle.main.bundleIdentifier == "local.notchtunes" else {
            tell("Couldn't update NotchTunes",
                 "This copy isn't running from an installed NotchTunes.app, so it won't replace itself.")
            return
        }

        func quoted(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf \(quoted(here))
        /usr/bin/ditto \(quoted(newApp.path)) \(quoted(here))
        /usr/bin/open \(quoted(here))
        """

        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", script]
        do {
            try shell.run()
        } catch {
            tell("Couldn't update NotchTunes", "The installer didn't start.")
            return
        }
        logLine("update: handing over to the installer and quitting")
        NSApp.terminate(nil)
    }
}
