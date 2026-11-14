#import "PkViewController.h"
#import <AudioToolbox/AudioToolbox.h>
#import "CtlModel.h"
#import "CtlUI.h"
#import "PkDial.h"
#import "PkPairingView.h"
#import "PkSplashView.h"
#import "SFLog.h"

#include "PkDebugHelpers.inc"     // FindId, ListIds, AuditText (gli stessi controlli del controller iPad)

// ---------- dati ----------
// Parametri regolabili con la rotella: id, sigla, nome, unità, colore, intervallo, passo, decimali, chiave di stato, valori rapidi
static NSArray<NSDictionary *> *Params(void) {
    static NSArray *a; static dispatch_once_t once;
    dispatch_once(&once, ^{
        a = @[
          @{@"id": @"hr", @"t": @"FC", @"name": @"Frequenza cardiaca", @"u": @"bpm", @"c": CTL_HR, @"min": @20, @"max": @250, @"step": @1, @"dec": @0,
            @"k": @"heart_rate_bpm", @"q": @[@30, @40, @50, @60, @80, @100, @120, @140, @160, @180, @200]},
          @{@"id": @"spo2", @"t": @"SpO₂", @"name": @"Saturazione", @"u": @"%", @"c": CTL_SPO2, @"min": @50, @"max": @100, @"step": @1, @"dec": @0,
            @"k": @"spo2_percent", @"q": @[@70, @75, @80, @85, @88, @90, @92, @94, @96, @98, @100]},
          @{@"id": @"bp", @"t": @"PA", @"name": @"Pressione arteriosa", @"u": @"mmHg", @"c": CTL_BP, @"min": @30, @"max": @250, @"step": @1, @"dec": @0,
            @"k": @"systolic_mmhg", @"q": @[@"60/30", @"70/40", @"80/45", @"90/55", @"100/60", @"120/80", @"140/90", @"160/95", @"180/105", @"200/115"]},
          @{@"id": @"rr", @"t": @"FR", @"name": @"Frequenza respiratoria", @"u": @"atti/min", @"c": CTL_CO2, @"min": @0, @"max": @60, @"step": @1, @"dec": @0,
            @"k": @"respiratory_rate_rpm", @"q": @[@0, @6, @8, @10, @12, @16, @20, @25, @30, @35, @40]},
          @{@"id": @"etco2", @"t": @"EtCO₂", @"name": @"CO₂ di fine espirazione", @"u": @"mmHg", @"c": CTL_CO2, @"min": @0, @"max": @100, @"step": @1, @"dec": @0,
            @"k": @"etco2_mmhg", @"q": @[@0, @10, @15, @20, @25, @30, @35, @40, @45, @50, @60]},
          @{@"id": @"temp", @"t": @"Temp", @"name": @"Temperatura", @"u": @"°C", @"c": CTL_TEMP, @"min": @32, @"max": @42, @"step": @0.1, @"dec": @1,
            @"k": @"temperature_c", @"q": @[@34.0, @35.0, @36.0, @36.5, @37.0, @37.5, @38.0, @38.5, @39.0, @40.0, @41.0]},
        ];
    });
    return a;
}
static NSDictionary *Param(NSString *pid) { for (NSDictionary *p in Params()) if ([p[@"id"] isEqualToString:pid]) return p; return nil; }

static NSArray<NSArray *> *Rhythms(void) {      // chiave API, nome
    return @[@[@"sinus", @"Sinusale"], @[@"sinus_tachycardia", @"Tachicardia sinusale"], @[@"sinus_bradycardia", @"Bradicardia sinusale"],
             @[@"afib", @"Fibrillazione atriale"], @[@"vt_pulse", @"TV con polso"], @[@"vt", @"TV senza polso"],
             @[@"vf", @"Fibrillazione ventricolare"], @[@"pea", @"PEA"], @[@"asystole", @"Asistolia"]];
}
static NSString *RhythmName(NSString *r) { for (NSArray *a in Rhythms()) if ([a[0] isEqualToString:r]) return a[1]; return r ?: @"--"; }

static NSArray<NSArray *> *Sensors(void) {      // chiave API, nome, colore
    return @[@[@"ecg", @"Elettrodi ECG", CTL_HR], @[@"pads", @"Piastre defibrillatore", CTL_HR], @[@"spo2", @"Sonda SpO₂", CTL_SPO2],
             @[@"nibp", @"Bracciale NIBP", CTL_BP], @[@"art", @"Linea arteriosa", CTL_BP], @[@"etco2", @"Capnografia", CTL_CO2],
             @[@"temp", @"Sonda temperatura", CTL_TEMP]];
}
static NSArray<NSNumber *> *Times(void) { return @[@0, @10, @30, @60, @120, @300]; }
static NSString *TimeName(NSInteger s) {
    if (s == 0) return @"Subito";
    return s < 60 ? [NSString stringWithFormat:@"%ld s", (long)s] : [NSString stringWithFormat:@"%ld min", (long)s / 60];
}
static NSString *Clock(NSInteger s) { return [NSString stringWithFormat:@"%ld:%02ld", (long)MAX(0, s) / 60, (long)MAX(0, s) % 60]; }
static NSString *Fmt(double v, NSInteger dec) { return dec ? [NSString stringWithFormat:@"%.*f", (int)dec, v] : [NSString stringWithFormat:@"%ld", (long)lround(v)]; }

static const CGFloat W = 320, kTabH = 48;

@implementation PkViewController {
    NSString *_updAsked; NSInteger _updPct;
    CtlModel *_m;
    // intestazione
    UILabel *_monName, *_clock, *_batt; UIView *_dot, *_battBox, *_battFill, *_busy; UILabel *_busyText;
    // tessere
    NSMutableDictionary<NSString *, UIView *> *_tiles; NSMutableDictionary<NSString *, UILabel *> *_tileVal, *_tileSub;
    // schede
    NSInteger _tab; NSArray<UIView *> *_pages; NSMutableArray<CtlButton *> *_tabBtns;
    PkDial *_dial; NSString *_sel; NSInteger _bpPart;          // 0 = sistolica, 1 = diastolica
    UIScrollView *_chips; NSMutableArray<CtlButton *> *_chipBtns; NSString *_chipsFor;
    UIView *_dock; NSMutableArray<CtlButton *> *_timeBtns; CtlButton *_apply, *_cancel;
    NSMutableDictionary<NSString *, CtlButton *> *_rhythmBtns, *_sensorBtns, *_actBtns;
    NSMutableDictionary<NSString *, UILabel *> *_sensorState, *_actSub;
    // modifiche
    NSInteger _modeSec;
    NSMutableDictionary<NSString *, NSNumber *> *_pending, *_live;      // in coda / mentre si gira
    NSMutableDictionary<NSString *, NSArray *> *_hold;                  // appena inviati (valore, ora): finché il monitor non li conferma
    NSString *_pendingRhythm;
    // varie
    PkPairingView *_pair; UILabel *_toast; NSString *_lastMsg; CFTimeInterval _clockArmed; CtlButton *_take; BOOL _wasMine, _wasIdle;
    UIView *_outcome; NSString *_outcomeSig;
}

- (instancetype)initWithModel:(CtlModel *)model {
    if ((self = [super init])) {
        _m = model; _sel = @"hr";
        _pending = [NSMutableDictionary dictionary]; _live = [NSMutableDictionary dictionary]; _hold = [NSMutableDictionary dictionary];
        _modeSec = [[NSUserDefaults standardUserDefaults] integerForKey:@"pk_mode"];
        if (![Times() containsObject:@(_modeSec)]) _modeSec = 0;
    }
    return self;
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

#pragma mark - costruzione

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = CTL_BG;
    CGFloat H = self.view.bounds.size.height;
    [self buildHeader];
    [self buildTiles];
    UIView *pp = [[UIView alloc] initWithFrame:CGRectMake(0, 158, W, 266)], *pr = [[UIView alloc] initWithFrame:CGRectMake(0, 158, W, 266)];
    UIView *ps = [[UIView alloc] initWithFrame:CGRectMake(0, 158, W, H - 158 - kTabH)], *pa = [[UIView alloc] initWithFrame:CGRectMake(0, 158, W, H - 158 - kTabH)];
    _pages = @[pp, pr, ps, pa];
    for (UIView *v in _pages) [self.view addSubview:v];
    [self buildParams:pp]; [self buildRhythm:pr]; [self buildSensors:ps]; [self buildActions:pa];
    [self buildDock:H]; [self buildTabs:H];
    _toast = CtlLabel(CGRectMake(12, H - kTabH - 120, W - 24, 34), @"", 13, YES, CTL_INK);
    _toast.textAlignment = NSTextAlignmentCenter; _toast.backgroundColor = [UIColor colorWithRed:0.20 green:0.23 blue:0.28 alpha:0.97];
    _toast.layer.cornerRadius = 10; _toast.layer.masksToBounds = YES; _toast.numberOfLines = 2; _toast.alpha = 0;
    _toast.adjustsFontSizeToFitWidth = YES; _toast.minimumScaleFactor = 0.75;
    [self.view addSubview:_toast];
    _pair = [[PkPairingView alloc] initWithFrame:self.view.bounds model:_m]; [self.view addSubview:_pair];
    [self selectParam:@"hr"]; [self showTab:0];
    __weak PkViewController *me = self;
    _m.onUpdate = ^{ [me refresh]; };
    [self refresh];
    [self showSplash:NO];
}

- (void)buildHeader {
    _dot = [[UIView alloc] initWithFrame:CGRectMake(10, 14, 8, 8)]; _dot.layer.cornerRadius = 4; [self.view addSubview:_dot];
    _monName = CtlLabel(CGRectMake(22, 7, 104, 22), @"", 11, NO, CTL_INK2); _monName.adjustsFontSizeToFitWidth = YES; _monName.minimumScaleFactor = 0.8;
    [self.view addSubview:_monName];
    CtlButton *clk = [CtlButton buttonWithTitle:@"" style:CtlButtonQuiet color:nil frame:CGRectMake(116, 2, 88, 32) target:nil action:NULL];
    clk.backgroundColor = [UIColor clearColor]; clk.accessibilityIdentifier = @"timer";
    _clock = CtlLabel(clk.bounds, @"0:00", 20, YES, CTL_INK); _clock.font = CtlDigits(20, YES); _clock.textAlignment = NSTextAlignmentCenter; _clock.userInteractionEnabled = NO;
    [clk addSubview:_clock];
    __weak PkViewController *me = self; clk.onTap = ^{ [me clockTapped]; };
    [self.view addSubview:clk];
    _batt = CtlLabel(CGRectMake(226, 7, 54, 22), @"", 11, NO, CTL_INK2); _batt.textAlignment = NSTextAlignmentRight; [self.view addSubview:_batt];
    _battBox = [[UIView alloc] initWithFrame:CGRectMake(285, 12, 22, 11)]; _battBox.layer.borderWidth = 1; _battBox.layer.cornerRadius = 2.5;
    _battBox.layer.borderColor = CTL_INK2.CGColor; [self.view addSubview:_battBox];
    UIView *nub = [[UIView alloc] initWithFrame:CGRectMake(307.5, 15.5, 2, 4)]; nub.backgroundColor = CTL_INK2; [self.view addSubview:nub];
    _battFill = [[UIView alloc] initWithFrame:CGRectMake(2, 2, 18, 7)]; _battFill.layer.cornerRadius = 1; [_battBox addSubview:_battFill];
    // un altro controller sta comandando: barra arancione con «Prendi»
    _busy = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 36)]; _busy.backgroundColor = CtlRGB(0.36, 0.22, 0.02); _busy.hidden = YES;
    _busyText = CtlLabel(CGRectMake(10, 0, 210, 36), @"", 12, YES, CTL_ORANGE); _busyText.numberOfLines = 2;
    _busyText.adjustsFontSizeToFitWidth = YES; _busyText.minimumScaleFactor = 0.8; [_busy addSubview:_busyText];
    CtlButton *take = [CtlButton buttonWithTitle:@"Prendi" style:CtlButtonFilled color:CTL_ORANGE frame:CGRectMake(W - 92, 4, 84, 28) target:nil action:NULL];
    take.accessibilityIdentifier = @"busy.take"; _take = take; CtlModel *model = _m; take.onTap = ^{ PkClick(); [model takeControl]; };
    [_busy addSubview:take]; [self.view addSubview:_busy];
}

- (void)buildTiles {
    _tiles = [NSMutableDictionary dictionary]; _tileVal = [NSMutableDictionary dictionary]; _tileSub = [NSMutableDictionary dictionary];
    __weak PkViewController *me = self;
    NSArray *ps = Params();
    for (NSUInteger i = 0; i < ps.count; i++) {
        NSDictionary *p = ps[i]; NSString *pid = p[@"id"];
        CtlButton *t = [CtlButton buttonWithTitle:@"" style:CtlButtonQuiet color:nil frame:CGRectMake(6 + (i % 3) * 104, 38 + (i / 3) * 60, 100, 56) target:nil action:NULL];
        t.backgroundColor = CTL_CARD; t.layer.cornerRadius = 10; t.layer.borderColor = [p[@"c"] CGColor];
        t.accessibilityIdentifier = [@"tile." stringByAppendingString:pid];
        UILabel *ti = CtlLabel(CGRectMake(8, 4, 84, 14), p[@"t"], 11, YES, p[@"c"]); ti.userInteractionEnabled = NO; [t addSubview:ti];
        UILabel *v = CtlLabel(CGRectMake(6, 15, 88, 26), @"--", 24, YES, p[@"c"]); v.font = CtlDigits(24, YES); v.textAlignment = NSTextAlignmentRight;
        v.adjustsFontSizeToFitWidth = YES; v.minimumScaleFactor = 0.6; v.userInteractionEnabled = NO; [t addSubview:v];
        UILabel *s = CtlLabel(CGRectMake(6, 40, 88, 13), @"", 10, NO, CTL_INK3); s.textAlignment = NSTextAlignmentRight;
        s.adjustsFontSizeToFitWidth = YES; s.minimumScaleFactor = 0.75; s.userInteractionEnabled = NO; [t addSubview:s];
        t.onTap = ^{ PkClick(); [me selectParam:pid]; [me showTab:0]; };
        _tiles[pid] = t; _tileVal[pid] = v; _tileSub[pid] = s;
        [self.view addSubview:t];
    }
}

- (void)buildParams:(UIView *)pg {
    _dial = [[PkDial alloc] initWithFrame:CGRectMake((W - 228) / 2, 0, 228, 228)]; _dial.accessibilityIdentifier = @"dial";
    __weak PkViewController *me = self;
    _dial.onChange = ^(double v, BOOL final) { [me dialChanged:v final:final]; };
    _dial.onCenterTap = ^{ [me dialCenterTapped]; };
    [pg addSubview:_dial];
    _chips = [[CtlScrollView alloc] initWithFrame:CGRectMake(0, 230, W, 34)];
    _chips.showsHorizontalScrollIndicator = NO; _chips.contentInset = UIEdgeInsetsMake(0, 8, 0, 8);
    [pg addSubview:_chips];
}

- (void)buildRhythm:(UIView *)pg {
    _rhythmBtns = [NSMutableDictionary dictionary];
    __weak PkViewController *me = self;
    NSArray *rs = Rhythms(); CGFloat bw = (W - 16 - 6) / 2, bh = 44;
    UILabel *h = CtlLabel(CGRectMake(10, 0, W - 20, 18), @"RITMO · parte con il tempo scelto qui sotto", 11, YES, CTL_INK3);
    h.adjustsFontSizeToFitWidth = YES; h.minimumScaleFactor = 0.8; [pg addSubview:h];
    for (NSUInteger i = 0; i < rs.count; i++) {
        NSString *r = rs[i][0];
        CGRect f = i == rs.count - 1 && rs.count % 2 ? CGRectMake(8, 22 + (i / 2) * (bh + 4), W - 16, bh) : CGRectMake(8 + (i % 2) * (bw + 6), 22 + (i / 2) * (bh + 4), bw, bh);
        CtlButton *b = [CtlButton buttonWithTitle:rs[i][1] style:CtlButtonQuiet color:CTL_INK frame:f target:nil action:NULL];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:14]; b.maxLines = 2; b.accessibilityIdentifier = [@"rhythm." stringByAppendingString:r];
        b.onTap = ^{ PkClick(); [me rhythmTapped:r]; };
        _rhythmBtns[r] = b; [pg addSubview:b];
    }
}

- (void)buildSensors:(UIView *)pg {
    _sensorBtns = [NSMutableDictionary dictionary]; _sensorState = [NSMutableDictionary dictionary];
    __weak PkViewController *me = self;
    UILabel *h = CtlLabel(CGRectMake(10, 0, W - 20, 18), @"SONDE · un tocco collega o stacca", 11, YES, CTL_INK3); [pg addSubview:h];
    NSArray *ss = Sensors(); CGFloat rh = MIN(46, (pg.bounds.size.height - 26) / ss.count - 4);
    for (NSUInteger i = 0; i < ss.count; i++) {
        NSString *k = ss[i][0];
        CtlButton *b = [CtlButton buttonWithTitle:@"" style:CtlButtonQuiet color:nil frame:CGRectMake(8, 22 + i * (rh + 4), W - 16, rh) target:nil action:NULL];
        b.backgroundColor = CTL_CARD; b.layer.cornerRadius = 10; b.accessibilityIdentifier = [@"sensor." stringByAppendingString:k];
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 8, 4, rh - 16)]; bar.backgroundColor = ss[i][2]; bar.userInteractionEnabled = NO; [b addSubview:bar];
        UILabel *n = CtlLabel(CGRectMake(14, 0, 170, rh), ss[i][1], 15, YES, CTL_INK); n.userInteractionEnabled = NO; [b addSubview:n];
        UILabel *st = CtlLabel(CGRectMake(W - 16 - 112, (rh - 26) / 2, 104, 26), @"", 11, YES, CTL_INK3);
        st.textAlignment = NSTextAlignmentCenter; st.layer.cornerRadius = 13; st.layer.masksToBounds = YES; st.userInteractionEnabled = NO; [b addSubview:st];
        b.onTap = ^{ PkClick(); [me sensorTapped:k]; };
        _sensorBtns[k] = b; _sensorState[k] = st; [pg addSubview:b];
    }
}

- (void)buildActions:(UIView *)pg {
    _actBtns = [NSMutableDictionary dictionary]; _actSub = [NSMutableDictionary dictionary];
    __weak PkViewController *me = self;
    NSArray *acts = @[@[@"cpr", @"RCP", @"cpr"], @[@"vent", @"Ventila", @"lungs"], @[@"nibp", @"Misura NIBP", @"gauge"],
                      @[@"mute", @"Silenzia", @"bell.slash"], @[@"pause", @"Pausa", @"pause"], @[@"crt", @"Refill", @"tap"]];
    CGFloat bw = (W - 16 - 8) / 2, bh = MIN(104, (pg.bounds.size.height - 8 - 16) / 3);
    for (NSUInteger i = 0; i < acts.count; i++) {
        NSString *k = acts[i][0];
        CtlButton *b = [CtlButton buttonWithTitle:acts[i][1] style:CtlButtonTinted color:CTL_TINT frame:CGRectMake(8 + (i % 2) * (bw + 8), 4 + (i / 2) * (bh + 8), bw, bh) target:nil action:NULL];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:16]; [b setIcon:acts[i][2] above:YES]; b.accessibilityIdentifier = [@"act." stringByAppendingString:k];
        b.titleEdgeInsets = UIEdgeInsetsMake(0, 0, 18, 0); b.imageEdgeInsets = UIEdgeInsetsMake(-18, 0, 0, 0);
        UILabel *s = CtlLabel(CGRectMake(6, bh - 30, bw - 12, 24), @"", 11, NO, CTL_INK2); s.textAlignment = NSTextAlignmentCenter; s.numberOfLines = 2;
        s.adjustsFontSizeToFitWidth = YES; s.minimumScaleFactor = 0.8; s.userInteractionEnabled = NO; [b addSubview:s];
        b.onTap = ^{ PkClick(); [me actionTapped:k]; };
        _actBtns[k] = b; _actSub[k] = s; [pg addSubview:b];
    }
}

- (void)buildDock:(CGFloat)H {
    _dock = [[UIView alloc] initWithFrame:CGRectMake(0, H - kTabH - 94, W, 92)]; [self.view addSubview:_dock];
    __weak PkViewController *me = self;
    UILabel *l = CtlLabel(CGRectMake(10, 0, W - 20, 14), @"TEMPO DI TRANSIZIONE", 10, YES, CTL_INK3); [_dock addSubview:l];
    _timeBtns = [NSMutableArray array];
    NSArray *ts = Times(); CGFloat bw = (W - 16 - 5 * 4) / ts.count;
    for (NSUInteger i = 0; i < ts.count; i++) {
        NSInteger s = [ts[i] integerValue];
        CtlButton *b = [CtlButton buttonWithTitle:TimeName(s) style:CtlButtonQuiet color:CTL_INK frame:CGRectMake(8 + i * (bw + 4), 16, bw, 30) target:nil action:NULL];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:12]; b.maxLines = 1; b.accessibilityIdentifier = [NSString stringWithFormat:@"time.%ld", (long)s];
        b.onTap = ^{ PkClick(); [me setMode:s]; };
        [_timeBtns addObject:b]; [_dock addSubview:b];
    }
    _apply = [CtlButton buttonWithTitle:@"" style:CtlButtonFilled color:CTL_TINT frame:CGRectMake(8, 52, W - 16 - 48, 38) target:nil action:NULL];
    _apply.titleLabel.font = [UIFont boldSystemFontOfSize:14]; _apply.maxLines = 1; _apply.accessibilityIdentifier = @"apply";
    _apply.onTap = ^{ PkClick(); [me applyPending]; };
    [_dock addSubview:_apply];
    _cancel = [CtlButton buttonWithTitle:@"" style:CtlButtonQuiet color:CTL_INK2 frame:CGRectMake(W - 8 - 42, 52, 42, 38) target:nil action:NULL];
    [_cancel setIcon:@"trash" above:NO]; _cancel.accessibilityIdentifier = @"cancel";
    _cancel.onTap = ^{ PkClick(); [me cancelPending]; };
    [_dock addSubview:_cancel];
}

- (void)buildTabs:(CGFloat)H {
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, H - kTabH, W, kTabH)]; bar.backgroundColor = CTL_CARD; [self.view addSubview:bar];
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 0.5)]; line.backgroundColor = CTL_LINE; [bar addSubview:line];
    _tabBtns = [NSMutableArray array];
    __weak PkViewController *me = self;
    NSArray *tabs = @[@[@"Parametri", @"gauge"], @[@"Ritmo", @"monitor"], @[@"Sonde", @"plus"], @[@"Azioni", @"cpr"]];
    for (NSUInteger i = 0; i < tabs.count; i++) {
        CtlButton *b = [CtlButton buttonWithTitle:tabs[i][0] style:CtlButtonQuiet color:CTL_INK3 frame:CGRectMake(i * W / 4, 1, W / 4, kTabH - 1) target:nil action:NULL];
        b.backgroundColor = [UIColor clearColor]; b.titleLabel.font = [UIFont systemFontOfSize:10]; [b setIcon:tabs[i][1] above:YES];
        b.accessibilityIdentifier = [NSString stringWithFormat:@"tab.%lu", (unsigned long)i];
        b.onTap = ^{ PkClick(); [me showTab:i]; };
        [_tabBtns addObject:b]; [bar addSubview:b];
    }
}

- (void)showTab:(NSInteger)i {
    _tab = i;
    for (NSUInteger k = 0; k < _pages.count; k++) _pages[k].hidden = k != (NSUInteger)i;
    _dock.hidden = i > 1;
    for (NSUInteger k = 0; k < _tabBtns.count; k++) [_tabBtns[k] setStyle:CtlButtonQuiet color:k == (NSUInteger)i ? CTL_TINT : CTL_INK3];
    for (NSUInteger k = 0; k < _tabBtns.count; k++) _tabBtns[k].backgroundColor = [UIColor clearColor];
    [self refresh];
}

#pragma mark - valori

- (NSDictionary *)st { return _m.state ?: @{}; }
- (NSNumber *)stateNum:(NSString *)k { id v = self.st[k]; return [v isKindOfClass:[NSNumber class]] ? v : nil; }
// valore che il monitor ha impostato ora (o quello appena inviato, finché il monitor non lo conferma)
- (double)currentOf:(NSString *)k {
    NSArray *h = _hold[k]; NSNumber *s = [self stateNum:k];
    if (h) {
        if (CACurrentMediaTime() - [h[1] doubleValue] < 4 && (!s || fabs(s.doubleValue - [h[0] doubleValue]) > 0.01)) return [h[0] doubleValue];
        [_hold removeObjectForKey:k];
    }
    return s.doubleValue;
}
- (double)targetOf:(NSString *)k { NSNumber *v = _live[k] ?: _pending[k]; return v ? v.doubleValue : [self currentOf:k]; }
- (NSString *)selKey { return [_sel isEqualToString:@"bp"] ? (_bpPart ? @"diastolic_mmhg" : @"systolic_mmhg") : Param(_sel)[@"k"]; }
- (NSDictionary *)transitionFor:(NSString *)k { NSDictionary *t = self.st[@"transitions"]; t = [t isKindOfClass:[NSDictionary class]] ? t[k] : nil; return [t isKindOfClass:[NSDictionary class]] ? t : nil; }
- (BOOL)sensorOn:(NSString *)k { NSDictionary *s = self.st[@"sensors"]; return [s isKindOfClass:[NSDictionary class]] && [s[k] boolValue]; }

#pragma mark - rotella e valori rapidi

- (void)selectParam:(NSString *)pid {
    if (![_sel isEqualToString:pid]) _bpPart = 0;
    _sel = pid;
    [self configureDial];
    [self buildChips];
    [self refresh];
}
- (void)configureDial {
    NSDictionary *p = Param(_sel); BOOL bp = [_sel isEqualToString:@"bp"];
    NSString *title = bp ? (_bpPart ? @"PA diastolica" : @"PA sistolica") : p[@"t"];     // in alto nella rotella c'è poco spazio: la sigla
    double min = bp && _bpPart ? 15 : [p[@"min"] doubleValue], max = bp && _bpPart ? 160 : [p[@"max"] doubleValue];
    [_dial configureTitle:title unit:p[@"u"] color:p[@"c"] min:min max:max step:[p[@"step"] doubleValue] decimals:[p[@"dec"] integerValue]];
}
- (void)buildChips {
    if ([_chipsFor isEqualToString:_sel]) return;
    _chipsFor = _sel;
    for (UIView *v in [_chips.subviews copy]) if ([v isKindOfClass:[CtlButton class]]) [v removeFromSuperview];
    _chipBtns = [NSMutableArray array];
    __weak PkViewController *me = self;
    NSDictionary *p = Param(_sel); CGFloat x = 0;
    for (id q in p[@"q"]) {
        NSString *t = [q isKindOfClass:[NSString class]] ? q : Fmt([q doubleValue], [p[@"dec"] integerValue]);
        CGFloat w = MAX(44, [t sizeWithAttributes:@{NSFontAttributeName: CtlDigits(15, YES)}].width + 22);
        CtlButton *b = [CtlButton buttonWithTitle:t style:CtlButtonQuiet color:CTL_INK frame:CGRectMake(x, 0, w, 32) target:nil action:NULL];
        b.titleLabel.font = CtlDigits(15, YES); b.maxLines = 1; b.accessibilityIdentifier = [@"chip." stringByAppendingString:t];
        b.onTap = ^{ PkClick(); [me chipTapped:q]; };
        [_chipBtns addObject:b]; [_chips addSubview:b]; x += w + 6;
    }
    _chips.contentSize = CGSizeMake(x - 6, 32);
    // il valore attuale al centro della fila
    double cur = [self targetOf:[self selKey]]; NSUInteger best = 0; double bd = DBL_MAX; NSUInteger i = 0;
    for (id q in p[@"q"]) { double v = [q isKindOfClass:[NSString class]] ? [q doubleValue] : [q doubleValue]; if (fabs(v - cur) < bd) { bd = fabs(v - cur); best = i; } i++; }
    if (_chipBtns.count) {
        CGFloat off = CGRectGetMidX(_chipBtns[best].frame) - W / 2;
        _chips.contentOffset = CGPointMake(MAX(-8, MIN(off, _chips.contentSize.width - W + 8)), 0);
    }
}

- (void)dialChanged:(double)v final:(BOOL)final {
    NSString *k = [self selKey];
    if (!final) { _live[k] = @(v); [self refreshTiles]; return; }
    [_live removeObjectForKey:k];
    [self commit:@{k: @(v)}];
}
- (void)dialCenterTapped {
    if (![_sel isEqualToString:@"bp"]) { [self flash:@"Gira la rotella: piano = 1 alla volta, veloce = salti più grandi"]; return; }
    PkClick(); _bpPart = 1 - _bpPart; [self configureDial]; [self refresh];
}
- (void)chipTapped:(id)q {
    if ([q isKindOfClass:[NSString class]]) {          // pressione "120/80": tutte e due
        NSArray *sd = [q componentsSeparatedByString:@"/"];
        [self commit:@{@"systolic_mmhg": @([sd[0] integerValue]), @"diastolic_mmhg": @([sd[1] integerValue])}];
    } else [self commit:@{Param(_sel)[@"k"]: q}];
}

// Una modifica decisa (dito sollevato o valore rapido): subito al monitor, oppure in coda se è scelto un tempo
- (void)commit:(NSDictionary<NSString *, NSNumber *> *)vals {
    NSMutableDictionary *v = [vals mutableCopy];
    // la diastolica resta sotto la sistolica (il monitor rifiuterebbe il comando)
    if (v[@"systolic_mmhg"] || v[@"diastolic_mmhg"]) {
        double s = v[@"systolic_mmhg"] ? [v[@"systolic_mmhg"] doubleValue] : [self targetOf:@"systolic_mmhg"];
        double d = v[@"diastolic_mmhg"] ? [v[@"diastolic_mmhg"] doubleValue] : [self targetOf:@"diastolic_mmhg"];
        if (d > s - 10) { if (v[@"systolic_mmhg"] && !v[@"diastolic_mmhg"]) d = MAX(15, s - 10); else s = MIN(250, d + 10); }
        v[@"systolic_mmhg"] = @(lround(s)); v[@"diastolic_mmhg"] = @(lround(d));
    }
    if (_modeSec == 0) {
        NSNumber *temp = v[@"temperature_c"]; [v removeObjectForKey:@"temperature_c"];
        __weak PkViewController *me = self;
        if (temp) { [_m command:@"set_temperature" value:@(round(temp.doubleValue * 10) / 10) done:^(BOOL ok, NSString *e) { if (!ok) [me flash:e]; }]; _hold[@"temperature_c"] = @[temp, @(CACurrentMediaTime())]; }
        if (v.count) {
            for (NSString *k in v) _hold[k] = @[v[k], @(CACurrentMediaTime())];
            [_m command:@"transition" value:@{@"params": v, @"duration_s": @0} done:^(BOOL ok, NSString *e) { if (!ok) [me flash:e]; }];
        }
    } else {
        for (NSString *k in v) {
            if (fabs([v[k] doubleValue] - [self currentOf:k]) < 0.01 && ![self transitionFor:k]) [_pending removeObjectForKey:k];
            else _pending[k] = v[k];
        }
    }
    [self refresh];
}

- (void)rhythmTapped:(NSString *)r {
    NSString *cur = self.st[@"rhythm"];
    __weak PkViewController *me = self;
    if (_modeSec == 0) {
        if ([r isEqualToString:cur]) return;
        [_m command:@"transition" value:@{@"rhythm": r, @"duration_s": @0} done:^(BOOL ok, NSString *e) { if (!ok) [me flash:e]; }];
    } else _pendingRhythm = [r isEqualToString:_pendingRhythm] || [r isEqualToString:cur] ? nil : r;
    [self refresh];
}

- (void)setMode:(NSInteger)s {
    _modeSec = s; [[NSUserDefaults standardUserDefaults] setInteger:s forKey:@"pk_mode"];
    if (s == 0 && (_pending.count || _pendingRhythm)) [self applyPending];      // tornando a «Subito» quel che è in coda parte
    [self refresh];
}
- (NSUInteger)pendingCount { return _pending.count - (_pending[@"diastolic_mmhg"] && _pending[@"systolic_mmhg"] ? 1 : 0) + (_pendingRhythm ? 1 : 0); }
- (void)applyPending {
    if (!_pending.count && !_pendingRhythm) return;
    NSMutableDictionary *p = [_pending mutableCopy]; NSNumber *temp = p[@"temperature_c"]; [p removeObjectForKey:@"temperature_c"];
    __weak PkViewController *me = self;
    if (temp) [_m command:@"set_temperature" value:@(round(temp.doubleValue * 10) / 10) done:^(BOOL ok, NSString *e) { if (!ok) [me flash:e]; }];
    if (p.count || _pendingRhythm) {
        NSMutableDictionary *v = [@{@"params": p, @"duration_s": @(_modeSec)} mutableCopy];
        if (_pendingRhythm) v[@"rhythm"] = _pendingRhythm;
        NSString *what = [NSString stringWithFormat:@"Avviato: %@%@", TimeName(_modeSec), temp ? @" (temperatura subito)" : @""];
        [_m command:@"transition" value:v done:^(BOOL ok, NSString *e) { [me flash:ok ? what : e]; }];
    } else [self flash:@"Temperatura impostata"];
    [_pending removeAllObjects]; _pendingRhythm = nil;
    [self refresh];
}
- (void)cancelPending { [_pending removeAllObjects]; _pendingRhythm = nil; [self refresh]; }

#pragma mark - sonde e azioni

- (void)sensorTapped:(NSString *)k {
    __weak PkViewController *me = self;
    [_m command:@"set_sensor" value:@{@"sensor": k, @"connected": @((BOOL)![self sensorOn:k])} done:^(BOOL ok, NSString *e) { if (!ok) [me flash:e]; }];
}
- (void)actionTapped:(NSString *)k {
    NSDictionary *s = self.st; __weak PkViewController *me = self;
    void (^chk)(BOOL, NSString *) = ^(BOOL ok, NSString *e) { if (!ok) [me flash:e]; };
    if ([k isEqualToString:@"cpr"]) [_m command:@"set_cpr" value:@((BOOL)![s[@"cpr_active"] boolValue]) done:chk];
    else if ([k isEqualToString:@"vent"]) {
        if (![s[@"ventilation_manual"] boolValue]) { [self flash:@"Il paziente respira da solo: le ventilazioni servono in RCP o in apnea"]; return; }
        [_m command:@"ventilate" value:nil done:chk];
    }
    else if ([k isEqualToString:@"nibp"]) { [_m startNibp]; [self flash:@"Misura NIBP avviata"]; }
    else if ([k isEqualToString:@"mute"]) [_m command:@"mute_alarms" value:@((BOOL)![s[@"alarms_muted"] boolValue]) done:chk];
    else if ([k isEqualToString:@"pause"]) [_m command:@"set_simulation_running" value:@((BOOL)![s[@"simulation_running"] boolValue]) done:chk];
    else if ([k isEqualToString:@"crt"]) [_m command:@"assess_crt" value:nil done:^(BOOL ok, NSString *e) { [me flash:ok ? @"Refill misurato sul monitor" : e]; }];
}

- (void)clockTapped {
    PkClick();
    if (CACurrentMediaTime() - _clockArmed < 3) {
        _clockArmed = 0; __weak PkViewController *me = self;
        [_m command:@"reset_clock" value:nil done:^(BOOL ok, NSString *e) { [me flash:ok ? @"Timer azzerato" : e]; }];
    } else { _clockArmed = CACurrentMediaTime(); [self flash:@"Tocca ancora il timer per azzerarlo"]; }
}

- (void)flash:(NSString *)text {
    if (!text.length) return;
    _toast.text = text; [self.view bringSubviewToFront:_toast];
    [UIView animateWithDuration:0.2 animations:^{ self->_toast.alpha = 1; }];
    NSString *t = [text copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self->_toast.text isEqualToString:t]) [UIView animateWithDuration:0.4 animations:^{ self->_toast.alpha = 0; }];
    });
}

#pragma mark - aggiornamento

- (NSString *)textFor:(NSString *)pid value:(BOOL)target {
    NSDictionary *p = Param(pid);
    if ([pid isEqualToString:@"bp"]) {
        double s = target ? [self targetOf:@"systolic_mmhg"] : [self currentOf:@"systolic_mmhg"], d = target ? [self targetOf:@"diastolic_mmhg"] : [self currentOf:@"diastolic_mmhg"];
        return [NSString stringWithFormat:@"%ld/%ld", lround(s), lround(d)];
    }
    NSString *k = p[@"k"]; if (![self stateNum:k] && !_pending[k] && !_live[k]) return @"--";
    return Fmt(target ? [self targetOf:k] : [self currentOf:k], [p[@"dec"] integerValue]);
}

- (void)refreshTiles {
    NSDictionary *st = self.st;
    NSDictionary *sensorFor = @{@"hr": @[@"ecg", @"pads"], @"spo2": @[@"spo2"], @"bp": @[@"nibp", @"art"], @"etco2": @[@"etco2"], @"temp": @[@"temp"]};
    for (NSDictionary *p in Params()) {
        NSString *pid = p[@"id"]; BOOL bp = [pid isEqualToString:@"bp"];
        NSArray *keys = bp ? @[@"systolic_mmhg", @"diastolic_mmhg"] : @[p[@"k"]];
        BOOL live = NO, pend = NO; NSDictionary *tr = nil;
        for (NSString *k in keys) { live |= _live[k] != nil; pend |= _pending[k] != nil; tr = tr ?: [self transitionFor:k]; }
        UILabel *v = _tileVal[pid], *s = _tileSub[pid];
        v.text = [self textFor:pid value:live];
        NSString *sub = @""; UIColor *col = CTL_INK3;
        if (pend) { sub = [@"→ " stringByAppendingString:[self textFor:pid value:YES]]; col = CTL_YELLOW; }
        else if (tr) {
            NSString *to = bp ? [NSString stringWithFormat:@"%@/%@", [self transitionFor:@"systolic_mmhg"][@"to"] ?: @(lround([self currentOf:@"systolic_mmhg"])), [self transitionFor:@"diastolic_mmhg"][@"to"] ?: @(lround([self currentOf:@"diastolic_mmhg"]))] : Fmt([tr[@"to"] doubleValue], [p[@"dec"] integerValue]);
            sub = [NSString stringWithFormat:@"→ %@ · %@", to, Clock([tr[@"remaining_s"] integerValue])]; col = CTL_INK2;
        } else if (sensorFor[pid]) {
            BOOL any = NO; for (NSString *k in sensorFor[pid]) any |= [self sensorOn:k];
            if (!any && _m.state) sub = @"non collegata";
            else if ([pid isEqualToString:@"hr"]) sub = RhythmName(st[@"rhythm"]);
        }
        if (![s.text isEqualToString:sub]) s.text = sub;
        s.textColor = col;
        UIView *t = _tiles[pid]; t.layer.borderWidth = [pid isEqualToString:_sel] && _tab == 0 ? 2 : 0;
    }
}

// Aggiornamento disponibile sul monitor: lo si propone una volta per versione (mai a metà scenario senza chiederlo)
- (void)offerUpdate {
    NSString *v = _m.updateVersion;
    if (!v || [v isEqualToString:_updAsked] || self.presentedViewController) return;
    _updAsked = [v copy];
    NSString *name = @"similFranz Pocket";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Aggiornamento %@", v]
        message:[NSString stringWithFormat:@"Il monitor ha la versione %@ di %@. L'installazione richiede meno di un minuto: l'app si chiude e si riapre da sola.", v, name]
        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) me = self; CtlModel *m = _m;
    [a addAction:[UIAlertAction actionWithTitle:@"Più tardi" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Installa ora" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [me flash:@"Scarico l'aggiornamento dal monitor…"];
        [m installUpdate:^(NSString *err) { [me flash:err ? [@"Aggiornamento non riuscito: " stringByAppendingString:err] : @"Installazione in corso: l'app si riapre da sola"]; }];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

// Dopo ogni scarica (anche sincronizzata) il monitor aspetta l'istruttore: la domanda copre lo schermo finché non si risponde.
- (void)refreshOutcome {
    NSDictionary *d = [self.st[@"defib"] isKindOfClass:[NSDictionary class]] ? self.st[@"defib"] : @{};
    BOOL pending = _m.stage == CtlStageReady && [d[@"outcome_pending"] boolValue];
    NSString *from = [d[@"outcome_from"] isKindOfClass:[NSString class]] ? d[@"outcome_from"] : nil;
    NSString *sig = pending ? [NSString stringWithFormat:@"%@|%@", from, d[@"outcome_shock"]] : nil;
    if ((sig == _outcomeSig) || [sig isEqualToString:_outcomeSig]) return;
    _outcomeSig = sig;
    [_outcome removeFromSuperview]; _outcome = nil;
    if (!pending) return;
    BOOL sync = [d[@"outcome_sync"] boolValue]; NSInteger joule = [d[@"outcome_energy_j"] integerValue];
    CGFloat H = self.view.bounds.size.height, top = 24;     // sotto la riga con monitor, orologio e batteria
    _outcome = [[UIView alloc] initWithFrame:CGRectMake(0, top, W, H - top)];
    _outcome.backgroundColor = CtlRGB(0.17, 0.12, 0.01); _outcome.accessibilityIdentifier = @"outcome";
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 4)]; bar.backgroundColor = CTL_YELLOW; [_outcome addSubview:bar];
    UILabel *t = CtlLabel(CGRectMake(16, 16, W - 32, 52), sync ? @"Cardioversione erogata: che cosa succede adesso?" : @"Scarica erogata: che cosa succede adesso?", 19, YES, CTL_INK);
    t.numberOfLines = 2; [_outcome addSubview:t];
    UILabel *sub = CtlLabel(CGRectMake(16, 70, W - 32, 36), [NSString stringWithFormat:@"%@ n. %@%@ · il paziente è ancora in %@", sync ? @"Sincronizzata" : @"Scarica",
                            d[@"outcome_shock"] ?: @"", joule > 0 ? [NSString stringWithFormat:@" · %ld J", (long)joule] : @"", [RhythmName(from) lowercaseString]], 13, NO, CtlRGB(1, 0.88, 0.6));
    sub.numberOfLines = 2; [_outcome addSubview:sub];
    NSArray *opts = @[@[@"stay", [NSString stringWithFormat:@"Resta in %@", [RhythmName(from) lowercaseString]]], @[@"sinus", @"Sinusale (ROSC)"],
                      @[@"sinus_tachycardia", @"Tachicardia sinusale (ROSC)"], @[@"vf", @"Fibrillazione ventricolare"],
                      @[@"asystole", @"Asistolia"], @[@"pea", @"PEA"], @[@"other", @"Altro ritmo…"]];
    CGFloat y = 116, bh = MIN(52, (H - top - y - 16) / opts.count - 8);
    CtlModel *m = _m; __weak typeof(self) me = self;
    for (NSArray *o in opts) {
        BOOL stay = [o[0] isEqualToString:@"stay"], other = [o[0] isEqualToString:@"other"];
        CtlButton *b = [CtlButton buttonWithTitle:o[1] style:(stay || other) ? CtlButtonQuiet : CtlButtonFilled color:[o[0] hasPrefix:@"sinus"] ? CTL_GREEN : CTL_TINT
                                            frame:CGRectMake(16, y, W - 32, bh) target:nil action:NULL];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:16]; b.accessibilityIdentifier = [@"outcome." stringByAppendingString:o[0]];
        b.onTap = other ? ^{ [me outcomeOther]; } : ^{ [m command:@"defib_outcome" value:o[0]]; };
        [_outcome addSubview:b]; y += bh + 8;
    }
    [self.view addSubview:_outcome];
    [self.view bringSubviewToFront:_toast];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}
- (void)outcomeOther {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Dopo la scarica il paziente passa a" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    CtlModel *m = _m;
    for (NSArray *r in Rhythms())
        [a addAction:[UIAlertAction actionWithTitle:r[1] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [m command:@"defib_outcome" value:r[0]]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)refresh {
    if (_m.updateVersion && _m.updateProgress < 0) [self offerUpdate];
    if (_m.updateProgress >= 0 && (NSInteger)(_m.updateProgress * 10) != _updPct) { _updPct = (NSInteger)(_m.updateProgress * 10); [self flash:[NSString stringWithFormat:@"Scarico l'aggiornamento dal monitor: %ld%%", (long)lround(_m.updateProgress * 100)]]; }
    if (!_dial) return;
    NSDictionary *st = self.st;
    BOOL ready = _m.stage == CtlStageReady;
    _pair.hidden = ready; if (!ready) [_pair refresh];
    // intestazione
    _dot.backgroundColor = ready ? CTL_GREEN : CTL_ORANGE;
    NSString *mn = _m.monitorName ?: @"nessun monitor";
    if (![_monName.text isEqualToString:mn]) _monName.text = mn;
    BOOL running = st[@"simulation_running"] ? [st[@"simulation_running"] boolValue] : YES;
    _clock.text = running ? Clock([st[@"scenario_time_s"] integerValue]) : [@"II " stringByAppendingString:Clock([st[@"scenario_time_s"] integerValue])];
    _clock.textColor = running ? CTL_INK : CTL_ORANGE;
    UIDevice *dev = [UIDevice currentDevice]; if (!dev.batteryMonitoringEnabled) dev.batteryMonitoringEnabled = YES;
    float lvl = dev.batteryLevel; BOOL chg = dev.batteryState == UIDeviceBatteryStateCharging || dev.batteryState == UIDeviceBatteryStateFull;
    _batt.text = lvl < 0 ? @"" : [NSString stringWithFormat:@"%@%ld%%", chg ? @"↯ " : @"", lround(lvl * 100)];
    _battFill.frame = CGRectMake(2, 2, 18 * MAX(0.05, lvl < 0 ? 1 : lvl), 7);
    _battFill.backgroundColor = lvl >= 0 && lvl < 0.2 && !chg ? CTL_RED : (chg ? CTL_GREEN : CTL_INK2);
    // un solo controller alla volta (regole sul monitor): chi comanda attivamente è protetto, chi è fermo da un minuto cede
    NSDictionary *c = _m.controller;
    BOOL other = ready && [c[@"active"] boolValue] && ![c[@"mine"] boolValue], idle = other && [c[@"protected"] isEqual:@NO];
    BOOL busy = other && !idle;
    _busy.hidden = !busy;
    if (other) {
        NSString *kind = @{@"web": @"web app", @"ipad": @"iPad", @"ipod": @"iPod"}[c[@"kind"] ?: @""] ?: @"controller";
        NSString *who = [NSString stringWithFormat:@"«%@» (%@, %@)", c[@"name"] ?: @"un altro controller", kind, [c[@"transport"] isEqual:@"direct"] ? @"diretto" : @"Wi-Fi"];
        if (busy) _busyText.text = c[@"lost_to"] ? [NSString stringWithFormat:@"%@ ha preso il comando", who] : [NSString stringWithFormat:@"Comanda %@", who];
        [_take setTitle:c[@"lost_to"] ? @"Riprendi" : @"Prendi" forState:UIControlStateNormal];
        if (idle && !_wasIdle) { NSInteger a = [c[@"action_idle_s"] integerValue];
            [self flash:[NSString stringWithFormat:@"%@ è fermo da %@: il primo comando passa a te", who, a < 90 ? [NSString stringWithFormat:@"%ld s", (long)a] : [NSString stringWithFormat:@"%ld min", (long)lround(a / 60.0)]]]; }
    }
    if (_wasMine && other && c[@"lost_to"]) [self flash:[NSString stringWithFormat:@"«%@» ha preso il comando", c[@"lost_to"]]];
    _wasMine = [c[@"mine"] boolValue]; _wasIdle = idle;
    if (_m.lastMessage.length && ![_m.lastMessage isEqualToString:_lastMsg]) [self flash:_m.lastMessage];
    _lastMsg = _m.lastMessage;
    [self refreshTiles];
    [self refreshOutcome];
    // rotella
    NSString *k = [self selKey];
    NSMutableArray *note = [NSMutableArray array];
    NSDictionary *tr = [self transitionFor:k];
    NSInteger dec = [Param(_sel)[@"dec"] integerValue];
    if (_pending[k]) [note addObject:[NSString stringWithFormat:@"in coda · ora %@", Fmt([self currentOf:k], dec)]];
    else if (tr) [note addObject:[NSString stringWithFormat:@"in corso → %@ · %@", Fmt([tr[@"to"] doubleValue], dec), Clock([tr[@"remaining_s"] integerValue])]];
    if ([_sel isEqualToString:@"bp"]) [note addObject:_bpPart ? @"tocca qui: sistolica" : @"tocca qui: diastolica"];
    else if (!note.count) [note addObject:@"piano ±1 · veloce a salti"];
    [_dial showValue:[self targetOf:k] current:[self currentOf:k] note:[note componentsJoinedByString:@"\n"]];
    // valori rapidi: evidenziato quello uguale al valore scelto
    NSString *now = [self textFor:_sel value:YES];
    for (CtlButton *b in _chipBtns) {
        BOOL on = [[b titleForState:UIControlStateNormal] isEqualToString:now];
        [b setStyle:on ? CtlButtonFilled : CtlButtonQuiet color:on ? Param(_sel)[@"c"] : CTL_INK];
        if (on) [b setTitleColor:CTL_BG forState:UIControlStateNormal];
    }
    // ritmo
    NSString *cr = st[@"rhythm"];
    for (NSString *r in _rhythmBtns) {
        CtlButton *b = _rhythmBtns[r]; BOOL cur = [r isEqualToString:cr], pend = [r isEqualToString:_pendingRhythm];
        [b setStyle:cur ? CtlButtonFilled : (pend ? CtlButtonTinted : CtlButtonQuiet) color:cur ? CTL_HR : (pend ? CTL_YELLOW : CTL_INK)];
        if (cur) [b setTitleColor:CTL_BG forState:UIControlStateNormal];
    }
    // dock: tempo e avvio
    NSArray *ts = Times();
    for (NSUInteger i = 0; i < _timeBtns.count; i++) {
        BOOL on = [ts[i] integerValue] == _modeSec;
        [_timeBtns[i] setStyle:on ? CtlButtonFilled : CtlButtonQuiet color:on ? CTL_TINT : CTL_INK];
    }
    NSUInteger n = [self pendingCount];
    if (_modeSec == 0) {
        [_apply setTitle:@"Subito: parte quando sollevi il dito" forState:UIControlStateNormal];
        [_apply setStyle:CtlButtonQuiet color:CTL_INK3]; _apply.enabled = NO;
    } else if (!n) {
        [_apply setTitle:[NSString stringWithFormat:@"Scegli i valori, poi avvia in %@", TimeName(_modeSec)] forState:UIControlStateNormal];
        [_apply setStyle:CtlButtonQuiet color:CTL_INK3]; _apply.enabled = NO;
    } else {
        [_apply setTitle:[NSString stringWithFormat:@"Avvia in %@ · %lu %@", TimeName(_modeSec), (unsigned long)n, n == 1 ? @"modifica" : @"modifiche"] forState:UIControlStateNormal];
        [_apply setStyle:CtlButtonFilled color:CTL_TINT]; _apply.enabled = YES;
    }
    _cancel.hidden = n == 0;
    _apply.frame = CGRectMake(8, 52, n ? W - 16 - 48 : W - 16, 38);
    // sonde
    for (NSString *sk in _sensorBtns) {
        BOOL on = [self sensorOn:sk]; UILabel *l = _sensorState[sk];
        NSString *t = on ? @"COLLEGATA" : @"STACCATA";
        if (![l.text isEqualToString:t]) l.text = t;
        l.textColor = on ? CTL_BG : CTL_INK3; l.backgroundColor = on ? CTL_GREEN : CTL_CARD2;
    }
    // azioni
    BOOL cpr = [st[@"cpr_active"] boolValue], vm = [st[@"ventilation_manual"] boolValue], muted = [st[@"alarms_muted"] boolValue];
    [_actBtns[@"cpr"] setStyle:cpr ? CtlButtonFilled : CtlButtonTinted color:CTL_RED];
    [_actBtns[@"cpr"] setTitle:cpr ? @"RCP in corso" : @"RCP" forState:UIControlStateNormal];
    _actSub[@"cpr"].text = cpr ? @"tocca per fermarla" : @"avvia le compressioni";
    [_actBtns[@"vent"] setStyle:vm ? CtlButtonTinted : CtlButtonQuiet color:vm ? CTL_SPO2 : CTL_INK3];
    _actSub[@"vent"].text = vm ? [NSString stringWithFormat:@"%@ nell'ultimo minuto", st[@"breaths_last_min"] ?: @0] : @"respira da solo";
    NSString *ns = st[@"nibp_status"];
    [_actBtns[@"nibp"] setStyle:CtlButtonTinted color:CTL_BP];
    _actSub[@"nibp"].text = [ns isEqualToString:@"measuring"] ? @"misura in corso…" : ([st[@"nibp_last_systolic_mmhg"] isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"ultima %@/%@", st[@"nibp_last_systolic_mmhg"], st[@"nibp_last_diastolic_mmhg"]] : @"una misura ora");
    [_actBtns[@"mute"] setStyle:muted ? CtlButtonFilled : CtlButtonTinted color:CTL_YELLOW];
    [_actBtns[@"mute"] setTitle:muted ? @"Silenziati" : @"Silenzia" forState:UIControlStateNormal];
    _actSub[@"mute"].text = muted ? [NSString stringWithFormat:@"ancora %@", Clock([st[@"alarms_muted_remaining_s"] integerValue])] : @"allarmi del monitor";
    [_actBtns[@"pause"] setStyle:running ? CtlButtonTinted : CtlButtonFilled color:CTL_ORANGE];
    [_actBtns[@"pause"] setTitle:running ? @"Pausa" : @"Riprendi" forState:UIControlStateNormal];
    [_actBtns[@"pause"] setIcon:running ? @"pause" : @"play" above:YES];
    _actSub[@"pause"].text = running ? @"ferma tracce e timer" : @"simulazione in pausa";
    [_actBtns[@"crt"] setStyle:CtlButtonTinted color:CTL_TEMP];
    _actSub[@"crt"].text = [st[@"crt_s"] isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"fai valutare (%@ s)", Fmt([st[@"crt_s"] doubleValue], 1)] : @"fai valutare";
    for (NSString *ak in _actBtns) { UILabel *l = _actSub[ak]; l.textColor = [_actBtns[ak] titleColorForState:UIControlStateNormal]; l.alpha = 0.85; }
}

#pragma mark - avvio

- (void)showSplash:(BOOL)still {
    [[self.view viewWithTag:7777] removeFromSuperview];
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    PkSplashView *sp = [[PkSplashView alloc] initWithFrame:self.view.bounds version:ver]; sp.tag = 7777;
    [self.view addSubview:sp];
    if (still) { [sp makeStatic]; return; }
    CtlModel *m = _m;
    [sp runStages:@[@[@"Preparo la rotella", ^{ PkClick(); }],
                    @[@"Preparo i comandi", [NSNull null]],
                    @[@"Cerco il monitor", [NSNull null], ^BOOL { return m.stage == CtlStageReady || m.link.monitors.count > 0; }, @6]]
         minStage:1.0 completion:nil];
}

#pragma mark - verifica da Mac (simulafranz-pocket://…)

- (void)debug:(NSString *)host query:(NSDictionary<NSString *, NSString *> *)q {
    UIWindow *w = [UIApplication sharedApplication].delegate.window;
    if ([host isEqualToString:@"shot"]) {
        UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 0);
        [w drawViewHierarchyInRect:w.bounds afterScreenUpdates:YES];
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
        NSString *dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"shots"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        [UIImagePNGRepresentation(img) writeToFile:[dir stringByAppendingFormat:@"/%@.png", q[@"name"] ?: @"shot"] atomically:YES];
        return;
    }
    if ([host isEqualToString:@"audit"]) {
        NSMutableArray *out = [NSMutableArray array]; NSInteger n = 0;
        AuditText(w, nil, out, &n);
        SFLog(@"AUDIT %@: %ld testi, %lu problemi", q[@"name"] ?: @"", (long)n, (unsigned long)out.count);
        for (NSString *o in out) SFLog(@"AUDIT   %@", o);
        return;
    }
    if ([host isEqualToString:@"splash"]) { if (q[@"off"]) [[self.view viewWithTag:7777] removeFromSuperview]; else [self showSplash:q[@"static"] != nil]; return; }
    if ([host isEqualToString:@"turn"]) { [_dial debugTurn:[q[@"n"] integerValue]]; return; }
    if ([host isEqualToString:@"pin"]) { [_m submitPin:q[@"v"] ?: @""]; return; }
    if ([host isEqualToString:@"forget"]) { [_m forgetMonitor]; return; }
    if ([host isEqualToString:@"list"]) { NSMutableArray *a = [NSMutableArray array]; ListIds(self.view, a); SFLog(@"ID visibili: %@", [a componentsJoinedByString:@" "]); return; }
    if ([host isEqualToString:@"cmd"]) {
        id v = q[@"v"] ? [NSJSONSerialization JSONObjectWithData:[q[@"v"] dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingAllowFragments error:NULL] : nil;
        [_m command:q[@"n"] ?: @"" value:v]; return;
    }
    UIView *v = q[@"id"] ? FindId(self.view, q[@"id"]) : nil;
    if (!v) { SFLog(@"debug %@: elemento \"%@\" non trovato", host, q[@"id"]); return; }
    CGPoint c = [v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), CGRectGetMidY(v.bounds)) toView:v.window];
    UIView *hit = [v.window hitTest:c withEvent:nil];
    BOOL reach = hit == v || [hit isDescendantOfView:v];
    SFLog(@"debug %@ %@ %@", host, q[@"id"], reach ? @"ok" : [NSString stringWithFormat:@"COPERTO da %@ (%@)", NSStringFromClass(hit.class), hit.accessibilityIdentifier]);
    if (reach && [host isEqualToString:@"tap"] && [v isKindOfClass:[UIControl class]]) [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
}
@end
