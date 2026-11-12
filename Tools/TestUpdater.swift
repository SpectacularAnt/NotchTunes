import Foundation

// Tests for Updater.isNewer. Run with Tools/test-updater.sh.

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "pass  " : "FAIL  ") + name)
    if !ok { failures += 1 }
}

check("1.2 is newer than 1.1", Updater.isNewer("1.2", than: "1.1"))
check("1.1 is not newer than 1.1", !Updater.isNewer("1.1", than: "1.1"))
check("1.0 is not newer than 1.1", !Updater.isNewer("1.0", than: "1.1"))
check("1.10 is newer than 1.9 (numbers, not text)", Updater.isNewer("1.10", than: "1.9"))
check("2.0 is newer than 1.99", Updater.isNewer("2.0", than: "1.99"))
check("1.1.1 is newer than 1.1", Updater.isNewer("1.1.1", than: "1.1"))
check("1.1.0 is the same as 1.1", !Updater.isNewer("1.1.0", than: "1.1"))

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
