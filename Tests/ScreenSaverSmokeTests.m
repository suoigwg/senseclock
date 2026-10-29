#import <AppKit/AppKit.h>
#import <ScreenSaver/ScreenSaver.h>

// Loads the built plugin exactly through its declared principal class, rather
// than linking its Swift source into the test executable.
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        [NSApplication sharedApplication];
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error = nil;
        if (![bundle loadAndReturnError:&error]) {
            NSLog(@"Bundle load failed: %@", error);
            return 1;
        }
        for (NSString *asset in @[@"cloud-day", @"cloud-storm", @"moon"]) {
            NSCAssert([bundle URLForResource:asset withExtension:@"png" subdirectory:@"Weather"] != nil,
                      @"Photographic asset missing from bundle: %@", asset);
        }
        Class principal = bundle.principalClass;
        NSCAssert([principal isSubclassOfClass:ScreenSaverView.class], @"ScreenSaverView principal class missing");
        for (NSNumber *preview in @[@YES, @NO]) {
            NSRect frame = preview.boolValue ? NSMakeRect(0, 0, 320, 180) : NSMakeRect(0, 0, 1920, 1080);
            ScreenSaverView *view = [[principal alloc] initWithFrame:frame isPreview:preview.boolValue];
            NSCAssert(view != nil, @"Initialization failed");
            [view startAnimation];
            [view animateOneFrame];
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                pixelsWide:frame.size.width pixelsHigh:frame.size.height bitsPerSample:8
                samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                bytesPerRow:0 bitsPerPixel:0];
            [NSGraphicsContext saveGraphicsState];
            NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
            [view drawRect:frame];
            [NSGraphicsContext restoreGraphicsState];
            NSCAssert(view.hasConfigureSheet && view.configureSheet != nil, @"Settings sheet missing");
            NSWindow *sheet = view.configureSheet;
            NSWindowStyleMask style = sheet.styleMask;
            sheet.styleMask = NSWindowStyleMaskBorderless;
            NSCAssert(sheet.canBecomeKeyWindow, @"The remote host's borderless settings panel must accept keyboard focus");
            sheet.styleMask = style;
            NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 600)
                styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
            [parent beginSheet:sheet completionHandler:nil];
            NSCAssert(sheet.sheetParent == parent, @"Settings sheet was not attached");
            NSCAssert([NSApp sendAction:NSSelectorFromString(@"cancelSettings") to:view from:nil], @"Cancel action missing");
            NSCAssert(!sheet.isVisible, @"Cancel did not hide the settings sheet");
            [parent orderOut:nil];
            [view stopAnimation];
            NSCAssert(!view.isAnimating, @"Animation timer did not stop");
        }
        puts("Screen saver checks passed: bundle loading, principal class, preview/full-size rendering, settings, start/stop.");
    }
    return 0;
}
