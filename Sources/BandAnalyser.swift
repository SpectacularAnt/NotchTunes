import Accelerate

/// Turns a stream of sound into six bar heights.
///
/// Each time some sound arrives, the most recent 2048 samples are split into
/// their frequencies (a Fourier transform, done by Apple's Accelerate library)
/// and gathered into six bands from bass to treble. Each band's loudness
/// becomes one bar.
///
/// Kept apart from the audio plumbing, and free of anything but arithmetic, so
/// Tools/test-bands.sh can feed it made-up tones and check the right bar
/// answers.
final class BandAnalyser {

    /// Where each band starts and stops, in Hz: bass, low mids, mids, upper
    /// mids, presence, treble.
    static let edges: [Float] = [40, 120, 300, 800, 2000, 5000, 12000]
    static var bandCount: Int { edges.count - 1 }

    /// The six bar heights, shaped the way the Dynamic Island's are.
    ///
    /// Apple's bars are a mirrored glyph, tallest in the middle, that pulses
    /// with the music. So:
    ///  - the middle pair follows the bass and low mids, the next pair out the
    ///    mids, the outer pair the treble — each side its own range, so the two
    ///    halves move alike but are never identical;
    ///  - mostly, each bar follows how far its range has just *jumped* — a
    ///    drum hit, a new note — with only a little of its plain loudness
    ///    underneath, so the glyph leaps on hits and sinks between them;
    ///  - the biggest jump anywhere lifts every bar a little, so a kick drum
    ///    moves the whole glyph together;
    ///  - and the result is scaled by the glyph's silhouette.
    ///
    ///  - and a floor beneath all that, from how loud each range is and its
    ///    *flicker* — the small quick rises and falls every range has from
    ///    moment to moment — so a dense passage with nothing jumping out
    ///    still has height and movement. The bar is whichever is higher, the
    ///    beat's response or this floor, so the floor never blunts a hit.
    ///
    /// (Following loudness alone looked frozen: in a full song every range is
    /// loud nearly all the time, so every bar sat at its maximum. Following
    /// jumps alone went flat: in a dense, even passage — a wall of guitars, a
    /// held vocal over pads — nothing jumps, and the glyph dropped to dots
    /// mid-song. And bass on the left with treble on the right showed pitch
    /// well, but didn't look like Apple's.)
    ///
    /// `liveliness` scales how much the jumps move the bars: 1 normally, less
    /// toward the calm end of the bounce slider.
    static func islandBars(levels: [Float], jumps: [Float], flicker: [Float]? = nil,
                           liveliness: Float = 1) -> [Float] {
        guard levels.count == bandCount, jumps.count == bandCount else { return levels }
        let flicker = flicker ?? [Float](repeating: 0, count: bandCount)
        let beat = jumps.max() ?? 0
        return (0..<bandCount).map { bar in
            let range = islandSource[bar]
            // Whichever is higher: the beat's response — exactly as it was
            // before flicker existed, so hits and the bounce slider behave
            // the same — or the quiet-passage floor of loudness and flicker,
            // which only shows when nothing is jumping.
            let hits = 0.2 * levels[range] + liveliness * (0.55 * jumps[range] + 0.35 * beat)
            let floor = 0.3 * levels[range] + liveliness * 0.4 * flicker[range]
            let height = max(hits, floor)
            return islandShape[bar] * min(1, height)
        }
    }

    /// The bars as they should be drawn now.
    var islandBars: [Float] {
        Self.islandBars(levels: levels, jumps: jumps, flicker: flicker, liveliness: liveliness)
    }

    /// Toward Calm, the beats move the bars less overall as well as needing
    /// to be bigger — 60% at the very calm end, full from the middle up.
    var liveliness: Float {
        let b = max(0, min(1, bounce))
        return b < 0.5 ? 0.6 + 0.8 * b : 1
    }

    /// Which range each bar follows, left to right.
    static let islandSource = [4, 2, 0, 1, 3, 5]

    /// How tall each bar can get, left to right: tallest in the middle, and a
    /// touch lopsided, as the island's glyph is.
    static let islandShape: [Float] = [0.5, 0.78, 1.0, 0.94, 0.8, 0.56]

    private let size = 2048
    private let log2n = vDSP_Length(11)
    private let setup: FFTSetup
    private var window: [Float]
    private var recent: [Float] = []

    /// The loudest any band has been lately, in decibels. Every bar is
    /// measured against this one shared figure, so the bars keep their balance
    /// — a bass note fills the bass bar and leaves the treble empty — while
    /// quiet passages and loud ones both use the full height.
    ///
    /// (Measuring each band against its own best was tried first. It made every
    /// bar full, because even the faint spill-over from a single note becomes
    /// "loud" for a band that's otherwise silent.)
    private var loudest: Float = -50

    /// How much each band is lifted before comparing. Music has far more energy
    /// in the bass than the treble — about 4 dB less for every octave up — so
    /// without this the bass would fill its bar and the cymbals would never
    /// show. The figure is that 4 dB per octave, counted from the middle of
    /// the bass band.
    private static let lift: [Float] = (0..<bandCount).map { band in
        let middle = (edges[band] * edges[band + 1]).squareRoot()
        let bass = (edges[0] * edges[1]).squareRoot()
        return 4 * log2(middle / bass)
    }

    /// The bar heights as last worked out, 0...1, by band.
    private(set) var levels: [Float]

    /// How far each band has just jumped above its own recent level, 0...1:
    /// near 1 on a hit, sinking back to 0 while the sound holds steady.
    private(set) var jumps: [Float]

    /// How much each band is wavering from moment to moment, 0...1: its
    /// level against its own last tenth of a second or so, either way.
    private(set) var flicker: [Float]

    /// Each band's level over roughly the last tenth of a second.
    private var recentLevel: [Float]

    /// Wavering by this many decibels counts as full flicker. Small on
    /// purpose: it's the fine texture, not the hits.
    static let fullFlicker: Float = 4

    /// Each band's level over the last second or so, in the same lifted
    /// decibels — what a jump is measured against.
    private var usual: [Float]
    private var heardAnything = false

    /// How bouncy the bars are, 0 (calm) to 1 (very bouncy) — the slider in
    /// Settings. 0.5 is the middle, and what the bars were tuned at.
    var bounce: Float = 0.5

    /// How many decibels above usual counts as a full jump. A drum hit is
    /// typically 6–12 dB above the music around it, so Calm needs 18 dB —
    /// hardly anything reaches the top — and Bouncy needs 4, so even a modest
    /// beat does. The middle stays at 9, where the bars were tuned.
    var fullJump: Float {
        let b = max(0, min(1, bounce))
        return b < 0.5 ? 18 - 18 * b : 9 - 10 * (b - 0.5)
    }

    /// How quickly a jump falls away, in seconds. Calm drifts down; Bouncy
    /// snaps back, ready for the next hit.
    var fallTime: Float {
        let b = max(0, min(1, bounce))
        return b < 0.5 ? 0.2 - 0.2 * b : 0.1 - 0.08 * (b - 0.5)
    }

    init() {
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        levels = [Float](repeating: 0, count: BandAnalyser.bandCount)
        jumps = [Float](repeating: 0, count: BandAnalyser.bandCount)
        flicker = [Float](repeating: 0, count: BandAnalyser.bandCount)
        recentLevel = [Float](repeating: -60, count: BandAnalyser.bandCount)
        usual = [Float](repeating: -50, count: BandAnalyser.bandCount)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Adds some mono samples and updates `levels`.
    func add(_ samples: [Float], sampleRate: Float) {
        recent.append(contentsOf: samples)
        if recent.count > size { recent.removeFirst(recent.count - size) }
        guard recent.count == size, sampleRate > 0 else { return }

        let power = spectrum()
        let binWidth = sampleRate / Float(size)

        // Each band's average power, in decibels, lifted for its place.
        var lifted = [Float](repeating: -120, count: BandAnalyser.bandCount)
        for band in 0..<BandAnalyser.bandCount {
            // Each frequency slot belongs to exactly one band.
            let low = max(1, Int((BandAnalyser.edges[band] / binWidth).rounded(.up)))
            let high = min(power.count - 1, Int((BandAnalyser.edges[band + 1] / binWidth).rounded(.up)) - 1)
            guard high >= low else { continue }
            var total: Float = 0
            for bin in low...high { total += power[bin] }
            lifted[band] = 10 * log10(total / Float(high - low + 1) + 1e-12) + BandAnalyser.lift[band]
        }

        // The loudest jumps up straight away and sinks back slowly, and never
        // below a floor — or silence would be scaled up until the noise in it
        // filled the bars.
        loudest = max(lifted.max() ?? -120, loudest - 0.04, -50)

        for band in 0..<BandAnalyser.bandCount {
            // Within 24 dB of the loudest counts; anything quieter is empty.
            // A narrow window on purpose: with a wider one, every band of a
            // full mix sits near the top and the bars all look alike. Squaring
            // then lets the loudest band stand clear of the next few.
            let closeness = max(0, min(1, 1 - (loudest - lifted[band]) / 24))
            let target = closeness * closeness

            // Rises quickly, falls gently, as a level meter does.
            let speed: Float = target > levels[band] ? 0.6 : 0.14
            levels[band] += (target - levels[band]) * speed
        }

        // Jumps: each band against its own last second or so. Measured by
        // time rather than per update, since updates don't come at a fixed
        // rate.
        let seconds = Float(samples.count) / sampleRate
        if !heardAnything {
            // Start from what's playing, not from silence — or everything
            // would look like a jump for the first few seconds.
            usual = lifted.map { max($0, -60) }
            heardAnything = true
        }
        for band in 0..<BandAnalyser.bandCount {
            let above = lifted[band] - usual[band]
            // The usual level catches up with a range getting louder in about
            // a third of a second — so a steady sound stops counting as a jump
            // — and lets go of a quieter one over a second and a half, so the
            // gap after a hit doesn't make the next hit look small.
            let now = max(lifted[band], -60)
            let settle = 1 - exp(-seconds / (now > usual[band] ? 0.35 : 1.5))
            usual[band] += (now - usual[band]) * settle

            let target = max(0, min(1, above / fullJump))
            // Leaps up at once; falls quickly enough to be clear of the next
            // beat, about a tenth of a second.
            let speed: Float = target > jumps[band] ? 0.8 : 1 - exp(-seconds / fallTime)
            jumps[band] += (target - jumps[band]) * speed

            // Flicker: how far this band is from where it was a moment ago,
            // up or down. Only while there's sound to speak of — silence's
            // own noise shouldn't twitch the bars.
            let wobble = abs(now - recentLevel[band])
            recentLevel[band] += (now - recentLevel[band]) * (1 - exp(-seconds / 0.12))
            let audible = levels[band] > 0.05
            let flick = audible ? max(0, min(1, wobble / BandAnalyser.fullFlicker)) : 0
            let flickSpeed: Float = flick > flicker[band] ? 0.5 : 1 - exp(-seconds / 0.12)
            flicker[band] += (flick - flicker[band]) * flickSpeed
        }
    }

    /// The power at each frequency in the most recent samples.
    private func spectrum() -> [Float] {
        let half = size / 2
        var windowed = [Float](repeating: 0, count: size)
        vDSP_vmul(recent, 1, window, 1, &windowed, 1, vDSP_Length(size))

        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!,
                                            imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { samples in
                    samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        return power
    }
}
