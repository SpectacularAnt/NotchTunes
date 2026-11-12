import AppKit
import SwiftUI

/// The two ways the visualizer can look.
enum VisualizerStyle: String {
    /// The album cover, large, on a background in the cover's own colours.
    case cover
    /// The notch's moving bars, filling the window.
    case bars

    var menuTitle: String {
        switch self {
        case .cover: return "Album Cover"
        case .bars: return "Moving Bars"
        }
    }
}

/// What the visualizer window is showing. Its own small object so switching
/// style redraws the window in place rather than rebuilding it.
final class VisualizerState: ObservableObject {
    @Published var style: VisualizerStyle = .cover
}

/// A big window for the visualizer, opened from the menu bar item.
///
/// It reads from the same model as the notch, so it needs no music reading of
/// its own: whatever the notch knows, this shows.
final class VisualizerWindowController: NSObject, NSWindowDelegate {

    private let model: NowPlayingModel
    private let state = VisualizerState()
    private var window: NSWindow?

    init(model: NowPlayingModel) {
        self.model = model
    }

    var currentStyle: VisualizerStyle? { window?.isVisible == true ? state.style : nil }

    func show(_ style: VisualizerStyle) {
        // The style changes with an animation if the window is already open,
        // so switching is a fade rather than a jump.
        withAnimation(.easeInOut(duration: 0.6)) { state.style = style }

        if window == nil {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            // Most of the screen, but not quite all of it: full screen is one
            // click (or F) away, and a window you can see round is less of an
            // ambush.
            let size = NSSize(width: (screen.width * 0.8).rounded(), height: (screen.height * 0.8).rounded())
            let window = VisualizerWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false)
            window.title = "NotchTunes Visualizer"
            // The colours run right up under the title bar, with the traffic
            // lights floating on top, as Music's own full-screen player does.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .black
            window.minSize = NSSize(width: 480, height: 360)
            window.collectionBehavior = [.fullScreenPrimary]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: VisualizerView(model: model, state: state))
            window.center()
            self.window = window
        }

        // An app with no Dock icon has to bring itself forward, or the window
        // opens behind whatever you were using.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Dropped rather than kept hidden, so the moving bars aren't drawing
        // sixty times a second into a window nobody can see.
        window?.contentView = nil
        window = nil
    }
}

/// Keys for the window: F for full screen, Escape to leave it — or, when not
/// full screen, to close the window.
private final class VisualizerWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        let isFullScreen = styleMask.contains(.fullScreen)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "f":
            toggleFullScreen(nil)
        case "\u{1b}":     // Escape
            if isFullScreen { toggleFullScreen(nil) } else { performClose(nil) }
        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - The views

/// Not private, so Tools/preview-panel.sh can draw it.
struct VisualizerView: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var state: VisualizerState

    var body: some View {
        ZStack {
            switch state.style {
            case .cover:
                CoverVisualizer(model: model).transition(.opacity)
            case .bars:
                BarsVisualizer(model: model).transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

/// The cover, big and centred, with the song beneath it, on a gradient in
/// the cover's own colours.
///
/// A new song cross-fades: the old cover dissolves into the new one while the
/// background drifts from one song's colours to the next. Each song is its own
/// view, identified by the song, which is what lets SwiftUI fade one out as the
/// other comes in.
private struct CoverVisualizer: View {
    @ObservedObject var model: NowPlayingModel

    /// Slow enough to feel like a dissolve rather than a cut.
    private static let change = Animation.easeInOut(duration: 1.1)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width * 0.5, geo.size.height * 0.58)
            let identity = model.track?.identity ?? "none"

            ZStack {
                // A fresh layer for each set of colours, faded over the old
                // one. Gradients don't reliably animate their colours on
                // their own; a cross-fade between two always does.
                ZStack {
                    DriftingColors(colors: model.backdrop)
                        .id(model.backdrop.description)
                        .transition(.opacity)
                }
                .animation(Self.change, value: model.backdrop)

                VStack(spacing: side * 0.09) {
                    ZStack {
                        cover(side: side)
                            .id(identity)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity))
                    }
                    .frame(width: side, height: side)

                    ZStack {
                        caption(side: side)
                            .id(identity)
                            .transition(.opacity)
                    }
                }
                .animation(Self.change, value: identity)
            }
        }
    }

    private func cover(side: CGFloat) -> some View {
        ZStack {
            if let image = model.track?.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.12)
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.3))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.045, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: side * 0.06, y: side * 0.03)
        // Shrinks a touch while paused, as the iPhone's cover does.
        .scaleEffect((model.track?.isPlaying ?? false) ? 1 : 0.9)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: model.track?.isPlaying)
    }

    private func caption(side: CGFloat) -> some View {
        let size = max(15, side * 0.065)
        return VStack(spacing: size * 0.25) {
            Text(model.track?.title ?? "Nothing playing")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
            Text(model.track?.artist ?? "")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.white.opacity(0.65))
        }
        .lineLimit(1)
        .frame(maxWidth: side * 1.4)
    }
}

/// The cover's colours, moving: the gradient underneath, with large, very
/// blurred clouds of the same colours drifting slowly across it — the way
/// Music's own full-screen player moves behind the cover.
///
/// Each cloud follows its own slow loop, two waves of different lengths
/// sideways and up and down, so the pattern takes minutes to come round again
/// and never looks like it's on rails. Slow on purpose: something to notice
/// out of the corner of your eye, not something to watch.
///
/// Not private, so the preview tool can draw it.
struct DriftingColors: View {
    let colors: [Color]

    /// One cloud: which colour, how big (as a share of the window), and how
    /// fast it travels each way, in loops per minute.
    private struct Cloud {
        let colour: Int
        let size: CGFloat
        let speedX: Double, speedY: Double
        let phaseX: Double, phaseY: Double
        let lightness: Double
    }

    private static let clouds: [Cloud] = [
        Cloud(colour: 0, size: 0.95, speedX: 1.3, speedY: 0.9, phaseX: 0.0, phaseY: 1.6, lightness: 0.10),
        Cloud(colour: 1, size: 1.05, speedX: 0.8, speedY: 1.2, phaseX: 2.2, phaseY: 0.3, lightness: 0.0),
        Cloud(colour: 0, size: 0.75, speedX: 1.1, speedY: 1.5, phaseX: 4.1, phaseY: 3.4, lightness: -0.12),
        Cloud(colour: 1, size: 0.70, speedX: 1.6, speedY: 0.7, phaseX: 5.3, phaseY: 2.5, lightness: 0.12),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let span = max(w, h)

            // Twenty redraws a second is plenty for something this slow.
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                let minutes = context.date.timeIntervalSinceReferenceDate / 60

                ZStack {
                    ForEach(Self.clouds.indices, id: \.self) { i in
                        let cloud = Self.clouds[i]
                        let x = 0.5 + 0.38 * sin(2 * .pi * cloud.speedX * minutes + cloud.phaseX)
                        let y = 0.5 + 0.38 * sin(2 * .pi * cloud.speedY * minutes + cloud.phaseY)

                        Circle()
                            .fill(colour(cloud))
                            .frame(width: span * cloud.size, height: span * cloud.size)
                            .position(x: w * x, y: h * y)
                            .opacity(0.75)
                    }
                }
                // Blurred heavily enough that the circles stop being circles
                // and become soft light.
                .blur(radius: span * 0.12)
                // Drawn off-screen as one picture by the graphics card, which
                // is what keeps a blur this size cheap.
                .drawingGroup()
                // The plain gradient underneath, kept out of the blur: blurring
                // it too would fade its edges into a dark border.
                .background(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            }
        }
        .clipped()
    }

    /// A cloud's colour, nudged lighter or darker so two clouds of the same
    /// colour still read as separate shapes.
    private func colour(_ cloud: Cloud) -> Color {
        let base = colors[min(cloud.colour, colors.count - 1)]
        let ns = NSColor(base).usingColorSpace(.deviceRGB) ?? .gray
        let brightness = min(1, max(0, ns.brightnessComponent + CGFloat(cloud.lightness)))
        return Color(nsColor: NSColor(deviceHue: ns.hueComponent, saturation: ns.saturationComponent,
                                      brightness: brightness, alpha: 1))
    }
}

/// The moving bars, filling the window, on black with a soft glow of the
/// cover's colour behind them. The colour drifts to the next song's.
private struct BarsVisualizer: View {
    @ObservedObject var model: NowPlayingModel

    var body: some View {
        GeometryReader { geo in
            let height = min(geo.size.height * 0.45, geo.size.width * 0.38)
            let identity = model.track?.identity ?? "none"

            ZStack {
                Color.black
                // Cross-faded for the same reason as the cover's background.
                ZStack {
                    RadialGradient(colors: [model.accent.opacity(0.22), .clear],
                                   center: .center, startRadius: 0, endRadius: height * 1.6)
                        .id(model.accent.description)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 1.1), value: model.accent)

                VStack(spacing: height * 0.22) {
                    // Cross-faded on a colour change: the bars are painted
                    // directly, so their colour can't animate by itself.
                    ZStack {
                        Waveform(isPlaying: model.track?.isPlaying ?? false,
                                 color: model.accent,
                                 height: height,
                                 framesPerSecond: 60)
                            .id(model.accent.description)
                            .transition(.opacity)
                    }
                    .animation(.easeInOut(duration: 1.1), value: model.accent)

                    ZStack {
                        caption(size: max(14, height * 0.085))
                            .id(identity)
                            .transition(.opacity)
                    }
                    .animation(.easeInOut(duration: 1.1), value: identity)
                }
            }
        }
    }

    private func caption(size: CGFloat) -> some View {
        VStack(spacing: size * 0.25) {
            Text(model.track?.title ?? "Nothing playing")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(model.track?.artist ?? "")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.white.opacity(0.5))
        }
        .lineLimit(1)
    }
}
