import Foundation

/// Demo mode shows a sample song, so the notch can be checked without starting
/// any music. `paused` previews the paused state, where the bar hides itself:
///
///     NOTCHTUNES_DEMO=1 ./NotchTunes.app/Contents/MacOS/NotchTunes
///     NOTCHTUNES_DEMO=paused ./NotchTunes.app/Contents/MacOS/NotchTunes
private let demoSetting = ProcessInfo.processInfo.environment["NOTCHTUNES_DEMO"] ?? ""
let isDemoMode = demoSetting == "1" || demoSetting == "paused"
let demoIsPlaying = demoSetting != "paused"

/// Narrates what the app is doing, which is the quickest way to see why the pill
/// is not appearing. On in demo mode, or on its own:
///
///     NOTCHTUNES_VERBOSE=1 ./NotchTunes.app/Contents/MacOS/NotchTunes
let isVerbose = isDemoMode || ProcessInfo.processInfo.environment["NOTCHTUNES_VERBOSE"] == "1"

func logLine(_ message: String) {
    guard isVerbose else { return }
    FileHandle.standardError.write(Data("NotchTunes: \(message)\n".utf8))
}

/// True only inside Tools/preview-panel.sh. Its renderer can't draw a few
/// things — what's inside a scrolling row, or anything that takes a drop — so
/// those parts draw a plain stand-in instead while it's set.
var isRenderingPreview = false

/// Forces the bars' knobs on, which they otherwise only are under the cursor.
/// Used by Tools/preview-panel.sh to show that state in a still image:
///
///     NOTCHTUNES_SHOW_KNOBS=1
let forceKnobsVisible = ProcessInfo.processInfo.environment["NOTCHTUNES_SHOW_KNOBS"] == "1"
