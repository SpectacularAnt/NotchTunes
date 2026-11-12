import AppKit

// Tests for the clipboard. Run with Tools/test-shelf.sh.

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "pass  " : "FAIL  ") + name + (detail.isEmpty ? "" : "   " + detail))
    if !ok { failures += 1 }
}

// Pictures go in a scratch folder, never the app's real one.
Shelf.folder = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Clipboard")

/// Runs a drop through the loader and waits for the answer.
func drop(_ providers: [NSItemProvider]) -> [ShelfItem] {
    var result: [ShelfItem]?
    Shelf.load(providers) { result = $0 }
    let deadline = Date().addingTimeInterval(5)
    while result == nil && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return result ?? []
}

func kind(_ item: ShelfItem?) -> String {
    switch item?.kind {
    case .file: return "file"
    case .image: return "image"
    case .link: return "link"
    case .text: return "text"
    case nil: return "nothing"
    }
}

// A real file on disk, as Finder would drag it.
let file = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Notes.txt")
try! "hello".write(to: file, atomically: true, encoding: .utf8)

let fromFinder = drop([NSItemProvider(contentsOf: file)!])
check("a dragged file is kept as a file", kind(fromFinder.first) == "file", kind(fromFinder.first))
check("it's named after the file", fromFinder.first?.name == "Notes.txt", fromFinder.first?.name ?? "")
check("and has the file's icon", fromFinder.first?.icon != nil)

let link = drop([NSItemProvider(object: URL(string: "https://www.apple.com/music/")! as NSURL)])
check("a web address is kept as a link", kind(link.first) == "link", kind(link.first))
check("named after its site", link.first?.name == "www.apple.com", link.first?.name ?? "")

let text = drop([NSItemProvider(object: "Shopping list\nmilk\neggs" as NSString)])
check("dragged text is kept as text", kind(text.first) == "text", kind(text.first))
check("named after its first line", text.first?.name == "Shopping list", text.first?.name ?? "")

let picture = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
    NSColor.orange.setFill(); rect.fill(); return true
}
let image = drop([NSItemProvider(object: picture)])
check("a picture is kept as a picture", kind(image.first) == "image", kind(image.first))
if case .image(let saved)? = image.first?.kind {
    check("saved as a PNG it can be dragged out as", FileManager.default.fileExists(atPath: saved.path)
          && saved.pathExtension == "png", saved.lastPathComponent)
}

let several = drop([NSItemProvider(contentsOf: file)!, NSItemProvider(object: "two" as NSString)])
check("dropping several things keeps each", several.count == 2, "\(several.count)")
check("in the order they came", kind(several.first) == "file" && kind(several.last) == "text")

// Merging
var shelf = Shelf.merge(fromFinder, into: [])
shelf = Shelf.merge(text, into: shelf)
check("newest goes first", kind(shelf.first) == "text")
let again = drop([NSItemProvider(contentsOf: file)!])
shelf = Shelf.merge(again, into: shelf)
check("the same file twice is only kept once", shelf.count == 2, "\(shelf.count)")
shelf = Shelf.merge(drop([NSItemProvider(object: "Shopping list\nmilk\neggs" as NSString)]), into: shelf)
check("but the same text twice is two things", shelf.count == 3, "\(shelf.count)")

// Dragging back out
let out = shelf.last!.dragProvider()
check("a kept file can be dragged out as a file",
      out.hasItemConformingToTypeIdentifier("public.file-url"), out.registeredTypeIdentifiers.joined(separator: ","))

// Clearing
Shelf.removeSavedImages()
check("clearing deletes the saved pictures", !FileManager.default.fileExists(atPath: Shelf.folder.path))
check("but never a file that was dropped from elsewhere", FileManager.default.fileExists(atPath: file.path))

print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
exit(failures == 0 ? 0 : 1)
