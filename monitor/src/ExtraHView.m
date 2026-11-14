#import "ExtraHView.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "SimulationState.h"
#import "WaveformEngine.h"
#import "SoundEngine.h"
#import "TraceView.h"
#import "SFLog.h"
#import "SFTactile.h"
#import "SFBolt.h"
#import "SFJitter.h"
#import "SFFlatten.h"

static UIColor *EH(CGFloat r, CGFloat g, CGFloat b) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1]; }

// Aggiornamenti "solo se cambia": il layout si aggiorna a ogni lettura dello stato e ogni 0,25 s. Riassegnare lo stesso
// testo, colore o titolo a etichette e tasti costringeva UIKit a ridisegnarli ogni volta (con i tasti in rilievo
// costa molto, sia all'app sia al compositore di sistema): ora si tocca una vista solo quando il valore cambia davvero.
static inline void EHSetText(UILabel *l, NSString *t) { if (!(l.text == t || [l.text isEqualToString:t])) l.text = t; }
static inline void EHSetColor(UILabel *l, UIColor *c) { if (![l.textColor isEqual:c]) l.textColor = c; }
static inline void EHSetBg(UIView *v, UIColor *c) { if (![v.backgroundColor isEqual:c]) v.backgroundColor = c; }
static inline void EHSetFrame(UIView *v, CGRect f) { if (!CGRectEqualToRect(v.frame, f)) v.frame = f; }
static inline void EHSetHidden(UIView *v, BOOL h) { if (v.hidden != h) v.hidden = h; }
static inline void EHSetAlpha(UIView *v, CGFloat a) { if (fabs(v.alpha - a) > 0.001) v.alpha = a; }
static inline void EHSetTitle(UIButton *b, NSString *t) { if (![[b titleForState:UIControlStateNormal] isEqualToString:t]) [b setTitle:t forState:UIControlStateNormal]; }
static inline void EHSetTitleColor(UIButton *b, UIColor *c) { if (![[b titleColorForState:UIControlStateNormal] isEqual:c]) [b setTitleColor:c forState:UIControlStateNormal]; }
#define EH_ACCENT EH(214, 132, 52)      // arancio smorzato: il colore di extraH (solo filetti e scritte piccole)
#define EH_KEY    EH(74, 79, 86)        // tasti in gomma scura
#define EH_KEYHI  EH(96, 102, 110)
#define EH_HR     EH(70, 235, 110)
#define EH_SPO2   EH(60, 205, 255)
#define EH_NIBP   EH(240, 240, 245)
#define EH_CO2    EH(245, 215, 70)
#define EH_TEMP   EH(205, 160, 255)
#define EH_WHITE  EH(236, 238, 242)
#define EH_GREY   EH(150, 156, 164)
#define EH_RED    EH(226, 70, 56)
#define EH_AMBER  EH(214, 168, 70)
#define EH_SHOCK  EH(128, 34, 30)        // tasto di scarica: rosso scuro opaco
#define EH_LINE   EH(96, 101, 110)       // filetti dei pannelli

// I messaggi del modello dicono "shock": su extraH il tasto si chiama SCARICA, e i messaggi lo seguono.
static NSString *EHText(NSString *m) {
    if (!m.length) return m;
    for (NSArray *r in @[@[@"SHOCK NON CONSIGLIATO", @"SCARICA NON CONSIGLIATA"], @[@"SHOCK CONSIGLIATO", @"SCARICA CONSIGLIATA"],
                         @[@"SHOCK EROGATO", @"SCARICA EROGATA"], @[@"SHOCK", @"SCARICA"], @[@"Shock", @"Scarica"]])
        m = [m stringByReplacingOccurrencesOfString:r[0] withString:r[1]];
    return m;
}

@implementation ExtraHView {
    SimulationState *_state; WaveformEngine *_engine; SoundEngine *_sound;
    SLSnapshot *_snap;
    BOOL _off, _flattened, _pads;        // _pads: la traccia ECG viene dalle piastre (nessun elettrodo collegato)
    NSMutableDictionary<NSString *, UIButton *> *_keys;
    NSMutableDictionary<NSString *, UIView *> *_plugMark, *_modeLed;
    UIView *_screen, *_offCover, *_powerLed, *_chargeTrack, *_chargeFill, *_alarmLamp;
    TraceView *_ecg, *_pleth, *_co2;
    UILabel *_clock, *_modeLbl, *_batt, *_elapsed, *_msg, *_ecgLbl;
    UILabel *_hr, *_sp, *_nibp, *_nibpSt, *_et, *_rr, *_temp;
    UIView *_shockLamp; UILabel *_leadKeyNote; BOOL _leadPads;      // _leadPads: con elettrodi e piastre collegati, la derivazione scelta dall'operatore
    UILabel *_thTitle, *_thBig, *_thBig2, *_thState, *_thSub, *_thSync;
    UIView *_popup;
    NSString *_alarmText, *_note; NSInteger _alarmLevel, _mutedRem; BOOL _muted; NSDictionary *_severity;
    NSTimeInterval _onAt, _lastSlow, _noteUntil;
    NSDateFormatter *_fmt, *_fmtHM;
}

- (instancetype)initWithFrame:(CGRect)frame state:(SimulationState *)state engine:(WaveformEngine *)engine sound:(SoundEngine *)sound {
    if ((self = [super initWithFrame:frame])) {
        _state = state; _engine = engine; _sound = sound;
        _keys = [NSMutableDictionary dictionary]; _plugMark = [NSMutableDictionary dictionary]; _modeLed = [NSMutableDictionary dictionary];
        _fmt = [NSDateFormatter new]; _fmt.dateFormat = @"dd/MM/yyyy  HH:mm:ss";
        _fmtHM = [NSDateFormatter new]; _fmtHM.dateFormat = @"HH:mm";
        _snap = [state snapshot];
        _off = !state.devicePowered;
        self.backgroundColor = EH(22, 23, 26);
        [self buildBody];
        [self buildScreen];
        [self buildKeys];
        _offCover.hidden = !_off;
        if (!_off) _onAt = CACurrentMediaTime();
        [self updateWithSnapshot:_snap];
    }
    return self;
}

// la decorazione fissa (scocca, scritte, sfumature) diventa una sola immagine: meno lavoro per il compositore
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window || _flattened) return;
    _flattened = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray *keep = [NSMutableArray arrayWithObjects:self->_powerLed, self->_alarmLamp, nil];
        [keep addObjectsFromArray:self->_modeLed.allValues];
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
// tasto fisico: gomma scura con scritta chiara (o colore dato), in rilievo e con animazione di pressione
- (UIButton *)key:(NSString *)name title:(NSString *)title frame:(CGRect)f bg:(UIColor *)bg fg:(UIColor *)fg size:(CGFloat)size action:(SEL)sel {
    return [self key:name title:title frame:f bg:bg fg:fg size:size radius:9 action:sel];
}
- (UIButton *)key:(NSString *)name title:(NSString *)title frame:(CGRect)f bg:(UIColor *)bg fg:(UIColor *)fg size:(CGFloat)size radius:(CGFloat)radius action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f; b.backgroundColor = bg; b.layer.cornerRadius = radius;
    b.layer.borderWidth = 1; b.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.55].CGColor;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:fg forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:size];
    b.titleLabel.numberOfLines = 2; b.titleLabel.textAlignment = NSTextAlignmentCenter; b.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    b.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 4);
    if (sel) [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    _keys[name] = b;
    [SFTactile applyToFace:b control:b radius:radius strength:1];
    // tasto fermo = una sola immagine per il compositore (ombra, riflesso e scritta insieme): si rifà solo se il tasto cambia
    b.layer.shouldRasterize = YES; b.layer.rasterizationScale = [UIScreen mainScreen].scale;
    return b;
}

#pragma mark - Scocca

// pannello di un gruppo di tasti: fondo appena più scuro, filetto sottile e legenda piccola in alto a sinistra
- (void)panel:(CGRect)f legend:(NSString *)legend {
    UIView *p = [self box:f color:EH(40, 43, 48) radius:10 in:self];
    p.layer.borderWidth = 1; p.layer.borderColor = EH_LINE.CGColor;
    [self label:CGRectMake(f.origin.x + 10, f.origin.y + 5, f.size.width - 20, 13) in:self size:9.5 bold:YES color:EH_GREY align:NSTextAlignmentLeft].text = legend;
}
// passo numerato del defibrillatore: numero in un cerchietto a filetto + nome del passo
- (void)stepLabel:(NSString *)n text:(NSString *)t at:(CGPoint)o {
    UIView *c = [self box:CGRectMake(o.x, o.y, 18, 18) color:[UIColor clearColor] radius:9 in:self];
    c.layer.borderWidth = 1; c.layer.borderColor = EH_ACCENT.CGColor;
    [self label:c.bounds in:c size:11.5 bold:YES color:EH_ACCENT align:NSTextAlignmentCenter].text = n;
    [self label:CGRectMake(o.x + 24, o.y, 170, 18) in:self size:11.5 bold:YES color:EH_WHITE align:NSTextAlignmentLeft].text = t;
}

- (void)buildBody {
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    // scocca grafite opaca, luce appena accennata dall'alto, bordo sottile
    CAGradientLayer *body = [self gradient:CGRectMake(4, 4, W - 8, H - 8) colors:@[EH(58, 61, 67), EH(46, 49, 54), EH(36, 38, 42)] radius:22 in:self];
    body.borderWidth = 1; body.borderColor = EH(84, 88, 96).CGColor;
    // (4) prese dei sensori
    [self panel:CGRectMake(12, 44, 122, 474) legend:@"SENSORI"];
    // (3) tasti del dispositivo
    [self panel:CGRectMake(12, 526, 122, 190) legend:@"DISPOSITIVO"];
    _powerLed = [self box:CGRectMake(64, 612, 18, 5) color:EH(40, 60, 44) radius:2.5 in:self];
    [self label:CGRectMake(12, 620, 122, 12) in:self size:9 bold:NO color:EH_GREY align:NSTextAlignmentCenter].text = @"ACCENSIONE";
    // cornice dello schermo
    UIView *bez = [self box:CGRectMake(140, 46, 640, 482) color:EH(14, 15, 17) radius:8 in:self];
    bez.layer.borderWidth = 1; bez.layer.borderColor = EH(84, 88, 96).CGColor;
    // (2) monitoraggio, sotto lo schermo a sinistra
    [self panel:CGRectMake(140, 540, 340, 92) legend:@"MONITORAGGIO"];
    // (1) terapia elettrica: un solo pannello a L (colonna a destra dello schermo + fascia in basso con il pacer)
    UIBezierPath *l = [UIBezierPath bezierPath]; CGFloat r = 10;
    [l moveToPoint:CGPointMake(790 + r, 44)];
    [l addLineToPoint:CGPointMake(1012 - r, 44)]; [l addQuadCurveToPoint:CGPointMake(1012, 44 + r) controlPoint:CGPointMake(1012, 44)];
    [l addLineToPoint:CGPointMake(1012, 716 - r)]; [l addQuadCurveToPoint:CGPointMake(1012 - r, 716) controlPoint:CGPointMake(1012, 716)];
    [l addLineToPoint:CGPointMake(490 + r, 716)]; [l addQuadCurveToPoint:CGPointMake(490, 716 - r) controlPoint:CGPointMake(490, 716)];
    [l addLineToPoint:CGPointMake(490, 540 + r)]; [l addQuadCurveToPoint:CGPointMake(490 + r, 540) controlPoint:CGPointMake(490, 540)];
    [l addLineToPoint:CGPointMake(790 - r, 540)]; [l addQuadCurveToPoint:CGPointMake(790, 540 - r) controlPoint:CGPointMake(790, 540)];
    [l addLineToPoint:CGPointMake(790, 44 + r)]; [l addQuadCurveToPoint:CGPointMake(790 + r, 44) controlPoint:CGPointMake(790, 44)];
    [l closePath];
    UIView *lp = [[UIView alloc] initWithFrame:self.bounds]; lp.userInteractionEnabled = NO; [self addSubview:lp];
    CAShapeLayer *ls = [CAShapeLayer layer]; ls.path = l.CGPath; ls.fillColor = EH(40, 43, 48).CGColor; ls.strokeColor = EH_ACCENT.CGColor; ls.lineWidth = 1;
    [lp.layer addSublayer:ls];
    [self label:CGRectMake(800, 49, 202, 13) in:self size:9.5 bold:YES color:EH_ACCENT align:NSTextAlignmentLeft].text = @"TERAPIA ELETTRICA";
    [self label:CGRectMake(800, 66, 202, 12) in:self size:9 bold:NO color:EH_GREY align:NSTextAlignmentLeft].text = @"MODO (di nuovo lo stesso tasto: spento)";
    [self stepLabel:@"1" text:@"ENERGIA" at:CGPointMake(800, 180)];
    [self stepLabel:@"2" text:@"CARICA" at:CGPointMake(800, 256)];
    [self stepLabel:@"3" text:@"SCARICA" at:CGPointMake(800, 382)];
    [self label:CGRectMake(502, 546, 300, 13) in:self size:9.5 bold:YES color:EH_ACCENT align:NSTextAlignmentLeft].text = @"PACER (attivo nel modo PACER)";
    // pacer: tre colonne che riempiono il pannello — frequenza, uscita (− / + grandi), poi modo e avvio
    [self label:CGRectMake(504, 568, 160, 14) in:self size:10.5 bold:YES color:EH_WHITE align:NSTextAlignmentCenter].text = @"FREQUENZA";
    [self label:CGRectMake(680, 568, 160, 14) in:self size:10.5 bold:YES color:EH_WHITE align:NSTextAlignmentCenter].text = @"USCITA";
    [self label:CGRectMake(504, 670, 160, 12) in:self size:9 bold:NO color:EH_GREY align:NSTextAlignmentCenter].text = @"ppm · 5 a ogni tocco";
    [self label:CGRectMake(680, 670, 160, 12) in:self size:9 bold:NO color:EH_GREY align:NSTextAlignmentCenter].text = @"mA · 5 a ogni tocco";
    [self box:CGRectMake(671, 572, 1, 112) color:EH(74, 78, 86) radius:0 in:self];
    [self box:CGRectMake(851, 572, 1, 112) color:EH(74, 78, 86) radius:0 in:self];
    // targhetta e griglia dell'altoparlante
    UILabel *brand = [self label:CGRectMake(150, 646, 120, 26) in:self size:20 bold:YES color:EH_WHITE align:NSTextAlignmentLeft];
    NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:@"extra" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:20 weight:UIFontWeightLight], NSForegroundColorAttributeName: EH_WHITE}];
    [t appendAttributedString:[[NSAttributedString alloc] initWithString:@"H" attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:20], NSForegroundColorAttributeName: EH_ACCENT}]];
    brand.attributedText = t;
    UILabel *sim = [self label:CGRectMake(150, 674, 200, 26) in:self size:9 bold:NO color:EH_GREY align:NSTextAlignmentLeft];
    sim.numberOfLines = 2; sim.text = @"similFranz · SIMULAZIONE\nNON PER USO CLINICO";
    for (int rr = 0; rr < 4; rr++) for (int c = 0; c < 9; c++)
        [self box:CGRectMake(370 + c * 12, 654 + rr * 12, 5, 5) color:EH(22, 23, 26) radius:2.5 in:self];
    // spia d'allarme, sopra lo schermo
    _alarmLamp = [self box:CGRectMake(420, 18, 80, 10) color:EH(60, 20, 18) radius:5 in:self];
    _alarmLamp.layer.borderWidth = 1; _alarmLamp.layer.borderColor = EH(20, 20, 22).CGColor;
}

#pragma mark - Schermo

- (TraceView *)trace:(CGRect)f color:(UIColor *)c speed:(double)sp min:(double)mn max:(double)mx sampler:(double (^)(NSTimeInterval))smp {
    TraceView *t = [[TraceView alloc] initWithFrame:f];
    t.traceColor = c; t.label = @""; t.minValue = mn; t.maxValue = mx; t.sweepSpeed = sp; t.sampler = smp;
    [_screen addSubview:t];
    return t;
}
// riquadro numerico: intestazione piccola colorata + valore grande
- (UILabel *)numeric:(NSString *)title unit:(NSString *)unit frame:(CGRect)f color:(UIColor *)c size:(CGFloat)size {
    UIView *ln = [self box:CGRectMake(f.origin.x, f.origin.y, f.size.width, 1) color:EH(50, 54, 60) radius:0 in:_screen]; (void)ln;
    [self label:CGRectMake(f.origin.x + 4, f.origin.y + 3, f.size.width * 0.6, 14) in:_screen size:11.5 bold:YES color:c align:NSTextAlignmentLeft].text = title;
    [self label:CGRectMake(f.origin.x + f.size.width * 0.5, f.origin.y + 3, f.size.width * 0.5 - 4, 14) in:_screen size:10 bold:NO color:EH_GREY align:NSTextAlignmentRight].text = unit;
    UILabel *v = [self label:CGRectMake(f.origin.x + 2, f.origin.y + 16, f.size.width - 4, f.size.height - 18) in:_screen size:size bold:YES color:c align:NSTextAlignmentCenter];
    v.font = [UIFont monospacedDigitSystemFontOfSize:size weight:UIFontWeightBold];
    return v;
}

- (void)buildScreen {
    CGRect sf = CGRectMake(146, 52, 628, 470);
    _screen = [[UIView alloc] initWithFrame:sf];
    _screen.backgroundColor = [UIColor blackColor]; _screen.opaque = YES;      // niente ritaglio: le tracce stanno già dentro lo schermo
    [self addSubview:_screen];
    CGFloat SW = sf.size.width;
    // barra di stato
    [self box:CGRectMake(0, 0, SW, 24) color:EH(26, 28, 32) radius:0 in:_screen];
    _clock = [self label:CGRectMake(6, 2, 190, 20) in:_screen size:12 bold:NO color:EH_WHITE align:NSTextAlignmentLeft];
    _modeLbl = [self label:CGRectMake(210, 2, 208, 20) in:_screen size:13 bold:YES color:EH_ACCENT align:NSTextAlignmentCenter];
    _batt = [self label:CGRectMake(SW - 196, 2, 96, 20) in:_screen size:12 bold:YES color:EH_WHITE align:NSTextAlignmentRight];
    _elapsed = [self label:CGRectMake(SW - 94, 2, 88, 20) in:_screen size:14 bold:YES color:EH_WHITE align:NSTextAlignmentRight];
    _elapsed.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightBold];
    // riga dei messaggi e degli allarmi
    _msg = [self label:CGRectMake(6, 26, SW - 12, 24) in:_screen size:15 bold:YES color:EH_WHITE align:NSTextAlignmentLeft];

    __weak WaveformEngine *eng = _engine; __weak ExtraHView *ws = self;
    CGFloat tw = 424, tx = 4;
    _ecg = [self trace:CGRectMake(tx, 54, tw, 112) color:EH_HR speed:90 min:-0.9 max:1.7 sampler:^double(NSTimeInterval t) {
        ExtraHView *me = ws; if (!me) return 0;
        SLSnapshot *s = me->_snap;
        if (me->_pads ? !s.padsConnected : !s.ecgConnected) return 0;
        return [eng ecgAt:t lead:me->_pads ? SLLeadPads : SLLeadII];
    }];
    _ecg.edgeArtifacts = YES; _ecg.markerYOffset = 16;
    _ecg.markerSampler = ^NSInteger(NSTimeInterval t0, NSTimeInterval t1) {
        ExtraHView *me = ws; if (!me) return 0;
        SLSnapshot *s = me->_snap;
        if (me->_pads ? !s.padsConnected : !s.ecgConnected) return 0;
        return [eng markersFrom:t0 to:t1 sync:(s.defib.mode == SLDefibManual && s.defib.sync)];
    };
    _ecgLbl = [self label:CGRectMake(tx + 4, 54, 200, 15) in:_screen size:12 bold:NO color:EH_HR align:NSTextAlignmentLeft];
    _pleth = [self trace:CGRectMake(tx, 170, tw, 78) color:EH_SPO2 speed:90 min:-0.05 max:1.05 sampler:^double(NSTimeInterval t) { return [eng plethAt:t]; }];
    _pleth.autoScale = 1; _pleth.minSpan = 0.15;
    [self label:CGRectMake(tx + 4, 170, 200, 15) in:_screen size:12 bold:NO color:EH_SPO2 align:NSTextAlignmentLeft].text = @"Pletismografia";
    _co2 = [self trace:CGRectMake(tx, 252, tw, 78) color:EH_CO2 speed:30 min:-1 max:60 sampler:^double(NSTimeInterval t) { return [eng capnoAt:t]; }];
    _co2.filled = YES; _co2.showScaleLabels = YES;
    [self label:CGRectMake(tx + 4, 252, 200, 15) in:_screen size:12 bold:NO color:EH_CO2 align:NSTextAlignmentLeft].text = @"CO₂   0 – 60 mmHg";

    // numerici a destra, ognuno all'altezza della sua traccia
    CGFloat nx = 434, nw = SW - nx - 2;
    _hr = [self numeric:@"FC" unit:@"bpm" frame:CGRectMake(nx, 54, nw, 112) color:EH_HR size:70];
    _sp = [self numeric:@"SpO₂" unit:@"%" frame:CGRectMake(nx, 170, nw, 78) color:EH_SPO2 size:46];
    _nibp = [self numeric:@"NIBP" unit:@"mmHg" frame:CGRectMake(nx, 252, nw, 78) color:EH_NIBP size:30];
    _nibp.frame = CGRectMake(nx + 2, 268, nw - 4, 38);
    _nibpSt = [self label:CGRectMake(nx + 4, 306, nw - 8, 22) in:_screen size:11 bold:NO color:EH_GREY align:NSTextAlignmentCenter];
    _et = [self numeric:@"EtCO₂" unit:@"mmHg" frame:CGRectMake(nx, 334, nw / 2, 70) color:EH_CO2 size:32];
    _rr = [self numeric:@"FR" unit:@"/min" frame:CGRectMake(nx + nw / 2, 334, nw / 2, 70) color:EH_WHITE size:32];
    _temp = [self numeric:@"TEMP" unit:@"°C" frame:CGRectMake(nx, 408, nw, 60) color:EH_TEMP size:28];

    // riquadro della terapia elettrica, sotto le tracce
    UIView *th = [self box:CGRectMake(tx, 336, tw, 130) color:EH(18, 20, 23) radius:0 in:_screen];
    th.layer.borderWidth = 1.5; th.layer.borderColor = EH_ACCENT.CGColor;
    _thTitle = [self label:CGRectMake(10, 6, 250, 16) in:th size:12 bold:YES color:EH_ACCENT align:NSTextAlignmentLeft];
    _thSync = [self label:CGRectMake(tw - 84, 6, 74, 18) in:th size:12 bold:YES color:EH(20, 20, 20) align:NSTextAlignmentCenter];
    _thSync.layer.backgroundColor = EH_AMBER.CGColor; _thSync.text = @"SYNC"; _thSync.hidden = YES;
    _thBig = [self label:CGRectMake(10, 24, 190, 62) in:th size:52 bold:YES color:EH_ACCENT align:NSTextAlignmentLeft];
    _thBig.font = [UIFont monospacedDigitSystemFontOfSize:52 weight:UIFontWeightBold];
    _thBig2 = [self label:CGRectMake(204, 24, 210, 62) in:th size:52 bold:YES color:EH_ACCENT align:NSTextAlignmentLeft];
    _thBig2.font = [UIFont monospacedDigitSystemFontOfSize:52 weight:UIFontWeightBold];
    _thState = [self label:CGRectMake(204, 26, 210, 58) in:th size:19 bold:YES color:EH_WHITE align:NSTextAlignmentLeft];
    _thState.numberOfLines = 3;
    _chargeTrack = [self box:CGRectMake(10, 92, tw - 20, 10) color:EH(48, 52, 58) radius:0 in:th];
    _chargeFill = [self box:CGRectMake(0, 0, 0, 10) color:EH_ACCENT radius:0 in:_chargeTrack];
    _thSub = [self label:CGRectMake(10, 106, tw - 20, 18) in:th size:12.5 bold:NO color:EH_GREY align:NSTextAlignmentLeft];

    _offCover = [[UIView alloc] initWithFrame:_screen.bounds]; _offCover.backgroundColor = EH(6, 6, 7);
    [_screen addSubview:_offCover];
}

#pragma mark - Tasti

- (void)socket:(NSString *)sensor label:(NSString *)lbl key:(NSString *)name y:(CGFloat)y color:(UIColor *)c {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(20, y, 106, 68);
    b.backgroundColor = EH(52, 55, 61); b.layer.cornerRadius = 9; b.layer.borderWidth = 1; b.layer.borderColor = EH(96, 100, 108).CGColor;
    [b addTarget:self action:@selector(plugTapped:) forControlEvents:UIControlEventTouchUpInside];
    b.accessibilityIdentifier = sensor;
    b.layer.shouldRasterize = YES; b.layer.rasterizationScale = [UIScreen mainScreen].scale;
    [self addSubview:b];
    UILabel *l = [self label:CGRectMake(0, 4, 106, 16) in:b size:12.5 bold:YES color:EH_WHITE align:NSTextAlignmentCenter]; l.text = lbl;
    // presa incassata: rettangolo scuro con quattro contatti; con il sensore collegato compare la spina colorata
    UIView *port = [self box:CGRectMake(21, 26, 64, 30) color:EH(10, 10, 11) radius:6 in:b];
    port.layer.borderWidth = 1.5; port.layer.borderColor = EH(120, 125, 132).CGColor;
    for (int i = 0; i < 4; i++) [self box:CGRectMake(11 + i * 12, 11, 6, 8) color:EH(150, 130, 60) radius:1.5 in:port];
    UIView *plug = [self box:CGRectMake(17, 22, 72, 38) color:c radius:7 in:b];
    plug.layer.borderWidth = 1.5; plug.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.45].CGColor;
    [self box:CGRectMake(8, 8, 56, 5) color:[UIColor colorWithWhite:1 alpha:0.35] radius:2.5 in:plug];
    [self box:CGRectMake(8, 25, 56, 5) color:[UIColor colorWithWhite:0 alpha:0.25] radius:2.5 in:plug];
    plug.hidden = YES;
    _plugMark[sensor] = plug; _keys[name] = b;
}

- (void)buildKeys {
    // (4) prese dei sensori
    NSArray *socks = @[@[@"ecg", @"ECG", @"PLUG-ECG", EH_HR], @[@"spo2", @"SpO₂", @"PLUG-SPO2", EH_SPO2], @[@"nibp", @"NIBP", @"PLUG-NIBP", EH_NIBP],
                       @[@"etco2", @"CO₂", @"PLUG-CO2", EH_CO2], @[@"temp", @"TEMP", @"PLUG-TEMP", EH_TEMP], @[@"pads", @"PIASTRE", @"PLUG-PADS", EH_ACCENT]];
    CGFloat y = 64;
    for (NSArray *s in socks) { [self socket:s[0] label:s[1] key:s[2] y:y color:s[3]]; y += 75; }
    // (3) dispositivo: accensione (tasto tondo scuro con anello verde sottile) e menu
    UIButton *pw = [self key:@"POWER" title:@"" frame:CGRectMake(45, 546, 56, 56) bg:EH_KEY fg:EH_WHITE size:12 radius:28 action:@selector(kPower)];
    pw.layer.borderWidth = 1.5; pw.layer.borderColor = EH(70, 190, 110).CGColor;
    CAShapeLayer *sym = [CAShapeLayer layer]; CGPoint c = CGPointMake(28, 30);
    UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:c radius:11 startAngle:-M_PI_2 + 0.62 endAngle:-M_PI_2 - 0.62 + 2 * M_PI clockwise:YES];
    [p moveToPoint:CGPointMake(c.x, c.y - 16)]; [p addLineToPoint:CGPointMake(c.x, c.y - 3)];
    sym.path = p.CGPath; sym.strokeColor = EH(120, 220, 150).CGColor; sym.fillColor = nil; sym.lineWidth = 2.5; sym.lineCap = kCALineCapRound;
    [pw.layer addSublayer:sym];
    [self key:@"MENU" title:@"MENU" frame:CGRectMake(22, 646, 102, 46) bg:EH_KEY fg:EH_WHITE size:13 action:@selector(kMenu)];

    // (2) monitoraggio
    [self key:@"NIBP" title:@"AVVIA\nNIBP" frame:CGRectMake(150, 562, 102, 58) bg:EH_KEY fg:EH_WHITE size:13 action:@selector(kNibp)];
    [self key:@"SILENCE" title:@"SILENZIA\nALLARMI" frame:CGRectMake(259, 562, 102, 58) bg:EH_KEY fg:EH_AMBER size:13 action:@selector(kSilence)];
    UIButton *ld = [self key:@"LEAD" title:@"DERIVAZIONE" frame:CGRectMake(368, 562, 102, 58) bg:EH_KEY fg:EH_WHITE size:11.5 action:@selector(kLead)];
    ld.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 16, 4);
    _leadKeyNote = [self label:CGRectMake(4, 34, 94, 16) in:ld size:11 bold:NO color:EH_HR align:NSTextAlignmentCenter];

    // (1) terapia elettrica — colonna: modo, poi 1 energia, 2 carica, 3 scarica in ordine di lettura
    NSArray *modes = @[@[@"MODE-DAE", @"DAE"], @[@"MODE-MAN", @"MANUALE"], @[@"MODE-PACE", @"PACER"]];
    for (NSUInteger i = 0; i < modes.count; i++) {
        CGFloat x = 800 + i * 69;
        UIButton *b = [self key:modes[i][0] title:modes[i][1] frame:CGRectMake(x, 88, 64, 36) bg:EH_KEYHI fg:EH_WHITE size:11.5 action:@selector(modeTapped:)];
        b.tag = (NSInteger)i + 1; b.titleEdgeInsets = UIEdgeInsetsMake(0, 1, 0, 1); b.titleLabel.adjustsFontSizeToFitWidth = YES; b.titleLabel.minimumScaleFactor = 0.8; b.titleLabel.numberOfLines = 1;
        _modeLed[modes[i][0]] = [self box:CGRectMake(x + 20, 81, 24, 4) color:EH(70, 50, 30) radius:2 in:self];
    }
    [self key:@"ENERGY-" title:@"−" frame:CGRectMake(800, 202, 98, 44) bg:EH_KEYHI fg:EH_WHITE size:26 action:@selector(kEnergyDown)];
    [self key:@"ENERGY+" title:@"+" frame:CGRectMake(904, 202, 98, 44) bg:EH_KEYHI fg:EH_WHITE size:26 action:@selector(kEnergyUp)];
    [self key:@"CHARGE" title:@"CARICA" frame:CGRectMake(800, 278, 202, 48) bg:EH(120, 96, 44) fg:EH(250, 232, 190) size:17 action:@selector(kCharge)];
    [self key:@"DISARM" title:@"ANNULLA\nCARICA" frame:CGRectMake(800, 332, 98, 38) bg:EH_KEY fg:EH_WHITE size:10.5 action:@selector(kDisarm)];
    [self key:@"SYNC" title:@"SYNC" frame:CGRectMake(904, 332, 98, 38) bg:EH_KEY fg:EH_AMBER size:13 action:@selector(kSync)];
    // 3 scarica: tasto rosso scuro opaco, simbolo piccolo, spia ad anello che si accende solo a defibrillatore carico
    UIButton *sh = [self key:@"SHOCK" title:@"" frame:CGRectMake(800, 404, 202, 62) bg:EH_SHOCK fg:EH_WHITE size:12 action:@selector(kShock)];
    sh.layer.borderColor = EH(70, 16, 14).CGColor;
    _shockLamp = [self box:CGRectMake(14, 19, 24, 24) color:EH(60, 18, 16) radius:12 in:sh];
    _shockLamp.layer.borderWidth = 1.5; _shockLamp.layer.borderColor = EH(196, 120, 110).CGColor;
    CAShapeLayer *bolt = [CAShapeLayer layer]; bolt.path = SFBoltPath(CGRectMake(86, 17, 30, 28)).CGPath;
    bolt.fillColor = EH(238, 214, 206).CGColor; bolt.strokeColor = EH(60, 14, 12).CGColor; bolt.lineWidth = 0.75; bolt.lineJoin = kCALineJoinRound;
    [sh.layer addSublayer:bolt];
    UILabel *n3 = [self label:CGRectMake(162, 19, 26, 24) in:sh size:17 bold:YES color:EH(238, 214, 206) align:NSTextAlignmentCenter]; n3.text = @"3";
    [self key:@"ANALYZE" title:@"ANALIZZA (DAE)" frame:CGRectMake(800, 132, 202, 38) bg:EH_KEY fg:EH(150, 196, 240) size:13.5 action:@selector(kAnalyze)];      // l'analisi viene prima della carica: sotto i modi, sopra il percorso 1-2-3
    // pacer, nella fascia bassa dello stesso pannello: frequenza, uscita, modo, avvio
    [self key:@"RATE-" title:@"−" frame:CGRectMake(504, 588, 77, 74) bg:EH_KEY fg:EH_WHITE size:26 action:@selector(kRateDown)];
    [self key:@"RATE+" title:@"+" frame:CGRectMake(587, 588, 77, 74) bg:EH_KEY fg:EH_WHITE size:26 action:@selector(kRateUp)];
    [self key:@"MA-" title:@"−" frame:CGRectMake(680, 588, 77, 74) bg:EH_KEY fg:EH_WHITE size:26 action:@selector(kMaDown)];
    [self key:@"MA+" title:@"+" frame:CGRectMake(763, 588, 77, 74) bg:EH_KEY fg:EH_WHITE size:26 action:@selector(kMaUp)];
    [self key:@"DEMAND" title:@"DEMAND / FISSO" frame:CGRectMake(862, 568, 138, 50) bg:EH_KEY fg:EH_WHITE size:12 action:@selector(kDemand)];
    [self key:@"PACE" title:@"AVVIA" frame:CGRectMake(862, 626, 138, 76) bg:EH_KEY fg:EH(120, 220, 150) size:17 action:@selector(kPace)];
}

#pragma mark - Stato

- (void)setAlarmText:(NSString *)text level:(NSInteger)level severity:(NSDictionary *)severity muted:(BOOL)muted remaining:(NSInteger)rem {
    _alarmText = text; _alarmLevel = level; _severity = severity; _muted = muted; _mutedRem = rem;
}
- (BOOL)poweredOff { return _off; }
- (void)setDevicePowered:(BOOL)on { if (on != !_off) [self kPower]; }
- (BOOL)on { return !_off; }
- (void)note:(NSString *)t { _note = t; _noteUntil = CACurrentMediaTime() + 3; }

- (void)updateWithSnapshot:(SLSnapshot *)s {
    _snap = s;
    SLDefibInfo *d = s.defib;
    // sorgente della traccia ECG: gli elettrodi; se ci sono solo le piastre, le piastre
    // derivazione: con una sola sorgente collegata si usa quella; con entrambe decide l'operatore (tasto DERIVAZIONE)
    BOOL pads = s.padsConnected && (!s.ecgConnected || _leadPads);
    if (pads != _pads) { _pads = pads; [_ecg resetAtTime:CACurrentMediaTime()]; }
    EHSetText(_leadKeyNote, _pads ? @"piastre" : @"II");
    BOOL src = _pads ? s.padsConnected : s.ecgConnected;
    _ecg.disconnected = !src; _ecg.noSignalText = nil;
    EHSetText(_ecgLbl, _pads ? @"ECG dalle piastre" : @"ECG  II");
    _pleth.disconnected = !s.spo2Connected; _pleth.noSignalText = nil;
    _pleth.flatWhenNoSignal = s.spo2Connected && (!s.pulsePresent || s.spo2Searching);
    _co2.disconnected = !s.etco2Connected; _co2.noSignalText = nil;
    for (NSString *k in _plugMark) {
        BOOL on = [@{@"ecg": @(s.ecgConnected), @"spo2": @(s.spo2Connected), @"nibp": @(s.nibpConnected), @"etco2": @(s.etco2Connected),
                     @"temp": @(s.tempConnected), @"pads": @(s.padsConnected)}[k] boolValue];
        _plugMark[k].hidden = !on;
    }
    NSString *hr = @"---";
    if (src) {
        NSString *r = s.rhythm;
        if (d.paceCapture) hr = [NSString stringWithFormat:@"%ld", (long)d.paceRate];
        else if ([r isEqualToString:SLRhythmVentricularFib]) hr = @"FV";
        else if ([r isEqualToString:SLRhythmVentricularTachy] || [r isEqualToString:SLRhythmVentricularTachyPulse]) hr = @"TV";
        else if ([r isEqualToString:SLRhythmAsystole]) hr = @"Asi";
        else hr = [NSString stringWithFormat:@"%ld", (long)SFJ(@"hr", s.heartRate, 2)];
    }
    EHSetText(_hr, hr);
    BOOL leak = s.nibpStatus == SLNibpError && [s.nibpError isEqualToString:@"cuff"];
    EHSetText(_nibp, s.nibpLastSystolic >= 0 ? [NSString stringWithFormat:@"%ld/%ld (%ld)", (long)s.nibpLastSystolic, (long)s.nibpLastDiastolic, (long)s.meanArterialPressure] : @"---/---");
    EHSetText(_nibpSt, s.nibpStatus == SLNibpMeasuring ? @"misura in corso…" : (leak ? @"bracciale non collegato" :
                   (s.nibpStatus == SLNibpError ? ([s.nibpError isEqualToString:@"motion"] ? @"artefatto da movimento" : @"nessun polso rilevato") :
                   (s.nibpMeasuredAt ? [@"misurata alle " stringByAppendingString:[_fmtHM stringFromDate:s.nibpMeasuredAt]] : (s.nibpConnected ? @"premere AVVIA NIBP" : @"bracciale non collegato")))));
    EHSetText(_et, (s.etco2Connected && s.respRate > 0) ? [NSString stringWithFormat:@"%ld", (long)SFJ(@"co2", s.etco2, 1)] : @"---");
    EHSetText(_rr, (s.etco2Connected || s.ecgConnected) ? [NSString stringWithFormat:@"%ld", (long)SFJ(@"rr", s.respRate, 1)] : @"---");
    EHSetText(_temp, s.tempConnected ? [[NSString stringWithFormat:@"%.1f", s.temperatureTenths / 10.0] stringByReplacingOccurrencesOfString:@"." withString:@","] : @"---");

    // modo attivo: spia accesa e nome nella barra di stato
    NSString *active = d.mode == SLDefibAED ? @"MODE-DAE" : (d.mode == SLDefibManual ? @"MODE-MAN" : (d.mode == SLDefibPacer ? @"MODE-PACE" : @"MODE-MON"));
    // i tasti di ogni terapia sono attivi solo nel loro modo (gli altri restano visibili ma spenti)
    BOOL pm = !_off && d.mode == SLDefibPacer, mm = !_off && d.mode == SLDefibManual, am = !_off && d.mode == SLDefibAED;
    // tasto spento = stesso tasto, più scuro e con la scritta grigia: OPACO (niente trasparenze, che costano a ogni fotogramma)
    NSDictionary *groups = @{@"RATE-": @(pm), @"RATE+": @(pm), @"MA-": @(pm), @"MA+": @(pm), @"DEMAND": @(pm), @"PACE": @(pm),
                             @"ENERGY-": @(mm), @"ENERGY+": @(mm), @"CHARGE": @(mm), @"DISARM": @(mm), @"SYNC": @(mm),
                             @"ANALYZE": @(am), @"SHOCK": @((BOOL)(mm || am))};
    for (NSString *k in groups) {
        UIButton *b = _keys[k]; BOOL on = [groups[k] boolValue];
        if (b.enabled == on && b.tag != 0) continue;            // nessun cambiamento: non si tocca il tasto
        if (b.tag == 0) { b.tag = 77; objc_setAssociatedObject(b, "ehbg", b.backgroundColor, OBJC_ASSOCIATION_RETAIN); }
        b.enabled = on;
        b.backgroundColor = on ? objc_getAssociatedObject(b, "ehbg") : EH(50, 53, 58);
        [b setTitleColor:EH(104, 109, 116) forState:UIControlStateDisabled];
    }
    EHSetText(_modeLbl, @{@"MODE-MON": @"MONITOR", @"MODE-DAE": @"DAE", @"MODE-MAN": @"DEFIBRILLATORE MANUALE", @"MODE-PACE": @"PACER"}[active]);
    EHSetTitle(_keys[@"PACE"], d.paceRunning ? @"FERMA" : @"AVVIA");
    EHSetTitleColor(_keys[@"PACE"], d.paceRunning ? EH_RED : EH(120, 220, 150));
    EHSetTitleColor(_keys[@"SYNC"], d.sync ? EH(30, 24, 8) : EH_AMBER);
    if (mm) EHSetBg(_keys[@"SYNC"], d.sync ? EH_AMBER : EH_KEY);
    EHSetTitle(_keys[@"SILENCE"], s.alarmsMuted ? @"RIATTIVA\nALLARMI" : @"SILENZIA\nALLARMI");
    [self updateTherapy:d];
}

// riquadro della terapia: cambia contenuto con il modo
- (void)updateTherapy:(SLDefibInfo *)d {
    CGFloat full = _chargeTrack.bounds.size.width;
    EHSetHidden(_thSync, !(d.mode == SLDefibManual && d.sync));
    EHSetHidden(_thBig2, YES); EHSetHidden(_thState, NO); EHSetHidden(_chargeTrack, YES);
    EHSetFrame(_thBig, CGRectMake(10, 24, 190, 62));
    NSString *shocks = d.shockCount ? [NSString stringWithFormat:@"Scariche erogate: %ld", (long)d.shockCount] : @"Nessuna scarica erogata";
    if (d.mode == SLDefibManual) {
        EHSetText(_thTitle, @"DEFIBRILLATORE MANUALE");
        EHSetText(_thBig, [NSString stringWithFormat:@"%ld J", (long)(d.charge == SLChargeNone ? d.energy : d.chargedEnergy ?: d.energy)]);
        EHSetText(_thState, d.charge == SLChargeCharging ? @"IN CARICA…" : (d.charge == SLChargeReady ? (d.syncPending ? @"IN ATTESA\nDELL'ONDA R" : @"CARICO\nPREMERE SCARICA") : @"PRONTO\nPER LA CARICA"));
        EHSetColor(_thState, d.charge == SLChargeReady ? EH_RED : EH_WHITE);
        EHSetHidden(_chargeTrack, NO);
        EHSetFrame(_chargeFill, CGRectMake(0, 0, full * (d.charge == SLChargeReady ? 1 : (d.charge == SLChargeCharging ? d.chargeProgress : 0)), 10));
        EHSetText(_thSub, [NSString stringWithFormat:@"%@%@", shocks, d.lastShockEnergy ? [NSString stringWithFormat:@"  ·  ultima: %ld J%@", (long)d.lastShockEnergy, d.lastShockSynced ? @" sincronizzata" : @""] : @""]);
    } else if (d.mode == SLDefibAED) {
        EHSetText(_thTitle, @"DAE — SEGUIRE LE ISTRUZIONI");
        EHSetFrame(_thBig, CGRectMake(10, 24, 96, 62));
        EHSetText(_thBig, (d.aedPhase == SLAedCPR || d.aedPhase == SLAedAnalyzing) && d.aedRemaining > 0 ? [NSString stringWithFormat:@"%ld:%02ld", (long)d.aedRemaining / 60, (long)d.aedRemaining % 60] : @"");
        EHSetFrame(_thState, CGRectMake(_thBig.text.length ? 112 : 10, 26, _thBig.text.length ? 302 : 404, 58));
        EHSetText(_thState, EHText(d.message) ?: @"");
        EHSetColor(_thState, d.aedPhase == SLAedReady ? EH_RED : EH_WHITE);
        EHSetHidden(_chargeTrack, d.charge == SLChargeNone);
        EHSetFrame(_chargeFill, CGRectMake(0, 0, full * (d.charge == SLChargeReady ? 1 : d.chargeProgress), 10));
        EHSetText(_thSub, [NSString stringWithFormat:@"%@  ·  energia %ld J", shocks, (long)d.energy]);
        return;
    } else if (d.mode == SLDefibPacer) {
        EHSetText(_thTitle, d.paceDemand ? @"PACER — MODO DEMAND" : @"PACER — MODO FISSO");
        EHSetText(_thBig, [NSString stringWithFormat:@"%ld", (long)d.paceSetRate]);
        EHSetHidden(_thBig2, NO); EHSetHidden(_thState, YES);
        EHSetText(_thBig2, [NSString stringWithFormat:@"%ld", (long)d.paceOutput]);
        NSString *st = !d.paceRunning ? @"fermo" : (d.pacePaused ? @"in pausa" : (!d.paceActive ? @"non stimola" : (d.paceCapture ? (d.paceMechanical ? @"CATTURA con polso" : @"cattura elettrica") : @"nessuna cattura")));
        EHSetText(_thSub, [NSString stringWithFormat:@"ppm (frequenza)          mA (uscita)          stato: %@", st]);
        EHSetFrame(_thBig, CGRectMake(10, 24, 150, 62)); EHSetFrame(_thBig2, CGRectMake(170, 24, 150, 62));
        return;
    } else {
        EHSetText(_thTitle, @"TERAPIA ELETTRICA");
        EHSetText(_thBig, @"");
        EHSetFrame(_thState, CGRectMake(10, 26, 404, 58));
        EHSetText(_thState, @"Solo monitoraggio.\nPer la terapia scegliere il modo:\nDAE · MANUALE · PACER"); EHSetColor(_thState, EH_GREY);
        EHSetText(_thSub, shocks);
        return;
    }
    EHSetFrame(_thState, CGRectMake(204, 26, 210, 58));
}

- (void)tick:(NSTimeInterval)now snapshot:(SLSnapshot *)s {
    _snap = s;
    SLDefibInfo *d = s.defib;
    BOOL run = s.simulationRunning && !_off;
    for (TraceView *t in @[_ecg, _pleth, _co2]) { if (run) [t advanceTo:now]; else [t resetAtTime:now]; }
    if (now - _lastSlow < 0.25) return;
    _lastSlow = now;
    BOOL blink = fmod(now, 0.5) < 0.25;
    EHSetText(_clock, [_fmt stringFromDate:[NSDate date]]);
    NSInteger el = (NSInteger)(now - _onAt);
    EHSetText(_elapsed, [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)el / 3600, (long)(el / 60) % 60, (long)el % 60]);
    UIDevice *dev = [UIDevice currentDevice]; if (!dev.batteryMonitoringEnabled) dev.batteryMonitoringEnabled = YES;
    float lvl = dev.batteryLevel;
    BOOL chg = dev.batteryState == UIDeviceBatteryStateCharging || dev.batteryState == UIDeviceBatteryStateFull;
    EHSetText(_batt, lvl < 0 ? @"batteria ?" : [NSString stringWithFormat:@"%@ %ld%%", chg ? @"in carica" : @"batteria", (long)lroundf(lvl * 100)]);
    EHSetColor(_batt, (lvl >= 0 && lvl < 0.2 && !chg) ? EH_RED : EH_WHITE);
    EHSetText(_sp, s.spo2Displayable ? (s.lowPerfusion && fmod(now, 6) < 4 ? @"?" : [NSString stringWithFormat:@"%ld", (long)SFJ(@"spo2", s.spo2, 1)]) : @"---");
    // valori in allarme lampeggianti, spia in alto
    NSDictionary *map = @{@"hr": _hr, @"spo2": _sp, @"etco2": _et, @"nibp": _nibp};
    for (NSString *k in map) { NSInteger l2 = [_severity[k] integerValue]; EHSetAlpha((UILabel *)map[k], (l2 >= 2 && !blink) ? 0.3 : 1); }
    EHSetBg(_alarmLamp, _off ? EH(60, 20, 18) : (_alarmLevel == 3 ? (blink ? EH(255, 40, 30) : EH(90, 20, 18)) : (_alarmLevel > 0 ? (fmod(now, 1) < 0.5 ? EH(250, 200, 30) : EH(90, 70, 16)) : EH(60, 20, 18))));
    EHSetBg(_powerLed, _off ? EH(40, 60, 44) : EH(70, 235, 110));
    BOOL ready = !_off && d.charge == SLChargeReady && !d.syncPending;
    EHSetBg(_shockLamp, ready ? (blink ? EH(255, 132, 104) : EH(214, 66, 50)) : EH(60, 18, 16));      // solo la spia si accende: il tasto resta opaco
    // riga dei messaggi: nota del dispositivo, messaggio della terapia (manuale e pacer), poi l'allarme
    NSString *m = (_note && now < _noteUntil) ? _note : nil;
    if (!m) _note = nil;
    if (!m && (d.mode == SLDefibManual || d.mode == SLDefibPacer)) m = EHText(d.message);
    BOOL isAlarm = NO;
    if (!m.length && _alarmLevel > 0) { m = _muted ? [NSString stringWithFormat:@"Allarmi silenziati %ld s · %@", (long)_mutedRem, _alarmText ?: @""] : _alarmText; isAlarm = YES; }
    EHSetText(_msg, m ?: @"");
    EHSetColor(_msg, isAlarm ? (_alarmLevel == 3 ? EH_RED : EH_AMBER) : EH_WHITE);
    [self updateTherapy:d];
}

- (void)resetTracesAt:(NSTimeInterval)t { for (TraceView *v in @[_ecg, _pleth, _co2]) [v resetAtTime:t]; }

#pragma mark - Azioni

- (BOOL)cmd:(NSString *)name value:(id)value {
    NSMutableDictionary *c = [@{@"command": name} mutableCopy];
    if (value) c[@"value"] = value;
    NSString *err = nil;
    BOOL ok = [_state applyCommand:c error:&err];
    if ([name hasPrefix:@"defib_"]) SFLog(@"ExtraHView: %@ %@ -> %@", name, value ?: @"", ok ? @"ok" : @"rifiutato");
    _snap = [_state snapshot]; [self updateWithSnapshot:_snap];
    return ok;
}

- (void)kPower {
    _off = !_off;
    _state.devicePowered = !_off;
    _offCover.hidden = !_off;
    [self closePopup];
    if (_off) { if (_snap.defib.paceRunning) [self cmd:@"defib_pacer" value:@{@"running": @NO}]; [self cmd:@"defib_mode" value:@"off"]; }
    else { _onAt = CACurrentMediaTime(); [self resetTracesAt:_onAt]; [self note:@"Autotest superato"]; }
    [self updateWithSnapshot:[_state snapshot]];
}

- (void)plugTapped:(UIButton *)b {
    if (![self on]) return;
    NSString *k = b.accessibilityIdentifier;
    BOOL on = [@{@"ecg": @(_snap.ecgConnected), @"spo2": @(_snap.spo2Connected), @"nibp": @(_snap.nibpConnected), @"etco2": @(_snap.etco2Connected),
                 @"temp": @(_snap.tempConnected), @"pads": @(_snap.padsConnected)}[k] boolValue];
    if (!on) [self cmd:@"set_sensor" value:@{@"sensor": k, @"connected": @YES}];       // un tocco collega; non scollega mai
}

- (void)kLead {
    if (![self on]) return;
    if (_snap.ecgConnected && _snap.padsConnected) { _leadPads = !_leadPads; [self updateWithSnapshot:_snap]; }
    else [self note:_snap.ecgConnected || _snap.padsConnected ? @"Una sola sorgente ECG collegata" : @"Collegare gli elettrodi ECG o le piastre"];
}
// i tasti del modo sono a scatto: di nuovo lo stesso tasto spegne la terapia (resta il monitoraggio)
- (void)modeTapped:(UIButton *)b {
    if (![self on]) return;
    SLDefibInfo *d = _snap.defib;
    NSString *want = @[@"off", @"aed", @"manual", @"pacer"][(NSUInteger)b.tag];
    if ((b.tag == 1 && d.mode == SLDefibAED) || (b.tag == 2 && d.mode == SLDefibManual) || (b.tag == 3 && d.mode == SLDefibPacer)) { want = @"off"; b = nil; }
    NSInteger tag = b ? b.tag : 0;
    if (d.paceRunning && tag != 3) [self cmd:@"defib_pacer" value:@{@"running": @NO}];
    if (d.sync && tag != 2) [self cmd:@"defib_sync" value:@NO];
    [self cmd:@"defib_mode" value:want];
}

// scala delle energie di extraH (bifasico): sottoinsieme di quelle del modello
+ (NSArray<NSNumber *> *)energies { return @[@5, @10, @20, @30, @50, @70, @100, @120, @150, @170, @200, @300, @360]; }
- (void)energyStep:(NSInteger)dir {
    if (![self on]) return;
    if (_snap.defib.mode != SLDefibManual) { [self note:@"L'energia si sceglie nel modo MANUALE"]; return; }
    NSArray<NSNumber *> *list = [ExtraHView energies];
    NSInteger cur = _snap.defib.energy, i = 0;
    for (NSInteger k = 0; k < (NSInteger)list.count; k++) if (list[(NSUInteger)k].integerValue <= cur) i = k;
    i = MAX(0, MIN((NSInteger)list.count - 1, i + dir));
    [self cmd:@"defib_energy" value:list[(NSUInteger)i]];
}
- (void)kEnergyUp { [self energyStep:1]; }
- (void)kEnergyDown { [self energyStep:-1]; }
- (void)kCharge {
    if (![self on]) return;
    if (_snap.defib.mode != SLDefibManual) { [self note:@"La carica manuale è nel modo MANUALE"]; return; }
    if (![self cmd:@"defib_charge" value:nil] && !_snap.padsConnected) [self note:@"Collegare le piastre"];
}
- (void)kDisarm { if ([self on] && _snap.defib.charge != SLChargeNone) { [self cmd:@"defib_disarm" value:nil]; [self note:@"Carica annullata"]; } }
- (void)kShock { if ([self on]) [self cmd:@"defib_shock" value:nil]; }
- (void)kSync {
    if (![self on]) return;
    if (_snap.defib.mode != SLDefibManual) { [self note:@"SYNC è disponibile nel modo MANUALE"]; return; }
    [self cmd:@"defib_sync" value:@((BOOL)!_snap.defib.sync)];
}
- (void)kAnalyze {
    if (![self on]) return;
    if (_snap.defib.mode != SLDefibAED) { [self note:@"L'analisi è nel modo DAE"]; return; }
    [self cmd:@"defib_analyze" value:nil];
}
- (void)kNibp { if ([self on]) { [_state startNibpMeasurementError:NULL]; [self updateWithSnapshot:[_state snapshot]]; } }
- (void)kSilence { if ([self on]) [self cmd:@"mute_alarms" value:[_state snapshot].alarmsMuted ? @NO : @120]; }
- (BOOL)pacer { if (![self on]) return NO; if (_snap.defib.mode != SLDefibPacer) { [self note:@"Prima scegliere il modo PACER"]; return NO; } return YES; }
- (void)kRateUp   { if ([self pacer]) [self cmd:@"defib_pacer" value:@{@"rate": @(MIN(180, _snap.defib.paceSetRate + 5))}]; }
- (void)kRateDown { if ([self pacer]) [self cmd:@"defib_pacer" value:@{@"rate": @(MAX(30, _snap.defib.paceSetRate - 5))}]; }
- (void)kMaUp     { if ([self pacer]) [self cmd:@"defib_pacer" value:@{@"output_ma": @(MIN(200, _snap.defib.paceOutput + 5))}]; }
- (void)kMaDown   { if ([self pacer]) [self cmd:@"defib_pacer" value:@{@"output_ma": @(MAX(0, _snap.defib.paceOutput - 5))}]; }
- (void)kDemand   { if ([self pacer]) [self cmd:@"defib_pacer" value:@{@"demand": @((BOOL)!_snap.defib.paceDemand)}]; }
- (void)kPace     { if ([self pacer]) [self cmd:@"defib_pacer" value:@{@"running": @((BOOL)!_snap.defib.paceRunning)}]; }

#pragma mark - Menu

- (void)closePopup { [_popup removeFromSuperview]; _popup = nil; for (NSString *k in @[@"M-LAYOUT", @"M-VOLUMI", @"M-INFO", @"M-CHIUDI"]) [_keys removeObjectForKey:k]; }
- (void)kMenu {
    if (![self on]) { if (self.onLayoutMenu) self.onLayoutMenu(); return; }      // da spento apre direttamente il menu dei layout
    if (_popup) { [self closePopup]; return; }
    _popup = [[UIView alloc] initWithFrame:CGRectMake(146 + 124, 52 + 80, 380, 300)];
    _popup.backgroundColor = EH(24, 26, 30); _popup.layer.borderWidth = 2; _popup.layer.borderColor = EH_ACCENT.CGColor;
    [self label:CGRectMake(16, 10, 348, 26) in:_popup size:18 bold:YES color:EH_ACCENT align:NSTextAlignmentLeft].text = @"Menu";
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    NSArray *rows = @[@[@"M-LAYOUT", [NSString stringWithFormat:@"Layout del monitor  (similFranz Monitor v%@)", ver], NSStringFromSelector(@selector(mLayout))],
                      @[@"M-VOLUMI", @"Volumi", NSStringFromSelector(@selector(mVolumes))],
                      @[@"M-INFO", @"Controller e PIN", NSStringFromSelector(@selector(mInfo))],
                      @[@"M-CHIUDI", @"Chiudi", NSStringFromSelector(@selector(closePopup))]];
    CGFloat y = 46;
    for (NSArray *r in rows) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(16, y, 348, 52); b.backgroundColor = EH_KEY; b.layer.borderWidth = 1; b.layer.borderColor = EH(110, 115, 122).CGColor;
        [b setTitle:r[1] forState:UIControlStateNormal]; [b setTitleColor:EH_WHITE forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:16]; b.titleLabel.adjustsFontSizeToFitWidth = YES; b.titleLabel.minimumScaleFactor = 0.6;
        b.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
        [b addTarget:self action:NSSelectorFromString(r[2]) forControlEvents:UIControlEventTouchUpInside];
        [_popup addSubview:b]; _keys[r[0]] = b;
        y += 60;
    }
    [self addSubview:_popup];
}
- (void)mLayout { [self closePopup]; if (self.onLayoutMenu) self.onLayoutMenu(); }
- (void)mVolumes { [self closePopup]; if (self.onVolumes) self.onVolumes(); }
- (void)mInfo { [self closePopup]; if (self.onInfo) self.onInfo(); }

#pragma mark - Autotest

- (BOOL)tapKey:(NSString *)k {
    UIButton *target = _keys[k];
    if (!target) { SFLog(@"SELFTEST tasto %@ inesistente", k); return NO; }
    UIWindow *w = self.window;
    CGPoint p = [target convertPoint:CGPointMake(CGRectGetMidX(target.bounds), CGRectGetMidY(target.bounds)) toView:w];
    UIView *c = [w hitTest:p withEvent:nil]; while (c && ![c isKindOfClass:[UIControl class]]) c = c.superview;
    BOOL ok = c == target;
    if (!ok) SFLog(@"SELFTEST tasto %@ -> SBAGLIATO (%@)", k, NSStringFromClass([c class]));
    if ([c isKindOfClass:[UIControl class]]) { [(UIControl *)c sendActionsForControlEvents:UIControlEventTouchDown]; [(UIControl *)c sendActionsForControlEvents:UIControlEventTouchUpInside]; }
    _snap = [_state snapshot]; [self updateWithSnapshot:_snap];
    return ok;
}

- (void)runSelfTestWithShot:(void (^)(NSString *))shot done:(void (^)(NSInteger))done {
    __block NSInteger fails = 0;
    ExtraHView *me = self; SimulationState *st = _state;
    void (^check)(BOOL, NSString *) = ^(BOOL c, NSString *what) { if (!c) fails++; SFLog(@"SELFTEST %@ %@", c ? @"PASS" : @"FAIL", what); };
    void (^set)(NSString *, id) = ^(NSString *cmd, id v) { NSMutableDictionary *d = [@{@"command": cmd} mutableCopy]; if (v) d[@"value"] = v; [st applyCommand:d error:NULL]; };
    SLDefibInfo *(^D)(void) = ^SLDefibInfo *{ return [st snapshot].defib; };
    NSMutableArray *steps = [NSMutableArray array];
    void (^step)(double, dispatch_block_t) = ^(double delay, dispatch_block_t b) { [steps addObject:@[@(delay), [b copy]]]; };

    step(0.8, ^{ shot(@"E00-spento");
                 { __block BOOL lm = NO; void (^old)(void) = me.onLayoutMenu; me.onLayoutMenu = ^{ lm = YES; }; [me tapKey:@"MENU"]; check(lm, @"spento: MENU apre il menu dei layout"); me.onLayoutMenu = old; }
                 [me tapKey:@"PLUG-ECG"]; check(![st snapshot].ecgConnected, @"spento: le prese non collegano");
                 check([me tapKey:@"POWER"] && !me->_off && [st snapshot].devicePowered, @"accensione"); });
    step(0.4, ^{ NSInteger bad = 0;
                 for (NSString *k in me->_keys) { UIButton *t = me->_keys[k];
                     CGPoint p = [t convertPoint:CGPointMake(CGRectGetMidX(t.bounds), CGRectGetMidY(t.bounds)) toView:me.window];
                     UIView *h = [me.window hitTest:p withEvent:nil]; while (h && ![h isKindOfClass:[UIControl class]]) h = h.superview;
                     if (!t.enabled) continue;                    // i tasti di un'altra terapia sono spenti: si provano nel loro modo
                     if (h != t) { bad++; SFLog(@"SELFTEST tasto non raggiungibile: %@", k); } }
                 check(bad == 0, [NSString stringWithFormat:@"tasti attivi tutti raggiungibili (%lu in tutto)", (unsigned long)me->_keys.count]);
                 check(!me->_keys[@"CHARGE"].enabled && !me->_keys[@"PACE"].enabled && !me->_keys[@"ANALYZE"].enabled && !me->_keys[@"SHOCK"].enabled, @"solo monitoraggio: i tasti della terapia sono spenti");
                 for (NSString *k in @[@"PLUG-ECG", @"PLUG-SPO2", @"PLUG-NIBP", @"PLUG-CO2", @"PLUG-TEMP", @"PLUG-PADS"]) [me tapKey:k];
                 SLSnapshot *sn = [st snapshot];
                 check(sn.ecgConnected && sn.spo2Connected && sn.nibpConnected && sn.etco2Connected && sn.tempConnected && sn.padsConnected, @"prese: tutti i sensori collegati");
                 check([me tapKey:@"LEAD"] && me->_pads, @"DERIVAZIONE: piastre"); [me tapKey:@"LEAD"]; check(!me->_pads, @"DERIVAZIONE: II");
                 [me tapKey:@"PLUG-ECG"]; check([st snapshot].ecgConnected, @"un secondo tocco non scollega");
                 check([me tapKey:@"NIBP"] && [st snapshot].nibpStatus == SLNibpMeasuring, @"AVVIA NIBP");
                 check([me tapKey:@"SILENCE"] && [st snapshot].alarmsMuted, @"SILENZIA ALLARMI"); [me tapKey:@"SILENCE"]; check(![st snapshot].alarmsMuted, @"RIATTIVA ALLARMI");
                 check([me tapKey:@"MENU"] && me->_popup, @"MENU: finestra");
                 { __block BOOL v = NO; void (^old)(void) = me.onVolumes; me.onVolumes = ^{ v = YES; }; [me tapKey:@"M-VOLUMI"]; check(v && !me->_popup, @"Menu › Volumi"); me.onVolumes = old; }
                 [me tapKey:@"MENU"];
                 { __block BOOL v = NO; void (^old)(void) = me.onInfo; me.onInfo = ^{ v = YES; }; [me tapKey:@"M-INFO"]; check(v, @"Menu › Controller e PIN"); me.onInfo = old; } });
    step(2.5, ^{ shot(@"E01-monitor"); });
    // manuale su FV: energia, carica, scarica
    step(0.3, ^{ set(@"set_rhythm", @"vf");
                 check([me tapKey:@"MODE-MAN"] && D().mode == SLDefibManual, @"modo MANUALE");
                 NSInteger e0 = D().energy; [me tapKey:@"ENERGY+"]; check(D().energy > e0, [NSString stringWithFormat:@"1 energia + (%ld -> %ld J)", (long)e0, (long)D().energy]);
                 [me tapKey:@"ENERGY-"]; check(D().energy == e0, @"1 energia −");
                 while (D().energy < 200) [me tapKey:@"ENERGY+"]; check(D().energy == 200, @"energia 200 J");
                 check([me tapKey:@"CHARGE"] && D().charge == SLChargeCharging, @"2 CARICA"); });
    step(2.5, ^{ shot(@"E02-in-carica"); });
    step(4.5, ^{ check(D().charge == SLChargeReady && D().chargedEnergy == 200, @"carico a 200 J"); shot(@"E03-carico");
                 check([me tapKey:@"DISARM"] && D().charge == SLChargeNone, @"ANNULLA CARICA"); [me tapKey:@"CHARGE"]; });
    step(7.0, ^{ check([me tapKey:@"SHOCK"] && D().shockCount == 1, @"3 SCARICA erogata"); });
    step(1.5, ^{ shot(@"E04-dopo-scarica");
                 set(@"set_rhythm", @"afib"); check([me tapKey:@"SYNC"] && D().sync, @"SYNC attivo"); [me tapKey:@"SYNC"]; check(!D().sync, @"SYNC spento"); });
    // pacer su bradicardia
    step(0.3, ^{ set(@"set_rhythm", @"sinus_bradycardia"); set(@"set_heart_rate", @38);
                 check(!me->_keys[@"RATE+"].enabled, @"tasti del pacer spenti fuori dal modo PACER");
                 check([me tapKey:@"MODE-PACE"] && D().mode == SLDefibPacer, @"modo PACER");
                 NSInteger r0 = D().paceSetRate; [me tapKey:@"RATE+"]; [me tapKey:@"RATE+"]; check(D().paceSetRate == r0 + 10, @"FREQ + (5 ppm a tocco)");
                 while (D().paceOutput < 90) [me tapKey:@"MA+"]; check(D().paceOutput == 90, @"mA + fino a 90 mA");
                 BOOL dm = D().paceDemand; [me tapKey:@"DEMAND"]; check(D().paceDemand != dm, @"DEMAND / FISSO"); [me tapKey:@"DEMAND"];
                 check([me tapKey:@"PACE"] && D().paceRunning, @"AVVIA PACER"); });
    step(3.5, ^{ check(D().paceCapture, @"cattura sopra la soglia"); shot(@"E05-pacer");
                 check([me tapKey:@"PACE"] && !D().paceRunning, @"FERMA PACER");
                 check([me tapKey:@"MODE-PACE"] && D().mode == SLDefibOff, @"di nuovo PACER: terapia spenta, solo monitoraggio"); });
    // DAE su FV
    step(0.3, ^{ set(@"set_rhythm", @"vf"); check([me tapKey:@"MODE-DAE"] && D().mode == SLDefibAED && D().aedPhase == SLAedAnalyzing, @"modo DAE: analisi"); });
    step(17.0, ^{ check(D().aedPhase == SLAedReady, @"DAE: scarica consigliata, carico"); shot(@"E06-dae");
                  check([me tapKey:@"SHOCK"] && D().aedPhase == SLAedCPR && D().shockCount == 2, @"DAE: scarica, poi RCP"); });
    step(1.5, ^{ shot(@"E07-dae-rcp"); check([me tapKey:@"ANALYZE"] && D().aedPhase == SLAedAnalyzing, @"ANALIZZA: nuova analisi");
                 check([me tapKey:@"MODE-DAE"] && D().mode == SLDefibOff, @"di nuovo DAE: solo monitoraggio");
                 check([me tapKey:@"POWER"] && me->_off && D().mode == SLDefibOff, @"spegnimento"); });

    double at = 0;
    for (NSArray *sp in steps) { at += [sp[0] doubleValue]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(at * NSEC_PER_SEC)), dispatch_get_main_queue(), sp[1]); }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((at + 0.3) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SFLog(@"SELFTEST FINE EXTRAH: %ld errori", (long)fails);
        done(fails);
    });
}

@end
