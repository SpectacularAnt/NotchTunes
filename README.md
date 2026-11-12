# NotchTunes

A music widget that lives on the notch, in three states:

- **A wider notch.** The notch appears to grow: one black bar reaching a square
  out either side, with album artwork on the left and, on the right, the
  Dynamic Island's moving bars — tinted from the cover, settling into dots
  when the music is paused. This is up the whole time a song is loaded in Music, paused included.
- **Expanded.** Move your cursor onto the notch and it springs open into a panel
  laid out like the Dynamic Island's music view: artwork and the song along the
  top with the moving bars at the end, the scrubber with its times either side
  across the middle, and repeat, previous, play/pause, next and AirPlay along
  the bottom — with the volume standing vertically down the right-hand edge. The black runs from the top of the
  screen, so the panel is continuous with the notch rather than a slab hanging
  under it.
- **Out of the way.** Nothing on screen once Music is stopped or closed.

It never appears in the Dock.

This folder holds the source. **The app itself lives in `/Applications`**, where
you'd normally look for it.

## Build it

1. Open Terminal in this folder.
2. Run `./build.sh`.
3. It compiles, signs, and installs `/Applications/NotchTunes.app`, replacing
   whatever was there and quitting the running copy first.

To put it somewhere else: `INSTALL_DIR=~/Applications ./build.sh`.

## Run it

1. Open **NotchTunes** from Applications, Spotlight, or Launchpad.
2. The first time, a **Welcome to NotchTunes** window lists the permissions it
   uses, with an **Allow…** button for each. Each one brings up macOS's own
   prompt; click **OK** / **Allow**.
3. Play something in Music. The notch widens and stays that way.
4. Move your cursor onto the black bar at the top. The panel springs open.

Nothing in the Dock, nothing in Cmd-Tab. The small music-note icon in the menu
bar is how you reach the **Visualizer**, **Permissions…**, **Settings…** and
**Quit NotchTunes**. **Permissions…** brings the welcome window back.

### The permissions

| Permission | What for | Without it |
| --- | --- | --- |
| **Automation → Music** (and **Spotify**, if installed) | Reading the song and working the buttons, by sending Apple Events. | Nothing works — this is the one that's needed. |
| **System Audio Recording Only** | Letting the moving bars hear the music and follow it. | The bars move on their own pattern instead. |

That's all. **Accessibility**, **App Management** and **Media & Apple Music**
are not used — they were only ever needed by features that have since been
removed — so they can be switched off.

macOS can't tell an app whether system-audio recording was allowed, so the
window shows that one as "Asked" until the bars actually hear music.

## Updates

Choose **Check for Updates…** from the music-note menu. NotchTunes asks GitHub
for the latest release and compares its version with its own:

- **Up to date:** it says so.
- **Newer version:** it shows what's new and offers **Install and Relaunch**.
  That downloads the release, checks it really is NotchTunes at that version,
  quits, swaps the new copy into place, and reopens it. Because each build is
  signed ad hoc, macOS may ask for NotchTunes' permissions again afterwards.

Nothing is checked or downloaded unless you choose it. The only thing sent to
GitHub is the request itself, with "NotchTunes" as the program's name.

Checking only works while the repository is **public**: GitHub won't show a
private repository's releases to an app that isn't signed in.

### Publishing a new version

1. Raise `CFBundleShortVersionString` in `Resources/Info.plist` (and
   `CFBundleVersion` by one). Copies only offer a version higher than their own.
2. Commit and push.
3. Run `./Tools/release.sh "What's new"`. It builds a fresh copy in a temporary
   folder — the one you're using keeps running — zips it, and publishes it as a
   GitHub release tagged `v<version>`.

`Tools/test-updater.sh` tests the version comparison (so 1.10 counts as newer
than 1.9).

## Settings

Click the music-note icon in the menu bar and choose **Settings…** (or press ⌘,
while it's open). Changes apply straight away and are remembered.

| Setting | Default | What it does |
| --- | --- | --- |
| Keep it visible while a song is loaded | On | Leaves the bar up the whole time there's a song in Music, paused included. Turn it **off** if you'd rather it only announced new songs and then got out of the way. |
| Show on every desktop | Off | The notch follows you to every desktop, and hides itself while a full-screen app is in front — macOS counts each full-screen app as a desktop of its own, so without that check it would float over full-screen videos. Off, it stays on one desktop and **Move to This Desktop** brings it across. |
| Delay before the panel opens | Instant | How long your cursor has to rest on the notch before the panel opens. Raise it if the panel opens when you're only reaching for the menu bar. Leaving the notch early cancels it, so passing over opens nothing. |
| How long a new song is announced | 3 seconds | Only used when the setting above is **off**: how long the bar appears when a song starts. Set it to **Off** to stop announcing new songs at all. |
| Hold the panel to quit | On | Pressing and holding empty space on the open panel quits the app. See below. |
| How long to hold | 2 seconds | Anywhere from 1 to 5 seconds. |
| Moving bars follow the music | On | The bars listen to the music and move with it. Off, they move on their own pattern. The line beneath says whether it can hear anything right now. See below. |
| How bouncy the bars are | Middle | From **Calm** to **Bouncy**: how big a beat has to be to send the bars to the top, how quickly they drop back, and — toward Calm — how much beats move them at all. The middle is how they were tuned. Only used while the bars follow the music. |
| Keep the Dock away in Study Mode | Off | The Dock won't appear while Study Mode is on. See Study Mode. |
| Show the battery in Study Mode | 20% | The battery appears in the strip once it's at or below this level. All the way right shows it always. |

## The controls

| Control | What it does |
| --- | --- |
| Repeat (bottom left) | Cycles off → repeat all → repeat this song, as Music does. Lit while it's on; shows a small 1 for "this song". Spotify only has on and off. |
| AirPlay (bottom right) | Lists the AirPlay devices Music can play to, with a tick by the one in use; pick one to send the sound there. The glyph becomes the device's own (a HomePod, headphones) while it's playing somewhere other than this Mac. Music only — Spotify can't be told where to play. |
| Scrubber | Drag to move through the track, or click anywhere on it to jump there. It only seeks when you let go. |
| Previous / next | Skips to the previous or next track. |
| Play/pause | Toggles playback. It shows what it's *about* to do: pause while playing. |
| Volume (vertical, right) | Changes the music app's own volume, live as you drag. Click anywhere on it to jump to that level. |

Time elapsed sits under the left of the scrubber and time *remaining* under the
right, the way a phone shows it.

Both bars are drawn by hand rather than being system sliders, and they behave
like Control Center's sound and brightness bars: a thin track that fills from one
end, with a **knob that fades in as the cursor comes near** — a plain fade where
it sits, as macOS's own sliders do, with no growing or sliding in. At rest each
bar is a clean line. A plain click sets a value — there's nothing to catch hold
of.

Control Center's own bars were measured on screen for reference: a **4pt** track
with a **14pt** knob (8 and 28 pixels on a 2x display). These sit a little
heavier at **6pt**. The knob is a **slightly stretched pill, 20 × 14pt**, lying
along the bar — wide on the scrubber, tall on the volume — which is the shape
macOS's sliders use, Music's mini player among them. It's a fixed size rather
than a multiple of the track: about as big as the thing wants to be to read and
to grab, whatever the track beneath it is doing.

Both bars are **20pt to the mouse**, so a thin bar is still easy to grab.

Two details that matter:

- The knob stays up for the whole of a drag, even if the cursor wanders off the
  bar, so it doesn't vanish mid-adjustment.
- The knob rides the fill's *drawn* edge, not the raw fraction. The fill is held
  at a one-thickness minimum so it stays a capsule rather than a sliver; near
  zero those two numbers disagree, and a knob following the fraction drifts
  behind the edge it's meant to mark.

### Why the knob is an overlay

It would be natural to put the knob in the same `ZStack` as the track and fill.
Don't: **a `ZStack` takes the size of its largest child**, so a knob wider than
the track stretches the track out to match it. A 4pt bar drew 14pt thick, and
looked plausible enough that it took measuring pixels to catch. The knob goes in
an `.overlay`, which doesn't affect the size of what it sits on.

### Why hovering is polled

SwiftUI's `.onHover` does nothing here. It relies on a tracking area that only
fires for an *active* window, and this one never is — an accessory app with a
non-activating panel. It fails silently: no hover, no error.

So hovering is worked out from the cursor position the app already polls sixteen
times a second. Each bar reports its own frame through a SwiftUI preference, so
the layout is still only described in one place, and `NotchWindow.updateBarHover`
flips the cursor from screen coordinates into the window's to see which frame it
lands in.

## Start it automatically at login

1. Open System Settings → General → Login Items & Extensions.
2. Under "Open at Login", click **+**.
3. Pick `NotchTunes` from Applications.

## What it does and doesn't cover

It reads **Music.app** and **Spotify** (if you install it). It asks those apps
directly, which is the approach that still works — macOS now blocks the private
framework the system's own Now Playing widget uses.

### Podcasts

Podcasts has no scripting at all — no way in like Music's and Spotify's — so it
comes through **macOS's own Now Playing service** instead, the one Control
Center uses. That service has been closed to outside apps since macOS 15.4, but
it still answers Apple's own programs, and `/usr/bin/perl` is one of them that
will load a library it's handed. So NotchTunes runs perl with a small helper
(`Helper/NowPlayingHelper.m`, loaded by `Helper/NowPlayingHelper.pl`) that
listens to the service and reports every change as a line of JSON. Nothing is
polled: the helper waits, and speaks when something changes.

- Title, show, artwork, play/pause, the scrubber and seeking all work.
- The skip buttons become **back 15 seconds** and **forward 30**, as Apple's
  podcast player has them.
- The volume bar sets the **Mac's** volume, since Podcasts' own can't be reached.
- Repeat and AirPlay are dimmed: Podcasts has neither to offer from outside.
- The moving bars follow the audio like any other app.

**This can break with a macOS update** — it relies on Apple leaving that door
open. If it does, Podcasts simply stops appearing; Music and Spotify don't go
through it at all. `Sources/SystemNowPlaying.swift` and the helper are the
places to look. Only Podcasts is taken from it, though it can see any app, so
adding another (a browser, say) is one line in `SystemNowPlaying.bundleIDs`.

### Spotify

Everything works with Spotify except where Spotify itself has no way in:

| | Music | Spotify |
| --- | --- | --- |
| Song, artist, cover, play/pause, skip, scrubber, volume | ✓ | ✓ |
| Moving bars follow the music | ✓ | ✓ — its helper processes are listened to as well, since Spotify can play from any of them |
| Visualizer | ✓ | ✓ |
| Repeat | off / all / this song | on / off only — Spotify has no "this song" |
| AirPlay | ✓ | — Spotify can't be told where to play; the button is dimmed |

With both apps open, the one playing wins. With both paused, the notch keeps the
song from whichever played **last**, so pausing Spotify doesn't flip it over to
whatever Music has loaded.

Spotify's dictionary says it reports a song's length in seconds, but it actually
reports milliseconds, and NotchTunes divides accordingly. If the times under the
scrubber ever look wildly wrong with Spotify, that's the first place to look.

Things to know:

- Audio playing in a **browser tab** (YouTube, Apple Music on the web,
  SoundCloud) won't show up, because there's no app to ask.
- In a **full-screen** app the bar hides itself completely, and comes back when
  you leave. See below for how.
- **While the panel is open it catches clicks** across its whole area, so clicks
  don't reach the menu bar underneath it. That's unavoidable — a panel with
  sliders on it has to receive the mouse. Every other moment, clicks pass
  straight through.

## Checking it without playing music

Preview everything with a sample song, whose scrubber advances on its own:

    NOTCHTUNES_DEMO=1 /Applications/NotchTunes.app/Contents/MacOS/NotchTunes

Or preview the paused state, which shows the pause glyph:

    NOTCHTUNES_DEMO=paused /Applications/NotchTunes.app/Contents/MacOS/NotchTunes

Or run it on real music and have it narrate what it reads and which state it's
in, which is the fastest way to see why nothing is appearing:

    NOTCHTUNES_VERBOSE=1 /Applications/NotchTunes.app/Contents/MacOS/NotchTunes

## The icon

`Resources/AppIcon.icns`, drawn in code by `Tools/MakeIcon.swift`. Change the
artwork there and run:

    ./Tools/make-icon.sh

`build.sh` only copies the result, so you don't pay for redrawing it on every
build. `Resources/AppIcon-preview.png` is the 512px version, to look at.

**The artwork fills the whole square, with no rounded corners of its own.** That
is not a style choice. macOS 26 and later round icons to the system's shape
themselves; an icon that already had its own rounded square with transparent
margins got treated as a small image and given a dark tile behind it, so it
showed up as one rounded square nested inside another. Filling the canvas lets
the system simply mask it, and it then looks like any other app.

`build.sh` re-registers the app with LaunchServices on every install, so the
icon shouldn't go stale. If it ever does:

    touch /Applications/NotchTunes.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/NotchTunes.app

## Looking at a layout change

The panel can be rendered straight to a PNG without running the app or playing
anything:

    ./Tools/preview-panel.sh            # writes panel-preview.png
                                        # and panel-preview-hover.png

The second image forces the knobs on, which they otherwise only are under the
cursor. A real screenshot of the running app, `Resources/screenshot-hover.png`,
is kept on this Mac for comparison but left out of the repository, since it
shows other windows behind the notch.

## How the pieces fit together

| File | What it does |
| --- | --- |
| `Sources/main.swift` | Starts the app and sets the policy that hides it from the Dock. |
| `Sources/AppController.swift` | Owns the window, the once-a-second poll, and the menu bar Quit item. |
| `Sources/NotchGeometry.swift` | Measures the notch and works out where the squares and the panel go. |
| `Sources/NotchWindow.swift` | Decides which of the three states is showing. |
| `Sources/NotchView.swift` | How the squares and the panel look. |
| `Sources/Waveform.swift` | The moving bars, and the colours taken from the cover: one to tint the bars, two for the visualizer's background. The bars are decorative: following the real sound would need permission to record it. |
| `Sources/Visualizer.swift` | The visualizer window and its two styles. |
| `Sources/Shelf.swift` | The clipboard: what a drop turns into, and dragging things back out. |
| `Sources/StudyMode.swift` | Study Mode: the strip over the menu bar, its clock, battery and timer, holding to end it, and the Dock cover. |
| `Sources/Updater.swift` | Check for Updates: asks GitHub for the latest release, and installs it. |
| `Sources/SystemNowPlaying.swift` | Podcasts, through macOS's Now Playing service and the helper in `Helper/`. |
| `Sources/AudioTap.swift` | Listens to Music's (or Spotify's) sound so the bars can follow it. |
| `Sources/BandAnalyser.swift` | Splits that sound into six bands, bass to treble — one per bar. Tested by `Tools/test-bands.sh`. |
| `Sources/NowPlaying.swift` | Asks Music and Spotify what's playing. |
| `Sources/PlayerControl.swift` | Sends play/pause, volume and seek back to them. |
| `Sources/MouseWatcher.swift` | Notices when your cursor arrives on the notch. |
| `Sources/Settings.swift` | The settings, saved in UserDefaults. |
| `Sources/HoldToQuit.swift` | Decides when holding the panel means "quit". Pure logic, tested on its own. |
| `Sources/SettingsWindow.swift` | The settings window and its sliders. |
| `Sources/Diagnostics.swift` | The demo and verbose switches above. |
| `Resources/Info.plist` | `LSUIElement` (no Dock icon), `CFBundleIconFile`, and the permission wording. |
| `Tools/MakeIcon.swift` | Draws the app icon at every size it's needed in. |
| `Tools/PreviewPanel.swift` | Renders the expanded panel to a PNG, for checking a layout. Also `hold` and `settings`. |
| `Tools/TestHoldToQuit.swift` | The hold-to-quit tests. No window, no mouse. |

## Why it reads the way it does — and how much it costs

All figures below are from the same `top` numbers Gauge's Apps tab shows, with
music playing, on this Mac.

| | NotchTunes | Music |
| --- | --- | --- |
| Music on its own, NotchTunes not running | — | about 6% |
| Before | about 15% | about 16% |
| Now | **about 2.5%** | **about 6%** |

Three things made the difference:

1. **The moving bars are plain Core Animation layers, not SwiftUI.** Each frame
   used to go through SwiftUI's whole render pass — and, drawn as six separate
   shapes, re-measured the entire notch window — while its background rendering
   kept starting and stopping threads. Now a frame is six heights changing.
   Bars that can't be seen (the closed panel's, the hidden notch's) stop
   altogether.
2. **Music is asked for only what's needed.** It used to be asked for its whole
   record of the song (`properties of current track`: sixty-odd fields, lyrics
   included) because that was quickest for NotchTunes — but it was building
   that record that cost Music ten points. Now the full details (nine fields,
   asked one by one) are read only when something changes, and otherwise a
   quick check of four: playing or paused, position, volume, repeat.
3. **Changes are announced rather than polled for.** Music and Spotify both
   announce song changes and play/pause to the system; NotchTunes listens, and
   reads in full when they do. The quick check runs four times a second while
   the panel is open, for the scrubber, and every two seconds while it's closed,
   as a safety net. A full read every 15 seconds catches anything else.

Artwork is fetched only when the song changes, and a failed fetch is never
cached (that once left the cover blank for a whole song).

Setting up the audio listener happens off the main thread: macOS can hold that
call for as long as its permission prompt sits unanswered, and on the main
thread that froze the notch.

## The expand animation

There is **one** black shape, and expanding grows it from 252 × 34 to 320 × 166.
Nothing fades into anything else — the black is never interrupted, it just
changes size, which is what makes it read as the notch stretching rather than a
panel appearing over it.

Three details do the work:

- **A spring, not a curve.** `.spring(response: 0.34, dampingFraction: 0.78)`
  overshoots slightly at the end, which is what gives it the rubbery feel. The
  window is 16pt larger than the panel at the sides and bottom purely to give
  that overshoot somewhere to go — clipped, it would look broken at exactly the
  moment it's meant to look alive. That slack is deliberately **not** added above:
  the top edge has to stay flush with the top of the screen.
- **The corner radius grows too** (11pt → 20pt). `NotchShape` is `Animatable`, so
  the radius interpolates along with the size instead of snapping at frame one.
- **The contents are staggered.** The side icons leave in 0.1s; the controls
  arrive 0.08s later over 0.22s, drifting down 10pt as though emerging from
  behind the notch. Collapsing reverses it: the controls go first, and the icons
  only return once the shape is back to size, so they never show against a
  half-grown shape.

## Quitting when the menu bar is hidden

Some apps — exam lockdown software, mostly — hide the menu bar, which takes the
**Quit NotchTunes** item with it. The notch stays on screen regardless, so the
way out lives there instead.

Open the panel, then **press and hold any empty part of it**. After a quarter of
a second a hint fades in — *Keep holding to quit*, with a bar filling up — and
when the bar is full, NotchTunes quits. Let go before then and nothing happens.

"Empty" means anywhere that isn't a control: the artwork, the song title, the
gaps. Holding the volume bar, the scrubber or a transport button never quits,
and neither does a press that moves more than a few points — that's a drag.

### How it decides

The rules live in `HoldToQuitDetector` (`Sources/HoldToQuit.swift`), which is
pure logic: it's handed one sample at a time — where the cursor is, whether the
button is down, whether the panel is open — and answers *idle*, *holding* or
*quit*. The window feeds it from the cursor poll that already runs about sixteen
times a second.

It's built that way, rather than with SwiftUI's `LongPressGesture`, so that the
rules can be tested **without a window or a mouse**:

    ./Tools/test-hold-to-quit.sh

Fifteen cases, from "holding empty space quits" to "dragging the volume bar
across empty space doesn't". The first one is the positive control: if it fails,
every "doesn't" after it means nothing, so it runs first. The tests have also
been checked the other way — remove the rule that skips controls and exactly the
two tests about holding controls fail.

The hold has to *begin* on empty panel space, with the panel already open. A
press that started somewhere else and was dragged in doesn't count, and nor does
one still held from before the panel opened.

## Study Mode

As few distractions as a Mac allows. From the music-note menu choose **Study
Mode**, then how long: **Until I End It**, or 25 minutes to 2 hours.

- A **black strip covers the whole menu bar** — every menu and icon, on every
  desktop, full-screen apps included. Its menus can't be opened.
- In the top-right corner: a small white **clock**; the **time left**, if a
  timer's running; and the **battery**, once it's at or below the level set in
  Settings (red at 10% unless charging).
- The **music notch keeps working** on top of the strip.
- **To end it:** press and hold anywhere on the strip (or the open music panel)
  for the hold-to-quit time. Here it ends Study Mode rather than quitting —
  the menu bar comes back and NotchTunes keeps running. This always works in
  Study Mode, even with hold-to-quit switched off, since the menu is covered.
- **When a timer runs out**, a soft chime plays and the menu bar comes back.
- **Keep the Dock away** (Settings, off by default): the Dock won't appear
  until Study Mode ends. macOS has no switch for another app to turn the Dock
  off, so this uses the Dock's own settings: hiding on, with a thousand-second
  wait before it slides in — long enough that it never does. Your original
  values are saved first and put back when Study Mode ends, when NotchTunes
  quits, and at the next launch if it ever closed mid-session. The Dock
  restarts for a moment as Study Mode starts and ends, which is how it picks
  up the change.

What it doesn't block: ⌘-Tab, Mission Control, Spotlight and keyboard
shortcuts all still work. It covers the notched screen; other displays keep
their menu bars.

`Tools/test-study.sh` checks the battery reading, and the Dock commands — built and checked, never run.

## The clipboard

A shelf in the notch for things you want to keep within reach.

1. **Drag** anything — files, folders, pictures, links, text — towards the
   notch. As it gets close, the notch opens into an outlined area that says
   **Drop here to keep it**, and brightens when you're over it.
2. **Let go.** The item is kept, and a **Clipboard** section appears in the
   panel under the player, with a tile for each thing.
3. **Drag a tile back out** to wherever you want it: Finder, an email, a
   message, a document. It stays in the clipboard too.
4. **Clear** empties it. The section disappears and the notch goes back to
   exactly how it looks without it.

Details:

- The section only exists while something is in it.
- With nothing playing, the clipboard keeps the notch up on its own: the bar
  shows a tray and how many things are kept, and the panel is just the
  clipboard.
- Files are kept as references to where they already are — nothing is copied
  or moved. A picture dragged from somewhere that isn't a file (a web page) is
  saved as a PNG in NotchTunes' cache folder, so it can be dragged out as one.
- This is NotchTunes' own shelf, separate from the Mac's copy-and-paste
  clipboard: it doesn't change what ⌘V pastes.
- It doesn't survive quitting NotchTunes; saved pictures are tidied up at the
  next launch.
- Spotting a drag needs no permission. Every drag puts what it's carrying on a
  shared "drag pasteboard"; NotchTunes notices when that changes while the
  mouse button is down, on the cursor check it already does.
- Dragging an item *out* of the clipboard doesn't turn the panel into a drop
  area under your hand: drags that start inside the open panel are ignored.

`Tools/test-shelf.sh` tests what each kind of drop turns into, merging and
clearing, with made-up drops and a scratch folder.

## Bars that follow the music

The moving bars — beside the notch, in the panel, and in the visualizer — follow
the actual music, shaped the way the Dynamic Island's are: a mirrored glyph,
tallest in the middle. The middle pair follows the bass and low mids, the next
pair out the mids, the outer pair the treble — each side its own range, so the
halves move alike without being identical.

What moves them is mostly **change**, not loudness: how far each range has just
jumped above its own level over the last moment. A drum hit or a new note
stands well above what's around it for an instant, so the bars leap on hits and
sink between them; a sustained sound settles to a low base. The biggest jump
anywhere lifts every bar a little, so a kick drum moves the whole glyph.

Two earlier versions, for the record: bass-left/treble-right showed pitch well
but didn't look like Apple's; and following loudness alone looked frozen,
because in a full song every range is loud nearly all the time.

How: macOS 14.2 added **process taps**, which let one app hear another app's
sound as it plays, without changing what you hear. NotchTunes taps Music (or
Spotify) while something is playing, splits the last 40 ms of sound into its
frequencies many times a second, and measures six bands against the loudest of
them, with the treble lifted a little because music has far less energy up
there. It stops listening a few seconds after you pause.

- **Permission.** macOS asks once whether NotchTunes may record system audio —
  choose **System Audio Recording Only**; it never sees the screen. You'll find
  it later in System Settings → Privacy & Security → Screen & System Audio
  Recording. As with any permission, a rebuild may need it switched off and on.
- **Protected music.** If macOS hands over silence — a stream it protects, or
  the permission turned down — the bars notice after a few seconds and fall back
  to their own pattern. Settings says which is happening.
- Nothing is recorded or kept: the sound goes straight into the band maths and
  is gone.

## The visualizer

Click the music-note icon in the menu bar and choose **Visualizer**, then a style:

- **Album Cover** — the cover, large and centred, with the song beneath it, on a
  background in the cover's two main colours. Soft, heavily blurred clouds of
  those colours drift slowly behind it, as in Music's own full-screen player —
  each on its own loop of about a minute, so the pattern never visibly repeats.
  The cover shrinks a little while paused.
- **Moving Bars** — the notch's bars, filling the window, in the cover's colour
  with a soft glow behind them.

When the song changes, everything cross-fades: the old cover dissolves into the
new one, and the colours drift from one song's to the next over about a second.
Choosing the other style while the window is open fades between the two.

It opens as a large window. Press **F** (or the green button) for full screen,
and **Escape** to leave full screen, or to close the window when it isn't. It
reads from the same place as the notch, so it adds no extra work for Music.

The colours come from sorting the cover's pixels into colour families rather than
averaging them all: an orange flower on green leaves averages to mustard, which
isn't in the picture at all, whereas families give orange and green.

## Moving it between desktops

The menu bar icon has **Move to This Desktop**. Click it from whichever desktop
you want the notch on.

It doesn't follow you on its own, and that's worth understanding before trying
to "fix" it. The window's `collectionBehavior` includes `.moveToActiveSpace`,
which sounds exactly like what's wanted — but Apple's definition is *the window
moves to the active space when the **application** becomes active*. This is an
accessory app with a non-activating panel: it never becomes active, so that
condition never fires and the flag does nothing here.

The move itself works by allowing every Space for a moment, ordering the window
in — which places it on the one you're looking at — then withdrawing that
permission, which leaves it there. `orderFrontRegardless()` alone isn't enough,
because macOS remembers the Space a window already belongs to.

Making it automatic would mean watching `activeSpaceDidChangeNotification` and
moving on every switch. The catch is full screen: the move uses
`.canJoinAllSpaces`, and "all Spaces" includes the one a full-screen app
creates, so an automatic version would put the bar back over full-screen windows
unless it could tell the two apart — which is exactly the thing that turned out
to be hard to detect reliably.

## Full screen

The bar disappears in full screen, and there is no code that detects it. The
window's `collectionBehavior` says which Spaces it is allowed into:

    collectionBehavior = [.moveToActiveSpace, .stationary, .ignoresCycle]

It used to say `.canJoinAllSpaces`, and "all Spaces" includes the one a
full-screen app creates — which is exactly why the bar floated over full-screen
windows. `.moveToActiveSpace` follows you between ordinary desktops without
joining a full-screen Space, so macOS leaves it out on its own.

Worth knowing if you ever revisit this: `.fullScreenAuxiliary` is *not* what
puts it there. Removing that alone changed nothing — `.canJoinAllSpaces` was
doing it. Measured by watching whether the window appears in
`CGWindowListCopyWindowInfo` while another app is full screen: all 16 samples
before, none of the 14 settled samples after, with one frame of overlap during
the Space-slide animation.

## The hover area

The area that opens the panel is the bar itself, plus 10pt at each side. It stops
at the bottom of the menu bar and **never reaches below it**.

That boundary is the whole point. An earlier version reached 64pt further down,
to make an invisible target easier to hit back when the bar spent most of its
time hidden. But opening the panel makes it take mouse events, so hovering that
area and clicking sent the click to the panel instead of to whatever was
underneath — and a browser's tab strip sits exactly there. Reaching for a tab got
you the panel.

It doesn't need the reach any more: the bar is on screen the whole time a song is
loaded, so there's something visible to aim at, and the panel can only open while
a song is loaded anyway.

Verified at eight heights: everything in the top 34pt opens it, everything below
(42, 55, 70, 90, 120pt down) leaves it alone. Once it *is* open, the panel counts
as part of the area, so moving down onto the controls doesn't close it.

## Staying flush with the top of the screen

Two things are needed, and both were learned the hard way:

- **Every frame is rounded to whole points.** The notch is 33.5pt tall here, so
  the natural frames land on half points. A 165.5pt layout inside a 166pt window
  leaves SwiftUI centring it, which showed up as a hairline of wallpaper along
  the very top edge. The frames are now measured *down from the top of the
  screen* and rounded, so the top edge is exact. The bar's height rounds **up**,
  because half a point of extra black is invisible while half a point of gap is
  not.
- **`constrainFrameRect` is overridden to do nothing.** AppKit's default is to
  shove windows down clear of the menu bar, which is precisely where this one
  wants to be.

Things worth knowing if you come back to change this:

- It is **one window** covering both the bar and the expanded panel, plus the
  overshoot slack. Opening up is a change of what's *drawn*, not a window resize
  — resizing a window can't be animated smoothly enough to look right at this
  size.
- The bar is drawn as **one solid black shape straight across the notch**, the
  full height of the notch and flush with the top of the screen. Only the bottom
  outer corners are rounded; the joins either side of the notch are left square,
  so there's no seam where the bar meets the real notch. That flushness is the
  whole illusion — an earlier version inset the squares by 2pt top and bottom and
  rounded all four corners, and the slivers of wallpaper showing through gave it
  away as two tabs stuck to the notch.
  The middle section isn't drawn at all (the notch is physically there), but the
  black background runs behind it so it all reads as one shape.
- The window only accepts mouse events while expanded. The rest of the time
  `ignoresMouseEvents` is on, so clicks pass through to the menu bar. That's also
  why the cursor is found by *polling* its position instead of waiting for
  mouse-entered events — the window mostly doesn't receive any. Polling needs no
  permission from you either.
- Slider values are *held* for a moment after you let go, because the poll would
  otherwise yank the handle back out from under your finger before the music app
  caught up. Clicking play/pause flips the glyph immediately and ignores the
  poll's answer for 0.6s, for the same reason.
- A **failed** artwork fetch is never cached. When a track has just changed the
  music app often hasn't loaded the cover yet, and caching that empty answer is
  what used to leave the square blank for the rest of the song. It retries on the
  next poll, up to six times, so a track with genuinely no cover stops being
  asked.
- `build.sh` assembles and signs the bundle in a temporary folder and then copies
  it here with `ditto`. This folder is inside iCloud Drive, which keeps attaching
  its own file attributes, and `codesign` refuses to sign a bundle carrying them.
  Clearing them first is a race that fails about half the time.
- `build.sh` also builds against the macOS 26 SDK on purpose. The Command Line
  Tools here ship a Swift 6.3 compiler next to a macOS 27 SDK that needs 6.4, and
  those two refuse to work together.
