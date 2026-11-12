import AppKit
import SwiftUI

/// The settings window, opened from the menu bar item.
final class SettingsWindowController {

    private var window: NSWindow?

    func show() {
        if window == nil {
            let panel = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 580),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false)
            panel.title = "NotchTunes Settings"
            panel.contentView = NSHostingView(rootView: SettingsView(settings: .shared))
            // Without this the window is destroyed on close and reopening crashes.
            panel.isReleasedWhenClosed = false
            panel.center()
            window = panel
        }

        // An app with no Dock icon has to bring itself forward, or the window
        // opens behind whatever you were using and won't take typing.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Not private, so Tools/preview-panel.sh can draw it.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var audio = AudioFollower.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Keep it visible while a song is loaded", isOn: $settings.keepVisible)
                .font(.system(size: 12, weight: .semibold))

            VStack(alignment: .leading, spacing: 5) {
                Toggle("Show on every desktop", isOn: $settings.allDesktops)
                    .font(.system(size: 12, weight: .semibold))
                Text(settings.allDesktops
                     ? "Follows you between desktops, and hides over full-screen apps."
                     : "Stays on one desktop. Move to This Desktop brings it across.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            row(title: "Delay before the panel opens",
                detail: settings.hoverDelay < 0.01
                    ? "Opens as soon as your cursor reaches the notch"
                    : String(format: "Rest on the notch for %.2f seconds", settings.hoverDelay),
                value: $settings.hoverDelay,
                range: 0...1.5,
                low: "Instant",
                high: "1.5s")

            row(title: "How long a new song is announced",
                detail: settings.keepVisible
                    ? "Not used while it's kept visible"
                    : (settings.peekDuration < 0.01
                        ? "Don't announce new songs at all"
                        : String(format: "%.1f seconds", settings.peekDuration)),
                value: $settings.peekDuration,
                range: 0...10,
                low: "Off",
                high: "10s")
                .opacity(settings.keepVisible ? 0.4 : 1)
                .disabled(settings.keepVisible)

            Divider()

            Toggle("Hold the panel to quit", isOn: $settings.holdToQuit)
                .font(.system(size: 12, weight: .semibold))

            row(title: "How long to hold",
                detail: settings.holdToQuit
                    ? String(format: "Press and hold empty space on the open panel for %.1f seconds. "
                             + "Useful when the menu bar is hidden and Quit can't be reached.",
                             settings.holdToQuitSeconds)
                    : "Switched off",
                value: $settings.holdToQuitSeconds,
                range: 1...5,
                low: "1s",
                high: "5s")
                .opacity(settings.holdToQuit ? 1 : 0.4)
                .disabled(!settings.holdToQuit)

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Toggle("Moving bars follow the music", isOn: $settings.barsFollowMusic)
                    .font(.system(size: 12, weight: .semibold))
                Text(audioNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            row(title: "How bouncy the bars are",
                detail: settings.barsFollowMusic
                    ? "How far they leap on each beat, and how quickly they drop back."
                    : "Only used while the bars follow the music",
                value: $settings.barBounce,
                range: 0...1,
                low: "Calm",
                high: "Bouncy")
                .opacity(settings.barsFollowMusic ? 1 : 0.4)
                .disabled(!settings.barsFollowMusic)

            Spacer(minLength: 0)

            Text("Changes apply straight away.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 380, height: 580)
    }

    /// One line on whether the bars can actually hear anything.
    private var audioNote: String {
        guard settings.barsFollowMusic else { return "The bars move on their own pattern." }
        switch audio.status {
        case .following: return "Listening to the music now."
        case .silent: return "The music comes through silent, so the bars use their own pattern."
        case .unavailable: return "macOS wouldn't allow listening, so the bars use their own pattern."
        case .idle: return "Listens while music is playing."
        }
    }

    private func row(title: String,
                     detail: String,
                     value: Binding<Double>,
                     range: ClosedRange<Double>,
                     low: String,
                     high: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))

            Slider(value: value, in: range) {
                EmptyView()
            } minimumValueLabel: {
                Text(low).font(.system(size: 9)).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(high).font(.system(size: 9)).foregroundStyle(.secondary)
            }

            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
