#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const NSUInteger MaxInputFiles = 10;

@interface KeyboardPreset : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic) NSUInteger width;
@property(nonatomic) NSUInteger height;
@property(nonatomic) NSUInteger recommendedFrames;
@end

@implementation KeyboardPreset
@end

@interface ImageInfo : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic) NSUInteger width;
@property(nonatomic) NSUInteger height;
@property(nonatomic) NSUInteger frames;
@property(nonatomic) unsigned long long bytes;
@property(nonatomic) BOOL animated;
@property(nonatomic, copy) NSString *status;
@property(nonatomic) BOOL readable;
@end

@implementation ImageInfo
@end

static KeyboardPreset *Preset(NSString *name, NSUInteger width, NSUInteger height, NSUInteger frames) {
    KeyboardPreset *preset = [KeyboardPreset new];
    preset.name = name;
    preset.width = width;
    preset.height = height;
    preset.recommendedFrames = frames;
    return preset;
}

static NSArray<KeyboardPreset *> *KeyboardPresets(void) {
    static NSArray<KeyboardPreset *> *presets;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        presets = @[
            Preset(@"AULA F108Pro", 240, 135, 140),
            Preset(@"AULA F75 Max", 128, 128, 120)
        ];
    });
    return presets;
}

static NSString *HumanSize(unsigned long long bytes) {
    double value = (double)bytes;
    NSArray<NSString *> *units = @[@"B", @"KB", @"MB", @"GB"];
    NSUInteger unit = 0;
    while (value >= 1024.0 && unit + 1 < units.count) {
        value /= 1024.0;
        unit++;
    }
    return [NSString stringWithFormat:unit == 0 ? @"%.0f %@" : @"%.1f %@", value, units[unit]];
}

static ImageInfo *InspectImage(NSURL *url) {
    ImageInfo *info = [ImageInfo new];
    info.path = url.path;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
    info.bytes = attrs.fileSize;

    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) {
        info.status = @"Unsupported image file.";
        info.readable = NO;
        return info;
    }

    size_t frameCount = CGImageSourceGetCount(source);
    info.frames = MAX((NSUInteger)frameCount, 1);
    info.animated = info.frames > 1;

    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    info.width = [properties[(NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
    info.height = [properties[(NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    CFRelease(source);

    if (info.width == 0 || info.height == 0) {
        info.status = @"Could not read image dimensions.";
        info.readable = NO;
        return info;
    }

    info.status = @"Ready.";
    info.readable = YES;
    return info;
}

@interface DropView : NSView
@property(nonatomic, copy) void (^filesHandler)(NSArray<NSURL *> *urls);
@end

@implementation DropView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 8.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [NSColor separatorColor].CGColor;
        self.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    self.layer.borderColor = [NSColor controlAccentColor].CGColor;
    return NSDragOperationCopy;
}
- (void)draggingExited:(id<NSDraggingInfo>)sender {
    self.layer.borderColor = [NSColor separatorColor].CGColor;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    self.layer.borderColor = [NSColor separatorColor].CGColor;
    NSArray<NSURL *> *urls = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
                                                                       options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (urls.count > 0 && self.filesHandler) {
        self.filesHandler(urls);
        return YES;
    }
    return NO;
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTextFieldDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSPopUpButton *modelPopup;
@property(nonatomic, strong) NSTextField *widthField;
@property(nonatomic, strong) NSTextField *heightField;
@property(nonatomic, strong) NSTextField *frameLimitField;
@property(nonatomic, strong) NSTextField *targetLabel;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *detailsLabel;
@property(nonatomic, strong) NSTextField *resizeNoticeLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSButton *chooseButton;
@property(nonatomic, strong) NSButton *uploadButton;
@property(nonatomic, strong) NSProgressIndicator *progress;
@property(nonatomic, strong) NSArray<ImageInfo *> *selectedInfos;
@property(nonatomic) BOOL selectionWasCapped;
@property(nonatomic, strong) NSTask *uploadTask;
@property(nonatomic, strong) NSURL *temporaryUploadURL;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildWindow];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 420)
                                             styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"AULA GIF Uploader";
    self.window.releasedWhenClosed = NO;
    [self.window center];

    NSView *content = self.window.contentView;

    [content addSubview:[self label:@"Keyboard" frame:NSMakeRect(24, 366, 90, 18) size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor alignment:NSTextAlignmentLeft]];
    self.modelPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(24, 336, 180, 28) pullsDown:NO];
    for (KeyboardPreset *preset in KeyboardPresets()) {
        [self.modelPopup addItemWithTitle:preset.name];
    }
    self.modelPopup.target = self;
    self.modelPopup.action = @selector(modelChanged:);
    [content addSubview:self.modelPopup];

    [content addSubview:[self label:@"Width" frame:NSMakeRect(224, 366, 70, 18) size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor alignment:NSTextAlignmentLeft]];
    self.widthField = [self numberField:NSMakeRect(224, 336, 70, 28)];
    [content addSubview:self.widthField];

    [content addSubview:[self label:@"Height" frame:NSMakeRect(310, 366, 70, 18) size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor alignment:NSTextAlignmentLeft]];
    self.heightField = [self numberField:NSMakeRect(310, 336, 70, 28)];
    [content addSubview:self.heightField];

    [content addSubview:[self label:@"Frames" frame:NSMakeRect(396, 366, 80, 18) size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor alignment:NSTextAlignmentLeft]];
    self.frameLimitField = [self numberField:NSMakeRect(396, 336, 80, 28)];
    [content addSubview:self.frameLimitField];

    self.targetLabel = [self label:@"" frame:NSMakeRect(24, 306, 472, 18) size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor alignment:NSTextAlignmentLeft];
    [content addSubview:self.targetLabel];

    DropView *drop = [[DropView alloc] initWithFrame:NSMakeRect(24, 126, 472, 166)];
    __weak typeof(self) weakSelf = self;
    drop.filesHandler = ^(NSArray<NSURL *> *urls) {
        [weakSelf selectURLs:urls];
    };
    [content addSubview:drop];

    self.titleLabel = [self label:@"Drag & drop images/GIFs here" frame:NSMakeRect(48, 222, 424, 26) size:18 weight:NSFontWeightSemibold color:NSColor.labelColor alignment:NSTextAlignmentCenter];
    [content addSubview:self.titleLabel];

    self.detailsLabel = [self label:@"Drop up to 10 files here or choose them from Finder." frame:NSMakeRect(48, 176, 424, 42) size:13 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor alignment:NSTextAlignmentCenter];
    self.detailsLabel.maximumNumberOfLines = 2;
    [content addSubview:self.detailsLabel];

    self.chooseButton = [NSButton buttonWithTitle:@"Choose Images/GIFs" target:self action:@selector(chooseFile:)];
    self.chooseButton.frame = NSMakeRect(176, 138, 168, 30);
    self.chooseButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:self.chooseButton];

    self.resizeNoticeLabel = [self label:@"Images that do not match the target size are resized before upload." frame:NSMakeRect(24, 104, 472, 18) size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor alignment:NSTextAlignmentCenter];
    [content addSubview:self.resizeNoticeLabel];

    self.statusLabel = [self label:@"Connect the AULA keyboard in wired USB mode before uploading." frame:NSMakeRect(24, 86, 472, 18) size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor alignment:NSTextAlignmentCenter];
    [content addSubview:self.statusLabel];

    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(24, 62, 472, 12)];
    self.progress.minValue = 0;
    self.progress.maxValue = 100;
    self.progress.doubleValue = 0;
    self.progress.indeterminate = NO;
    [content addSubview:self.progress];

    self.uploadButton = [NSButton buttonWithTitle:@"Send to Keyboard" target:self action:@selector(upload:)];
    self.uploadButton.frame = NSMakeRect(184, 22, 152, 32);
    self.uploadButton.bezelStyle = NSBezelStyleRounded;
    self.uploadButton.enabled = NO;
    [content addSubview:self.uploadButton];

    [self applyPreset:KeyboardPresets().firstObject];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color alignment:(NSTextAlignment)alignment {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.alignment = alignment;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    return label;
}

- (NSTextField *)numberField:(NSRect)frame {
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
    field.delegate = self;
    field.alignment = NSTextAlignmentRight;
    field.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
    return field;
}

- (KeyboardPreset *)selectedPreset {
    NSInteger index = self.modelPopup.indexOfSelectedItem;
    NSArray<KeyboardPreset *> *presets = KeyboardPresets();
    if (index < 0 || (NSUInteger)index >= presets.count) {
        return presets.firstObject;
    }
    return presets[(NSUInteger)index];
}

- (void)modelChanged:(id)sender {
    [self applyPreset:self.selectedPreset];
}

- (void)applyPreset:(KeyboardPreset *)preset {
    self.widthField.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)preset.width];
    self.heightField.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)preset.height];
    self.frameLimitField.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)preset.recommendedFrames];
    [self refreshValidation];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    [self refreshValidation];
}

- (NSUInteger)integerFromField:(NSTextField *)field {
    NSInteger value = field.integerValue;
    return value > 0 ? (NSUInteger)value : 0;
}

- (NSUInteger)targetWidth {
    return [self integerFromField:self.widthField];
}

- (NSUInteger)targetHeight {
    return [self integerFromField:self.heightField];
}

- (NSUInteger)frameLimit {
    NSUInteger value = [self integerFromField:self.frameLimitField];
    return value > 255 ? 255 : value;
}

- (BOOL)hasReadableSelection {
    if (self.selectedInfos.count == 0) {
        return NO;
    }
    for (ImageInfo *info in self.selectedInfos) {
        if (!info.readable) {
            return NO;
        }
    }
    return YES;
}

- (NSUInteger)selectedFrameCount {
    NSUInteger total = 0;
    for (ImageInfo *info in self.selectedInfos) {
        total += MAX(info.frames, 1);
    }
    return total;
}

- (unsigned long long)selectedByteCount {
    unsigned long long total = 0;
    for (ImageInfo *info in self.selectedInfos) {
        total += info.bytes;
    }
    return total;
}

- (void)refreshValidation {
    KeyboardPreset *preset = self.selectedPreset;
    NSUInteger width = self.targetWidth;
    NSUInteger height = self.targetHeight;
    NSUInteger frameLimit = self.frameLimit;
    BOOL validTarget = width > 0 && height > 0 && frameLimit > 0;

    self.targetLabel.stringValue = [NSString stringWithFormat:@"%@ preset: %lu x %lu, recommended max %lu frames. Current target: %lu x %lu, sending up to %lu frame%@.",
        preset.name,
        (unsigned long)preset.width,
        (unsigned long)preset.height,
        (unsigned long)preset.recommendedFrames,
        (unsigned long)width,
        (unsigned long)height,
        (unsigned long)frameLimit,
        frameLimit == 1 ? @"" : @"s"
    ];

    if (!validTarget) {
        self.statusLabel.textColor = NSColor.systemRedColor;
        self.statusLabel.stringValue = @"Width, height, and frame limit must be positive numbers.";
        self.resizeNoticeLabel.textColor = NSColor.secondaryLabelColor;
        self.resizeNoticeLabel.stringValue = @"Images that do not match the target size are resized before upload.";
        self.uploadButton.enabled = NO;
        return;
    }

    if (self.selectedInfos.count == 0) {
        self.statusLabel.textColor = NSColor.secondaryLabelColor;
        self.statusLabel.stringValue = @"Connect the AULA keyboard in wired USB mode before uploading.";
        self.resizeNoticeLabel.textColor = NSColor.secondaryLabelColor;
        self.resizeNoticeLabel.stringValue = @"Images that do not match the target size are resized before upload.";
        self.uploadButton.enabled = NO;
        return;
    }

    for (ImageInfo *info in self.selectedInfos) {
        if (!info.readable) {
            self.statusLabel.textColor = NSColor.systemRedColor;
            self.statusLabel.stringValue = info.status ?: @"Unsupported image file.";
            self.resizeNoticeLabel.textColor = NSColor.systemRedColor;
            self.resizeNoticeLabel.stringValue = @"Cannot inspect one of the selected files for resizing.";
            self.uploadButton.enabled = NO;
            return;
        }
    }

    NSUInteger sourceFrames = self.selectedFrameCount;
    NSUInteger sentFrames = MIN(sourceFrames, frameLimit);
    BOOL multipleFiles = self.selectedInfos.count > 1;
    ImageInfo *firstInfo = self.selectedInfos.firstObject;
    BOOL willResize = multipleFiles || firstInfo.width != width || firstInfo.height != height;
    BOOL willTrim = sourceFrames > frameLimit;

    NSMutableArray<NSString *> *notes = [NSMutableArray array];
    if (self.selectionWasCapped) {
        [notes addObject:[NSString stringWithFormat:@"using first %lu files", (unsigned long)MaxInputFiles]];
    }
    [notes addObject:multipleFiles ? [NSString stringWithFormat:@"will merge %lu files", (unsigned long)self.selectedInfos.count] : (willResize ? [NSString stringWithFormat:@"will resize to %lu x %lu", (unsigned long)width, (unsigned long)height] : @"size matches target")];
    [notes addObject:willTrim ? [NSString stringWithFormat:@"will trim %lu to %lu frames", (unsigned long)sourceFrames, (unsigned long)sentFrames] : [NSString stringWithFormat:@"will send %lu frame%@", (unsigned long)sentFrames, sentFrames == 1 ? @"" : @"s"]];

    self.resizeNoticeLabel.textColor = willResize ? NSColor.systemOrangeColor : NSColor.secondaryLabelColor;
    if (multipleFiles) {
        self.resizeNoticeLabel.stringValue = [NSString stringWithFormat:@"Merge required: selected files will become one GIF fitted into %lu x %lu.", (unsigned long)width, (unsigned long)height];
    } else if (willResize) {
        self.resizeNoticeLabel.stringValue = [NSString stringWithFormat:@"Resize required: %lu x %lu will be fitted into %lu x %lu before upload.",
            (unsigned long)firstInfo.width,
            (unsigned long)firstInfo.height,
            (unsigned long)width,
            (unsigned long)height
        ];
    } else {
        self.resizeNoticeLabel.stringValue = [NSString stringWithFormat:@"No resize needed: source already matches %lu x %lu.", (unsigned long)width, (unsigned long)height];
    }

    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Ready: %@.", [notes componentsJoinedByString:@", "]];
    self.uploadButton.enabled = YES;
}

- (void)chooseFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    panel.allowedContentTypes = @[UTTypeGIF, UTTypePNG, UTTypeJPEG, UTTypeImage];
    if ([panel runModal] == NSModalResponseOK) {
        [self selectURLs:panel.URLs];
    }
}

- (void)selectURLs:(NSArray<NSURL *> *)urls {
    NSUInteger count = MIN(urls.count, MaxInputFiles);
    self.selectionWasCapped = urls.count > MaxInputFiles;
    NSMutableArray<ImageInfo *> *infos = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger index = 0; index < count; index++) {
        [infos addObject:InspectImage(urls[index])];
    }
    self.selectedInfos = infos;
    self.progress.doubleValue = 0;

    if (infos.count == 1) {
        ImageInfo *info = infos.firstObject;
        NSURL *url = urls.firstObject;
        self.titleLabel.stringValue = url.lastPathComponent ?: @"Selected file";
        self.detailsLabel.stringValue = [NSString stringWithFormat:@"%lu x %lu | %lu frame%@ | %@",
            (unsigned long)info.width,
            (unsigned long)info.height,
            (unsigned long)info.frames,
            info.frames == 1 ? @"" : @"s",
            HumanSize(info.bytes)
        ];
    } else {
        NSUInteger frames = self.selectedFrameCount;
        self.titleLabel.stringValue = [NSString stringWithFormat:@"%lu files selected", (unsigned long)infos.count];
        self.detailsLabel.stringValue = [NSString stringWithFormat:@"Will merge into one GIF | %lu total frames | %@",
            (unsigned long)frames,
            HumanSize(self.selectedByteCount)
        ];
    }
    [self refreshValidation];
}

- (void)setBusy:(BOOL)busy {
    self.modelPopup.enabled = !busy;
    self.widthField.enabled = !busy;
    self.heightField.enabled = !busy;
    self.frameLimitField.enabled = !busy;
    self.chooseButton.enabled = !busy;
    self.uploadButton.enabled = !busy && self.hasReadableSelection && self.targetWidth > 0 && self.targetHeight > 0 && self.frameLimit > 0;
}

- (NSURL *)probeURL {
    return [[[NSBundle mainBundle] executableURL].URLByDeletingLastPathComponent URLByAppendingPathComponent:@"F75Probe"];
}

- (NSDictionary *)gifFramePropertiesForSource:(CGImageSourceRef)source index:(size_t)index {
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, index, NULL));
    NSDictionary *gif = properties[(NSString *)kCGImagePropertyGIFDictionary];
    NSNumber *delay = gif[(NSString *)kCGImagePropertyGIFUnclampedDelayTime] ?: gif[(NSString *)kCGImagePropertyGIFDelayTime];
    double seconds = delay.doubleValue > 0.0 ? delay.doubleValue : 0.12;
    return @{
        (NSString *)kCGImagePropertyGIFDictionary: @{
            (NSString *)kCGImagePropertyGIFDelayTime: @(seconds)
        }
    };
}

- (NSURL *)mergedGIFURLWithFrameLimit:(NSUInteger)frameLimit error:(NSError **)error {
    NSUInteger totalFrames = MIN(self.selectedFrameCount, frameLimit);
    if (totalFrames == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"AulaGifUploader" code:1 userInfo:@{NSLocalizedDescriptionKey: @"No frames to merge."}];
        }
        return nil;
    }

    NSString *fileName = [NSString stringWithFormat:@"AulaGifUploader-%@.gif", NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, (__bridge CFStringRef)UTTypeGIF.identifier, totalFrames, NULL);
    if (!destination) {
        if (error) {
            *error = [NSError errorWithDomain:@"AulaGifUploader" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Could not create merged GIF."}];
        }
        return nil;
    }

    NSDictionary *gifProperties = @{
        (NSString *)kCGImagePropertyGIFDictionary: @{
            (NSString *)kCGImagePropertyGIFLoopCount: @0
        }
    };
    CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)gifProperties);

    NSUInteger written = 0;
    for (ImageInfo *info in self.selectedInfos) {
        if (written >= totalFrames) {
            break;
        }
        NSURL *sourceURL = [NSURL fileURLWithPath:info.path];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)sourceURL, NULL);
        if (!source) {
            continue;
        }

        size_t count = MAX(CGImageSourceGetCount(source), 1);
        for (size_t index = 0; index < count && written < totalFrames; index++) {
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, index, NULL);
            if (!image) {
                continue;
            }
            NSDictionary *frameProperties = [self gifFramePropertiesForSource:source index:index];
            CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)frameProperties);
            CGImageRelease(image);
            written++;
        }
        CFRelease(source);
    }

    BOOL finalized = CGImageDestinationFinalize(destination);
    CFRelease(destination);

    if (!finalized || written == 0) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        if (error) {
            *error = [NSError errorWithDomain:@"AulaGifUploader" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Could not finalize merged GIF."}];
        }
        return nil;
    }

    return url;
}

- (void)upload:(id)sender {
    if (!self.hasReadableSelection || self.targetWidth == 0 || self.targetHeight == 0 || self.frameLimit == 0) {
        return;
    }

    NSURL *probe = [self probeURL];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:probe.path]) {
        [self fail:@"Bundled F75Probe helper is missing."];
        return;
    }

    self.temporaryUploadURL = nil;
    NSURL *uploadURL = [NSURL fileURLWithPath:self.selectedInfos.firstObject.path];
    if (self.selectedInfos.count > 1) {
        NSError *mergeError = nil;
        uploadURL = [self mergedGIFURLWithFrameLimit:self.frameLimit error:&mergeError];
        if (!uploadURL) {
            [self fail:mergeError.localizedDescription ?: @"Could not merge selected files."];
            return;
        }
        self.temporaryUploadURL = uploadURL;
    }

    self.progress.doubleValue = 1;
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    self.statusLabel.stringValue = self.selectedInfos.count > 1 ? @"Merging complete. Uploading..." : @"Uploading...";
    [self setBusy:YES];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = probe;
    task.currentDirectoryURL = probe.URLByDeletingLastPathComponent;
    task.arguments = @[
        @"--wired",
        @"--screen-upload-image", uploadURL.path,
        @"--screen-width", [NSString stringWithFormat:@"%lu", (unsigned long)self.targetWidth],
        @"--screen-height", [NSString stringWithFormat:@"%lu", (unsigned long)self.targetHeight],
        @"--screen-max-frames", [NSString stringWithFormat:@"%lu", (unsigned long)self.frameLimit],
        @"--screen-fit", @"contain",
        @"--screen-pixel-format", @"rgb565le",
        @"--screen-pixel-layout", @"row",
        @"--screen-slot", @"1",
        @"--screen-chunk-ack",
        @"--screen-chunk-delay", @"0.005",
        @"--seconds", @"1"
    ];

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    self.uploadTask = task;

    __weak typeof(self) weakSelf = self;
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        if (data.length == 0) {
            return;
        }
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        [weakSelf parseProgress:text];
    };

    task.terminationHandler = ^(NSTask *finishedTask) {
        pipe.fileHandleForReading.readabilityHandler = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf setBusy:NO];
            weakSelf.uploadTask = nil;
            if (weakSelf.temporaryUploadURL) {
                [[NSFileManager defaultManager] removeItemAtURL:weakSelf.temporaryUploadURL error:nil];
                weakSelf.temporaryUploadURL = nil;
            }
            if (finishedTask.terminationStatus == 0) {
                weakSelf.progress.doubleValue = 100;
                weakSelf.statusLabel.textColor = NSColor.systemGreenColor;
                weakSelf.statusLabel.stringValue = @"Complete!";
            } else {
                weakSelf.statusLabel.textColor = NSColor.systemRedColor;
                weakSelf.statusLabel.stringValue = [NSString stringWithFormat:@"Upload failed (%d). Check wired USB mode and permissions.", finishedTask.terminationStatus];
            }
        });
    };

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [self setBusy:NO];
        if (self.temporaryUploadURL) {
            [[NSFileManager defaultManager] removeItemAtURL:self.temporaryUploadURL error:nil];
            self.temporaryUploadURL = nil;
        }
        [self fail:error.localizedDescription ?: @"Could not start upload helper."];
    }
}

- (void)parseProgress:(NSString *)text {
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"chunk ([0-9]+)/([0-9]+)" options:0 error:nil];
    for (NSString *line in lines) {
        NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (match.numberOfRanges == 3) {
            NSInteger current = [[line substringWithRange:[match rangeAtIndex:1]] integerValue];
            NSInteger total = [[line substringWithRange:[match rangeAtIndex:2]] integerValue];
            if (total > 0) {
                double percent = MAX(1.0, MIN(99.0, ((double)current / (double)total) * 100.0));
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.progress.doubleValue = percent;
                    self.statusLabel.stringValue = [NSString stringWithFormat:@"Uploading... %ld/%ld", (long)current, (long)total];
                });
            }
        }
    }
}

- (void)fail:(NSString *)message {
    self.statusLabel.textColor = NSColor.systemRedColor;
    self.statusLabel.stringValue = message;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"AULA GIF Uploader";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
