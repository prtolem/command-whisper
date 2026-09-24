#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <Speech/Speech.h>
#import <Sparkle/Sparkle.h>
#import "TextCleaner.h"

static NSString * const CWErrorDomain = @"local.commandwhisper.error";
static BOOL CWPreviewMode = NO;

static NSError *CWError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:CWErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

#pragma mark - Right Command monitor

@interface CWRightCommandMonitor : NSObject
@property (nonatomic, copy) void (^onHoldBegan)(void);
@property (nonatomic, copy) void (^onHoldEnded)(void);
@property (nonatomic, copy) void (^onShortcut)(void);
- (BOOL)start;
- (BOOL)isRunning;
- (void)requestPermission;
@end

@implementation CWRightCommandMonitor {
    CFMachPortRef _eventTap;
    CFRunLoopSourceRef _runLoopSource;
    BOOL _rightCommandDown;
    BOOL _holdStarted;
    BOOL _cancelled;
    NSUInteger _generation;
}

static CGEventRef CWEventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo) {
    CWRightCommandMonitor *monitor = (__bridge CWRightCommandMonitor *)userInfo;
    [monitor handleType:type event:event];
    return event;
}

- (void)dealloc {
    if (_runLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
        CFRelease(_runLoopSource);
    }
    if (_eventTap) CFRelease(_eventTap);
}

- (BOOL)start {
    if (_eventTap) {
        if (!CGEventTapIsEnabled(_eventTap)) CGEventTapEnable(_eventTap, true);
        return CGEventTapIsEnabled(_eventTap);
    }
    CGEventMask mask = CGEventMaskBit(kCGEventFlagsChanged) | CGEventMaskBit(kCGEventKeyDown);
    _eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                 mask, CWEventTapCallback, (__bridge void *)self);
    if (!_eventTap) return NO;
    _runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(_eventTap, true);
    return YES;
}

- (BOOL)isRunning {
    return _eventTap != NULL && CGEventTapIsEnabled(_eventTap);
}

- (void)requestPermission {
    CGRequestListenEventAccess();
}

- (void)handleType:(CGEventType)type event:(CGEventRef)event {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (_eventTap) CGEventTapEnable(_eventTap, true);
        return;
    }
    if (type == kCGEventKeyDown && _rightCommandDown) {
        _cancelled = YES;
        _generation++;
        if (_holdStarted && self.onShortcut) dispatch_async(dispatch_get_main_queue(), self.onShortcut);
        return;
    }
    if (type != kCGEventFlagsChanged || CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) != 54) return;

    // A flags-changed event for keycode 54 alternates the physical right Command
    // state. Toggling here also works when the left Command remains held.
    BOOL down = !_rightCommandDown;
    if (down && !_rightCommandDown) {
        _rightCommandDown = YES;
        _cancelled = NO;
        _holdStarted = NO;
        NSUInteger generation = ++_generation;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.22 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self->_rightCommandDown && !self->_cancelled && self->_generation == generation) {
                self->_holdStarted = YES;
                if (self.onHoldBegan) self.onHoldBegan();
            }
        });
    } else if (!down && _rightCommandDown) {
        _rightCommandDown = NO;
        _generation++;
        if (_holdStarted && !_cancelled && self.onHoldEnded) dispatch_async(dispatch_get_main_queue(), self.onHoldEnded);
        _holdStarted = NO;
        _cancelled = NO;
    }
}
@end

#pragma mark - Transcription

@interface CWTranscriber : NSObject
@property (nonatomic, copy) void (^onLevel)(float level);
- (void)requestPermissions:(void (^)(BOOL granted))completion;
- (BOOL)start:(NSError **)error;
- (void)stop:(void (^)(NSString * _Nullable text, NSError * _Nullable error))completion;
- (void)cancel;
@end

@implementation CWTranscriber {
    AVAudioEngine *_audioEngine;
    SFSpeechRecognitionTask *_task;
    SFSpeechAudioBufferRecognitionRequest *_request;
    NSString *_latestText;
    void (^_completion)(NSString *, NSError *);
    NSUInteger _generation;
    NSUInteger _meterFrame;
}

- (instancetype)init {
    if ((self = [super init])) _audioEngine = [AVAudioEngine new];
    return self;
}

- (void)requestPermissions:(void (^)(BOOL))completion {
    dispatch_group_t group = dispatch_group_create();
    __block BOOL microphone = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized;
    __block BOOL speech = SFSpeechRecognizer.authorizationStatus == SFSpeechRecognizerAuthorizationStatusAuthorized;
    if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusNotDetermined) {
        dispatch_group_enter(group);
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            microphone = granted;
            dispatch_group_leave(group);
        }];
    }
    if (SFSpeechRecognizer.authorizationStatus == SFSpeechRecognizerAuthorizationStatusNotDetermined) {
        dispatch_group_enter(group);
        [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
            speech = status == SFSpeechRecognizerAuthorizationStatusAuthorized;
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{ completion(microphone && speech); });
}

- (BOOL)start:(NSError **)error {
    if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] != AVAuthorizationStatusAuthorized ||
        SFSpeechRecognizer.authorizationStatus != SFSpeechRecognizerAuthorizationStatusAuthorized) {
        if (error) *error = CWError(1, @"Нет доступа к микрофону или распознаванию речи");
        return NO;
    }
    SFSpeechRecognizer *recognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:@"ru-RU"]];
    if (!recognizer || !recognizer.available) {
        if (error) *error = CWError(2, @"Распознавание речи сейчас недоступно");
        return NO;
    }
    [self cancel];
    _latestText = @"";
    _request = [SFSpeechAudioBufferRecognitionRequest new];
    _request.shouldReportPartialResults = YES;
    // Prefer the low-latency local model, but remain usable when the Russian
    // dictation asset has not been downloaded in System Settings.
    _request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition;
    _request.taskHint = SFSpeechRecognitionTaskHintDictation;
    _request.addsPunctuation = YES;

    AVAudioInputNode *input = _audioEngine.inputNode;
    AVAudioFormat *format = [input outputFormatForBus:0];
    if (format.sampleRate <= 0 || format.channelCount == 0) {
        if (error) *error = CWError(4, @"Не найден рабочий микрофон");
        return NO;
    }
    __weak SFSpeechAudioBufferRecognitionRequest *weakRequest = _request;
    __weak typeof(self) weakSelfForAudio = self;
    [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        [weakRequest appendAudioPCMBuffer:buffer];
        typeof(self) self = weakSelfForAudio;
        if (!self || !self.onLevel || ++self->_meterFrame % 2 != 0) return;
        const float *samples = buffer.floatChannelData[0];
        if (!samples || buffer.frameLength == 0) return;
        float rms = 0;
        vDSP_rmsqv(samples, 1, &rms, buffer.frameLength);
        float decibels = 20.0f * log10f(MAX(rms, 0.00001f));
        float normalized = MAX(0.0f, MIN(1.0f, (decibels + 52.0f) / 52.0f));
        void (^levelHandler)(float) = self.onLevel;
        dispatch_async(dispatch_get_main_queue(), ^{ levelHandler(normalized); });
    }];

    __weak typeof(self) weakSelf = self;
    _task = [recognizer recognitionTaskWithRequest:_request resultHandler:^(SFSpeechRecognitionResult *result, NSError *taskError) {
        typeof(self) self = weakSelf;
        if (!self) return;
        if (result) {
            self->_latestText = result.bestTranscription.formattedString ?: @"";
            if (result.final) [self completeWithText:self->_latestText error:nil];
        } else if (taskError && !self->_audioEngine.running) {
            if (self->_latestText.length) [self completeWithText:self->_latestText error:nil];
            else [self completeWithText:nil error:taskError];
        }
    }];
    [_audioEngine prepare];
    NSError *startError = nil;
    if (![_audioEngine startAndReturnError:&startError]) {
        [input removeTapOnBus:0];
        [_task cancel];
        _task = nil;
        _request = nil;
        if (error) *error = startError ?: CWError(5, @"Не удалось включить микрофон");
        return NO;
    }
    return YES;
}

- (void)stop:(void (^)(NSString *, NSError *))completion {
    _completion = [completion copy];
    if (self.onLevel) self.onLevel(0);
    if (_audioEngine.running) [_audioEngine stop];
    [_audioEngine.inputNode removeTapOnBus:0];
    [_request endAudio];
    NSUInteger generation = ++_generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_completion && self->_generation == generation) {
            if (self->_latestText.length) [self completeWithText:self->_latestText error:nil];
            else [self completeWithText:nil error:CWError(6, @"Речь не распознана")];
        }
    });
}

- (void)cancel {
    _generation++;
    if (self.onLevel) self.onLevel(0);
    if (_audioEngine.running) [_audioEngine stop];
    @try { [_audioEngine.inputNode removeTapOnBus:0]; } @catch (__unused NSException *exception) {}
    [_request endAudio];
    [_task cancel];
    _task = nil;
    _request = nil;
    _completion = nil;
    _latestText = @"";
}

- (void)completeWithText:(NSString *)text error:(NSError *)error {
    if (!_completion) return;
    void (^completion)(NSString *, NSError *) = _completion;
    _completion = nil;
    _generation++;
    [_task cancel];
    _task = nil;
    _request = nil;
    completion(text, error);
}
@end

#pragma mark - Text insertion

@interface CWTextInjector : NSObject
- (void)requestPermission;
- (BOOL)copyAndInsertIfPossible:(NSString *)text;
@end

@implementation CWTextInjector
- (void)requestPermission {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

- (BOOL)copyAndInsertIfPossible:(NSString *)text {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];
    if (![pasteboard setString:text forType:NSPasteboardTypeString]) return NO;
    if (!AXIsProcessTrusted()) return NO;

    AXUIElementRef system = AXUIElementCreateSystemWide();
    CFTypeRef focusedValue = NULL;
    AXError focusError = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute, &focusedValue);
    CFRelease(system);
    if (focusError != kAXErrorSuccess || !focusedValue) return NO;

    AXUIElementRef focused = (AXUIElementRef)focusedValue;
    Boolean selectedTextSettable = false;
    AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute, &selectedTextSettable);
    if (selectedTextSettable) {
        AXError insertError = AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute, (__bridge CFTypeRef)text);
        CFRelease(focusedValue);
        return insertError == kAXErrorSuccess;
    }

    CFTypeRef roleValue = NULL;
    AXUIElementCopyAttributeValue(focused, kAXRoleAttribute, &roleValue);
    NSString *role = CFBridgingRelease(roleValue);
    CFRelease(focusedValue);
    NSSet<NSString *> *editableRoles = [NSSet setWithArray:@[
        (__bridge NSString *)kAXTextFieldRole,
        (__bridge NSString *)kAXTextAreaRole,
        (__bridge NSString *)kAXComboBoxRole
    ]];
    if (![editableRoles containsObject:role]) return NO;

    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    if (!source) return NO;
    CGEventRef down = CGEventCreateKeyboardEvent(source, 9, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, 9, false);
    CFRelease(source);
    if (!down || !up) {
        if (down) CFRelease(down);
        if (up) CFRelease(up);
        return NO;
    }
    CGEventSetFlags(down, kCGEventFlagMaskCommand);
    CGEventSetFlags(up, kCGEventFlagMaskCommand);
    CGEventPost(kCGAnnotatedSessionEventTap, down);
    CGEventPost(kCGAnnotatedSessionEventTap, up);
    CFRelease(down);
    CFRelease(up);
    return YES;
}
@end

#pragma mark - HUD

typedef NS_ENUM(NSInteger, CWMeterMode) { CWMeterModeStopped, CWMeterModeListening, CWMeterModeProcessing };

@interface CWLevelMeterView : NSView
@property (nonatomic) float level;
- (void)startListening;
- (void)startProcessing;
- (void)stop;
@end

@implementation CWLevelMeterView {
    NSTimer *_timer;
    float _displayLevel;
    CGFloat _phase;
    CWMeterMode _mode;
}

- (BOOL)isFlipped { return YES; }

- (void)startListening {
    _mode = CWMeterModeListening;
    [self startTimer];
}

- (void)startProcessing {
    _mode = CWMeterModeProcessing;
    self.level = 0;
    [self startTimer];
}

- (void)stop {
    [_timer invalidate];
    _timer = nil;
    _mode = CWMeterModeStopped;
    _displayLevel = 0;
    self.level = 0;
    self.needsDisplay = YES;
}

- (void)startTimer {
    [_timer invalidate];
    NSTimeInterval interval = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0.1 : (1.0 / 30.0);
    _timer = [NSTimer timerWithTimeInterval:interval target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)tick:(NSTimer *)timer {
    _phase += _mode == CWMeterModeProcessing ? 0.24 : 0.17;
    float target = _mode == CWMeterModeProcessing ? 0.48f : self.level;
    _displayLevel += (target - _displayLevel) * (_displayLevel < target ? 0.42f : 0.18f);
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    const NSInteger barCount = 7;
    const CGFloat barWidth = 4;
    const CGFloat gap = 4;
    const CGFloat totalWidth = barCount * barWidth + (barCount - 1) * gap;
    CGFloat x = round((NSWidth(self.bounds) - totalWidth) / 2.0);
    CGFloat centerY = NSMidY(self.bounds);
    CGFloat available = NSHeight(self.bounds) - 8;
    CGFloat profile[] = {0.54, 0.74, 0.92, 0.68, 1.0, 0.76, 0.56};

    for (NSInteger i = 0; i < barCount; i++) {
        CGFloat pulse;
        if (_mode == CWMeterModeProcessing) {
            pulse = 0.30 + 0.34 * (sin(_phase + i * 0.72) + 1.0) / 2.0;
        } else {
            CGFloat organic = 0.78 + 0.22 * sin(_phase + i * 0.93);
            pulse = 0.10 + _displayLevel * profile[i] * organic;
        }
        CGFloat height = MAX(4, MIN(available, available * pulse));
        NSRect rect = NSMakeRect(x + i * (barWidth + gap), centerY - height / 2.0, barWidth, height);
        NSBezierPath *bar = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:barWidth / 2 yRadius:barWidth / 2];
        NSColor *color = i == 4
            ? [NSColor colorWithRed:0.36 green:0.96 blue:0.76 alpha:1.0]
            : [NSColor colorWithRed:0.32 green:0.78 blue:1.0 alpha:0.94];
        [color setFill];
        [bar fill];
    }
}
@end

@interface CWListeningHUD : NSObject
- (void)showListening;
- (void)showProcessing;
- (void)showMessage:(NSString *)text symbol:(NSString *)symbolName;
- (void)setLevel:(float)level;
- (void)hide;
@end

@implementation CWListeningHUD {
    NSPanel *_panel;
    NSImageView *_symbol;
    CWLevelMeterView *_meter;
    NSTextField *_label;
    NSTextField *_detail;
    NSUInteger _hideGeneration;
}
- (instancetype)init {
    if ((self = [super init])) {
        _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 330, 82)
                                           styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                             backing:NSBackingStoreBuffered defer:NO];
        _panel.level = NSFloatingWindowLevel;
        _panel.opaque = NO;
        _panel.backgroundColor = NSColor.clearColor;
        _panel.hasShadow = YES;
        _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorIgnoresCycle;
        _panel.hidesOnDeactivate = NO;
        NSView *content = _panel.contentView;
        NSVisualEffectView *material = [[NSVisualEffectView alloc] initWithFrame:content.bounds];
        material.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        material.material = NSVisualEffectMaterialHUDWindow;
        material.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        material.state = NSVisualEffectStateActive;
        material.wantsLayer = YES;
        material.layer.cornerRadius = 16;
        material.layer.masksToBounds = YES;
        [content addSubview:material];

        _meter = [[CWLevelMeterView alloc] initWithFrame:NSZeroRect];
        _meter.translatesAutoresizingMaskIntoConstraints = NO;
        [material addSubview:_meter];
        _symbol = [NSImageView new];
        _symbol.translatesAutoresizingMaskIntoConstraints = NO;
        _symbol.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:23 weight:NSFontWeightSemibold];
        _symbol.contentTintColor = [NSColor colorWithRed:0.36 green:0.96 blue:0.76 alpha:1.0];
        [material addSubview:_symbol];
        _label = [NSTextField labelWithString:@""];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        _label.textColor = NSColor.whiteColor;
        [material addSubview:_label];
        _detail = [NSTextField labelWithString:@""];
        _detail.translatesAutoresizingMaskIntoConstraints = NO;
        _detail.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
        _detail.textColor = [NSColor.whiteColor colorWithAlphaComponent:0.66];
        [material addSubview:_detail];
        [NSLayoutConstraint activateConstraints:@[
            [_meter.leadingAnchor constraintEqualToAnchor:material.leadingAnchor constant:16],
            [_meter.centerYAnchor constraintEqualToAnchor:material.centerYAnchor],
            [_meter.widthAnchor constraintEqualToConstant:56],
            [_meter.heightAnchor constraintEqualToConstant:42],
            [_symbol.centerXAnchor constraintEqualToAnchor:_meter.centerXAnchor],
            [_symbol.centerYAnchor constraintEqualToAnchor:_meter.centerYAnchor],
            [_symbol.widthAnchor constraintEqualToConstant:28],
            [_symbol.heightAnchor constraintEqualToConstant:28],
            [_label.leadingAnchor constraintEqualToAnchor:_meter.trailingAnchor constant:14],
            [_label.trailingAnchor constraintLessThanOrEqualToAnchor:material.trailingAnchor constant:-18],
            [_label.topAnchor constraintEqualToAnchor:material.topAnchor constant:21],
            [_detail.leadingAnchor constraintEqualToAnchor:_label.leadingAnchor],
            [_detail.trailingAnchor constraintLessThanOrEqualToAnchor:material.trailingAnchor constant:-18],
            [_detail.topAnchor constraintEqualToAnchor:_label.bottomAnchor constant:4]
        ]];
    }
    return self;
}
- (void)showListening {
    _symbol.hidden = YES;
    _meter.hidden = NO;
    [_meter startListening];
    [self showWithTitle:@"Слушаю" detail:@"Отпусти ⌘, чтобы вставить"];
}
- (void)showProcessing {
    _symbol.hidden = YES;
    _meter.hidden = NO;
    [_meter startProcessing];
    [self showWithTitle:@"Привожу текст в порядок" detail:@"Пунктуация · повторы · слова-паразиты"];
}
- (void)showMessage:(NSString *)text symbol:(NSString *)symbolName {
    [_meter stop];
    _meter.hidden = YES;
    _symbol.hidden = NO;
    _symbol.image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:text];
    NSString *detail;
    if ([symbolName containsString:@"exclamation"] || [symbolName containsString:@"questionmark"]) {
        detail = @"Попробуй ещё раз";
    } else if ([text containsString:@"буфер"]) {
        detail = @"Текст готов для ⌘V";
    } else {
        detail = @"Текст также остался в буфере";
    }
    [self showWithTitle:text detail:detail];
    NSUInteger generation = ++_hideGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_hideGeneration == generation) [self hide];
    });
}
- (void)setLevel:(float)level { _meter.level = level; }
- (void)hide { _hideGeneration++; [_meter stop]; [_panel orderOut:nil]; }
- (void)showWithTitle:(NSString *)title detail:(NSString *)detail {
    _hideGeneration++;
    _label.stringValue = title;
    _detail.stringValue = detail;
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    if (screen) {
        NSRect frame = screen.visibleFrame;
        [_panel setFrameOrigin:NSMakePoint(round(NSMidX(frame) - NSWidth(_panel.frame) / 2), round(NSMinY(frame) + 34))];
    }
    [_panel orderFrontRegardless];
}
@end

#pragma mark - Application

typedef NS_ENUM(NSInteger, CWMode) { CWModeReady, CWModeListening, CWModeTranscribing, CWModeUnavailable };

@interface CWAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation CWAppDelegate {
    NSStatusItem *_statusItem;
    CWRightCommandMonitor *_monitor;
    CWTranscriber *_transcriber;
    CWTextInjector *_injector;
    CWListeningHUD *_hud;
    CWMode _mode;
    NSString *_unavailableReason;
    SPUStandardUpdaterController *_updaterController;
    NSTimer *_permissionTimer;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _monitor = [CWRightCommandMonitor new];
    _transcriber = [CWTranscriber new];
    _injector = [CWTextInjector new];
    _hud = [CWListeningHUD new];
    _updaterController = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES updaterDelegate:nil userDriverDelegate:nil];
    _mode = CWModeReady;
    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    [self rebuildMenu];

    if (CWPreviewMode) {
        [_hud showListening];
        [_hud setLevel:0.72f];
        return;
    }

    __weak typeof(self) weakSelf = self;
    _monitor.onHoldBegan = ^{ [weakSelf beginListening]; };
    _monitor.onHoldEnded = ^{ [weakSelf finishListening]; };
    _monitor.onShortcut = ^{ [weakSelf cancelForShortcut]; };
    _transcriber.onLevel = ^(float level) {
        typeof(self) self = weakSelf;
        [self->_hud setLevel:level];
    };
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                       selector:@selector(workspaceDidWake:)
                                                           name:NSWorkspaceDidWakeNotification
                                                         object:nil];
    [self refreshGlobalHotkey];
    if (![self essentialPermissionsReady]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf showSetupAssistant]; });
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self refreshGlobalHotkey];
}

- (void)workspaceDidWake:(NSNotification *)notification {
    [self refreshGlobalHotkey];
}

- (void)rebuildMenu {
    NSString *symbol = @"waveform";
    NSString *status = @"Готово";
    if (_mode == CWModeListening) { symbol = @"waveform.circle.fill"; status = @"Слушаю…"; }
    else if (_mode == CWModeTranscribing) { symbol = @"ellipsis.circle"; status = @"Распознаю…"; }
    else if (_mode == CWModeUnavailable) { symbol = @"exclamationmark.triangle"; status = _unavailableReason ?: @"Нужно внимание"; }
    _statusItem.button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:status];

    NSMenu *menu = [NSMenu new];
    NSMenuItem *state = [[NSMenuItem alloc] initWithTitle:status action:nil keyEquivalent:@""];
    state.enabled = NO;
    [menu addItem:state];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *hint = [[NSMenuItem alloc] initWithTitle:@"Удерживай правый ⌘ и говори" action:nil keyEquivalent:@""];
    hint.enabled = NO;
    [menu addItem:hint];
    NSMenuItem *cleanup = [[NSMenuItem alloc] initWithTitle:@"Убирать слова-паразиты" action:@selector(toggleCleanup:) keyEquivalent:@""];
    cleanup.target = self;
    cleanup.state = [self cleanupEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:cleanup];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *permissions = [[NSMenuItem alloc] initWithTitle:@"Проверить разрешения…" action:@selector(requestPermissions:) keyEquivalent:@""];
    permissions.target = self;
    [menu addItem:permissions];
    NSMenuItem *updates = [[NSMenuItem alloc] initWithTitle:@"Проверить обновления…" action:@selector(checkForUpdates:) keyEquivalent:@""];
    updates.target = self;
    [menu addItem:updates];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Выйти" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    [menu addItem:quit];
    _statusItem.menu = menu;
}

- (BOOL)cleanupEnabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return [defaults objectForKey:@"removeFillers"] == nil ? YES : [defaults boolForKey:@"removeFillers"];
}

- (void)setMode:(CWMode)mode { _mode = mode; _unavailableReason = nil; [self rebuildMenu]; }
- (void)setUnavailable:(NSString *)reason { _mode = CWModeUnavailable; _unavailableReason = reason; [self rebuildMenu]; }

- (BOOL)essentialPermissionsReady {
    return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized
        && SFSpeechRecognizer.authorizationStatus == SFSpeechRecognizerAuthorizationStatusAuthorized
        && CGPreflightListenEventAccess();
}

- (void)refreshGlobalHotkey {
    BOOL inputAllowed = CGPreflightListenEventAccess();
    BOOL monitorRunning = inputAllowed && [_monitor start];
    BOOL speechReady = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized
        && SFSpeechRecognizer.authorizationStatus == SFSpeechRecognizerAuthorizationStatusAuthorized;

    if (monitorRunning && speechReady) {
        [_permissionTimer invalidate];
        _permissionTimer = nil;
        if (_mode == CWModeUnavailable) [self setMode:CWModeReady];
        return;
    }

    if (_mode != CWModeListening && _mode != CWModeTranscribing) {
        [self setUnavailable:inputAllowed ? @"Нужен доступ к микрофону и речи" : @"Нужен мониторинг ввода"];
    }
    if (!_permissionTimer) {
        _permissionTimer = [NSTimer timerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(permissionTimerFired:)
                                                userInfo:nil
                                                 repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:_permissionTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)permissionTimerFired:(NSTimer *)timer {
    [self refreshGlobalHotkey];
}

- (NSString *)permissionSummary {
    BOOL microphone = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized;
    BOOL speech = SFSpeechRecognizer.authorizationStatus == SFSpeechRecognizerAuthorizationStatusAuthorized;
    BOOL keyboard = CGPreflightListenEventAccess();
    BOOL accessibility = AXIsProcessTrusted();
    return [NSString stringWithFormat:@"%@  Микрофон\n%@  Распознавание речи\n%@  Мониторинг ввода\n%@  Универсальный доступ",
            microphone ? @"✓" : @"○", speech ? @"✓" : @"○", keyboard ? @"✓" : @"○", accessibility ? @"✓" : @"○"];
}

- (void)showSetupAssistant {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Настроим Command Whisper";
    alert.informativeText = [NSString stringWithFormat:@"Для удержания правого ⌘ и вставки текста нужны системные разрешения.\n\n%@\n\nВозвращайся в любое приложение — перезапуск больше не нужен.", [self permissionSummary]];
    [alert addButtonWithTitle:@"Выдать разрешения"];
    [alert addButtonWithTitle:@"Позже"];
    if ([alert runModal] == NSAlertFirstButtonReturn) [self requestPermissions:nil];
}

- (void)beginListening {
    if (_mode != CWModeReady) return;
    NSError *error = nil;
    if ([_transcriber start:&error]) {
        [self setMode:CWModeListening];
        [_hud showListening];
    } else {
        [self setUnavailable:error.localizedDescription];
        [_hud showMessage:error.localizedDescription symbol:@"exclamationmark.triangle.fill"];
    }
}

- (void)finishListening {
    if (_mode != CWModeListening) return;
    [self setMode:CWModeTranscribing];
    [_hud showProcessing];
    __weak typeof(self) weakSelf = self;
    [_transcriber stop:^(NSString *text, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self) return;
            [self setMode:CWModeReady];
            if (error || text.length == 0) {
                [self->_hud showMessage:error.localizedDescription ?: @"Речь не распознана" symbol:@"questionmark.bubble"];
                return;
            }
            NSString *cleaned = [CWTextCleaner clean:text removeFillers:[self cleanupEnabled]];
            if (cleaned.length == 0) {
                [self->_hud showMessage:@"Речь не распознана" symbol:@"questionmark.bubble"];
            } else if ([self->_injector copyAndInsertIfPossible:cleaned]) {
                [self->_hud showMessage:@"Вставлено и скопировано" symbol:@"checkmark.circle.fill"];
            } else {
                [self->_hud showMessage:@"Скопировано в буфер" symbol:@"doc.on.clipboard.fill"];
            }
        });
    }];
}

- (void)cancelForShortcut {
    if (_mode != CWModeListening) return;
    [_transcriber cancel];
    [self setMode:CWModeReady];
    [_hud hide];
}

- (void)toggleCleanup:(NSMenuItem *)sender {
    [NSUserDefaults.standardUserDefaults setBool:![self cleanupEnabled] forKey:@"removeFillers"];
    [self rebuildMenu];
}

- (void)requestPermissions:(id)sender {
    __weak typeof(self) weakSelf = self;
    [_transcriber requestPermissions:^(BOOL granted) {
        typeof(self) self = weakSelf;
        if (self) [self refreshGlobalHotkey];
    }];
    [_monitor requestPermission];
    [_injector requestPermission];
    [self refreshGlobalHotkey];
}

- (void)checkForUpdates:(id)sender {
    [_updaterController checkForUpdates:sender];
}
@end

static int CWRunSelfTest(void) {
    SFSpeechRecognizer *recognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:@"ru-RU"]];
    NSString *bundlePath = NSBundle.mainBundle.bundlePath ?: @"";
    NSDictionary *report = @{
        @"appVersion": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
        @"bundlePath": bundlePath,
        @"installedInApplications": @([bundlePath containsString:@"/Applications/"]),
        @"microphoneAuthorized": @([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized),
        @"speechAuthorized": @(SFSpeechRecognizer.authorizationStatus == SFSpeechRecognizerAuthorizationStatusAuthorized),
        @"russianRecognizerAvailable": @(recognizer != nil),
        @"onDeviceRecognitionAvailable": @(recognizer.supportsOnDeviceRecognition),
        @"inputMonitoringAuthorized": @(CGPreflightListenEventAccess()),
        @"accessibilityAuthorized": @(AXIsProcessTrusted()),
        @"updaterFrameworkLoaded": @(NSClassFromString(@"SPUStandardUpdaterController") != nil)
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    return recognizer != nil && NSClassFromString(@"SPUStandardUpdaterController") != nil ? 0 : 1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        CWPreviewMode = argc > 1 && strcmp(argv[1], "--preview") == 0;
        if (argc > 1 && strcmp(argv[1], "--self-test") == 0) return CWRunSelfTest();
        NSApplication *app = NSApplication.sharedApplication;
        CWAppDelegate *delegate = [CWAppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
