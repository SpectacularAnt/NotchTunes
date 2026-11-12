// NotchTunes' Now Playing helper.
//
// Reads what macOS's own Now Playing service (the private MediaRemote
// framework) says is playing, and sends it commands. Apple keeps that service
// for its own programs, so this library is loaded into one of them — perl —
// by NowPlayingHelper.pl, and talks to NotchTunes over standard output.
//
// Everything is looked up by name at run time, since the framework is private
// and has no headers. If a macOS update moves things, this is the file to fix.

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <unistd.h>

typedef void (*GetInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetIsPlaying)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetPID)(dispatch_queue_t, void (^)(int));
typedef void (*Register)(dispatch_queue_t);
typedef Boolean (*SendCommand)(int, CFDictionaryRef);
typedef void (*SetElapsed)(double);

static void *framework(void) {
    static void *handle;
    if (!handle) handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    return handle;
}

static void *find(const char *name) { return framework() ? dlsym(framework(), name) : NULL; }

/// One of the framework's string constants, or the name itself if missing —
/// the constants have always held their own names.
static NSString *key(const char *name) {
    CFStringRef *found = (CFStringRef *)find(name);
    return found ? (__bridge NSString *)*found : [NSString stringWithUTF8String:name];
}

static NSString *lastArtworkTag;

/// Asks for everything and prints one line of JSON.
static void report(void) {
    GetInfo getInfo = (GetInfo)find("MRMediaRemoteGetNowPlayingInfo");
    GetIsPlaying getIsPlaying = (GetIsPlaying)find("MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    GetPID getPID = (GetPID)find("MRMediaRemoteGetNowPlayingApplicationPID");
    if (!getInfo || !getIsPlaying || !getPID) {
        printf("{\"error\":\"MediaRemote functions missing\"}\n");
        fflush(stdout);
        return;
    }

    dispatch_queue_t queue = dispatch_get_main_queue();
    getPID(queue, ^(int pid) {
        getIsPlaying(queue, ^(Boolean playing) {
            getInfo(queue, ^(CFDictionaryRef raw) {
                NSDictionary *info = (__bridge NSDictionary *)raw;
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                NSString *bundle = [NSRunningApplication runningApplicationWithProcessIdentifier:pid].bundleIdentifier;
                out[@"bundle"] = bundle ?: @"";
                out[@"playing"] = @(playing);
                out[@"title"] = info[key("kMRMediaRemoteNowPlayingInfoTitle")] ?: @"";
                out[@"artist"] = info[key("kMRMediaRemoteNowPlayingInfoArtist")] ?: @"";
                out[@"album"] = info[key("kMRMediaRemoteNowPlayingInfoAlbum")] ?: @"";
                out[@"id"] = info[key("kMRMediaRemoteNowPlayingInfoContentItemIdentifier")] ?: @"";
                out[@"duration"] = info[key("kMRMediaRemoteNowPlayingInfoDuration")] ?: @0;
                out[@"elapsed"] = info[key("kMRMediaRemoteNowPlayingInfoElapsedTime")] ?: @0;
                out[@"rate"] = info[key("kMRMediaRemoteNowPlayingInfoPlaybackRate")] ?: @0;
                NSDate *stamp = info[key("kMRMediaRemoteNowPlayingInfoTimestamp")];
                out[@"timestamp"] = @(stamp ? stamp.timeIntervalSince1970 : 0);

                // Artwork only when it changes: it's tens of kilobytes, and
                // most updates are just the position moving on.
                NSData *art = info[key("kMRMediaRemoteNowPlayingInfoArtworkData")];
                NSString *tag = [NSString stringWithFormat:@"%@|%@|%@|%lu", out[@"title"], out[@"album"],
                                 info[key("kMRMediaRemoteNowPlayingInfoArtworkIdentifier")] ?: @"",
                                 (unsigned long)art.length];
                if (art.length > 0 && ![tag isEqualToString:lastArtworkTag]) {
                    out[@"artwork"] = [art base64EncodedStringWithOptions:0];
                    lastArtworkTag = tag;
                }

                NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
                if (json) {
                    fwrite(json.bytes, 1, json.length, stdout);
                    fputc('\n', stdout);
                    // A closed pipe means NotchTunes has gone: stop too.
                    if (fflush(stdout) != 0) exit(0);
                }
            });
        });
    });
}

/// perl calls these with its own arguments, which aren't needed.
void notchtunes_get(void *perl, void *cv) {
    report();
    // Give the answers a moment to come back, then stop.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ exit(0); });
    CFRunLoopRun();
}

void notchtunes_stream(void *perl, void *cv) {
    Register registerForNotifications = (Register)find("MRMediaRemoteRegisterForNowPlayingNotifications");
    if (registerForNotifications) registerForNotifications(dispatch_get_main_queue());

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) { report(); }];
    }
    report();

    // Stop if NotchTunes stops: it's this process's parent.
    pid_t parent = getppid();
    [NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *timer) {
        if (getppid() != parent) exit(0);
    }];
    CFRunLoopRun();
}

void notchtunes_send(void *perl, void *cv) {
    NSString *command = NSProcessInfo.processInfo.environment[@"NOTCHTUNES_ARGUMENT"] ?: @"";
    SendCommand send = (SendCommand)find("MRMediaRemoteSendCommand");
    SetElapsed setElapsed = (SetElapsed)find("MRMediaRemoteSetElapsedTime");

    // The framework's command numbers.
    NSDictionary *numbers = @{@"play": @0, @"pause": @1, @"toggle": @2, @"next": @4, @"previous": @5};
    if ([command hasPrefix:@"seek:"] && setElapsed) {
        setElapsed([[command substringFromIndex:5] doubleValue]);
    } else if (numbers[command] && send) {
        send([numbers[command] intValue], NULL);
    }
    // Let the command go out before the process ends.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{ exit(0); });
    CFRunLoopRun();
}
