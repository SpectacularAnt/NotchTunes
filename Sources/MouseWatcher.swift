import AppKit

/// Watches the cursor and reports when it moves into, or back out of, a rectangle.
///
/// We poll rather than use mouse-entered events on purpose. The window ignores
/// mouse events so clicks pass through it, which also means it never receives
/// enter or exit events of its own. Reading `NSEvent.mouseLocation` needs no
/// permission from you and costs almost nothing.
final class MouseWatcher {

    private var timer: Timer?
    private var wasInside = false

    func start(zone: @escaping () -> NSRect,
               onSample: @escaping (NSPoint) -> Void,
               onChange: @escaping (Bool) -> Void) {
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            guard let self else { return }
            let location = NSEvent.mouseLocation

            // Every tick, so things that follow the cursor closely — like which
            // bar it is over — stay current.
            onSample(location)

            // Never change answer mid-drag: dragging a slider can take the cursor
            // outside the zone, and collapsing the panel under your hand would
            // abandon the drag.
            guard NSEvent.pressedMouseButtons == 0 else { return }

            let isInside = zone().contains(location)
            guard isInside != self.wasInside else { return }   // only report changes
            self.wasInside = isInside
            onChange(isInside)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
