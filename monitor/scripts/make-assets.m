// Genera icone e launch image di SimulaFranz_Monitor con AppKit/Core Graphics (macOS).
// Uso: scripts/make-assets.sh  (compila ed esegue questo file, output in assets/)
#import <AppKit/AppKit.h>

static NSColor *RGB(int r, int g, int b, CGFloat a) { return [NSColor colorWithSRGBRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a]; }

static void SavePNG(NSBitmapImageRep *rep, NSString *path) {
    NSData *d = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [d writeToFile:path atomically:YES];
    printf("  %s (%ldx%ld)\n", path.lastPathComponent.UTF8String, (long)rep.pixelsWide, (long)rep.pixelsHigh);
}

static NSBitmapImageRep *Canvas(NSInteger w, NSInteger h) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    rep.size = NSMakeSize(w, h);
    return rep;
}

// Complesso PQRST armonico: somma di gaussiane (P, Q, R, S, T) campionata finemente -> curva continua e morbida
static CGFloat PQRST(CGFloat x) {   // x in 0..1 dentro il battito, risultato circa -0.4..1
    #define G(mu, sg, a) ((a) * exp(-0.5 * pow((x - (mu)) / (sg), 2)))
    return G(.18, .028, .13) + G(.345, .010, -.13) + G(.38, .012, 1.0) + G(.415, .011, -.30) + G(.62, .055, .30);
    #undef G
}
static NSBezierPath *ECGPath(NSRect r, int beats) {
    NSBezierPath *p = [NSBezierPath bezierPath];
    int n = 900 * beats;
    for (int i = 0; i <= n; i++) {
        CGFloat x = (CGFloat)i / n, ph = fmod(x * beats, 1.0);
        NSPoint q = NSMakePoint(r.origin.x + x * r.size.width, NSMidY(r) + PQRST(ph) * r.size.height / 2);
        if (i == 0) [p moveToPoint:q]; else [p lineToPoint:q];
    }
    p.lineJoinStyle = NSLineJoinStyleRound; p.lineCapStyle = NSLineCapStyleRound;
    return p;
}

static NSBezierPath *PlethPath(NSRect r, int beats) {
    NSBezierPath *p = [NSBezierPath bezierPath];
    int n = 200;
    for (int i = 0; i <= n; i++) {
        CGFloat x = (CGFloat)i / n, ph = fmod(x * beats, 1.0);
        CGFloat y = ph < .25 ? sin(ph / .25 * M_PI / 2) : exp(-(ph - .25) / .30) * (1 + .12 * exp(-pow((ph - .45) / .05, 2)));
        NSPoint q = NSMakePoint(r.origin.x + x * r.size.width, r.origin.y + y * r.size.height);
        if (i == 0) [p moveToPoint:q]; else [p lineToPoint:q];
    }
    p.lineJoinStyle = NSLineJoinStyleRound; p.lineCapStyle = NSLineCapStyleRound;
    return p;
}

static void Glow(NSBezierPath *p, NSColor *c, CGFloat width, CGFloat blur) {
    [NSGraphicsContext saveGraphicsState];
    NSShadow *sh = [NSShadow new]; sh.shadowColor = [c colorWithAlphaComponent:.9]; sh.shadowBlurRadius = blur; sh.shadowOffset = NSZeroSize;
    [sh set];
    [c setStroke]; p.lineWidth = width; [p stroke];
    [NSGraphicsContext restoreGraphicsState];
    [[NSColor colorWithWhite:1 alpha:.35] setStroke]; p.lineWidth = MAX(1, width * .28); [p stroke];   // anima chiara della traccia
}

static void Grid(NSRect r, CGFloat step, NSColor *c) {
    [c setStroke];
    NSBezierPath *g = [NSBezierPath bezierPath]; g.lineWidth = 1;
    for (CGFloat x = r.origin.x; x <= NSMaxX(r); x += step) { [g moveToPoint:NSMakePoint(x, r.origin.y)]; [g lineToPoint:NSMakePoint(x, NSMaxY(r))]; }
    for (CGFloat y = r.origin.y; y <= NSMaxY(r); y += step) { [g moveToPoint:NSMakePoint(r.origin.x, y)]; [g lineToPoint:NSMakePoint(NSMaxX(r), y)]; }
    [g stroke];
}

static void Icon(NSInteger S, NSString *path) {
    NSBitmapImageRep *rep = Canvas(S, S);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    NSRect R = NSMakeRect(0, 0, S, S);
    NSGradient *bg = [[NSGradient alloc] initWithColors:@[RGB(22, 58, 82, 1), RGB(8, 20, 32, 1), RGB(3, 7, 12, 1)]];
    [bg drawInRect:R relativeCenterPosition:NSMakePoint(0, .35)];
    if (S >= 58) Grid(R, S / 8.0, RGB(40, 90, 120, .22));
    // traccia ECG (2 battiti) e pletismografia
    Glow(ECGPath(NSMakeRect(-S * .02, S * .36, S * 1.04, S * .50), 2), RGB(60, 255, 110, 1), S * .052, S * .07);
    if (S >= 40) Glow(PlethPath(NSMakeRect(-S * .02, S * .10, S * 1.04, S * .15), 2), RGB(60, 220, 255, 1), S * .030, S * .04);
    [NSGraphicsContext restoreGraphicsState];
    SavePNG(rep, path);
}

static void Launch(NSInteger W, NSInteger H, NSString *path) {
    CGFloat k = W / 1024.0;
    NSBitmapImageRep *rep = Canvas(W, H);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    NSRect R = NSMakeRect(0, 0, W, H);
    NSGradient *bg = [[NSGradient alloc] initWithColors:@[RGB(14, 34, 50, 1), RGB(4, 10, 16, 1), RGB(0, 0, 0, 1)]];
    [bg drawInRect:R relativeCenterPosition:NSMakePoint(0, .15)];
    Grid(R, 32 * k, RGB(40, 90, 120, .10));

    // traccia ECG che attraversa lo schermo
    Glow(ECGPath(NSMakeRect(-20 * k, H * .50, W + 40 * k, 190 * k), 4), RGB(60, 255, 110, 1), 4.5 * k, 14 * k);

    // titolo
    NSShadow *ts = [NSShadow new]; ts.shadowColor = [NSColor colorWithWhite:0 alpha:.8]; ts.shadowBlurRadius = 10 * k; ts.shadowOffset = NSZeroSize;
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:@"SimulaFranz"
        attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:66 * k weight:NSFontWeightLight], NSForegroundColorAttributeName: [NSColor whiteColor], NSShadowAttributeName: ts}];
    [title appendAttributedString:[[NSAttributedString alloc] initWithString:@"_Monitor"
        attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:66 * k weight:NSFontWeightSemibold], NSForegroundColorAttributeName: RGB(60, 255, 110, 1), NSShadowAttributeName: ts}]];
    NSSize ts1 = title.size;
    [title drawAtPoint:NSMakePoint((W - ts1.width) / 2, H * .25)];

    NSDictionary *sub = @{NSFontAttributeName: [NSFont systemFontOfSize:19 * k weight:NSFontWeightRegular], NSForegroundColorAttributeName: RGB(150, 170, 185, 1)};
    NSString *s1 = @"Monitor multiparametrico per la simulazione sanitaria";
    NSSize ss = [s1 sizeWithAttributes:sub];
    [s1 drawAtPoint:NSMakePoint((W - ss.width) / 2, H * .25 - 34 * k) withAttributes:sub];

    NSDictionary *warn = @{NSFontAttributeName: [NSFont systemFontOfSize:14 * k weight:NSFontWeightBold], NSForegroundColorAttributeName: RGB(255, 158, 26, 1),
                           NSKernAttributeName: @(1.5 * k)};
    NSString *s2 = @"SIMULAZIONE — NON PER USO CLINICO";
    NSSize ws = [s2 sizeWithAttributes:warn];
    [s2 drawAtPoint:NSMakePoint((W - ws.width) / 2, 34 * k) withAttributes:warn];
    [NSGraphicsContext restoreGraphicsState];
    SavePNG(rep, path);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *out = argc > 1 ? @(argv[1]) : @"assets";
        printf("Asset SimulaFranz_Monitor -> %s\n", out.UTF8String);
        Icon(76,  [out stringByAppendingPathComponent:@"AppIcon76x76.png"]);
        Icon(152, [out stringByAppendingPathComponent:@"AppIcon76x76@2x.png"]);
        Icon(40,  [out stringByAppendingPathComponent:@"AppIcon40x40.png"]);       // Spotlight
        Icon(80,  [out stringByAppendingPathComponent:@"AppIcon40x40@2x.png"]);
        Icon(29,  [out stringByAppendingPathComponent:@"AppIcon29x29.png"]);       // Impostazioni
        Icon(58,  [out stringByAppendingPathComponent:@"AppIcon29x29@2x.png"]);
        Launch(1024, 768,  [out stringByAppendingPathComponent:@"LaunchImage-Landscape~ipad.png"]);
        Launch(2048, 1536, [out stringByAppendingPathComponent:@"LaunchImage-Landscape@2x~ipad.png"]);   // iPad mini 2 (retina)
    }
    return 0;
}
