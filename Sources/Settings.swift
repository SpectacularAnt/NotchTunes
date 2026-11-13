import Foundation

/// The things you can change, saved in UserDefaults so they survive a restart.
final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Key {
        static let hoverDelay = "hoverDelay"
        static let peekDuration = "peekDuration"
        static let keepVisible = "keepVisible"
        static let holdToQuit = "holdToQuit"
        static let holdToQuitSeconds = "holdToQuitSeconds"
        static let barsFollowMusic = "barsFollowMusic"
        static let barBounce = "barBounce"
        static let barLoudness = "barLoudness"
        static let allDesktops = "allDesktops"
        static let studyBlocksDock = "studyBlocksDock"
        static let studyBatteryThreshold = "studyBatteryThreshold"
    }

    /// How long the cursor has to rest on the notch before the panel opens.
    /// Zero opens it as soon as the cursor arrives, which is how it behaved
    /// before this setting existed.
    @Published var hoverDelay: Double {
        didSet { UserDefaults.standard.set(hoverDelay, forKey: Key.hoverDelay) }
    }

    /// Whether the bar stays on screen the whole time a song is loaded, paused
    /// included. With this off it only announces itself when a song starts, then
    /// hides until you hover the notch.
    @Published var keepVisible: Bool {
        didSet { UserDefaults.standard.set(keepVisible, forKey: Key.keepVisible) }
    }

    /// How long the bar stays up when a song starts, when it isn't being kept
    /// visible the whole time.
    @Published var peekDuration: Double {
        didSet { UserDefaults.standard.set(peekDuration, forKey: Key.peekDuration) }
    }

    /// Whether pressing and holding the expanded panel quits the app — the way
    /// out for when the menu bar, and the Quit item in it, has been hidden.
    @Published var holdToQuit: Bool {
        didSet { UserDefaults.standard.set(holdToQuit, forKey: Key.holdToQuit) }
    }

    /// How long that hold has to last.
    @Published var holdToQuitSeconds: Double {
        didSet { UserDefaults.standard.set(holdToQuitSeconds, forKey: Key.holdToQuitSeconds) }
    }

    /// Whether the moving bars listen to the music and follow it, rather than
    /// moving on their own pattern.
    @Published var barsFollowMusic: Bool {
        didSet { UserDefaults.standard.set(barsFollowMusic, forKey: Key.barsFollowMusic) }
    }

    /// How far the moving bars leap on each beat, 0 (calm) to 1 (bouncy).
    @Published var barBounce: Double {
        didSet {
            UserDefaults.standard.set(barBounce, forKey: Key.barBounce)
            AudioLevels.shared.bounce = Float(barBounce)
        }
    }

    /// Whether the notch shows on every desktop rather than only the one it
    /// was put on. Off, "Move to This Desktop" brings it across by hand.
    @Published var allDesktops: Bool {
        didSet { UserDefaults.standard.set(allDesktops, forKey: Key.allDesktops) }
    }

    /// Whether Study Mode blocks the Dock as well as the menu bar.
    @Published var studyBlocksDock: Bool {
        didSet { UserDefaults.standard.set(studyBlocksDock, forKey: Key.studyBlocksDock) }
    }

    /// In Study Mode, the battery shows once it's at or below this percentage.
    @Published var studyBatteryThreshold: Double {
        didSet { UserDefaults.standard.set(studyBatteryThreshold, forKey: Key.studyBatteryThreshold) }
    }

    /// How much the song's loudness shapes the moving bars: 0 (beats only)
    /// to 1 (loud parts tall, quiet parts low). The middle is the original.
    @Published var barLoudness: Double {
        didSet {
            UserDefaults.standard.set(barLoudness, forKey: Key.barLoudness)
            AudioLevels.shared.loudness = Float(barLoudness)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Key.hoverDelay: 0.0,
                                     Key.peekDuration: 3.0,
                                     Key.keepVisible: true,
                                     Key.holdToQuit: true,
                                     Key.holdToQuitSeconds: 2.0,
                                     Key.barsFollowMusic: true,
                                     Key.barBounce: 0.5,
                                     Key.barLoudness: 0.5,
                                     Key.allDesktops: false,
                                     Key.studyBlocksDock: false,
                                     Key.studyBatteryThreshold: 20.0])
        hoverDelay = defaults.double(forKey: Key.hoverDelay)
        peekDuration = defaults.double(forKey: Key.peekDuration)
        keepVisible = defaults.bool(forKey: Key.keepVisible)
        holdToQuit = defaults.bool(forKey: Key.holdToQuit)
        holdToQuitSeconds = defaults.double(forKey: Key.holdToQuitSeconds)
        barsFollowMusic = defaults.bool(forKey: Key.barsFollowMusic)
        barBounce = defaults.double(forKey: Key.barBounce)
        allDesktops = defaults.bool(forKey: Key.allDesktops)
        studyBlocksDock = defaults.bool(forKey: Key.studyBlocksDock)
        studyBatteryThreshold = defaults.double(forKey: Key.studyBatteryThreshold)
        barLoudness = defaults.double(forKey: Key.barLoudness)
        // didSet doesn't run during init, so hand the saved values over here.
        AudioLevels.shared.bounce = Float(barBounce)
        AudioLevels.shared.loudness = Float(barLoudness)
    }
}
