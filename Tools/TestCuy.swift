import Foundation

// Tests for the cuy. Run with Tools/test-cuy.sh.

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "pass  " : "FAIL  ") + name + (detail.isEmpty ? "" : "   " + detail))
    if !ok { failures += 1 }
}

let mood = CuyMood.now
check("afternoon, memory calm: standby", mood(15, 0.5) == .standby)
check("11 PM: asleep", mood(23, 0.5) == .sleeping)
check("3 AM: asleep", mood(3, 0.5) == .sleeping)
check("7 AM: awake", mood(7, 0.5) == .standby)
check("memory three-quarters used: running", { if case .running = mood(15, 0.75) { return true }; return false }())
check("busy memory wakes it at night", { if case .running = mood(2, 0.9) { return true }; return false }())
if case .running(let slow) = mood(15, 0.76), case .running(let fast) = mood(15, 0.94) {
    check("runs faster the fuller memory gets", fast > slow, String(format: "%.2f → %.2f", slow, fast))
    check("and flips its frames faster", CuyMood.running(pace: fast).framesPerSecond > CuyMood.running(pace: slow).framesPerSecond)
}
check("sleeping flips slowest", CuyMood.sleeping.framesPerSecond < CuyMood.standby.framesPerSecond)

let used = CuyWatcher.memoryUsed()
check("reads this Mac's memory use", used > 0.05 && used < 1, String(format: "%.0f%% used", used * 100))

check("every mood has frames to flip through",
      !CuyArt.standby.isEmpty && !CuyArt.running.isEmpty && !CuyArt.sleeping.isEmpty)

// Resting, when nothing's going on.
var rests: [CuyActivity] = []
var current = CuyActivity.sit
for i in 0..<40 {
    let (next, seconds) = CuyRest.next(after: current, roll: Double(i % 10) / 10, length: 0.5)
    check("rest \(i) isn't the same as the one before", next != current)
    check("rest \(i) lasts a sensible while", seconds > 1 && seconds <= 18)
    rests.append(next); current = next
}
check("every resting activity comes up", Set([.sit, .loaf, .groom, .nibble, .yawn] as [CuyActivity])
      .isSubset(of: Set(rests.map { "\($0)" }.compactMap { name in
          [CuyActivity.sit, .loaf, .groom, .nibble, .yawn].first { "\($0)" == name } })))
check("each new activity has frames", [CuyActivity.loaf, .groom, .nibble, .yawn, .walk, .popcorn]
      .allSatisfy { !CuyArt.frames(for: $0).isEmpty })

// The room.
func room() -> CuyRoomBrain { CuyRoomBrain(width: 340, house: 62, bowl: 292, margin: 22) }
var seed: UInt64 = 7
func roll() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }

var brain = room()
var t = 0.0, walked = false, rested = false, ate = false, minX = CGFloat.infinity, maxX = -CGFloat.infinity
for _ in 0..<(15 * 120) {      // two minutes at fifteen steps a second
    t += 1.0 / 15
    brain.step(mood: .standby, now: t, dt: 1.0 / 15, roll: roll)
    minX = min(minX, brain.x); maxX = max(maxX, brain.x)
    if brain.activity == .walk { walked = true }
    if [.sit, .loaf, .groom, .yawn].contains(brain.activity) { rested = true }
    if brain.activity == .nibble { ate = true }
}
check("in two minutes of quiet it wanders, rests and eats", walked && rested && ate)
check("and stays inside the room", minX >= 22 && maxX <= 318, "\(Int(minX))…\(Int(maxX))")
check("it covers a fair bit of the room", maxX - minX > 120)

brain = room(); t = 0
for _ in 0..<(15 * 30) { t += 1.0 / 15; brain.step(mood: .sleeping, now: t, dt: 1.0 / 15, roll: roll) }
check("at night it goes to its house and sleeps", brain.activity == .sleep && abs(brain.x - 62) < 1,
      "at \(Int(brain.x)), \(brain.activity)")

brain = room(); t = 0
var turns = 0, wasRight = brain.facingRight
for _ in 0..<(15 * 10) {
    t += 1.0 / 15
    brain.step(mood: .running(pace: 1), now: t, dt: 1.0 / 15, roll: roll)
    if brain.facingRight != wasRight { turns += 1; wasRight = brain.facingRight }
}
check("with memory busy it does zoomies, lapping the room", brain.activity == .run && turns >= 4, "\(turns) turns in 10s")

brain = room()
brain.poke(now: 100)
check("a click makes it popcorn", brain.activity == .popcorn)
brain.step(mood: .standby, now: 100.2, dt: 0.2, roll: roll)
check("and the jump plays out", brain.activity == .popcorn)

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
