import Foundation

// Tests for BandAnalyser. Run with Tools/test-bands.sh.

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "pass  " : "FAIL  ") + name + (detail.isEmpty ? "" : "   " + detail))
    if !ok { failures += 1 }
}

let rate: Float = 48_000

/// Feeds `seconds` of sound in 512-sample pieces, the size Core Audio usually
/// hands over, and returns the analyser's levels at the end.
func levels(seconds: Float, _ sample: (Float) -> Float) -> [Float] {
    let analyser = BandAnalyser()
    var t: Float = 0
    let step = 1 / rate
    for _ in 0..<Int(seconds * rate / 512) {
        var piece = [Float](repeating: 0, count: 512)
        for i in 0..<512 { piece[i] = sample(t); t += step }
        analyser.add(piece, sampleRate: rate)
    }
    return analyser.levels
}

func tone(_ hz: Float, _ amp: Float = 0.5) -> (Float) -> Float {
    { t in amp * sin(2 * .pi * hz * t) }
}
func fmt(_ l: [Float]) -> String { l.map { String(format: "%.2f", $0) }.joined(separator: " ") }

let names = ["bass", "low mids", "mids", "upper mids", "presence", "treble"]
for (band, hz) in [(0, Float(70)), (1, 200), (2, 500), (3, 1300), (4, 3200), (5, 8000)] {
    let l = levels(seconds: 1, tone(hz))
    let loudest = l.indices.max { l[$0] < l[$1] }!
    check("a \(Int(hz)) Hz tone lights the \(names[band]) band", loudest == band && l[band] > 0.8, fmt(l))
}

let silent = levels(seconds: 1) { _ in 0 }
check("silence lights nothing", silent.allSatisfy { $0 < 0.05 }, fmt(silent))

let both = levels(seconds: 1) { t in tone(70)(t) + tone(3200)(t) }
check("bass and presence together light both", both[0] > 0.4 && both[4] > 0.8 && both[2] < 0.1, fmt(both))

// A quiet tone still fills its bar: each band is measured against its own
// recent loudest, so turning Music down doesn't flatten the bars.
let quiet = levels(seconds: 1, tone(200, 0.01))
check("a quiet tone still fills its bar", quiet[1] > 0.8, fmt(quiet))

// Falls back gently after the sound stops, rather than snapping to nothing.
let analyser = BandAnalyser()
var t: Float = 0
for _ in 0..<90 {
    var piece = [Float](repeating: 0, count: 512)
    for i in 0..<512 { piece[i] = tone(70)(t); t += 1 / rate }
    analyser.add(piece, sampleRate: rate)
}
// Six pieces of silence: enough to fill the 2048-sample window with it and
// then some, about 60 ms in all.
for _ in 0..<6 { analyser.add([Float](repeating: 0, count: 512), sampleRate: rate) }
let after = analyser.levels[0]
check("the bar falls gently when the sound stops", after > 0.3 && after < 0.95, String(format: "%.2f", after))

// The island shape
let flat = [Float](repeating: 0, count: 6)
let full = [Float](repeating: 1, count: 6)
let islandSilent = BandAnalyser.islandBars(levels: flat, jumps: flat)
check("silence: a flat glyph", islandSilent.allSatisfy { $0 == 0 }, fmt(islandSilent))

let steadyLoud = BandAnalyser.islandBars(levels: full, jumps: flat)
check("loud but steady: only a low base", steadyLoud.allSatisfy { $0 <= 0.2 }, fmt(steadyLoud))

let hit = BandAnalyser.islandBars(levels: full, jumps: full)
check("a hit everywhere: tallest in the middle",
      hit[2] == hit.max()! && hit[0] < hit[1] && hit[5] < hit[4], fmt(hit))
check("and roughly mirrored", abs(hit[0] - hit[5]) < 0.1 && abs(hit[1] - hit[4]) < 0.1, fmt(hit))

let kick = BandAnalyser.islandBars(levels: [1, 0.5, 0.3, 0.2, 0.1, 0.1], jumps: [1, 0, 0, 0, 0, 0])
check("a kick drum lifts the middle most", kick[2] == kick.max()!, fmt(kick))
check("and the whole glyph a little with it", kick.allSatisfy { $0 > 0.15 }, fmt(kick))

let cymbal = BandAnalyser.islandBars(levels: [0.3, 0.3, 0.3, 0.3, 0.5, 1], jumps: [0, 0, 0, 0, 0.3, 1])
check("a cymbal shows at the edges", cymbal[5] > cymbal[2], fmt(cymbal))

check("each range drives exactly one bar", Set(BandAnalyser.islandSource) == Set(0..<BandAnalyser.bandCount))
check("bass in the middle, treble at the edges",
      [2, 3].contains(BandAnalyser.islandSource.firstIndex(of: 0)!)
      && [0, 5].contains(BandAnalyser.islandSource.firstIndex(of: 5)!))

// Reacting over time: what you actually see.
func run(seconds: Float, bounce: Float = 0.5, _ sample: (Float) -> Float, watch: (Float, [Float]) -> Void) {
    let analyser = BandAnalyser()
    analyser.bounce = bounce
    var t: Float = 0
    for _ in 0..<Int(seconds * rate / 512) {
        var piece = [Float](repeating: 0, count: 512)
        for i in 0..<512 { piece[i] = sample(t); t += 1 / rate }
        analyser.add(piece, sampleRate: rate)
        watch(t, analyser.islandBars)
    }
}

// A steady tone for three seconds: the bars should settle down, not stay up.
var settled: [Float] = []
run(seconds: 3, tone(70)) { t, bars in if t > 2.9 && settled.isEmpty { settled = bars } }
check("a steady sound lets the bars settle low", settled[2] < 0.35, fmt(settled))

// A drum: a quiet hum with a loud bass thump twice a second.
func drum(_ t: Float) -> Float {
    let sinceHit = t.truncatingRemainder(dividingBy: 0.5)
    let thump: Float = sinceHit < 0.08 ? 0.9 * (1 - sinceHit / 0.08) : 0
    return 0.05 * sin(2 * .pi * 200 * t) + thump * sin(2 * .pi * 70 * t)
}
var highest: Float = 0, lowest: Float = 1
var fellBack = false
run(seconds: 3, drum) { t, bars in
    guard t > 1 else { return }               // after the first second's settling in
    highest = max(highest, bars[2]); lowest = min(lowest, bars[2])
    let sinceHit = t.truncatingRemainder(dividingBy: 0.5)
    if sinceHit > 0.3 && sinceHit < 0.35 && bars[2] < 0.3 { fellBack = true }
}
check("on a beat the middle bars leap", highest > 0.7, String(format: "%.2f", highest))
check("and between beats they sink", lowest < 0.25, String(format: "%.2f", lowest))
check("well before the next beat", fellBack)

// The bounce slider: a modest beat — a bass note swelling to twice as loud,
// twice a second — on Calm, the middle, and Bouncy.
func swell(_ t: Float) -> Float {
    let loud = t.truncatingRemainder(dividingBy: 0.5) < 0.08
    return (loud ? 0.6 : 0.3) * sin(2 * .pi * 70 * t)
}
func peak(bounce: Float) -> Float {
    var top: Float = 0
    run(seconds: 3, bounce: bounce, swell) { t, bars in if t > 1 { top = max(top, bars[2]) } }
    return top
}
let calm = peak(bounce: 0), middle = peak(bounce: 0.5), bouncy = peak(bounce: 1)
check("Calm leaps least, Bouncy most", calm < middle && middle < bouncy,
      String(format: "calm %.2f, middle %.2f, bouncy %.2f", calm, middle, bouncy))
check("Bouncy takes a modest beat to the top", bouncy > 0.85, String(format: "%.2f", bouncy))
check("Calm keeps it well short of the top", calm < 0.7, String(format: "%.2f", calm))

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
