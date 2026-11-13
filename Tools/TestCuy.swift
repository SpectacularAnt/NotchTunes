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

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
