/*
 * JSR-135 (MMAPI) javacall backend for iOS, built on AVFoundation.
 *
 *  - audio/video (mp3, wav, aac, m4a, mp4, 3gp, mpeg...) : AVPlayer
 *  - MIDI files                                          : AVAudioPlayer (system synth)
 *  - video frames: AVPlayerItemVideoOutput -> 32BGRA -> scaled (nearest) into the rectangle the
 *    MIDlet asked for with VideoControl.setDisplayLocation/Size -> published as an overlay that
 *    midp/lcd.c composites over the Java canvas (optionally only where the mask colour is).
 *  - Java pushes the media bytes with javacall_media_do_buffering(); they are spooled into a temp
 *    file (AVFoundation needs a seekable URL with a sensible extension) and opened at end-of-data.
 *
 * All entry points are called from the VM thread; AVFoundation callbacks arrive on other threads.
 */
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "javacall_multimedia.h"
#include "lcd_ios.h"

extern void javacall_printf(const char* format, ...);

#define TIME_UNKNOWN (-1)
/* -[NSString containsString:] only exists from iOS 8; we target iOS 7 */
#define HAS(str, sub) ([(str) rangeOfString:(sub)].location != NSNotFound)

@interface KVMMedia : NSObject <AVAudioPlayerDelegate>
@property (nonatomic) javacall_int64 playerId;
@property (nonatomic, copy) NSString* mime;
@property (nonatomic, copy) NSString* uri;
@property (nonatomic, copy) NSString* path;          // temp spool file
@property (nonatomic) FILE* fp;
@property (nonatomic) BOOL isMidi, isVideo, playing, visible, muted, needRescale;
@property (nonatomic, strong) AVURLAsset* asset;
@property (nonatomic, strong) AVPlayer* player;
@property (nonatomic, strong) AVPlayerItem* item;
@property (nonatomic, strong) AVPlayerItemVideoOutput* vout;
@property (nonatomic, strong) AVAudioPlayer* ap;      // MIDI
@property (nonatomic, strong) id endObserver;
@property (nonatomic, strong) dispatch_source_t timer;
@property (nonatomic) long durationMs;
@property (nonatomic) int vw, vh;
@property (nonatomic) float fps;
@property (nonatomic) int x, y, w, h;
@property (nonatomic) int volume;                    // 0..100
@property (nonatomic) long rate;                     // milli-percent, 100000 = 1.0x
@property (nonatomic) CVPixelBufferRef lastPB;       // retained manually
@property (nonatomic) uint32_t* buf0; @property (nonatomic) uint32_t* buf1;
@property (nonatomic) int bufW, bufH, bufIdx;
@property (nonatomic, strong) NSData* snapshot;
@end

static BOOL g_maskOn = NO;
static AVAudioPlayer* g_tone = nil;

@implementation KVMMedia
- (instancetype)init {
    if ((self = [super init])) { _durationMs = TIME_UNKNOWN; _volume = 100; _rate = 100000; _fps = 25; }
    return self;
}

// ---------- video frame pump ----------
static void scaleInto(uint32_t* dst, int dw, int dh, CVPixelBufferRef pb) {
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    const uint8_t* base = (const uint8_t*)CVPixelBufferGetBaseAddress(pb);
    size_t sw = CVPixelBufferGetWidth(pb), sh = CVPixelBufferGetHeight(pb), stride = CVPixelBufferGetBytesPerRow(pb);
    if (base && sw && sh) {
        int* xm = (int*)malloc(sizeof(int) * dw);
        for (int x = 0; x < dw; x++) xm[x] = (int)(((uint64_t)x * sw) / dw);
        for (int y = 0; y < dh; y++) {
            const uint32_t* srow = (const uint32_t*)(base + (size_t)(((uint64_t)y * sh) / dh) * stride);
            uint32_t* d = dst + (size_t)y * dw;
            for (int x = 0; x < dw; x++) d[x] = srow[xm[x]] | 0xFF000000u;
        }
        free(xm);
    }
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
}

- (void)publish {                                       // called with @synchronized(self)
    if (!self.visible || self.w <= 0 || self.h <= 0 || !self.lastPB) {
        pspkvm_ios_set_video_overlay((__bridge const void*)self, NULL, 0, 0, 0, 0);
        return;
    }
    if (self.bufW != self.w || self.bufH != self.h) {
        uint32_t* o0 = self.buf0; uint32_t* o1 = self.buf1;
        self.buf0 = (uint32_t*)calloc((size_t)self.w * self.h, 4);
        self.buf1 = (uint32_t*)calloc((size_t)self.w * self.h, 4);
        self.bufW = self.w; self.bufH = self.h; self.bufIdx = 0;
        // old buffers may still be referenced by the overlay until it is replaced below
        scaleInto(self.buf0, self.w, self.h, self.lastPB);
        pspkvm_ios_set_video_overlay((__bridge const void*)self, self.buf0, self.x, self.y, self.w, self.h);
        free(o0); free(o1);
        return;
    }
    uint32_t* back = self.bufIdx ? self.buf0 : self.buf1;     // not the one on screen
    scaleInto(back, self.w, self.h, self.lastPB);
    self.bufIdx = !self.bufIdx;
    pspkvm_ios_set_video_overlay((__bridge const void*)self, back, self.x, self.y, self.w, self.h);
}

- (void)startPump {
    if (!self.isVideo || self.timer) return;
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                              dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    dispatch_source_set_timer(t, DISPATCH_TIME_NOW, 33 * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
    __weak KVMMedia* ws = self;
    dispatch_source_set_event_handler(t, ^{
        KVMMedia* m = ws; if (!m) return;
        BOOL changed = NO;
        CMTime now = [m.item currentTime];
        if ([m.vout hasNewPixelBufferForItemTime:now]) {
            CVPixelBufferRef pb = [m.vout copyPixelBufferForItemTime:now itemTimeForDisplay:NULL];
            if (pb) {
                @synchronized (m) {
                    if (m.lastPB) CVPixelBufferRelease(m.lastPB);
                    m.lastPB = pb;
                    [m publish];
                }
                changed = YES;
            }
        } else if (m.needRescale) {
            @synchronized (m) { m.needRescale = NO; [m publish]; }
            changed = YES;
        }
        if (changed) pspkvm_ios_lcd_refresh();
    });
    dispatch_resume(t);
    self.timer = t;
}

- (void)stopPump {
    if (self.timer) { dispatch_source_cancel(self.timer); self.timer = nil; }
}

- (void)removeOverlay {
    @synchronized (self) {
        pspkvm_ios_set_video_overlay((__bridge const void*)self, NULL, 0, 0, 0, 0);
    }
    pspkvm_ios_lcd_refresh();
}

// ---------- AVAudioPlayerDelegate (MIDI) ----------
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer*)p successfully:(BOOL)ok {
    self.playing = NO;
    javanotify_on_media_notification(JAVACALL_EVENT_MEDIA_END_OF_MEDIA, self.playerId,
                                     (void*)(long)(p.duration * 1000.0));
}

// ---------- loading ----------
- (BOOL)prepareWithURL:(NSURL*)url timeout:(int)sec {
    AVURLAsset* a = [AVURLAsset URLAssetWithURL:url options:nil];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [a loadValuesAsynchronouslyForKeys:@[@"tracks", @"duration", @"playable"]
                     completionHandler:^{ dispatch_semaphore_signal(sem); }];
    if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)sec * NSEC_PER_SEC))) {
        javacall_printf("[media] timeout loading %s\n", url.absoluteString.UTF8String);
        return NO;
    }
    if (![a isPlayable]) {
        javacall_printf("[media] asset not playable: %s\n", url.absoluteString.UTF8String);
        return NO;
    }
    self.asset = a;
    CMTime d = a.duration;
    self.durationMs = (CMTIME_IS_NUMERIC(d) && !CMTIME_IS_INDEFINITE(d))
                      ? (long)(CMTimeGetSeconds(d) * 1000.0) : TIME_UNKNOWN;
    NSArray* vt = [a tracksWithMediaType:AVMediaTypeVideo];
    self.isVideo = vt.count > 0;
    if (self.isVideo) {
        AVAssetTrack* t = vt[0];
        CGSize sz = CGSizeApplyAffineTransform(t.naturalSize, t.preferredTransform);
        self.vw = (int)fabs(sz.width); self.vh = (int)fabs(sz.height);
        if (t.nominalFrameRate > 1.0f) self.fps = t.nominalFrameRate;
    }
    self.item = [AVPlayerItem playerItemWithAsset:a];
    if (self.isVideo) {
        self.vout = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:
                     @{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) }];
        [self.item addOutput:self.vout];
    }
    self.player = [AVPlayer playerWithPlayerItem:self.item];
    self.player.volume = self.volume / 100.0f;
    self.player.muted = self.muted;
    __weak KVMMedia* ws = self;
    self.endObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:self.item queue:nil
        usingBlock:^(NSNotification* n) {
            KVMMedia* m = ws; if (!m) return;
            m.playing = NO;
            javanotify_on_media_notification(JAVACALL_EVENT_MEDIA_END_OF_MEDIA, m.playerId,
                                             (void*)(long)(CMTimeGetSeconds(m.item.currentTime) * 1000.0));
        }];
    [self startPump];
    return YES;
}

- (BOOL)prepareMidiFromFile:(NSString*)path {
    NSError* err = nil;
    self.ap = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&err];
    if (!self.ap) { javacall_printf("[media] midi load failed\n"); return NO; }
    self.ap.delegate = self;
    self.ap.volume = self.volume / 100.0f;
    [self.ap prepareToPlay];
    self.durationMs = (long)(self.ap.duration * 1000.0);
    return YES;
}

- (void)teardown {
    [self stopPump];
    if (self.endObserver) { [[NSNotificationCenter defaultCenter] removeObserver:self.endObserver]; self.endObserver = nil; }
    [self.player pause]; [self.ap stop];
    [self removeOverlay];
    @synchronized (self) {
        if (_lastPB) { CVPixelBufferRelease(_lastPB); _lastPB = NULL; }
    }
}

- (void)dealloc {
    free(_buf0); free(_buf1);
    if (_fp) fclose(_fp);
    if (_path) [[NSFileManager defaultManager] removeItemAtPath:_path error:nil];
}
@end

// ======================= helpers =======================
static KVMMedia* M(javacall_handle h) { return (__bridge KVMMedia*)h; }

static NSString* utf16(const javacall_utf16* s, long n) {
    return (s && n > 0) ? [NSString stringWithCharacters:(const unichar*)s length:(NSUInteger)n] : @"";
}

static NSString* extForMime(NSString* m, BOOL* midi) {
    m = [m lowercaseString]; *midi = NO;
    if ([m hasPrefix:@"audio/mid"] || [m isEqualToString:@"audio/sp-midi"]) { *midi = YES; return @"mid"; }
    if (HAS(m, @"mpeg") && [m hasPrefix:@"audio"]) return @"mp3";
    if ([m isEqualToString:@"audio/mp3"]) return @"mp3";
    if (HAS(m, @"wav")) return @"wav";
    if ([m isEqualToString:@"audio/aac"] || [m isEqualToString:@"audio/aacp"]) return @"aac";
    if ([m hasPrefix:@"audio/mp4"] || [m isEqualToString:@"audio/x-m4a"]) return @"m4a";
    if ([m isEqualToString:@"video/3gpp"]) return @"3gp";
    if ([m isEqualToString:@"video/3gpp2"]) return @"3g2";
    if ([m isEqualToString:@"video/mpeg"]) return @"mpg";
    if ([m hasPrefix:@"video/"]) return @"mp4";
    if (HAS(m, @"amr")) return @"amr";
    return @"bin";
}

static long curMs(KVMMedia* m) {
    if (m.isMidi) return (long)(m.ap.currentTime * 1000.0);
    CMTime t = m.player.currentTime;
    return CMTIME_IS_NUMERIC(t) ? (long)(CMTimeGetSeconds(t) * 1000.0) : 0;
}

// ======================= javacall API =======================
const javacall_media_caps* javacall_media_get_caps(void) {
    // Types themselves are fixed on the Java side (DefaultConfiguration.jpp); the terminating
    // entry only lists the protocols. No AMR/JTS flags -> those stay off.
    static const javacall_media_caps caps[] = { { NULL, 2, { "device", "http" } } };
    return caps;
}

javacall_bool javacall_media_supports_mixing() { return JAVACALL_TRUE; }

javacall_result javacall_media_initialize(void) {
    NSError* e = nil;
    AVAudioSession* s = [AVAudioSession sharedInstance];
    [s setCategory:AVAudioSessionCategoryPlayback error:&e];
    [s setActive:YES error:nil];
    return JAVACALL_OK;
}

javacall_result javacall_media_finalize(void) { return JAVACALL_OK; }

javacall_handle javacall_media_create(javacall_int64 playerId, const javacall_utf16* mime, long mimeLength,
                                      const javacall_utf16* uri, long uriLength, long contentLength) {
    KVMMedia* m = [[KVMMedia alloc] init];
    m.playerId = playerId;
    m.mime = utf16(mime, mimeLength);
    m.uri  = utf16(uri, uriLength);
    BOOL midi = NO;
    NSString* ext = extForMime(m.mime, &midi);
    m.isMidi = midi;

    // Remote content: let AVFoundation stream it itself (see protocol_handled_by_device)
    if ([m.uri hasPrefix:@"http://"] || [m.uri hasPrefix:@"https://"]) {
        if (![m prepareWithURL:[NSURL URLWithString:m.uri] timeout:12]) return NULL;
    } else {
        m.path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"kvm_media_%lld.%@", (long long)playerId, ext]];
    }
    javacall_printf("[media] create id=%lld mime=%s uri=%s\n", (long long)playerId,
                    m.mime.UTF8String, m.uri.UTF8String);
    return (javacall_handle)CFBridgingRetain(m);
}

javacall_result javacall_media_close(javacall_handle h) {
    KVMMedia* m = M(h); if (!m) return JAVACALL_FAIL;
    [m teardown];
    return JAVACALL_OK;
}

javacall_result javacall_media_destroy(javacall_handle h) {
    if (!h) return JAVACALL_FAIL;
    KVMMedia* m = M(h); [m teardown];
    CFBridgingRelease(h);
    return JAVACALL_OK;
}

javacall_result javacall_media_acquire_device(javacall_handle h) { return JAVACALL_OK; }
javacall_result javacall_media_release_device(javacall_handle h) { return JAVACALL_OK; }

javacall_result javacall_media_protocol_handled_by_device(javacall_handle h) {
    KVMMedia* m = M(h);
    return (m && ([m.uri hasPrefix:@"http://"] || [m.uri hasPrefix:@"https://"])) ? JAVACALL_OK : JAVACALL_FAIL;
}

long javacall_media_do_buffering(javacall_handle h, const void* buffer, long length, long offset) {
    KVMMedia* m = M(h); if (!m || !m.path) return -1;
    if (buffer == NULL && length == -1) {                       // end of data -> open it
        if (m.fp) { fclose(m.fp); m.fp = NULL; }
        if (m.isMidi) return [m prepareMidiFromFile:m.path] ? 0 : -1;
        return [m prepareWithURL:[NSURL fileURLWithPath:m.path] timeout:10] ? 0 : -1;
    }
    if (offset == 0 || !m.fp) {
        if (m.fp) fclose(m.fp);
        m.fp = fopen(m.path.fileSystemRepresentation, "wb");
        if (!m.fp) return -1;
    }
    if (fwrite(buffer, 1, (size_t)length, m.fp) != (size_t)length) return -1;
    return length;
}

javacall_result javacall_media_clear_buffer(javacall_handle h) {
    KVMMedia* m = M(h); if (!m) return JAVACALL_FAIL;
    [m teardown];
    if (m.fp) { fclose(m.fp); m.fp = NULL; }
    if (m.path) [[NSFileManager defaultManager] removeItemAtPath:m.path error:nil];
    m.player = nil; m.item = nil; m.vout = nil; m.ap = nil; m.asset = nil;
    return JAVACALL_OK;
}

javacall_result javacall_media_start(javacall_handle h) {
    KVMMedia* m = M(h); if (!m) return JAVACALL_FAIL;
    if (m.isMidi) { if (!m.ap) return JAVACALL_FAIL; [m.ap play]; }
    else {
        if (!m.player) return JAVACALL_FAIL;
        [m.player play];
        if (m.rate != 100000) m.player.rate = m.rate / 100000.0f;
    }
    m.playing = YES;
    if (m.isVideo) [m startPump];
    return JAVACALL_OK;
}

javacall_result javacall_media_stop(javacall_handle h) {
    KVMMedia* m = M(h); if (!m) return JAVACALL_FAIL;
    if (m.isMidi) [m.ap pause]; else [m.player pause];
    m.playing = NO;
    return JAVACALL_OK;
}

javacall_result javacall_media_pause(javacall_handle h)  { return javacall_media_stop(h); }
javacall_result javacall_media_resume(javacall_handle h) { return javacall_media_start(h); }

long javacall_media_get_time(javacall_handle h) {
    KVMMedia* m = M(h); return m ? curMs(m) : -1;
}

long javacall_media_set_time(javacall_handle h, long ms) {
    KVMMedia* m = M(h); if (!m) return -1;
    if (ms < 0) ms = 0;
    if (m.durationMs >= 0 && ms > m.durationMs) ms = m.durationMs;
    if (m.isMidi) { m.ap.currentTime = ms / 1000.0; return ms; }
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [m.player seekToTime:CMTimeMakeWithSeconds(ms / 1000.0, 600)
         toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero
       completionHandler:^(BOOL f) { dispatch_semaphore_signal(sem); }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    m.needRescale = YES;
    return curMs(m);
}

long javacall_media_get_duration(javacall_handle h) {
    KVMMedia* m = M(h); return m ? m.durationMs : -1;
}

long javacall_media_get_volume(javacall_handle h) { KVMMedia* m = M(h); return m ? m.volume : -1; }

long javacall_media_set_volume(javacall_handle h, long level) {
    KVMMedia* m = M(h); if (!m) return -1;
    if (level < 0) level = 0; if (level > 100) level = 100;
    m.volume = (int)level;
    if (m.isMidi) m.ap.volume = level / 100.0f; else m.player.volume = level / 100.0f;
    return level;
}

javacall_bool javacall_media_is_mute(javacall_handle h) { KVMMedia* m = M(h); return (m && m.muted) ? JAVACALL_TRUE : JAVACALL_FALSE; }

javacall_result javacall_media_set_mute(javacall_handle h, javacall_bool mute) {
    KVMMedia* m = M(h); if (!m) return JAVACALL_FAIL;
    m.muted = (mute == JAVACALL_TRUE);
    if (m.isMidi) m.ap.volume = m.muted ? 0.0f : m.volume / 100.0f; else m.player.muted = m.muted;
    return JAVACALL_OK;
}

// ---- tones (Manager.playTone) ----
javacall_result javacall_media_play_tone(long note, long duration, long volume) {
    if (note < 0 || note > 127 || duration <= 0) return JAVACALL_FAIL;
    const int sr = 22050;
    int n = (int)((long long)sr * duration / 1000);
    double f = 440.0 * pow(2.0, (note - 69) / 12.0);
    NSMutableData* d = [NSMutableData dataWithLength:44 + (size_t)n * 2];
    uint8_t* p = (uint8_t*)d.mutableBytes;
    uint32_t dl = (uint32_t)n * 2, rl = 36 + dl, br = sr * 2, sr32 = sr;
    uint16_t fmt = 1, ch = 1, ba = 2, bps = 16; uint32_t sixteen = 16;
    memcpy(p, "RIFF", 4); memcpy(p + 4, &rl, 4); memcpy(p + 8, "WAVEfmt ", 8); memcpy(p + 16, &sixteen, 4);
    memcpy(p + 20, &fmt, 2); memcpy(p + 22, &ch, 2); memcpy(p + 24, &sr32, 4); memcpy(p + 28, &br, 4);
    memcpy(p + 32, &ba, 2); memcpy(p + 34, &bps, 2); memcpy(p + 36, "data", 4); memcpy(p + 40, &dl, 4);
    int16_t* s = (int16_t*)(p + 44);
    int fade = sr / 200;                                         // 5 ms de-click
    for (int i = 0; i < n; i++) {
        double e = i < fade ? (double)i / fade : (n - i < fade ? (double)(n - i) / fade : 1.0);
        s[i] = (int16_t)(sin(2.0 * M_PI * f * i / sr) * 22000.0 * e);
    }
    NSError* err = nil;
    AVAudioPlayer* ap = [[AVAudioPlayer alloc] initWithData:d error:&err];
    if (!ap) return JAVACALL_FAIL;
    ap.volume = (volume < 0 ? 0 : (volume > 100 ? 100 : volume)) / 100.0f;
    @synchronized ([KVMMedia class]) { [g_tone stop]; g_tone = ap; }
    [ap play];
    return JAVACALL_OK;
}

javacall_result javacall_media_stop_tone(void) {
    @synchronized ([KVMMedia class]) { [g_tone stop]; g_tone = nil; }
    return JAVACALL_OK;
}

// ---- VideoControl ----
javacall_result javacall_media_set_video_alpha(javacall_bool on, javacall_pixel color) {
    g_maskOn = (on == JAVACALL_TRUE);
    pspkvm_ios_set_video_mask(g_maskOn, (unsigned short)color);
    return JAVACALL_OK;
}

javacall_result javacall_media_get_video_size(javacall_handle h, long* width, long* height) {
    KVMMedia* m = M(h); if (!m || !m.isVideo) return JAVACALL_FAIL;
    *width = m.vw; *height = m.vh;
    return JAVACALL_OK;
}

javacall_result javacall_media_set_video_location(javacall_handle h, long x, long y, long w, long hh) {
    KVMMedia* m = M(h); if (!m || !m.isVideo) return JAVACALL_FAIL;
    @synchronized (m) {
        m.x = (int)x; m.y = (int)y; m.w = (int)w; m.h = (int)hh;
        m.needRescale = YES;
        if (m.lastPB) [m publish];
    }
    pspkvm_ios_lcd_refresh();
    return JAVACALL_OK;
}

javacall_result javacall_media_set_video_visible(javacall_handle h, javacall_bool visible) {
    KVMMedia* m = M(h); if (!m || !m.isVideo) return JAVACALL_FAIL;
    @synchronized (m) {
        m.visible = (visible == JAVACALL_TRUE);
        if (m.visible) { m.needRescale = YES; [m publish]; }
        else pspkvm_ios_set_video_overlay((__bridge const void*)m, NULL, 0, 0, 0, 0);
    }
    if (m.visible && !m.playing) {                              // nudge the output so the first frame is delivered before start()
        [m.player seekToTime:m.item.currentTime];
    }
    pspkvm_ios_lcd_refresh();
    return JAVACALL_OK;
}

// ---- snapshot ----
javacall_result javacall_media_start_video_snapshot(javacall_handle h, const javacall_utf16* imageType, long length) {
    KVMMedia* m = M(h); if (!m || !m.isVideo || !m.asset) return JAVACALL_FAIL;
    NSString* spec = [utf16(imageType, length) lowercaseString];
    BOOL jpeg = HAS(spec, @"jpeg") || HAS(spec, @"jpg");
    int tw = 0, th = 0;
    for (NSString* kv in [spec componentsSeparatedByString:@"&"]) {
        NSArray* p = [kv componentsSeparatedByString:@"="];
        if (p.count == 2) {
            if ([p[0] isEqualToString:@"width"])  tw = [p[1] intValue];
            if ([p[0] isEqualToString:@"height"]) th = [p[1] intValue];
        }
    }
    AVAssetImageGenerator* g = [[AVAssetImageGenerator alloc] initWithAsset:m.asset];
    g.appliesPreferredTrackTransform = YES;
    CMTime at = m.item.currentTime;
    NSError* err = nil;
    CGImageRef cg = [g copyCGImageAtTime:at actualTime:NULL error:&err];
    if (!cg) return JAVACALL_FAIL;
    UIImage* ui = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    if (tw > 0 && th > 0) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(tw, th), YES, 1.0);
        [ui drawInRect:CGRectMake(0, 0, tw, th)];
        ui = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    m.snapshot = jpeg ? UIImageJPEGRepresentation(ui, 0.85) : UIImagePNGRepresentation(ui);
    return m.snapshot ? JAVACALL_OK : JAVACALL_FAIL;
}

javacall_result javacall_media_get_video_snapshot_data_size(javacall_handle h, long* size) {
    KVMMedia* m = M(h); if (!m || !m.snapshot) return JAVACALL_FAIL;
    *size = (long)m.snapshot.length;
    return JAVACALL_OK;
}

javacall_result javacall_media_get_video_snapshot_data(javacall_handle h, char* buffer, long size) {
    KVMMedia* m = M(h); if (!m || !m.snapshot || size < (long)m.snapshot.length) return JAVACALL_FAIL;
    memcpy(buffer, m.snapshot.bytes, m.snapshot.length);
    m.snapshot = nil;
    return JAVACALL_OK;
}

// ---- FramePositioningControl ----
javacall_result javacall_media_map_frame_to_time(javacall_handle h, long frameNum, long* ms) {
    KVMMedia* m = M(h); if (!m || !m.isVideo) return JAVACALL_FAIL;
    *ms = (long)((double)frameNum * 1000.0 / m.fps);
    return JAVACALL_OK;
}

javacall_result javacall_media_map_time_to_frame(javacall_handle h, long ms, long* frameNum) {
    KVMMedia* m = M(h); if (!m || !m.isVideo) return JAVACALL_FAIL;
    *frameNum = (long)((double)ms * m.fps / 1000.0 + 0.5);
    return JAVACALL_OK;
}

javacall_result javacall_media_seek_to_frame(javacall_handle h, long frameNum, long* actual) {
    KVMMedia* m = M(h); if (!m || !m.isVideo) return JAVACALL_FAIL;
    if (frameNum < 0) frameNum = 0;
    long ms = (long)((double)frameNum * 1000.0 / m.fps);
    long got = javacall_media_set_time(h, ms);
    *actual = (long)((double)got * m.fps / 1000.0 + 0.5);
    return JAVACALL_OK;
}

javacall_result javacall_media_skip_frames(javacall_handle h, long framesToSkip) {
    KVMMedia* m = M(h); if (!m || !m.isVideo) return JAVACALL_FAIL;
    long ms = curMs(m) + (long)((double)framesToSkip * 1000.0 / m.fps);
    javacall_media_set_time(h, ms);
    return JAVACALL_OK;
}

// ---- RateControl (AVPlayer rate; milli-percent) ----
javacall_result javacall_media_get_max_rate(javacall_handle h, long* r) { *r = 200000; return JAVACALL_OK; }
javacall_result javacall_media_get_min_rate(javacall_handle h, long* r) { *r = 50000;  return JAVACALL_OK; }
javacall_result javacall_media_get_rate(javacall_handle h, long* r) { KVMMedia* m = M(h); if (!m) return JAVACALL_FAIL; *r = m.rate; return JAVACALL_OK; }
javacall_result javacall_media_set_rate(javacall_handle h, long r) {
    KVMMedia* m = M(h); if (!m || m.isMidi) return JAVACALL_FAIL;
    if (r < 50000) r = 50000; if (r > 200000) r = 200000;
    m.rate = r;
    if (m.playing) m.player.rate = r / 100000.0f;
    return JAVACALL_OK;
}

// ---- MVM ----
javacall_result javacall_media_to_foreground(javacall_handle h, javacall_media_mvm_option o) { return JAVACALL_OK; }
javacall_result javacall_media_to_background(javacall_handle h, javacall_media_mvm_option o) {
    KVMMedia* m = M(h);
    if (m && !(o & JAVACALL_MEDIA_PLAYABLE_FROM_BACKGROUND)) javacall_media_stop(h);
    return JAVACALL_OK;
}
