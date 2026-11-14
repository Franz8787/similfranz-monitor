// Icone e immagine di avvio di similFranz Pocket (AppKit, su Mac): fondo scuro, rotella con l'arco del valore.
#import <AppKit/AppKit.h>
static void Save(NSBitmapImageRep *rep, NSString *path) { [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]; }
static NSBitmapImageRep *Canvas(int w, int h) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    return rep;
}
static void Icon(int s, NSString *path) {
    NSBitmapImageRep *rep = Canvas(s, s); CGFloat k = s / 120.0, c = s / 2.0;
    [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithRed:.09 green:.12 blue:.16 alpha:1] endingColor:[NSColor colorWithRed:.03 green:.04 blue:.06 alpha:1]] drawInRect:NSMakeRect(0, 0, s, s) angle:-90];
    // binario dell'arco (da 225° a -45°, come un quadrante)
    NSBezierPath *tr = [NSBezierPath bezierPath]; [tr appendBezierPathWithArcWithCenter:NSMakePoint(c, c) radius:40 * k startAngle:225 endAngle:-45 clockwise:YES];
    tr.lineWidth = 9 * k; tr.lineCapStyle = NSLineCapStyleRound; [[NSColor colorWithWhite:1 alpha:.14] setStroke]; [tr stroke];
    NSBezierPath *ar = [NSBezierPath bezierPath]; [ar appendBezierPathWithArcWithCenter:NSMakePoint(c, c) radius:40 * k startAngle:225 endAngle:40 clockwise:YES];
    ar.lineWidth = 9 * k; ar.lineCapStyle = NSLineCapStyleRound; [[NSColor colorWithRed:.24 green:.92 blue:.45 alpha:1] setStroke]; [ar stroke];
    // rotella con le tacche
    [[NSColor colorWithRed:.16 green:.19 blue:.24 alpha:1] setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c - 27 * k, c - 27 * k, 54 * k, 54 * k)] fill];
    [[NSColor colorWithWhite:1 alpha:.25] setStroke];
    for (int i = 0; i < 24; i++) {
        CGFloat a = i * M_PI / 12; NSBezierPath *t = [NSBezierPath bezierPath]; t.lineWidth = 1.6 * k;
        [t moveToPoint:NSMakePoint(c + cos(a) * 20 * k, c + sin(a) * 20 * k)]; [t lineToPoint:NSMakePoint(c + cos(a) * 25 * k, c + sin(a) * 25 * k)]; [t stroke];
    }
    CGFloat a = 40 * M_PI / 180;
    [[NSColor whiteColor] setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c + cos(a) * 40 * k - 8 * k, c + sin(a) * 40 * k - 8 * k, 16 * k, 16 * k)] fill];
    Save(rep, path);
}
static void Launch(int w, int h, NSString *path) {
    NSBitmapImageRep *rep = Canvas(w, h);
    [[NSColor colorWithRed:.035 green:.045 blue:.06 alpha:1] setFill]; NSRectFill(NSMakeRect(0, 0, w, h));
    Save(rep, path);
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    NSString *o = @(argv[1]);
    Icon(120, [o stringByAppendingPathComponent:@"AppIcon60x60@2x.png"]); Icon(80, [o stringByAppendingPathComponent:@"AppIcon40x40@2x.png"]);
    Icon(58, [o stringByAppendingPathComponent:@"AppIcon29x29@2x.png"]);
    Launch(640, 1136, [o stringByAppendingPathComponent:@"LaunchImage-568h@2x.png"]);
} return 0; }
