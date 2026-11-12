import AppKit
import AudioToolbox
import CoreAudio
import os

/// The six bar heights, shared between the audio thread that writes them and
/// the screen that reads them sixty times a second.
final class AudioLevels {
    static let shared = AudioLevels()

    private var lock = os_unfair_lock()
    private var levels = [Float](repeating: 0, count: BandAnalyser.bandCount)
    private var updated = Date.distantPast
    private var following = false

    /// The bar heights, by bar (left to right), 0...1, already in the island's
    /// shape — or nil when the bars
    /// should use their own pattern instead: nothing is being heard, or what is
    /// heard is silence.
    func current() -> [Float]? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        // Half a second without news means the sound has stopped arriving.
        guard following, Date().timeIntervalSince(updated) < 0.5 else { return nil }
        return levels
    }

    private var heard = Date.distantPast

    /// When the audio last had any sound in it at all.
    var lastHeard: Date {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return heard
    }

    fileprivate func set(_ new: [Float], heardSound: Bool) {
        os_unfair_lock_lock(&lock)
        levels = new
        updated = Date()
        if heardSound { heard = updated }
        os_unfair_lock_unlock(&lock)
    }

    private var bounceValue: Float = 0.5

    /// The Settings slider, passed on to the analyser on the audio thread.
    var bounce: Float {
        get { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return bounceValue }
        set { os_unfair_lock_lock(&lock); bounceValue = newValue; os_unfair_lock_unlock(&lock) }
    }

    fileprivate func setFollowing(_ value: Bool) {
        os_unfair_lock_lock(&lock)
        following = value
        os_unfair_lock_unlock(&lock)
    }
}

/// Listens to one app's sound — Music's, or Spotify's — so the bars can move
/// with it.
///
/// This uses Core Audio's process taps (macOS 14.2 and later). A tap copies an
/// app's sound as it plays, without changing what you hear. The copy arrives
/// through a private "aggregate device" — a stand-in sound device only this
/// app can see — and each piece is handed to the band analyser.
///
/// macOS asks once for permission ("System Audio Recording Only"). If it's
/// turned down, or if an app's sound is protected and comes through silent,
/// the bars quietly go back to their own pattern.
final class AudioFollower: ObservableObject {
    static let shared = AudioFollower()

    enum Status: Equatable {
        case idle           // not listening: switched off, or nothing playing
        case following      // hearing the music
        case silent         // listening, but hearing only silence
        case unavailable    // macOS wouldn't set it up
    }

    /// For the one-line note in Settings.
    @Published private(set) var status: Status = .idle

    private var tap: AnyObject?          // a ProcessTap, where macOS has them
    private var tappedPID: pid_t?
    private var tappedBundleID = ""
    private var stopTimer: Timer?

    // Silence watching: how long it's been listening. When it last heard
    // anything is kept by AudioLevels, which the audio thread writes to.
    private var startedAt = Date()

    /// Where the listener is set up and taken down — never on the main thread.
    ///
    /// Setting up can stop and wait: the first time, macOS holds the call
    /// until you've answered its "record system audio" prompt, and that can be
    /// as long as the prompt sits there. It used to happen on the main thread,
    /// which froze the whole notch for that time.
    private let setupQueue = DispatchQueue(label: "NotchTunes.audioSetup", qos: .userInitiated)

    /// Counts starts and stops, so a setup that finishes after it's been
    /// overtaken — the music paused meanwhile, say — knows to throw itself away.
    private var generation = 0

    private init() {
        // Plugging in headphones or picking AirPods changes the device the
        // listener keeps time with, and the old one may be gone. Start again
        // on the new one.
        var where_ = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &where_, .main) { [weak self] _, _ in
            guard let self, self.tap != nil, let pid = self.tappedPID else { return }
            logLine("audio: output changed, listening again")
            self.start(pid: pid, bundleID: self.tappedBundleID)
        }
    }

    /// Called on every poll with what's playing. Starts listening when music
    /// plays, stops a few seconds after it stops.
    func update(app: String?, isPlaying: Bool, enabled: Bool) {
        let bundleID: String
        switch app {
        case "Spotify": bundleID = "com.spotify.client"
        case "Podcasts": bundleID = "com.apple.podcasts"
        default: bundleID = "com.apple.Music"
        }
        guard enabled, isPlaying, app != nil, let pid = Self.pid(of: bundleID) else {
            scheduleStop(immediately: !enabled)
            return
        }
        stopTimer?.invalidate()
        stopTimer = nil

        if tappedPID != pid { start(pid: pid, bundleID: bundleID) }
        checkForSilence()
    }

    private static func pid(of bundleID: String) -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
    }

    private func start(pid: pid_t, bundleID: String) {
        stop()
        guard #available(macOS 14.2, *) else { status = .unavailable; return }

        // Claimed straight away, so the next poll doesn't start a second one
        // while this is still being set up.
        tappedPID = pid
        tappedBundleID = bundleID
        let mine = generation

        setupQueue.async { [weak self] in
            let result: Result<ProcessTap, Error> = Result {
                // Called about ninety times a second, on the audio thread. The
                // note that something was heard goes in with the levels, rather
                // than waking the main thread each time.
                try ProcessTap(pid: pid, bundleID: bundleID) { levels, peak in
                    AudioLevels.shared.set(levels, heardSound: peak > 0.0001)
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let fresh):
                    guard self.generation == mine else {
                        // Overtaken while it was being set up: not wanted now.
                        self.setupQueue.async { fresh.stop() }
                        return
                    }
                    self.tap = fresh
                    self.startedAt = Date()
                    AudioLevels.shared.setFollowing(false)     // until something is heard
                    logLine("audio: listening to process \(pid)")
                case .failure(let error):
                    guard self.generation == mine else { return }
                    logLine("audio: couldn't listen — \(error)")
                    // tappedPID stays set, so it isn't retried four times a
                    // second. A new song starting (a different process, or this
                    // one after a stop) tries again.
                    self.status = .unavailable
                }
            }
        }
    }

    /// Decides between "following" and "silent". A protected stream, or a
    /// permission turned down, both arrive as perfect silence.
    private func checkForSilence() {
        guard tap != nil else { return }
        let hearing = Date().timeIntervalSince(AudioLevels.shared.lastHeard) < 1.0
        AudioLevels.shared.setFollowing(hearing)

        let next: Status
        if hearing {
            next = .following
        } else if Date().timeIntervalSince(startedAt) > 3 {
            next = .silent
        } else {
            return      // still settling in
        }
        if next != status {
            status = next
            logLine("audio: \(next)")
        }
    }

    private func scheduleStop(immediately: Bool) {
        guard tap != nil || tappedPID != nil else { return }
        if immediately { stop(); return }
        guard stopTimer == nil else { return }
        // A few seconds' grace, so pausing for a moment doesn't tear the whole
        // thing down and build it again.
        let timer = Timer(timeInterval: 4, repeats: false) { [weak self] _ in self?.stop() }
        RunLoop.main.add(timer, forMode: .common)
        stopTimer = timer
    }

    private func stop() {
        stopTimer?.invalidate()
        stopTimer = nil
        generation += 1
        // Taken down off the main thread too, for the same reason.
        if #available(macOS 14.2, *), let old = tap as? ProcessTap {
            setupQueue.async { old.stop() }
        }
        tap = nil
        tappedPID = nil
        AudioLevels.shared.setFollowing(false)
        if status != .idle {
            status = .idle
            logLine("audio: stopped listening")
        }
    }
}

/// One process tap, from setting up to tearing down.
@available(macOS 14.2, *)
private final class ProcessTap {

    struct Failure: Error, CustomStringConvertible {
        let step: String
        let code: OSStatus
        var description: String { "\(step) failed (\(code))" }
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "NotchTunes.audio", qos: .userInteractive)
    private let analyser = BandAnalyser()

    init(pid: pid_t, bundleID: String, onLevels: @escaping ([Float], Float) -> Void) throws {
        // 1. Core Audio's own ids for the app, and for its helpers. Spotify is
        //    built like a web browser, from a main app and several "Spotify
        //    Helper" processes, and its sound can come out of any of them —
        //    listening to the main one alone could hear nothing. So every
        //    process belonging to the app is included. Music has no helpers
        //    making sound, so for it this is just Music.
        var processes = Self.processObjects(belongingTo: bundleID)
        if processes.isEmpty { processes = [try Self.processObject(for: pid)] }
        logLine("audio: tapping \(processes.count) process(es) of \(bundleID)")

        // 2. The tap: a copy of that app's sound, mixed down to stereo, left
        //    playing as normal.
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        description.name = "NotchTunes"
        try Self.check("creating the tap", AudioHardwareCreateProcessTap(description, &tapID))

        // 3. A private stand-in device to receive it, timed by whatever you're
        //    listening on.
        let output = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NotchTunes listener",
            kAudioAggregateDeviceUIDKey: "local.notchtunes.listener.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: output,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        do {
            try Self.check("creating the listener",
                           AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID))

            // 4. What shape the sound arrives in.
            let format = try Self.format(of: tapID)
            let rate = Float(format.mSampleRate)
            let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            let channels = max(1, Int(format.mChannelsPerFrame))

            // 5. Each piece of sound as it arrives: down to mono, into the
            //    analyser, out as six heights.
            let analyser = self.analyser
            try Self.check("listening", AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue) { _, input, _, _, _ in
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                let mono = Self.mono(buffers, interleaved: interleaved, channels: channels)
                guard !mono.isEmpty else { return }
                let peak = mono.reduce(0) { max($0, abs($1)) }
                analyser.bounce = AudioLevels.shared.bounce
                analyser.add(mono, sampleRate: rate)
                onLevels(analyser.islandBars, peak)
            })
            try Self.check("starting", AudioDeviceStart(deviceID, procID))
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
            self.procID = nil
        }
        if deviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(deviceID)
            deviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit { stop() }

    // MARK: Helpers

    private static func check(_ step: String, _ code: OSStatus) throws {
        guard code == noErr else { throw Failure(step: step, code: code) }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Every process Core Audio knows about whose bundle ID is the app's own,
    /// or one of its helpers' ("com.spotify.client.helper…").
    private static func processObjects(belongingTo bundleID: String) -> [AudioObjectID] {
        var listAddress = address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &size) == noErr, size > 0 else { return [] }

        var all = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &listAddress, 0, nil, &size, &all) == noErr else { return [] }

        return all.filter { process in
            var idAddress = address(kAudioProcessPropertyBundleID)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(process, &idAddress, 0, nil, &nameSize, &name) == noErr,
                  let id = name?.takeRetainedValue() as String? else { return false }
            return id == bundleID || id.hasPrefix(bundleID + ".")
        }
    }

    private static func processObject(for pid: pid_t) throws -> AudioObjectID {
        var where_ = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check("finding the app's sound",
                  AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_,
                                             UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object))
        guard object != kAudioObjectUnknown else { throw Failure(step: "finding the app's sound", code: -1) }
        return object
    }

    private static func defaultOutputUID() throws -> String {
        var where_ = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check("finding the speakers",
                  AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size, &device))

        var uidAddress = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check("naming the speakers", AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &size, &uid))
        guard let name = uid?.takeRetainedValue() else { throw Failure(step: "naming the speakers", code: -1) }
        return name as String
    }

    private static func format(of tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var where_ = address(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check("reading the sound's format", AudioObjectGetPropertyData(tap, &where_, 0, nil, &size, &format))
        return format
    }

    /// Averages the channels into one. The tap hands over 32-bit floats.
    private static func mono(_ buffers: UnsafeMutableAudioBufferListPointer,
                             interleaved: Bool, channels: Int) -> [Float] {
        if interleaved {
            guard let first = buffers.first, let data = first.mData else { return [] }
            let total = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            let frames = total / channels
            return (0..<frames).map { frame in
                var sum: Float = 0
                for c in 0..<channels { sum += samples[frame * channels + c] }
                return sum / Float(channels)
            }
        }

        // One buffer per channel.
        let usable = buffers.compactMap { buffer -> UnsafeBufferPointer<Float>? in
            guard let data = buffer.mData else { return nil }
            return UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                                       count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
        }
        guard let frames = usable.map(\.count).min(), frames > 0 else { return [] }
        return (0..<frames).map { frame in
            usable.reduce(0) { $0 + $1[frame] } / Float(usable.count)
        }
    }
}
