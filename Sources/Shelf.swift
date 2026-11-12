import AppKit
import UniformTypeIdentifiers

/// One thing kept in the notch's clipboard: whatever was dropped on it.
///
/// This is NotchTunes' own shelf, not the Mac's copy-and-paste clipboard —
/// dropping something here doesn't change what ⌘V pastes, and clearing it
/// doesn't either.
struct ShelfItem: Identifiable, Equatable {

    enum Kind {
        /// A file or folder, kept as a reference to where it already is.
        case file(URL)
        /// A picture dragged from somewhere that isn't a file — a web page,
        /// say. Saved as a PNG in NotchTunes' own cache folder, so it can be
        /// dragged back out as a file.
        case image(URL)
        /// A web address.
        case link(URL)
        /// Some text.
        case text(String)
    }

    let id = UUID()
    let kind: Kind
    /// What the tile says underneath.
    let name: String
    /// A picture for the tile: the file's own icon, or the image itself. Nil
    /// for links and text, which get a symbol instead.
    let icon: NSImage?

    static func == (a: ShelfItem, b: ShelfItem) -> Bool { a.id == b.id }

    var symbol: String {
        switch kind {
        case .link: return "link"
        case .text: return "text.alignleft"
        default: return "doc"
        }
    }

    /// What gets handed over when the tile is dragged back out. It stays in
    /// the clipboard afterwards: dragging out is a copy, not a move.
    func dragProvider() -> NSItemProvider {
        switch kind {
        case .file(let url), .image(let url):
            return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
        case .link(let url):
            return NSItemProvider(object: url as NSURL)
        case .text(let text):
            return NSItemProvider(object: text as NSString)
        }
    }

    // MARK: Making them

    static func file(_ url: URL) -> ShelfItem {
        ShelfItem(kind: .file(url), name: url.lastPathComponent,
                  icon: NSWorkspace.shared.icon(forFile: url.path))
    }

    static func link(_ url: URL) -> ShelfItem {
        ShelfItem(kind: .link(url), name: url.host ?? url.absoluteString, icon: nil)
    }

    static func text(_ text: String) -> ShelfItem {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first ?? ""
        return ShelfItem(kind: .text(text), name: line.isEmpty ? "Text" : line, icon: nil)
    }

    static func image(_ image: NSImage) -> ShelfItem? {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        let url = Shelf.folder.appendingPathComponent("Image \(Shelf.stamp()).png")
        do {
            try FileManager.default.createDirectory(at: Shelf.folder, withIntermediateDirectories: true)
            try png.write(to: url)
        } catch { return nil }
        return ShelfItem(kind: .image(url), name: "Image", icon: image)
    }
}

/// Turning a drop into shelf items, and tidying up after them.
enum Shelf {

    /// Where dropped pictures are saved. Emptied when the clipboard is
    /// cleared, and when NotchTunes starts, since the clipboard doesn't
    /// survive a restart.
    static var folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("local.notchtunes/Clipboard", isDirectory: true)

    /// The kinds of thing the drop area accepts, best first.
    static let acceptedTypes: [UTType] = [.fileURL, .url, .image, .plainText, .text]

    /// Reads everything in a drop, then answers on the main thread. Each
    /// dragged thing becomes one item: a file if it is one, otherwise a
    /// picture, a link, or text, in that order.
    static func load(_ providers: [NSItemProvider], completion: @escaping ([ShelfItem]) -> Void) {
        let group = DispatchGroup()
        var found = [ShelfItem?](repeating: nil, count: providers.count)
        let lock = NSLock()
        func keep(_ item: ShelfItem?, at index: Int) {
            lock.lock(); found[index] = item; lock.unlock()
        }

        for (index, provider) in providers.enumerated() {
            group.enter()
            let isFile = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            if isFile || (!provider.canLoadObject(ofClass: NSImage.self) && provider.canLoadObject(ofClass: URL.self)) {
                // A file, or a plain link.
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        keep(url.isFileURL ? .file(url) : .link(url), at: index)
                    }
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                // A picture — which, dragged off a web page, often comes with
                // the page's link too. The picture is what you'd want kept.
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    if let image = image as? NSImage {
                        // Saving it writes a file, which is fine off the main
                        // thread, where this already is.
                        keep(.image(image), at: index)
                    }
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                    if let text = text as? String, !text.isEmpty {
                        keep(.text(text), at: index)
                    }
                    group.leave()
                }
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) { completion(found.compactMap { $0 }) }
    }

    /// Adds new items to the front, skipping a file that's already there.
    static func merge(_ new: [ShelfItem], into shelf: [ShelfItem]) -> [ShelfItem] {
        func path(_ item: ShelfItem) -> String? {
            if case .file(let url) = item.kind { return url.standardizedFileURL.path }
            return nil
        }
        let existing = Set(shelf.compactMap(path))
        let fresh = new.filter { path($0).map { !existing.contains($0) } ?? true }
        return fresh + shelf
    }

    /// Deletes the pictures NotchTunes saved. Files dropped from elsewhere are
    /// only references, and are never touched.
    static func removeSavedImages() {
        try? FileManager.default.removeItem(at: folder)
    }

    static func stamp() -> String {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        return format.string(from: Date())
    }
}
