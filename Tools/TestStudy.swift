import AppKit

// Tests for Study Mode: the battery reading, and keeping the Dock away (the
// commands it would run, without running them). Run with Tools/test-study.sh.

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "pass  " : "FAIL  ") + name + (detail.isEmpty ? "" : "   " + detail))
    if !ok { failures += 1 }
}

let battery = StudyController.readBattery()
check("reads the battery", battery != nil)
if let battery {
    check("as a percentage", (0...100).contains(battery.percent), "\(battery.percent)%, charging: \(battery.charging)")
}

// Keeping the Dock away — the commands only; nothing is run here.
let away = DockSuppressor.commandsToKeepAway()
check("turns hiding on with a very long wait, then restarts the Dock",
      away.contains(["/usr/bin/defaults", "write", "com.apple.dock", "autohide", "-bool", "true"])
      && away.contains { $0.contains("autohide-delay") && $0.contains("1000") }
      && away.last == ["/usr/bin/killall", "Dock"])

let usual = DockSuppressor.Original(autohide: true, delay: nil)
let back = DockSuppressor.commandsToRestore(usual)
check("puts back a Dock that was already hiding", back.contains(["/usr/bin/defaults", "write", "com.apple.dock", "autohide", "-bool", "true"]))
check("removes the wait again if there wasn't one before",
      back.contains(["/usr/bin/defaults", "delete", "com.apple.dock", "autohide-delay"]))
check("and restarts the Dock to apply it", back.last == ["/usr/bin/killall", "Dock"])

let shown = DockSuppressor.commandsToRestore(.init(autohide: false, delay: 0.5))
check("puts back an always-shown Dock", shown.contains(["/usr/bin/defaults", "write", "com.apple.dock", "autohide", "-bool", "false"]))
check("with its own wait", shown.contains(["/usr/bin/defaults", "write", "com.apple.dock", "autohide-delay", "-float", "0.5"]))

let never = DockSuppressor.commandsToRestore(.init(autohide: nil, delay: nil))
check("a setting that was never there is removed, not invented",
      never.contains(["/usr/bin/defaults", "delete", "com.apple.dock", "autohide"]))

for original in [usual, .init(autohide: false, delay: 0.5), .init(autohide: nil, delay: nil)] {
    check("saves and reads back \(original)", DockSuppressor.decode(DockSuppressor.encode(original)) == original)
}

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
