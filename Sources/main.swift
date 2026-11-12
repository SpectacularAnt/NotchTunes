import AppKit

// There is no Xcode project behind this app, so we assemble the application by
// hand instead of letting a storyboard do it. Top-level code like this only runs
// when the file is called main.swift.
let app = NSApplication.shared
let controller = AppController()
app.delegate = controller

// This is what keeps NotchTunes out of the Dock and out of the Cmd-Tab switcher.
// Info.plist sets LSUIElement too, which does the same job before we even launch.
app.setActivationPolicy(.accessory)

app.run()
