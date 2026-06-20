#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const NSUInteger MaxAllowedFrames = 120;

@interface ImageInfo : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic) NSUInteger width;
@property(nonatomic) NSUInteger height;
@property(nonatomic) NSUInteger frames;
@property(nonatomic) unsigned long long bytes;
@property(nonatomic) BOOL animated;
@property(nonatomic, copy) NSString *status;
@property(nonatomic) BOOL acceptable;
@end

@implementation ImageInfo
@end

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
        info.acceptable = NO;
        return info;
    }

    size_t frameCount = CGImageSourceGetCount(source);
    info.frames = MAX((NSUInteger)frameCount, 1);
    info.animated = info.frames > 1;

    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    info.width = [properties[(NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
    info.height = [properties[(NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    CFRelease(source);

    if (info.frames > MaxAllowedFrames) {
        info.status = [NSString stringWithFormat:@"Too many frames: %lu / %lu", (unsigned long)info.frames, (unsigned long)MaxAllowedFrames];
        info.acceptable = NO;
        return info;
    }

    if (info.width == 0 || info.height == 0) {
        info.status = @"Could not read image dimensions.";
        info.acceptable = NO;
        return info;
    }

    if (info.width == 128 && info.height == 128) {
        info.status = @"Ready. 128 x 128 image will upload as-is.";
    } else {
        info.status = @"Ready. The uploader will resize/crop to 128 x 128.";
    }
    info.acceptable = YES;
    return info;
}

@interface DropView : NSView
@property(nonatomic, copy) void (^fileHandler)(NSURL *url);
@property(nonatomic, strong) NSColor *borderColor;
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
    NSURL *url = [NSURL URLFromPasteboard:sender.draggingPasteboard];
    if (url && self.fileHandler) {
        self.fileHandler(url);
        return YES;
    }
    return NO;
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *detailsLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSButton *chooseButton;
@property(nonatomic, strong) NSButton *uploadButton;
@property(nonatomic, strong) NSProgressIndicator *progress;
@property(nonatomic, strong) ImageInfo *selectedInfo;
@property(nonatomic, strong) NSTask *uploadTask;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildWindow];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 440, 300)
                                             styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"F75 GIF Uploader";
    self.window.releasedWhenClosed = NO;
    [self.window center];

    NSView *content = self.window.contentView;
    DropView *drop = [[DropView alloc] initWithFrame:NSMakeRect(24, 86, 392, 158)];
    __weak typeof(self) weakSelf = self;
    drop.fileHandler = ^(NSURL *url) {
        [weakSelf selectURL:url];
    };
    [content addSubview:drop];

    self.titleLabel = [self label:@"Drop image/GIF here" frame:NSMakeRect(48, 188, 344, 26) size:18 weight:NSFontWeightSemibold color:NSColor.labelColor alignment:NSTextAlignmentCenter];
    [content addSubview:self.titleLabel];

    self.detailsLabel = [self label:@"128 x 128 target, max 120 frames" frame:NSMakeRect(48, 145, 344, 42) size:13 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor alignment:NSTextAlignmentCenter];
    self.detailsLabel.maximumNumberOfLines = 2;
    [content addSubview:self.detailsLabel];

    self.chooseButton = [NSButton buttonWithTitle:@"Choose Image/GIF" target:self action:@selector(chooseFile:)];
    self.chooseButton.frame = NSMakeRect(144, 104, 152, 32);
    self.chooseButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:self.chooseButton];

    self.statusLabel = [self label:@"Connect F75 Max in wired USB mode before uploading." frame:NSMakeRect(24, 58, 392, 18) size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor alignment:NSTextAlignmentCenter];
    [content addSubview:self.statusLabel];

    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(24, 34, 392, 12)];
    self.progress.minValue = 0;
    self.progress.maxValue = 100;
    self.progress.doubleValue = 0;
    self.progress.indeterminate = NO;
    [content addSubview:self.progress];

    self.uploadButton = [NSButton buttonWithTitle:@"Send to F75 Max" target:self action:@selector(upload:)];
    self.uploadButton.frame = NSMakeRect(148, 252, 144, 32);
    self.uploadButton.bezelStyle = NSBezelStyleRounded;
    self.uploadButton.enabled = NO;
    [content addSubview:self.uploadButton];

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

- (void)chooseFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    if (@available(macOS 12.0, *)) {
        panel.allowedContentTypes = @[UTTypeGIF, UTTypePNG, UTTypeJPEG, UTTypeImage];
    } else {
        panel.allowedFileTypes = @[@"gif", @"png", @"jpg", @"jpeg"];
    }
    if ([panel runModal] == NSModalResponseOK) {
        [self selectURL:panel.URL];
    }
}

- (void)selectURL:(NSURL *)url {
    ImageInfo *info = InspectImage(url);
    self.selectedInfo = info;
    self.progress.doubleValue = 0;

    NSString *name = url.lastPathComponent ?: @"Selected file";
    self.titleLabel.stringValue = name;
    self.detailsLabel.stringValue = [NSString stringWithFormat:@"%lu x %lu | %lu frame%@ | %@",
        (unsigned long)info.width,
        (unsigned long)info.height,
        (unsigned long)info.frames,
        info.frames == 1 ? @"" : @"s",
        HumanSize(info.bytes)
    ];
    self.statusLabel.stringValue = info.status ?: @"Ready.";
    self.statusLabel.textColor = info.acceptable ? NSColor.secondaryLabelColor : NSColor.systemRedColor;
    self.uploadButton.enabled = info.acceptable;
}

- (void)setBusy:(BOOL)busy {
    self.chooseButton.enabled = !busy;
    self.uploadButton.enabled = !busy && self.selectedInfo.acceptable;
}

- (NSURL *)probeURL {
    return [[[NSBundle mainBundle] executableURL].URLByDeletingLastPathComponent URLByAppendingPathComponent:@"F75Probe"];
}

- (void)upload:(id)sender {
    if (!self.selectedInfo.acceptable) {
        return;
    }

    NSURL *probe = [self probeURL];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:probe.path]) {
        [self fail:@"Bundled F75Probe helper is missing."];
        return;
    }

    self.progress.doubleValue = 1;
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    self.statusLabel.stringValue = @"Uploading...";
    [self setBusy:YES];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = probe;
    task.currentDirectoryURL = probe.URLByDeletingLastPathComponent;
    task.arguments = @[
        @"--wired",
        @"--screen-upload-image", self.selectedInfo.path,
        @"--screen-max-frames", [NSString stringWithFormat:@"%lu", (unsigned long)MaxAllowedFrames],
        @"--screen-fit", @"cover",
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
    alert.messageText = @"F75 GIF Uploader";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
