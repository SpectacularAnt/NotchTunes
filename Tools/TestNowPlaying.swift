import Foundation

// Tests for SystemNowPlaying.sameSong. Run with Tools/test-nowplaying.sh.

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "pass  " : "FAIL  ") + name)
    if !ok { failures += 1 }
}

let m = SystemNowPlaying.sameSong
check("the same title matches", m("The Night We Met", "The Night We Met"))
check("case doesn't matter", m("the night we met", "The Night We Met"))
check("one with a featured artist added matches",
      m("The Night We Met (feat. Justin Beaulieu)", "The Night We Met"))
check("either way round", m("The Night We Met", "The Night We Met (feat. Justin Beaulieu)"))
check("a live version's suffix matches", m("Stylo - Live", "Stylo"))
check("a different song doesn't", !m("The Night We Met", "Night Changes"))
check("a longer word sharing the start doesn't", !m("Stay", "Stayin' Alive"))
check("very short titles must match exactly", !m("Go", "Go Your Own Way"))
check("an empty title never matches", !m("", "The Night We Met"))

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
