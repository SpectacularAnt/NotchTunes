import AppKit

// Tests for Study Mode's readings. Run with Tools/test-study.sh.

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

if let screen = NSScreen.screens.first {
    let dock = StudyController.dockArea(on: screen)
    check("finds the Dock along an edge of the main screen",
          screen.frame.contains(dock.frame) && dock.frame.width > 0 && dock.frame.height > 0,
          "\(dock.frame), hides itself: \(dock.hides)")
    let thickness = min(dock.frame.width, dock.frame.height)
    check("about the Dock's size, not the whole screen", thickness > 20 && thickness < 200, "\(thickness)pt")
}

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
