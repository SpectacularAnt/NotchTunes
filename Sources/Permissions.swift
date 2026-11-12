import AppKit
import Combine
import CoreAudio
import SwiftUI

/// The permissions NotchTunes uses, how to tell whether each is granted, and
/// how to ask for it.
///
/// There are only two kinds:
///  - **Automation**, per music app: sending Music (or Spotify) the Apple
///    Events that read the song and press its buttons. Without it, nothing
///    works.
///  - **System audio recording**: hearing what the music app plays, for the
///    moving bars to follow. Without it, the bars use their own pattern.
enum Permissions {

    enum State: Equatable {
        case granted
        case denied
        case notAsked
        /// The app isn't open, so macOS can't ask about it yet.
        case appClosed
        /// The app isn't on this Mac at all.
        case notInstalled
        /// Asked, but macOS won't say what the answer was.
        case asked
    }

    // MARK: Automation

    static func automation(of bundleID: String) -> State {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { return .notInstalled }
        return state(from: determine(bundleID, ask: false))
    }

    /// Shows macOS's own "NotchTunes wants to control Music" prompt, if it
    /// hasn't been answered. Waits for the answer off the main thread, since
    /// asking blocks until you click, then answers on the main thread.
    static func requestAutomation(of bundleID: String, completion: @escaping (State) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let status = determine(bundleID, ask: true)
            DispatchQueue.main.async { completion(state(from: status)) }
        }
    }

    private static func determine(_ bundleID: String, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return OSStatus(procNotFound) }
        return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
    }

    private static func state(from status: OSStatus) -> State {
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .appClosed
        default: return .notAsked      // errAEEventWouldRequireUserConsent, mostly
        }
    }

    // MARK: Hearing the music

    /// Whether the system-audio permission has been asked for here. macOS has
    /// no public way to read the answer itself, so this only remembers that
    /// the question was put; the moving bars find out the rest for themselves.
    static var audioAsked: Bool {
        get { UserDefaults.standard.bool(forKey: "audioPermissionAsked") }
        set { UserDefaults.standard.set(newValue, forKey: "audioPermissionAsked") }
    }

    /// Brings up macOS's system-audio recording prompt by briefly setting up a
    /// tap — the same thing the moving bars do — and taking it down again at
    /// once. Nothing is listened to.
    static func requestAudio() {
        audioAsked = true
        guard #available(macOS 14.2, *) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            // A tap on everything except nothing: it needs no particular app
            // to be making sound, so it works whether or not Music is open.
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            description.isPrivate = true
            var tap = AudioObjectID(kAudioObjectUnknown)
            if AudioHardwareCreateProcessTap(description, &tap) == noErr {
                AudioHardwareDestroyProcessTap(tap)
            }
        }
    }

    // MARK: System Settings

    static func openAutomationSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    static func openAudioSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
    }

    private static func open(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}

/// The window that asks for the permissions: shown by itself the first time
/// NotchTunes opens, and from the menu bar item afterwards.
final class PermissionsWindowController: NSObject, NSWindowDelegate {

    private static let shownKey = "permissionsWindowShown"
    private var window: NSWindow?

    /// The first launch only.
    func showIfFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: Self.shownKey) else { return }
        show()
    }

    func show() {
        UserDefaults.standard.set(true, forKey: Self.shownKey)

        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "Welcome to NotchTunes"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: PermissionsView(onDone: { [weak window] in
                window?.performClose(nil)
            }))
            window.center()
            self.window = window
        }
        // No Dock icon, so it has to bring itself forward.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }
}

/// One row per permission, each with what it's for, where it stands, and a
/// button to ask for it. Re-checks every second, so answering a macOS prompt
/// or flipping a switch in System Settings shows up here by itself.
///
/// Not private, so Tools/preview-panel.sh can draw it.
struct PermissionsView: View {
    var onDone: () -> Void = {}

    /// For the preview tool, which can't wait for real answers.
    var fixed: (music: Permissions.State, spotify: Permissions.State, audioAsked: Bool)?

    @State private var music = Permissions.State.notAsked
    @State private var spotify = Permissions.State.notInstalled
    @State private var audioAsked = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NotchTunes needs a couple of permissions")
                    .font(.system(size: 15, weight: .semibold))
                Text("macOS asks for each one in its own window. You can change any of them later in System Settings → Privacy & Security.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            row(symbol: "music.note",
                title: "Control Music",
                detail: "Reads what's playing and works the buttons. Needed.",
                state: music,
                ask: { Permissions.requestAutomation(of: "com.apple.Music") { music = $0 } },
                settings: Permissions.openAutomationSettings)

            if spotify != .notInstalled {
                row(symbol: "music.note.list",
                    title: "Control Spotify",
                    detail: "The same, for when Spotify is the one playing.",
                    state: spotify,
                    ask: { Permissions.requestAutomation(of: "com.spotify.client") { spotify = $0 } },
                    settings: Permissions.openAutomationSettings)
            }

            row(symbol: "waveform",
                title: "Hear the music",
                detail: "Lets the moving bars follow the beat. Choose \"System Audio Recording Only\". Optional.",
                state: audioState,
                ask: { Permissions.requestAudio(); audioAsked = true },
                settings: Permissions.openAudioSettings)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440, height: 340)
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in refresh() }
    }

    /// Allowed once the bars are actually hearing music, which is the only
    /// sure sign; "asked" until then, since macOS keeps the answer to itself.
    private var audioState: Permissions.State {
        if fixed == nil, AudioFollower.shared.status == .following { return .granted }
        return audioAsked ? .asked : .notAsked
    }

    private func refresh() {
        if let fixed {
            music = fixed.music; spotify = fixed.spotify; audioAsked = fixed.audioAsked
            return
        }
        music = Permissions.automation(of: "com.apple.Music")
        spotify = Permissions.automation(of: "com.spotify.client")
        audioAsked = Permissions.audioAsked
    }

    private func row(symbol: String, title: String, detail: String,
                     state: Permissions.State,
                     ask: @escaping () -> Void, settings: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Group {
                switch state {
                case .granted:
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 11, weight: .medium))
                case .notAsked:
                    Button("Allow…", action: ask)
                case .denied:
                    Button("Open Settings", action: settings)
                case .appClosed:
                    Text("Asks when it opens")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                case .asked:
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Asked")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Button("Change in Settings", action: settings)
                            .buttonStyle(.link)
                            .font(.system(size: 10))
                    }
                case .notInstalled:
                    EmptyView()
                }
            }
            .frame(minWidth: 96, alignment: .trailing)
        }
    }
}
