import AppKit
import SwiftUI

// Renders the notch, expanded, straight to a PNG — without running the app,
// opening a window, or needing anything to be playing. Useful for looking at a
// layout change. Run it with Tools/preview-panel.sh.
//
// An optional second argument picks what to draw:
//   hold      the panel part-way through a hold-to-quit
//   settings  the settings pane
//   study            Study Mode's strip, timer running, battery low, mid-hold
//   study-start      the same strip at the start of its animation, at the notch
//   permissions      the permissions window, part-way through
//   permissions-new  the permissions window, nothing asked yet
//   repeat1   repeat set to "this song"
//   airplay   playing to a HomePod
//   collapsed the bar beside the notch
//   shelf       the panel with things in the clipboard
//   shelf-only  the panel with nothing playing: just the clipboard
//   shelf-bar   the bar with nothing playing and the clipboard in use
//   drop        the open area that appears while something's dragged in
//   cuy         every frame of the cuy's three moods, big
//   cuy-bar     the bar beside the notch, with the cuy's bubble
//   viz-cover the visualizer's album cover style (COVER=path picks a cover)
//   viz-bars  the visualizer's moving bars style

@MainActor
func write<V: View>(_ view: V, to path: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2

    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("could not render"); exit(1)
    }

    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)  (\(Int(image.size.width)) x \(Int(image.size.height)) points)")
    } catch {
        print("could not write: \(error)"); exit(1)
    }
}

@MainActor
func renderPreview(to path: String, mode: String) {
    // An accessory app with no windows: nothing appears, nothing takes focus.
    NSApplication.shared.setActivationPolicy(.accessory)
    // The bars are normally drawn as layers, which this renderer can't see.
    Waveform.drawForSnapshot = true
    isRenderingPreview = true
    CuyView.drawForSnapshot = true
    // Set either way: the preview keeps its own saved settings between runs.
    Settings.shared.cuyEnabled = mode == "cuy-bar"

    if mode == "cuy" {
        // Every frame of each mood, big, on black: standby, running, asleep.
        let rows = [CuyArt.standby, CuyArt.running, CuyArt.sleeping]
        let cell = CGSize(width: CuyArt.size.width * 4, height: CuyArt.size.height * 4)
        let columns = rows.map(\.count).max() ?? 1
        let canvas = NSImage(size: NSSize(width: cell.width * CGFloat(min(columns, 10)),
                                          height: cell.height * CGFloat(rows.reduce(0) { $0 + ($1.count + 9) / 10 })),
                             flipped: true) { rect in
            NSColor.black.setFill(); rect.fill()
            var y: CGFloat = 0
            for frames in rows {
                for (i, frame) in frames.enumerated() {
                    let x = CGFloat(i % 10) * cell.width
                    let row = CGFloat(i / 10) * cell.height
                    NSImage(cgImage: frame, size: cell).draw(in: NSRect(x: x, y: y + row, width: cell.width, height: cell.height))
                }
                y += cell.height * CGFloat((frames.count + 9) / 10)
            }
            return true
        }
        guard let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
        return
    }

    if mode == "study" || mode == "study-start" {
        // The right-hand end of the strip, with a timer running, the battery
        // under the threshold, and a hold under way.
        guard let screen = NSScreen.screens.first else { exit(1) }
        let study = StudyController()
        study.endsAt = Date().addingTimeInterval(25 * 60 - 3)
        study.battery = .init(percent: 14, charging: false)
        study.holdProgress = 0.45
        study.stripOpen = mode != "study-start"
        let notch = NotchGeometry.current()?.notch ?? NSRect(x: screen.frame.midX - 92, y: 0, width: 185, height: 34)
        write(StudyStripView(study: study, notch: notch, screen: screen.frame), to: path)
        return
    }

    if mode == "permissions" {
        write(PermissionsView(fixed: (music: .granted, spotify: .notAsked, audioAsked: true))
                .background(Color(white: 0.93)), to: path)
        return
    }
    if mode == "permissions-new" {
        write(PermissionsView(fixed: (music: .notAsked, spotify: .notInstalled, audioAsked: false))
                .background(Color(white: 0.93)), to: path)
        return
    }

    if mode == "settings" {
        // A neutral backdrop, since the pane is drawn without its window.
        write(SettingsView(settings: .shared).background(Color(white: 0.93)), to: path)
        return
    }

    guard let geometry = NotchGeometry.current() else {
        print("no screen to measure"); exit(1)
    }

    let model = NowPlayingModel()
    model.track = Track(title: "Rhinestone Eyes",
                        artist: "Gorillaz",
                        album: "Plastic Beach",
                        isPlaying: true,
                        source: "Music",   // so the AirPlay button draws as it would for Music
                        position: 74,
                        duration: 199,
                        volume: 62,
                        trackID: "",
                        artwork: NSImage(contentsOfFile: "Resources/AppIcon-preview.png"))
    model.track?.repeatMode = mode == "repeat1" ? "one" : "all"
    if let cover = model.track?.artwork { model.accent = ArtworkTint.color(for: cover) }
    if mode == "airplay" { model.airPlayRoute = "HomePod" }
    if mode == "viz-cover" || mode == "viz-bars" {
        // A cover with some colour in it, if one is given, to show the
        // background picking it up.
        if let path = ProcessInfo.processInfo.environment["COVER"], let image = NSImage(contentsOfFile: path) {
            model.track?.artwork = image
            model.accent = ArtworkTint.color(for: image)
        }
        if let cover = model.track?.artwork { model.backdrop = ArtworkTint.backdrop(for: cover) }
        let state = VisualizerState()
        state.style = mode == "viz-cover" ? .cover : .bars
        write(VisualizerView(model: model, state: state).frame(width: 960, height: 600), to: path)
        return
    }
    // The clipboard, with one of each kind of thing in it.
    if mode.hasPrefix("shelf") {
        let cover = NSImage(contentsOfFile: "Resources/AppIcon-preview.png") ?? NSImage()
        model.shelf = [
            .file(URL(fileURLWithPath: "/System/Applications/Music.app")),
            .file(URL(fileURLWithPath: "README.md")),
            ShelfItem(kind: .image(URL(fileURLWithPath: "/tmp/x.png")), name: "Image", icon: cover),
            .link(URL(string: "https://www.apple.com/music/")!),
            .text("Shopping list\nmilk"),
        ]
        if mode == "shelf-only" || mode == "shelf-bar" { model.track = nil }
    }
    if mode == "drop" { model.isDropTarget = true }

    if mode == "collapsed" || mode == "shelf-bar" || mode == "drop" || mode == "cuy-bar" {
        model.isOnScreen = true
        write(NotchView(model: model, geometry: geometry, control: PlayerControl()), to: path)
        return
    }
    model.isExpanded = true
    if mode == "hold" { model.holdProgress = 0.6 }

    write(NotchView(model: model, geometry: geometry, control: PlayerControl()), to: path)
}

// Top-level code already runs on the main thread; this tells the compiler so.
MainActor.assumeIsolated {
    let args = CommandLine.arguments
    renderPreview(to: args.count > 1 ? args[1] : "panel-preview.png",
                  mode: args.count > 2 ? args[2] : "")
}
