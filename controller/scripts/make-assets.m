// Icone e immagine di avvio di similFranz Controller (AppKit, su Mac): fondo scuro, tre cursori di regolazione.
#import <AppKit/AppKit.h>
static void Save(NSBitmapImageRep *rep, NSString *path) { [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]; }
static NSBitmapImageRep *Canvas(int w, int h) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    return rep;
}
static void Icon(int s, NSString *path) {
    NSBitmapImageRep *rep = Canvas(s, s); CGFloat k = s / 152.0;
    [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithRed:.09 green:.12 blue:.16 alpha:1] endingColor:[NSColor colorWithRed:.03 green:.04 blue:.06 alpha:1]] drawInRect:NSMakeRect(0, 0, s, s) angle:-90];
    NSArray *cols = @[[NSColor colorWithRed:.24 green:.92 blue:.45 alpha:1], [NSColor colorWithRed:.24 green:.84 blue:1 alpha:1], [NSColor colorWithRed:1 green:.36 blue:.32 alpha:1]];
    CGFloat pos[] = {0.68, 0.36, 0.56};
    for (int i = 0; i < 3; i++) {
        CGFloat y = (106 - i * 30) * k, x0 = 26 * k, x1 = 126 * k, kx = x0 + (x1 - x0) * pos[i];
        NSBezierPath *tr = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x0, y - 3 * k, x1 - x0, 6 * k) xRadius:3 * k yRadius:3 * k];
        [[NSColor colorWithWhite:1 alpha:.14] setFill]; [tr fill];
        NSBezierPath *fl = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x0, y - 3 * k, kx - x0, 6 * k) xRadius:3 * k yRadius:3 * k];
        [cols[i] setFill]; [fl fill];
        [[NSColor whiteColor] setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(kx - 10 * k, y - 10 * k, 20 * k, 20 * k)] fill];
    }
    Save(rep, path);
}
static void Launch(int w, int h, NSString *path) {
    NSBitmapImageRep *rep = Canvas(w, h);
    [[NSColor colorWithRed:.035 green:.045 blue:.06 alpha:1] setFill]; NSRectFill(NSMakeRect(0, 0, w, h));
    Save(rep, path);
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    NSString *o = @(argv[1]);
    Icon(76, [o stringByAppendingPathComponent:@"AppIcon76x76.png"]); Icon(152, [o stringByAppendingPathComponent:@"AppIcon76x76@2x.png"]);
    Icon(40, [o stringByAppendingPathComponent:@"AppIcon40x40.png"]); Icon(80, [o stringByAppendingPathComponent:@"AppIcon40x40@2x.png"]);
    Icon(29, [o stringByAppendingPathComponent:@"AppIcon29x29.png"]); Icon(58, [o stringByAppendingPathComponent:@"AppIcon29x29@2x.png"]);
    Launch(1024, 768, [o stringByAppendingPathComponent:@"LaunchImage-Landscape~ipad.png"]); Launch(2048, 1536, [o stringByAppendingPathComponent:@"LaunchImage-Landscape@2x~ipad.png"]);
} return 0; }
