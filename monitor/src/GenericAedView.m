#import "GenericAedView.h"
#import <QuartzCore/QuartzCore.h>
#import "SimulationState.h"
#import "WaveformEngine.h"
#import "SoundEngine.h"
#import "SFLog.h"
#import "SFTactile.h"
#import "SFBolt.h"
#import "SFFlatten.h"

static UIColor *GA(CGFloat r, CGFloat g, CGFloat b) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1]; }
// Tavolozza sobria: corpo grigio chiaro opaco, pannelli a filetto, un solo colore per la scarica (rosso scuro)
// e uno per lo stato (verde). Nessun riempimento saturo.
#define GA_BODY1  GA(214, 216, 213)
#define GA_BODY2  GA(190, 193, 190)
#define GA_PANEL  GA(226, 228, 225)
#define GA_LINE   GA(150, 154, 152)
#define GA_INK    GA(44, 48, 52)
#define GA_INK2   GA(96, 102, 106)
#define GA_DARK   GA(52, 56, 61)
#define GA_SHOCK  GA(150, 44, 34)
#define GA_LEDOFF GA(150, 154, 152)
#define GA_LEDON  GA(70, 200, 110)
#define PLUG_OUT  130         // spina fuori dalla presa: spostata a destra di tanto

@implementation GenericAedView {
    NSInteger _cprTotal;      // durata della RCP del ciclo in corso (letta una volta)
    SimulationState *_state; WaveformEngine *_engine; SoundEngine *_sound;
    SLSnapshot *_snap;
    BOOL _on, _child, _flattened;
    NSMutableDictionary<NSString *, UIButton *> *_keys;
    UIView *_shockRing;
    UIView *_screen, *_offCover, *_plug, *_plugNose, *_childLed, *_statusLamp, *_socketLamp, *_barTrack, *_barFill, *_beat;
    UILabel *_status, *_padsState, *_hint, *_cprHint;
    BOOL _plugIn;
    NSArray<UIView *> *_stepLed;
    UILabel *_patient, *_elapsed, *_big, *_cprTitle, *_cprTime, *_shocks, *_energy;
    NSTimeInterval _onAt, _lastSlow;
}

- (instancetype)initWithFrame:(CGRect)frame state:(SimulationState *)state engine:(WaveformEngine *)engine sound:(SoundEngine *)sound {
    if ((self = [super initWithFrame:frame])) {
        _state = state; _engine = engine; _sound = sound;
        _keys = [NSMutableDictionary dictionary];
        _snap = [state snapshot];
        self.backgroundColor = GA(20, 21, 23);
        [self buildBody];
        [self buildScreen];
        [self updateWithSnapshot:_snap];
    }
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window || _flattened) return;
    _flattened = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray *keep = [NSMutableArray arrayWithObjects:self->_plug, self->_statusLamp, self->_status, self->_socketLamp, self->_shockRing, self->_padsState, self->_hint, nil];
        [keep addObjectsFromArray:self->_stepLed];
        SFFlattenStatic(self, keep);
    });
}

#pragma mark - Utilità

- (UIView *)box:(CGRect)f color:(UIColor *)c radius:(CGFloat)r in:(UIView *)v {
    UIView *b = [[UIView alloc] initWithFrame:f];
    b.backgroundColor = c; b.layer.cornerRadius = r; b.userInteractionEnabled = NO;
    [v addSubview:b];
    return b;
}
- (UILabel *)label:(CGRect)f in:(UIView *)v size:(CGFloat)size bold:(BOOL)bold color:(UIColor *)c align:(NSTextAlignment)a {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.backgroundColor = [UIColor clearColor]; l.textColor = c; l.textAlignment = a;
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.5; l.userInteractionEnabled = NO;
    [v addSubview:l];
    return l;
}
- (CAGradientLayer *)gradient:(CGRect)f colors:(NSArray<UIColor *> *)cols radius:(CGFloat)r in:(UIView *)v {
    UIView *h = [[UIView alloc] initWithFrame:f]; h.userInteractionEnabled = NO; h.layer.cornerRadius = r;
    CAGradientLayer *g = [CAGradientLayer layer]; g.frame = h.bounds; g.cornerRadius = r;
    NSMutableArray *cg = [NSMutableArray array]; for (UIColor *c in cols) [cg addObject:(id)c.CGColor];
    g.colors = cg; [h.layer addSublayer:g]; [v addSubview:h];
    return g;
}
- (CAShapeLayer *)shape:(UIBezierPath *)p fill:(UIColor *)f stroke:(UIColor *)st width:(CGFloat)w in:(UIView *)v {
    CAShapeLayer *l = [CAShapeLayer layer];
    l.path = p.CGPath; l.fillColor = (f ?: [UIColor clearColor]).CGColor; l.strokeColor = (st ?: [UIColor clearColor]).CGColor;
    l.lineWidth = w; l.lineCap = kCALineCapRound; l.lineJoin = kCALineJoinRound;
    [v.layer addSublayer:l];
    return l;
}
- (UIButton *)button:(NSString *)name frame:(CGRect)f action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    _keys[name] = b;
    return b;
}

#pragma mark - Scocca

// Geometria (schermo 1024x768): a sinistra resta libera la fascia della targhetta Layout e del riquadro Controller.
// Corpo del dispositivo; in alto la fascia con accensione e stato; al centro schermo + passi illuminati; a destra
// bambino e scarica; in basso il vano delle piastre con la presa del connettore.
static const CGFloat kBX = 164, kBY = 18, kBW = 844, kBH = 734;

// pittogramma al tratto di un passo, disegnato dentro il riquadro r di v
- (void)pictogram:(NSInteger)n in:(UIView *)v rect:(CGRect)r {
    CGFloat x = r.origin.x, y = r.origin.y, w = r.size.width, h = r.size.height;
    UIColor *ink = GA_INK2;
    if (n == 1) {                // accensione
        CGPoint c = CGPointMake(x + w / 2, y + h / 2 + 2); CGFloat rr = MIN(w, h) * 0.34;
        UIBezierPath *pp = [UIBezierPath bezierPathWithArcCenter:c radius:rr startAngle:-M_PI_2 + 0.6 endAngle:-M_PI_2 - 0.6 + 2 * M_PI clockwise:YES];
        [pp moveToPoint:CGPointMake(c.x, c.y - rr - 4)]; [pp addLineToPoint:CGPointMake(c.x, c.y - rr * 0.25)];
        [self shape:pp fill:nil stroke:ink width:2 in:v];
    } else if (n == 2) {         // torso con le due piastre in posizione
        UIBezierPath *t = [UIBezierPath bezierPath];
        [t moveToPoint:CGPointMake(x + w * 0.34, y + h * 0.05)]; [t addQuadCurveToPoint:CGPointMake(x + w * 0.66, y + h * 0.05) controlPoint:CGPointMake(x + w * 0.5, y + h * 0.18)];
        [t addQuadCurveToPoint:CGPointMake(x + w * 0.86, y + h * 0.28) controlPoint:CGPointMake(x + w * 0.84, y + h * 0.07)];
        [t addLineToPoint:CGPointMake(x + w * 0.78, y + h * 0.98)]; [t addLineToPoint:CGPointMake(x + w * 0.22, y + h * 0.98)];
        [t addLineToPoint:CGPointMake(x + w * 0.14, y + h * 0.28)]; [t addQuadCurveToPoint:CGPointMake(x + w * 0.34, y + h * 0.05) controlPoint:CGPointMake(x + w * 0.16, y + h * 0.07)];
        [self shape:t fill:nil stroke:ink width:1.4 in:v];
        [self shape:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x + w * 0.24, y + h * 0.24, w * 0.2, h * 0.24) cornerRadius:2] fill:GA(150, 154, 152) stroke:GA_INK width:0.8 in:v];
        [self shape:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x + w * 0.56, y + h * 0.56, w * 0.2, h * 0.24) cornerRadius:2] fill:GA(150, 154, 152) stroke:GA_INK width:0.8 in:v];
    } else if (n == 3) {         // non toccare: mano aperta barrata
        CGFloat cx = x + w / 2, cy = y + h / 2;
        UIBezierPath *hand = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(cx - 10, cy - 2, 20, 18) cornerRadius:6];
        for (int k = 0; k < 4; k++) [hand appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(cx - 10 + k * 5.2, cy - 16 + (k == 0 || k == 3 ? 4 : 0), 4.2, 16) cornerRadius:2.1]];
        [self shape:hand fill:nil stroke:ink width:1.4 in:v];
        UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:CGPointMake(cx, cy) radius:MIN(w, h) * 0.46 startAngle:0 endAngle:2 * M_PI clockwise:YES];
        [ring moveToPoint:CGPointMake(cx - MIN(w, h) * 0.32, cy - MIN(w, h) * 0.32)]; [ring addLineToPoint:CGPointMake(cx + MIN(w, h) * 0.32, cy + MIN(w, h) * 0.32)];
        [self shape:ring fill:nil stroke:GA(150, 60, 48) width:1.8 in:v];
    } else {                     // scarica
        CGFloat bh = h * 0.8;
        [self shape:SFBoltPath(CGRectMake(x + w * 0.2, y + (h - bh) / 2, w * 0.6, bh)) fill:GA_SHOCK stroke:GA(90, 24, 18) width:0.75 in:v];
    }
}

// riquadro di un passo: spia in alto, numero, pittogramma, didascalia
- (UIView *)stepTile:(NSInteger)n caption:(NSString *)cap frame:(CGRect)f {
    UIView *t = [self box:f color:GA_PANEL radius:7 in:self];
    t.layer.borderWidth = 1; t.layer.borderColor = GA_LINE.CGColor;
    UILabel *num = [self label:CGRectMake(f.origin.x + 8, f.origin.y + 16, 18, 16) in:self size:12 bold:YES color:GA_INK align:NSTextAlignmentLeft];
    num.text = [NSString stringWithFormat:@"%ld", (long)n];
    [self pictogram:n in:self rect:CGRectMake(f.origin.x + 30, f.origin.y + 14, f.size.width - 60, f.size.height - 44)];
    UILabel *c = [self label:CGRectMake(f.origin.x + 4, CGRectGetMaxY(f) - 26, f.size.width - 8, 20) in:self size:10 bold:YES color:GA_INK align:NSTextAlignmentCenter];
    c.text = cap;
    return [self box:CGRectMake(f.origin.x + f.size.width / 2 - 16, f.origin.y + 6, 32, 4) color:GA_LEDOFF radius:2 in:self];
}

- (void)buildBody {
    CGRect body = CGRectMake(kBX, kBY, kBW, kBH);
    // corpo opaco grigio caldo: ombra corta, luce dall'alto appena accennata, filetto chiaro sul bordo
    UIView *sh = [self box:CGRectOffset(body, 0, 3) color:[UIColor blackColor] radius:30 in:self];
    sh.layer.shadowColor = [UIColor blackColor].CGColor; sh.layer.shadowOpacity = 0.5; sh.layer.shadowRadius = 6; sh.layer.shadowOffset = CGSizeMake(0, 3);
    sh.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:sh.bounds cornerRadius:30].CGPath;
    CAGradientLayer *bg = [self gradient:body colors:@[GA(214, 215, 210), GA(196, 198, 193), GA(184, 186, 181)] radius:30 in:self];
    bg.borderWidth = 1; bg.borderColor = GA(236, 237, 233).CGColor;

    // fascia superiore: accensione (1), nome, stato
    UIView *band = [self box:CGRectMake(kBX + 18, kBY + 16, kBW - 36, 74) color:GA_DARK radius:12 in:self];
    band.layer.borderWidth = 1; band.layer.borderColor = GA(30, 33, 36).CGColor;
    UIButton *pw = [self button:@"POWER" frame:CGRectMake(kBX + 34, kBY + 24, 58, 58) action:@selector(kPower)];
    pw.backgroundColor = GA(64, 69, 75); pw.layer.cornerRadius = 29; pw.layer.borderWidth = 2; pw.layer.borderColor = GA(84, 170, 112).CGColor;
    CGPoint pc = CGPointMake(29, 30);
    UIBezierPath *pp = [UIBezierPath bezierPathWithArcCenter:pc radius:11 startAngle:-M_PI_2 + 0.62 endAngle:-M_PI_2 - 0.62 + 2 * M_PI clockwise:YES];
    [pp moveToPoint:CGPointMake(pc.x, pc.y - 16)]; [pp addLineToPoint:CGPointMake(pc.x, pc.y - 3)];
    [self shape:pp fill:nil stroke:GA(150, 225, 170) width:2.6 in:pw];
    [SFTactile applyToFace:pw control:pw radius:29 strength:1];
    UILabel *on = [self label:CGRectMake(kBX + 102, kBY + 34, 120, 16) in:self size:10 bold:YES color:GA(170, 176, 182) align:NSTextAlignmentLeft]; on.text = @"1  ACCENSIONE";
    UILabel *t1 = [self label:CGRectMake(kBX + 102, kBY + 52, 330, 22) in:self size:16 bold:YES color:GA(228, 231, 234) align:NSTextAlignmentLeft];
    t1.text = @"DEFIBRILLATORE SEMIAUTOMATICO";
    // indicatore di stato: finestrella con spia e scritta (il dispositivo si è verificato da solo: pronto all'uso)
    UIView *win = [self box:CGRectMake(kBX + kBW - 190, kBY + 32, 150, 42) color:GA(18, 21, 23) radius:6 in:self];
    win.layer.borderWidth = 1; win.layer.borderColor = GA(110, 116, 120).CGColor;
    _statusLamp = [self box:CGRectMake(kBX + kBW - 178, kBY + 47, 12, 12) color:GA_LEDON radius:6 in:self];
    _status = [self label:CGRectMake(kBX + kBW - 158, kBY + 40, 112, 26) in:self size:13 bold:YES color:GA(200, 230, 210) align:NSTextAlignmentLeft];
    _status.text = @"PRONTO";

    // schermo: cornice scura incassata
    UIView *bez = [self box:CGRectMake(kBX + 22, kBY + 106, 500, 300) color:GA(26, 29, 32) radius:10 in:self];
    bez.layer.borderWidth = 1; bez.layer.borderColor = GA(120, 126, 130).CGColor;

    // passi illuminati sotto lo schermo: la spia si accende sul passo in corso
    NSArray *caps = @[@"ACCENDI", @"COLLEGA LE PIASTRE", @"NON TOCCARE", @"PREMI SCARICA"];
    NSMutableArray *leds = [NSMutableArray array];
    for (NSInteger k = 0; k < 4; k++) [leds addObject:[self stepTile:k + 1 caption:caps[(NSUInteger)k] frame:CGRectMake(kBX + 22 + k * 127, kBY + 418, 119, 92)]];
    _stepLed = leds;

    // colonna destra: paziente pediatrico, poi la scarica
    CGFloat rx = kBX + 540, rw = kBW - 540 - 22;
    UIView *cp = [self box:CGRectMake(rx, kBY + 106, rw, 92) color:GA_PANEL radius:8 in:self];
    cp.layer.borderWidth = 1; cp.layer.borderColor = GA_LINE.CGColor;
    UIButton *ch = [self button:@"CHILD" frame:CGRectMake(rx + 10, kBY + 116, rw - 20, 72) action:@selector(kChild)];
    ch.backgroundColor = GA(232, 233, 229); ch.layer.cornerRadius = 8; ch.layer.borderWidth = 1; ch.layer.borderColor = GA(150, 154, 152).CGColor;
    [SFTactile applyToButton:ch];
    // pittogramma del bambino (testa e corpo al tratto) e testo
    UIBezierPath *kid = [UIBezierPath bezierPathWithArcCenter:CGPointMake(40, 20) radius:7 startAngle:0 endAngle:2 * M_PI clockwise:YES];
    [kid moveToPoint:CGPointMake(40, 28)]; [kid addLineToPoint:CGPointMake(40, 46)];
    [kid moveToPoint:CGPointMake(28, 34)]; [kid addLineToPoint:CGPointMake(52, 34)];
    [kid moveToPoint:CGPointMake(40, 46)]; [kid addLineToPoint:CGPointMake(32, 60)]; [kid moveToPoint:CGPointMake(40, 46)]; [kid addLineToPoint:CGPointMake(48, 60)];
    [self shape:kid fill:nil stroke:GA_INK width:2 in:ch];
    UILabel *kl = [self label:CGRectMake(70, 14, 150, 22) in:ch size:15 bold:YES color:GA_INK align:NSTextAlignmentLeft]; kl.text = @"BAMBINO";
    UILabel *ks = [self label:CGRectMake(70, 38, 150, 18) in:ch size:10.5 bold:NO color:GA_INK2 align:NSTextAlignmentLeft]; ks.text = @"sotto 8 anni o 25 kg";
    _childLed = [self box:CGRectMake(rw - 20 - 30, 30, 14, 14) color:GA_LEDOFF radius:7 in:ch];
    _childLed.layer.borderWidth = 1; _childLed.layer.borderColor = GA(120, 126, 130).CGColor;

    UIView *sp = [self box:CGRectMake(rx, kBY + 210, rw, 300) color:GA_PANEL radius:8 in:self];
    sp.layer.borderWidth = 1; sp.layer.borderColor = GA_LINE.CGColor;
    UILabel *s4 = [self label:CGRectMake(rx + 14, kBY + 222, rw - 28, 18) in:self size:12 bold:YES color:GA_INK align:NSTextAlignmentLeft]; s4.text = @"4  SCARICA";
    // tasto quadrato a spigoli arrotondati, rosso scuro opaco; l'anello attorno si illumina solo a defibrillatore carico
    CGFloat ks2 = 150, kx = rx + (rw - ks2) / 2, ky = kBY + 270;
    _shockRing = [self box:CGRectMake(kx - 12, ky - 12, ks2 + 24, ks2 + 24) color:GA(176, 180, 176) radius:26 in:self];
    _shockRing.layer.borderWidth = 1; _shockRing.layer.borderColor = GA(126, 130, 128).CGColor;
    UIButton *shk = [self button:@"SHOCK" frame:CGRectMake(kx, ky, ks2, ks2) action:@selector(kShock)];
    shk.backgroundColor = GA_SHOCK; shk.layer.cornerRadius = 18; shk.layer.borderWidth = 1; shk.layer.borderColor = GA(84, 22, 16).CGColor;
    CAShapeLayer *bolt = [CAShapeLayer layer]; bolt.path = SFBoltPath(CGRectMake(ks2 / 2 - 18, ks2 / 2 - 24, 36, 42)).CGPath;
    bolt.fillColor = GA(238, 222, 214).CGColor; bolt.strokeColor = GA(84, 22, 16).CGColor; bolt.lineWidth = 0.75; bolt.lineJoin = kCALineJoinRound;
    [shk.layer addSublayer:bolt];
    [SFTactile applyToFace:shk control:shk radius:18 strength:1];
    UILabel *sc = [self label:CGRectMake(rx + 12, kBY + 450, rw - 24, 44) in:self size:10.5 bold:NO color:GA_INK2 align:NSTextAlignmentCenter];
    sc.numberOfLines = 2; sc.text = @"si illumina quando è carico\nprima di premere: nessuno tocca il paziente";

    // vano delle piastre: presa del connettore a sinistra, cavo, confezione delle piastre a destra
    CGFloat ty = kBY + 526, th = kBH - 526 - 20;
    UIView *tray = [self box:CGRectMake(kBX + 22, ty, kBW - 44, th) color:GA(170, 173, 168) radius:12 in:self];
    tray.layer.borderWidth = 1; tray.layer.borderColor = GA(140, 144, 140).CGColor;
    [self box:CGRectMake(kBX + 34, ty + 2, kBW - 68, 2) color:GA(150, 153, 148) radius:1 in:self];      // ombra interna sotto il bordo
    UILabel *t2 = [self label:CGRectMake(kBX + 38, ty + 10, 300, 16) in:self size:11 bold:YES color:GA_INK align:NSTextAlignmentLeft];
    t2.text = @"2  PIASTRE — CONNETTORE";
    // presa: incavo scuro con due contatti, spia accanto
    CGFloat sx = kBX + 44, sy = ty + 62;
    UIView *sock = [self box:CGRectMake(sx, sy, 92, 66) color:GA(24, 26, 28) radius:10 in:self];
    sock.layer.borderWidth = 2; sock.layer.borderColor = GA(110, 114, 112).CGColor;
    for (int k = 0; k < 2; k++) [self box:CGRectMake(sx + 28 + k * 26, sy + 26, 12, 14) color:GA(160, 142, 82) radius:2 in:self];
    _socketLamp = [self box:CGRectMake(sx + 36, sy - 18, 20, 8) color:GA_LEDOFF radius:4 in:self];
    UILabel *sl = [self label:CGRectMake(sx - 6, sy + 70, 104, 14) in:self size:9.5 bold:YES color:GA_INK2 align:NSTextAlignmentCenter]; sl.text = @"PRESA";
    // cavo fisso: dalla confezione delle piastre verso la presa (l'ultimo tratto si muove con la spina)
    CGFloat cy = sy + 33;
    UIBezierPath *cable = [UIBezierPath bezierPath];
    [cable moveToPoint:CGPointMake(kBX + 300, cy)]; [cable addLineToPoint:CGPointMake(kBX + 360, cy)];
    [cable addCurveToPoint:CGPointMake(kBX + 452, cy + 6) controlPoint1:CGPointMake(kBX + 400, cy) controlPoint2:CGPointMake(kBX + 420, cy + 34)];
    [self shape:cable fill:nil stroke:GA(52, 56, 60) width:8 in:self];
    // confezione delle piastre: busta con le due piastre adesive e il pittogramma della posizione
    CGFloat px = kBX + 452, pw2 = kBX + kBW - 34 - px;
    UIView *pack = [self box:CGRectMake(px, ty + 30, pw2, th - 42) color:GA(232, 233, 228) radius:8 in:self];
    pack.layer.borderWidth = 1; pack.layer.borderColor = GA(150, 154, 150).CGColor;
    UILabel *pk = [self label:CGRectMake(px + 12, ty + 36, pw2 - 24, 14) in:self size:9.5 bold:YES color:GA_INK2 align:NSTextAlignmentLeft];
    pk.text = @"PIASTRE ADESIVE · ADULTO / BAMBINO";
    for (int k = 0; k < 2; k++) {
        CGFloat ax = px + 12 + k * ((pw2 - 36) / 2 + 12), aw = (pw2 - 36) / 2, ay = ty + 56, ah = th - 76;
        UIView *pad = [self box:CGRectMake(ax, ay, aw, ah) color:GA(246, 246, 243) radius:10 in:self];
        pad.layer.borderWidth = 1; pad.layer.borderColor = GA(170, 172, 168).CGColor;
        [self box:CGRectMake(ax + 8, ay + 8, aw - 16, ah - 16) color:GA(236, 238, 232) radius:7 in:self];   // gel
        // pittogramma: torso con la posizione di QUESTA piastra (1 sotto la clavicola destra, 2 sul fianco sinistro)
        UIView *pv = [[UIView alloc] initWithFrame:CGRectMake(ax + 10, ay + 10, aw - 20, ah - 20)]; pv.userInteractionEnabled = NO; [self addSubview:pv];
        CGFloat w = pv.bounds.size.height * 0.8, h = pv.bounds.size.height, ox = (pv.bounds.size.width - w) / 2;
        UIBezierPath *t = [UIBezierPath bezierPath];
        [t moveToPoint:CGPointMake(ox + w * 0.34, h * 0.06)]; [t addQuadCurveToPoint:CGPointMake(ox + w * 0.66, h * 0.06) controlPoint:CGPointMake(ox + w * 0.5, h * 0.18)];
        [t addQuadCurveToPoint:CGPointMake(ox + w * 0.88, h * 0.3) controlPoint:CGPointMake(ox + w * 0.86, h * 0.08)];
        [t addLineToPoint:CGPointMake(ox + w * 0.8, h * 0.98)]; [t addLineToPoint:CGPointMake(ox + w * 0.2, h * 0.98)];
        [t addLineToPoint:CGPointMake(ox + w * 0.12, h * 0.3)]; [t addQuadCurveToPoint:CGPointMake(ox + w * 0.34, h * 0.06) controlPoint:CGPointMake(ox + w * 0.14, h * 0.08)];
        [self shape:t fill:nil stroke:GA_INK2 width:1.2 in:pv];
        CGRect mark = k == 0 ? CGRectMake(ox + w * 0.22, h * 0.22, w * 0.24, h * 0.22) : CGRectMake(ox + w * 0.56, h * 0.56, w * 0.24, h * 0.22);
        [self shape:[UIBezierPath bezierPathWithRoundedRect:mark cornerRadius:2] fill:GA(196, 92, 70) stroke:GA(120, 40, 30) width:0.8 in:pv];
        UILabel *n = [self label:CGRectMake(ax + 10, ay + 8, 20, 18) in:self size:13 bold:YES color:GA_INK align:NSTextAlignmentLeft];
        n.text = k == 0 ? @"1" : @"2";
    }
    _padsState = [self label:CGRectMake(px, ty + 10, pw2, 16) in:self size:10.5 bold:YES color:GA(28, 112, 60) align:NSTextAlignmentRight];
    _hint = [self label:CGRectMake(kBX + 38, ty + th - 30, 400, 18) in:self size:11 bold:NO color:GA_INK align:NSTextAlignmentLeft];

    // spina sul cavo: fuori dalla presa finché non la si inserisce (con l'ultimo tratto di cavo)
    // inserita: il naso sparisce nella presa e il corpo copre metà dell'incavo; sfilata: spostata a destra di PLUG_OUT
    _plug = [[UIView alloc] initWithFrame:CGRectMake(sx - 29, sy - 6, 300, 78)]; _plug.userInteractionEnabled = NO; [self addSubview:_plug];
    [self shape:[UIBezierPath bezierPathWithRect:CGRectMake(124, 35, 176, 8)] fill:GA(52, 56, 60) stroke:nil width:0 in:_plug];   // cavo
    [self box:CGRectMake(104, 28, 26, 22) color:GA(46, 50, 54) radius:5 in:_plug];                      // pressacavo
    _plugNose = [self box:CGRectMake(22, 24, 22, 30) color:GA(150, 154, 156) radius:3 in:_plug];        // naso metallico (sparisce nella presa)
    UIView *hs = [self box:CGRectMake(40, 8, 70, 62) color:GA(78, 83, 88) radius:9 in:_plug];           // corpo della spina
    hs.layer.borderWidth = 1; hs.layer.borderColor = GA(36, 39, 42).CGColor;
    [self box:CGRectMake(6, 5, 58, 3) color:GA(116, 121, 126) radius:1.5 in:hs];                        // riflesso
    for (int k = 0; k < 5; k++) [self box:CGRectMake(16 + k * 9, 18, 3, 30) color:GA(58, 62, 66) radius:1.5 in:hs];   // zigrinatura
    _plug.transform = CGAffineTransformMakeTranslation(PLUG_OUT, 0);

    // tutto il vano è il tasto: un tocco inserisce la spina
    [self button:@"PADS" frame:CGRectMake(kBX + 22, ty, 430, th) action:@selector(kPads)];

    // targhetta "similFranz Monitor · Layout" in alto a sinistra, fuori dal corpo
    UIButton *lay = SFLayoutButton(CGRectMake(6, 12, 138, 44), self, @selector(titleTapped)); [self addSubview:lay];
    _keys[@"LAYOUT"] = lay;
}

#pragma mark - Schermo

- (void)buildScreen {
    CGRect sf = CGRectMake(kBX + 30, kBY + 114, 484, 284);
    _screen = [[UIView alloc] initWithFrame:sf];
    _screen.backgroundColor = GA(10, 12, 14); _screen.opaque = YES;
    [self addSubview:_screen];
    CGFloat W = sf.size.width;
    [self box:CGRectMake(0, 0, W, 26) color:GA(30, 34, 38) radius:0 in:_screen];
    _patient = [self label:CGRectMake(12, 2, 200, 22) in:_screen size:12.5 bold:YES color:GA(200, 206, 212) align:NSTextAlignmentLeft];
    _elapsed = [self label:CGRectMake(W - 150, 2, 138, 22) in:_screen size:13 bold:NO color:GA(200, 206, 212) align:NSTextAlignmentRight];
    _elapsed.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    _big = [self label:CGRectMake(18, 36, W - 36, 196) in:_screen size:26 bold:NO color:[UIColor whiteColor] align:NSTextAlignmentCenter];
    _big.font = [UIFont systemFontOfSize:26 weight:UIFontWeightMedium]; _big.numberOfLines = 3;
    // RCP: tempo rimanente, barra, metronomo
    _cprTitle = [self label:CGRectMake(18, 140, 250, 16) in:_screen size:10.5 bold:YES color:GA(150, 158, 164) align:NSTextAlignmentLeft];
    _cprTitle.text = @"RCP · TEMPO RIMANENTE";
    _cprTime = [self label:CGRectMake(18, 156, 150, 40) in:_screen size:34 bold:NO color:GA(232, 235, 238) align:NSTextAlignmentLeft];
    _cprTime.font = [UIFont monospacedDigitSystemFontOfSize:34 weight:UIFontWeightMedium];
    _cprHint = [self label:CGRectMake(176, 160, W - 230, 36) in:_screen size:12 bold:NO color:GA(180, 188, 194) align:NSTextAlignmentLeft];
    _cprHint.numberOfLines = 2; _cprHint.text = @"spingi forte e veloce al centro del torace\nsegui il ritmo del metronomo";
    _beat = [self box:CGRectMake(W - 42, 166, 20, 20) color:GA_LEDON radius:10 in:_screen];
    _barTrack = [self box:CGRectMake(18, 206, W - 36, 6) color:GA(46, 52, 56) radius:0 in:_screen];
    _barFill = [self box:CGRectMake(0, 0, 0, 6) color:GA(150, 158, 164) radius:0 in:_barTrack];
    [self box:CGRectMake(0, 252, W, 1) color:GA(46, 52, 56) radius:0 in:_screen];
    _shocks = [self label:CGRectMake(12, 256, 250, 22) in:_screen size:12.5 bold:NO color:GA(186, 192, 198) align:NSTextAlignmentLeft];
    _energy = [self label:CGRectMake(W - 220, 256, 208, 22) in:_screen size:12.5 bold:NO color:GA(186, 192, 198) align:NSTextAlignmentRight];
    _offCover = [[UIView alloc] initWithFrame:_screen.bounds]; _offCover.backgroundColor = GA(10, 11, 12);
    [_screen addSubview:_offCover];
}

#pragma mark - Stato

static inline void GASetText(UILabel *l, NSString *t) { if (!(l.text == t || [l.text isEqualToString:t])) l.text = t; }
static inline void GASetFrame(UIView *v, CGRect f) { if (!CGRectEqualToRect(v.frame, f)) v.frame = f; }
static inline void GASetColor(UILabel *l, UIColor *c) { if (![l.textColor isEqual:c]) l.textColor = c; }
static inline void GASetBg(UIView *v, UIColor *c) { if (![v.backgroundColor isEqual:c]) v.backgroundColor = c; }

- (void)setAlarmText:(NSString *)text level:(NSInteger)level severity:(NSDictionary *)severity muted:(BOOL)muted remaining:(NSInteger)rem {}
// un DAE pubblico non ha allarmi da monitor né bip del battito: per il monitor è sempre "spento"
- (BOOL)poweredOff { return YES; }
- (void)setDevicePowered:(BOOL)on { if (on != _on) [self kPower]; }
- (void)titleTapped { if (self.onLayoutMenu) self.onLayoutMenu(); }
- (void)resetTracesAt:(NSTimeInterval)t {}

// energia crescente con le scariche: adulto 150 · 200 · 200 J, bambino 50 · 50 · 70 J
- (NSArray<NSNumber *> *)energies { return _child ? @[@50, @50, @70] : @[@150, @200, @200]; }

- (void)updateWithSnapshot:(SLSnapshot *)s {
    _snap = s;
    SLDefibInfo *d = s.defib;
    if (_on && d.mode != SLDefibAED) { _on = NO; _state.devicePowered = NO; }           // spento da un comando esterno
    if (!_on && d.mode == SLDefibAED) { _state.devicePowered = YES; _on = YES; _onAt = CACurrentMediaTime(); }   // acceso dal controller
    if (_offCover.hidden != _on) _offCover.hidden = _on;
    // spina: scorre dentro la presa quando la si collega (il cavo resta attaccato)
    BOOL conn = s.padsConnected;
    if (conn != _plugIn) {
        _plugIn = conn;
        CGAffineTransform t = conn ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(PLUG_OUT, 0);
        if (conn && self.window) [UIView animateWithDuration:0.35 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{ self->_plug.transform = t; }
                                              completion:^(BOOL f) { self->_plugNose.hidden = self->_plugIn; }];
        else { _plug.transform = t; _plugNose.hidden = conn; }
    }
    GASetText(_padsState, conn ? @"PIASTRE COLLEGATE E APPLICATE" : @"");
    GASetText(_hint, conn ? @"" : @"Tocca la spina o la presa per collegare le piastre");
    GASetBg(_childLed, (_on && _child) ? GA_LEDON : GA_LEDOFF);
    GASetText(_patient, _child ? @"BAMBINO" : @"ADULTO");
    GASetText(_shocks, [NSString stringWithFormat:@"Scariche erogate: %ld", (long)d.shockCount]);
    GASetText(_energy, [NSString stringWithFormat:@"Energia: %ld J", (long)d.energy]);
    GASetText(_status, _on ? @"IN USO" : @"PRONTO");
    if (_on && d.charge == SLChargeNone) {
        NSArray *e = [self energies];
        NSInteger want = [e[(NSUInteger)MIN((NSInteger)e.count - 1, d.shockCount)] integerValue];
        if (d.energy != want) [_state applyCommand:@{@"command": @"set_defib_config", @"value": @{@"aed_energy_j": @(want)}} error:NULL];
    }
    // spia del passo in corso: 2 piastre, 3 analisi (non toccare), 4 scarica
    NSInteger stepOn = !_on ? -1 : ((d.aedPhase == SLAedPads || !conn) ? 1 : ((d.aedPhase == SLAedAnalyzing || d.aedPhase == SLAedCharging) ? 2 : (d.aedPhase == SLAedReady ? 3 : -1)));
    for (NSInteger i = 0; i < 4; i++) GASetBg(_stepLed[(NSUInteger)i], i == stepOn ? GA_LEDON : GA_LEDOFF);
}


- (void)tick:(NSTimeInterval)now snapshot:(SLSnapshot *)s {
    _snap = s;
    if (now - _lastSlow < 0.2) return;
    _lastSlow = now;
    SLDefibInfo *d = s.defib;
    BOOL blink = fmod(now, 0.5) < 0.25;
    NSInteger el = _on ? (NSInteger)(now - _onAt) : 0;
    GASetText(_elapsed, [NSString stringWithFormat:@"%02ld:%02ld", (long)(el / 60), (long)el % 60]);
    BOOL cpr = _on && d.aedPhase == SLAedCPR;
    for (UIView *v in @[_cprTitle, _cprTime, _cprHint, _beat, _barTrack]) if (v.hidden != !cpr) v.hidden = !cpr;
    if (!cpr) _cprTotal = 0;
    NSString *m = d.message ?: @"";
    for (NSArray *r in @[@[@"SHOCK NON CONSIGLIATO", @"SCARICA NON CONSIGLIATA"], @[@"SHOCK CONSIGLIATO", @"SCARICA CONSIGLIATA"],
                         @[@"SHOCK EROGATO", @"SCARICA EROGATA"], @[@"PREMERE SHOCK", @"PREMERE IL TASTO SCARICA"], @[@"SHOCK", @"SCARICA"]])
        m = [m stringByReplacingOccurrencesOfString:r[0] withString:r[1]];      // il tasto si chiama SCARICA
    m = [m stringByReplacingOccurrencesOfString:@" — " withString:@"\n"];        // una frase per riga
    if (d.aedPhase == SLAedPads && _child) m = @"APPLICARE LE PIASTRE\nPEDIATRICHE";
    if (!s.padsConnected) m = _child ? @"COLLEGARE IL CONNETTORE\nDELLE PIASTRE PEDIATRICHE" : @"COLLEGARE IL CONNETTORE\nDELLE PIASTRE";
    if (!_on) m = @"";
    GASetText(_big, m);
    GASetFrame(_big, cpr ? CGRectMake(18, 34, _screen.bounds.size.width - 36, 100) : CGRectMake(18, 36, _screen.bounds.size.width - 36, 206));
    // spia della presa: lampeggia finché il connettore non è inserito
    GASetBg(_socketLamp, (_on && !s.padsConnected) ? (blink ? GA(250, 190, 70) : GA_LEDOFF) : (s.padsConnected && _on ? GA_LEDON : GA_LEDOFF));
    // stato a riposo: spia verde che pulsa lenta (autoverifica superata); acceso: fissa
    GASetBg(_statusLamp, (_on || fmod(now, 2.0) < 0.4) ? GA_LEDON : GA(40, 80, 54));
    GASetColor(_big, d.aedPhase == SLAedReady ? GA(255, 196, 176) : [UIColor whiteColor]);
    if (cpr) {
        if (!_cprTotal) _cprTotal = MAX(1, [[_state stateDictionary][@"defib"][@"config"][@"aed_cpr_s"] integerValue]);   // una volta per ciclo di RCP
        NSInteger total = _cprTotal;
        GASetText(_cprTime, [NSString stringWithFormat:@"%ld:%02ld", (long)d.aedRemaining / 60, (long)d.aedRemaining % 60]);
        GASetFrame(_barFill, CGRectMake(0, 0, _barTrack.bounds.size.width * MAX(0, MIN(1, 1.0 - (double)d.aedRemaining / total)), 6));
        _beat.alpha = fmod(now, 60.0 / 110.0) < 0.2 ? 1 : 0.25;        // battito visivo del metronomo (110 al minuto)
    }
    BOOL ready = _on && d.charge == SLChargeReady;
    GASetBg(_shockRing, ready ? (blink ? GA(236, 92, 70) : GA(190, 150, 142)) : GA(178, 182, 180));     // lampeggia l'anello, non il tasto
}

#pragma mark - Azioni

- (void)cmd:(NSString *)name value:(id)value {
    NSMutableDictionary *c = [@{@"command": name} mutableCopy];
    if (value) c[@"value"] = value;
    BOOL ok = [_state applyCommand:c error:NULL];
    if ([name hasPrefix:@"defib_"]) SFLog(@"GenericAedView: %@ %@ -> %@", name, value ?: @"", ok ? @"ok" : @"rifiutato");
    _snap = [_state snapshot]; [self updateWithSnapshot:_snap];
}
- (void)kPower {
    _on = !_on;
    _state.devicePowered = _on;
    if (_on) { _onAt = CACurrentMediaTime(); [self cmd:@"defib_mode" value:@"aed"]; }
    else [self cmd:@"defib_mode" value:@"off"];
    [self updateWithSnapshot:[_state snapshot]];
}
- (void)kPads { if (!_snap.padsConnected) [self cmd:@"set_sensor" value:@{@"sensor": @"pads", @"connected": @YES}]; }     // un tocco collega; non scollega mai
- (void)kShock { if (_on) [self cmd:@"defib_shock" value:nil]; }
- (void)kChild {
    if (!_on) return;
    _child = !_child;
    [self cmd:@"defib_event" value:_child ? @"Modalità bambino" : @"Modalità adulto"];
}

#pragma mark - Autotest

- (BOOL)tapKey:(NSString *)k {
    UIButton *target = _keys[k];
    if (!target) { SFLog(@"SELFTEST tasto %@ inesistente", k); return NO; }
    CGPoint p = [target convertPoint:CGPointMake(CGRectGetMidX(target.bounds), CGRectGetMidY(target.bounds)) toView:self.window];
    UIView *c = [self.window hitTest:p withEvent:nil]; while (c && ![c isKindOfClass:[UIControl class]]) c = c.superview;
    if ([c isKindOfClass:[UIControl class]]) { [(UIControl *)c sendActionsForControlEvents:UIControlEventTouchDown]; [(UIControl *)c sendActionsForControlEvents:UIControlEventTouchUpInside]; }
    _snap = [_state snapshot]; [self updateWithSnapshot:_snap];
    return c == target;
}
- (BOOL)reachable:(NSString *)k {
    UIButton *target = _keys[k];
    CGPoint p = [target convertPoint:CGPointMake(CGRectGetMidX(target.bounds), CGRectGetMidY(target.bounds)) toView:self.window];
    UIView *c = [self.window hitTest:p withEvent:nil]; while (c && ![c isKindOfClass:[UIControl class]]) c = c.superview;
    return c == target;
}

- (void)runSelfTestWithShot:(void (^)(NSString *))shot done:(void (^)(NSInteger))done {
    __block NSInteger fails = 0;
    GenericAedView *me = self; SimulationState *st = _state;
    void (^check)(BOOL, NSString *) = ^(BOOL c, NSString *what) { if (!c) fails++; SFLog(@"SELFTEST %@ %@", c ? @"PASS" : @"FAIL", what); };
    SLDefibInfo *(^D)(void) = ^SLDefibInfo *{ return [st snapshot].defib; };
    NSMutableArray *steps = [NSMutableArray array];
    void (^step)(double, dispatch_block_t) = ^(double delay, dispatch_block_t b) { [steps addObject:@[@(delay), [b copy]]]; };
    step(0.8, ^{ me->_child = NO; [me updateWithSnapshot:[st snapshot]]; shot(@"G00-spento");
                 BOOL all = YES; for (NSString *k in me->_keys) if (![me reachable:k]) { all = NO; SFLog(@"SELFTEST tasto non raggiungibile: %@", k); }
                 check(all, [NSString stringWithFormat:@"tasti tutti raggiungibili (%lu)", (unsigned long)me->_keys.count]);
                 [st applyCommand:@{@"command": @"set_rhythm", @"value": @"vf"} error:NULL];
                 [me tapKey:@"SHOCK"]; check(D().shockCount == 0, @"spento: SCARICA non fa nulla");
                 check([me tapKey:@"POWER"] && D().mode == SLDefibAED && D().aedPhase == SLAedPads, @"accensione: applicare le piastre"); });
    step(1.0, ^{ check([me->_big.text hasPrefix:@"COLLEGARE IL CONNETTORE"], @"schermo: collegare il connettore delle piastre"); shot(@"G01-piastre"); check([me tapKey:@"PADS"] && [st snapshot].padsConnected && D().aedPhase == SLAedAnalyzing, @"piastre collegate: analisi");
                 [me tapKey:@"PADS"]; check([st snapshot].padsConnected, @"un secondo tocco non scollega le piastre"); });
    step(2.0, ^{ shot(@"G02-analisi"); check(CGAffineTransformIsIdentity(me->_plug.transform), @"spina inserita nella presa"); [st applyCommand:@{@"command": @"patient_touch", @"value": @3} error:NULL]; });
    step(1.0, ^{ check(D().aedPhase == SLAedAnalyzing && [D().message containsString:@"FERMARE IL MOVIMENTO"], @"movimento: analisi interrotta"); });
    step(18.5, ^{ check(D().aedPhase == SLAedReady && D().chargedEnergy == 150, [NSString stringWithFormat:@"scarica consigliata, carico a 150 J (%ld)", (long)D().chargedEnergy]); shot(@"G03-pronto");
                  check([me tapKey:@"SHOCK"] && D().aedPhase == SLAedCPR && D().shockCount == 1, @"SCARICA: poi RCP"); });
    step(1.0, ^{ [st applyCommand:@{@"command": @"set_cpr", @"value": @YES} error:NULL]; });
    step(2.0, ^{ shot(@"G04-rcp"); check(D().energy == 200, [NSString stringWithFormat:@"energia successiva 200 J (%ld)", (long)D().energy]);
                 check([me tapKey:@"CHILD"] && me->_child, @"tasto bambino"); check(D().energy == 50, [NSString stringWithFormat:@"bambino: 50 J (%ld)", (long)D().energy]);
                 [me tapKey:@"CHILD"]; [st applyCommand:@{@"command": @"set_cpr", @"value": @NO} error:NULL];
                 { __block BOOL lm = NO; void (^old)(void) = me.onLayoutMenu; me.onLayoutMenu = ^{ lm = YES; }; [me tapKey:@"LAYOUT"]; check(lm, @"targhetta Layout: menu dei layout"); me.onLayoutMenu = old; }
                 check([me tapKey:@"POWER"] && D().mode == SLDefibOff, @"spegnimento"); });
    double at = 0;
    for (NSArray *sp in steps) { at += [sp[0] doubleValue]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(at * NSEC_PER_SEC)), dispatch_get_main_queue(), sp[1]); }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((at + 0.3) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SFLog(@"SELFTEST FINE DAE: %ld errori", (long)fails);
        done(fails);
    });
}

@end
