#import "CtlViewController.h"
#import "CtlModel.h"
#import "CtlUI.h"
#import "CtlPairingView.h"
#import "CtlScenarioEditor.h"
#import "CtlSplashView.h"
#import "CtlDebriefView.h"
#import "SFLog.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Tabelle

// parametri regolabili: chiave API, titolo, unità, min, max, passo, decimali, valori rapidi, comando "subito" (se non è una rampa)
static NSDictionary *PDef(NSString *key) {
    static NSDictionary *t; static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @{
          @"heart_rate_bpm":       @[@"Frequenza cardiaca", @"bpm", @0, @250, @1, @0, @[@40, @60, @80, @100, @130, @160], @""],
          @"spo2_percent":         @[@"SpO₂", @"%", @0, @100, @1, @0, @[@75, @85, @90, @94, @98], @""],
          @"systolic_mmhg":        @[@"Sistolica", @"mmHg", @40, @260, @1, @0, @[], @""],
          @"diastolic_mmhg":       @[@"Diastolica", @"mmHg", @20, @160, @1, @0, @[], @""],
          @"respiratory_rate_rpm": @[@"Frequenza respiratoria", @"atti/min", @0, @50, @1, @0, @[@0, @8, @12, @16, @24, @32], @""],
          @"etco2_mmhg":           @[@"EtCO₂", @"mmHg", @0, @100, @1, @0, @[@10, @20, @35, @45, @60], @""],
          @"temperature_c":        @[@"Temperatura", @"°C", @30, @43, @0.1, @1, @[@34, @35.5, @36.8, @38.5, @40], @"set_temperature"],
          @"crt_s":                @[@"Refill capillare", @"s", @0.5, @8, @0.5, @1, @[@1, @2, @3, @4, @6], @"set_crt"],
        };
    });
    return @{@"title": t[key][0], @"unit": t[key][1], @"min": t[key][2], @"max": t[key][3], @"step": t[key][4], @"dec": t[key][5], @"quick": t[key][6], @"now": t[key][7]};
}
static UIColor *PColor(NSString *key) {
    if ([key hasPrefix:@"heart"]) return CTL_HR;
    if ([key hasPrefix:@"spo2"]) return CTL_SPO2;
    if ([key hasSuffix:@"olic_mmhg"]) return CTL_BP;
    if ([key hasPrefix:@"temp"] || [key hasPrefix:@"crt"]) return CTL_TEMP;
    return CTL_CO2;
}
static NSString *PShort(NSString *key) {
    return @{@"heart_rate_bpm": @"FC", @"spo2_percent": @"SpO₂", @"systolic_mmhg": @"PAs", @"diastolic_mmhg": @"PAd",
             @"respiratory_rate_rpm": @"FR", @"etco2_mmhg": @"EtCO₂", @"temperature_c": @"Temp", @"crt_s": @"Refill"}[key] ?: key;
}
static NSArray<NSString *> *RhythmOrder(void) {
    return @[@"sinus", @"sinus_tachycardia", @"sinus_bradycardia", @"afib", @"vt_pulse", @"vt", @"vf", @"asystole", @"pea"];
}
static NSString *CtlKindName(NSString *k) { return @{@"web": @"web app", @"ipad": @"iPad", @"ipod": @"iPod"}[k ?: @""] ?: @"controller"; }
static NSString *CtlAgo(NSInteger s) { return s < 90 ? [NSString stringWithFormat:@"%ld s", (long)s] : [NSString stringWithFormat:@"%ld min", (long)lround(s / 60.0)]; }
NSString *CtlRhythmName(NSString *r) {
    return @{@"sinus": @"Sinusale", @"sinus_tachycardia": @"Tachicardia sinusale", @"sinus_bradycardia": @"Bradicardia sinusale",
             @"afib": @"Fibrillazione atriale", @"vt_pulse": @"TV con polso", @"vt": @"TV senza polso", @"vf": @"Fibrillazione ventricolare",
             @"asystole": @"Asistolia", @"pea": @"PEA"}[r ?: @""] ?: (r ?: @"--");
}
// tessere in alto -> parametri del pannello centrale
static NSArray<NSString *> *TileOrder(void) { return @[@"rhythm", @"hr", @"bp", @"spo2", @"resp", @"exam", @"defib"]; }
static NSArray<NSString *> *TileParams(NSString *tile) {
    return @{@"rhythm": @[@"heart_rate_bpm"], @"hr": @[@"heart_rate_bpm"], @"bp": @[@"systolic_mmhg", @"diastolic_mmhg"], @"spo2": @[@"spo2_percent"],
             @"resp": @[@"respiratory_rate_rpm", @"etco2_mmhg"], @"exam": @[@"temperature_c", @"crt_s"]}[tile] ?: @[];
}
static NSArray<NSArray *> *Sensors(void) {      // chiave API, nome, colore
    // le piastre stanno accanto agli elettrodi (tutte e due danno l'ECG) e hanno lo stesso colore
    return @[@[@"ecg", @"Elettrodi ECG", CTL_HR], @[@"pads", @"Piastre defibrillatore", CTL_HR], @[@"spo2", @"Sonda SpO₂", CTL_SPO2],
             @[@"nibp", @"Bracciale NIBP", CTL_BP], @[@"art", @"Linea arteriosa", CTL_BP], @[@"etco2", @"Capnografia", CTL_CO2],
             @[@"temp", @"Sonda temperatura", CTL_TEMP]];
}
// stati pronti (gli stessi della web app): nome, transizione, ritmo, parametri, valori immediati
static NSArray<NSDictionary *> *PresetStates(void) {
#define ST(n_, d_, r_, hr, s, d, sp, rr, et, crt) @{@"n": n_, @"d": @(d_), @"r": r_, @"p": @{@"heart_rate_bpm": @(hr), @"systolic_mmhg": @(s), @"diastolic_mmhg": @(d), @"spo2_percent": @(sp), @"respiratory_rate_rpm": @(rr), @"etco2_mmhg": @(et)}, @"now": @{@"crt_s": @(crt)}}
    return @[ ST(@"Sano", 10, @"sinus", 80, 120, 80, 98, 14, 38, 2),
              ST(@"Ipoteso", 30, @"sinus", 105, 90, 55, 95, 20, 32, 3),
              ST(@"Shock", 60, @"sinus_tachycardia", 135, 75, 45, 90, 28, 25, 5),
              ST(@"Insufficienza respiratoria", 60, @"sinus_tachycardia", 120, 135, 85, 82, 32, 55, 2),
              ST(@"Bradicardia instabile", 30, @"sinus_bradycardia", 38, 80, 50, 91, 10, 30, 4),
              ST(@"TV con polso", 10, @"vt_pulse", 180, 85, 55, 92, 22, 30, 3),
              @{@"n": @"Arresto in FV", @"d": @0, @"r": @"vf", @"p": @{}, @"now": @{}},
              ST(@"Post-ROSC", 30, @"sinus_tachycardia", 110, 95, 60, 94, 12, 40, 3) ];
#undef ST
}
static NSString *Dur(NSInteger s) { return s <= 0 ? @"subito" : (s < 60 ? [NSString stringWithFormat:@"%ld s", (long)s] : (s % 60 ? [NSString stringWithFormat:@"%ld min %ld s", (long)s / 60, (long)s % 60] : [NSString stringWithFormat:@"%ld min", (long)s / 60])); }
static NSString *Clock(NSInteger s) { return [NSString stringWithFormat:@"%02ld:%02ld", (long)(s / 60), (long)(s % 60)]; }
static NSString *Num(id v, NSInteger dec) {
    if (![v isKindOfClass:[NSNumber class]]) return @"--";
    return dec > 0 ? [[NSString stringWithFormat:@"%.*f", (int)dec, [v doubleValue]] stringByReplacingOccurrencesOfString:@"." withString:@","] : [NSString stringWithFormat:@"%ld", (long)lround([v doubleValue])];
}
// riassunto leggibile di un blocco di parametri (stato o fase)
NSString *CtlDescribeBlock(NSString *rhythm, NSDictionary *params, NSDictionary *extra) {
    NSMutableArray *a = [NSMutableArray array];
    if (rhythm.length) [a addObject:CtlRhythmName(rhythm)];
    NSNumber *s = params[@"systolic_mmhg"], *d = params[@"diastolic_mmhg"];
    if (params[@"heart_rate_bpm"]) [a addObject:[NSString stringWithFormat:@"FC %@", params[@"heart_rate_bpm"]]];
    if (s && d) [a addObject:[NSString stringWithFormat:@"PA %@/%@", s, d]];
    else { if (s) [a addObject:[NSString stringWithFormat:@"PAs %@", s]]; if (d) [a addObject:[NSString stringWithFormat:@"PAd %@", d]]; }
    if (params[@"spo2_percent"]) [a addObject:[NSString stringWithFormat:@"SpO₂ %@", params[@"spo2_percent"]]];
    if (params[@"respiratory_rate_rpm"]) [a addObject:[NSString stringWithFormat:@"FR %@", params[@"respiratory_rate_rpm"]]];
    if (params[@"etco2_mmhg"]) [a addObject:[NSString stringWithFormat:@"EtCO₂ %@", params[@"etco2_mmhg"]]];
    if (extra[@"temperature_c"]) [a addObject:[NSString stringWithFormat:@"Temp %@", Num(extra[@"temperature_c"], 1)]];
    if (extra[@"crt_s"]) [a addObject:[NSString stringWithFormat:@"Refill %@ s", Num(extra[@"crt_s"], 1)]];
    return a.count ? [a componentsJoinedByString:@" · "] : @"nessun cambiamento";
}

#pragma mark -

@interface CtlViewController ()
@end

@implementation CtlViewController {
    NSString *_updAsked; NSInteger _updPct;
    CtlModel *_m;
    // tessere
    NSMutableDictionary<NSString *, UIControl *> *_tiles; NSMutableDictionary<NSString *, UILabel *> *_tileValue, *_tileSub;
    NSString *_sel;
    // sinistra
    UISegmentedControl *_leftSeg; UIScrollView *_leftScroll; UIView *_leftFooter; NSString *_leftSig; NSInteger _open;
    NSMutableArray<NSDictionary *> *_custom; NSString *_lastState; NSTimeInterval _endArmed;
    UILabel *_phaseClock; CGRect _openRect; BOOL _pauseInit; UIControl *_clockBtn;
    UILabel *_regLast; CtlButton *_regDeb; NSInteger _quickSession;
    NSMutableArray *_updaters; NSMutableDictionary<NSString *, NSNumber *> *_setTouched; UIView *_outcome; NSString *_outcomeSig; BOOL _occlSaid; CtlButton *_moreBtn;
    NSMutableDictionary<NSString *, CtlButton *> *_siteBtn;
    NSMutableDictionary<NSString *, NSNumber *> *_quickCount; NSString *_quickFlash; NSTimeInterval _quickFlashUntil; CtlDebriefView *_debrief;
    // centro
    UIView *_center, *_edBody; UILabel *_edTitle, *_edSub, *_msg; NSString *_edBuilt;
    NSMutableDictionary<NSString *, CtlParamRow *> *_rows; NSMutableDictionary<NSString *, CtlButton *> *_rhythmBtn;
    UILabel *_nibpInfo;
    // destra
    NSMutableDictionary<NSString *, UISwitch *> *_sw; NSMutableDictionary<NSString *, NSNumber *> *_swTouched;
    CtlButton *_cprBtn, *_ventBtn, *_nibpBtn, *_muteBtn, *_touchBtn, *_layoutBtn; UILabel *_batt; UIView *_battBody, *_battFill; BOOL _muteShown, _pauseShown;
    // regia
    UILabel *_clock, *_pendLabel, *_busyText; CtlButton *_pauseBtn, *_applyBtn, *_cancelBtn, *_monBtn;
    UISegmentedControl *_modeSeg; UIView *_busyBar, *_bar; CtlButton *_takeBtn; BOOL _wasMine, _wasIdle;
    NSMutableDictionary<NSString *, NSNumber *> *_pending; NSString *_pendingRhythm; NSInteger _modeSec;
    NSString *_flash; NSTimeInterval _flashUntil;
    CtlPairingView *_pairing;
}

- (instancetype)initWithModel:(CtlModel *)model {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _m = model; _sel = @"hr"; _open = -1;
        _tiles = [NSMutableDictionary dictionary]; _tileValue = [NSMutableDictionary dictionary]; _tileSub = [NSMutableDictionary dictionary];
        _rows = [NSMutableDictionary dictionary]; _rhythmBtn = [NSMutableDictionary dictionary];
        _sw = [NSMutableDictionary dictionary]; _swTouched = [NSMutableDictionary dictionary];
        _pending = [NSMutableDictionary dictionary]; _quickCount = [NSMutableDictionary dictionary];
        _updaters = [NSMutableArray array]; _setTouched = [NSMutableDictionary dictionary]; _siteBtn = [NSMutableDictionary dictionary];
        NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"sf_states"];
        _custom = saved ? [saved mutableCopy] : [NSMutableArray array];
    }
    return self;
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

#pragma mark - Costruzione

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = CTL_BG;
    CGFloat W = 1024, H = 768;
    [self buildTiles];
    [self buildLeft];
    _center = CtlCard(CGRectMake(268, 108, 476, 588)); [self.view addSubview:_center];
    _edTitle = CtlLabel(CGRectMake(20, 14, 436, 28), @"", 22, YES, CTL_INK); [_center addSubview:_edTitle];
    _edSub = CtlLabel(CGRectMake(20, 42, 436, 32), @"", 12.5, NO, CTL_INK2); _edSub.numberOfLines = 2; [_center addSubview:_edSub];
    _edBody = [[UIView alloc] initWithFrame:CGRectMake(20, 84, 436, 464)]; [_center addSubview:_edBody];
    _msg = CtlLabel(CGRectMake(20, 552, 436, 28), @"", 13, NO, CTL_INK2); _msg.numberOfLines = 2; [_center addSubview:_msg];
    [self buildRight];
    [self buildBar];
    _pairing = [[CtlPairingView alloc] initWithFrame:CGRectMake(0, 0, W, H) model:_m];
    [self.view addSubview:_pairing];
    CtlViewController *me = self;
    _m.onUpdate = ^{ [me refresh]; };
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [self refresh];
    [self showSplash:NO];
}

- (void)buildTiles {
    NSDictionary *caps = @{@"rhythm": @"RITMO", @"hr": @"FC  bpm", @"bp": @"PA  mmHg", @"spo2": @"SpO₂  %", @"resp": @"FR · EtCO₂", @"exam": @"TEMP · REFILL", @"defib": @"DEFIBRILLATORE"};
    NSDictionary *cols = @{@"rhythm": CTL_INK, @"hr": CTL_HR, @"bp": CTL_BP, @"spo2": CTL_SPO2, @"resp": CTL_CO2, @"exam": CTL_TEMP, @"defib": CTL_ORANGE};
    CGFloat x = 8, w = (1024 - 16 - 6 * 6) / 7.0;
    for (NSString *k in TileOrder()) {
        UIControl *t = [[UIControl alloc] initWithFrame:CGRectMake(x, 8, w, 92)];
        t.backgroundColor = CTL_CARD; t.layer.cornerRadius = 12; t.layer.borderWidth = 2; t.layer.borderColor = [UIColor clearColor].CGColor;
        t.accessibilityIdentifier = [@"tile." stringByAppendingString:k];
        [t addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
        UILabel *c = CtlLabel(CGRectMake(12, 8, w - 24, 14), caps[k], 11, YES, CTL_INK2); c.userInteractionEnabled = NO; [t addSubview:c];
        BOOL words = [k isEqualToString:@"rhythm"] || [k isEqualToString:@"defib"];
        UILabel *v = CtlLabel(CGRectMake(12, 24, w - 24, 40), @"--", words ? 20 : 32, YES, cols[k]);
        v.font = words ? [UIFont boldSystemFontOfSize:20] : CtlDigits(32, YES);
        v.adjustsFontSizeToFitWidth = YES; v.minimumScaleFactor = 0.5; v.numberOfLines = words ? 2 : 1; v.userInteractionEnabled = NO;
        [t addSubview:v];
        UILabel *s = CtlLabel(CGRectMake(12, 68, w - 24, 16), @"", 11, NO, CTL_INK3); s.adjustsFontSizeToFitWidth = YES; s.minimumScaleFactor = 0.7; s.userInteractionEnabled = NO; [t addSubview:s];
        [self.view addSubview:t];
        _tiles[k] = t; _tileValue[k] = v; _tileSub[k] = s;
        x += w + 6;
    }
}

- (void)buildLeft {
    _leftSeg = [[UISegmentedControl alloc] initWithItems:@[@"Stati", @"Scenario", @"Registro"]];
    _leftSeg.frame = CGRectMake(8, 108, 252, 34); _leftSeg.tintColor = CTL_TINT;
    _leftSeg.selectedSegmentIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"sf_left"];
    _leftSeg.accessibilityIdentifier = @"left.seg";
    [_leftSeg addTarget:self action:@selector(leftChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_leftSeg];
    UIView *card = CtlCard(CGRectMake(8, 150, 252, 546)); [self.view addSubview:card];
    _leftScroll = [[CtlScrollView alloc] initWithFrame:CGRectMake(0, 0, 252, 546)];
    _leftScroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [card addSubview:_leftScroll];
    _leftFooter = [[UIView alloc] initWithFrame:CGRectMake(0, 546, 252, 0)]; _leftFooter.backgroundColor = CTL_CARD;
    [card addSubview:_leftFooter];
    card.clipsToBounds = YES;
}

- (void)buildRight {
    UIView *s = CtlCard(CGRectMake(752, 108, 264, 338)); [self.view addSubview:s];
    [s addSubview:CtlLabel(CGRectMake(16, 10, 140, 18), @"SONDE SUL PAZIENTE", 11, YES, CTL_INK2)];
    CGFloat y = 34;
    for (NSArray *d in Sensors()) {
        UILabel *l = CtlLabel(CGRectMake(16, y, 170, 42), d[1], 16, NO, CTL_INK); [s addSubview:l];
        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(264 - 16 - 51, y + 5, 51, 31)];
        sw.onTintColor = d[2]; sw.accessibilityIdentifier = [@"sw." stringByAppendingString:d[0]];
        [sw addTarget:self action:@selector(sensorChanged:) forControlEvents:UIControlEventValueChanged];
        [s addSubview:sw]; _sw[d[0]] = sw;
        if ([@[@"spo2", @"nibp", @"art"] containsObject:d[0]]) {       // lato della sonda: tocco = sposta dall'altro lato
            l.frame = CGRectMake(16, y, 132, 42); l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.8;
            CtlButton *sb = [CtlButton buttonWithTitle:@"dx" style:CtlButtonQuiet color:nil frame:CGRectMake(150, y + 6, 42, 30) target:self action:@selector(siteTapped:)];
            sb.titleLabel.font = [UIFont boldSystemFontOfSize:12]; sb.maxLines = 1; sb.accessibilityIdentifier = [@"site." stringByAppendingString:d[0]]; sb.hidden = YES;
            [s addSubview:sb]; _siteBtn[d[0]] = sb;
        }
        if (y > 34) { UIView *ln = [[UIView alloc] initWithFrame:CGRectMake(16, y, 232, 0.5)]; ln.backgroundColor = CTL_LINE; [s addSubview:ln]; }
        y += 43;
    }
    UIView *a = CtlCard(CGRectMake(752, 454, 264, 242)); [self.view addSubview:a];
    // tre righe con un razionale: 1) rianimazione (RCP e ventilazioni, i due tasti più usati in arresto),
    // 2) azioni rapide sul monitor e sul paziente, 3) impostazioni del monitor
    [a addSubview:CtlLabel(CGRectMake(16, 8, 232, 16), @"RIANIMAZIONE", 10.5, YES, CTL_INK2)];
    _cprBtn = [CtlButton buttonWithTitle:@"RCP in corso" style:CtlButtonQuiet color:nil frame:CGRectMake(12, 26, 116, 52) target:self action:@selector(toggleCpr)];
    _ventBtn = [CtlButton buttonWithTitle:@"Ventila" style:CtlButtonQuiet color:nil frame:CGRectMake(136, 26, 116, 52) target:self action:@selector(ventilate)];
    [a addSubview:CtlLabel(CGRectMake(16, 84, 232, 16), @"AZIONI RAPIDE", 10.5, YES, CTL_INK2)];
    _nibpBtn = [CtlButton buttonWithTitle:@"NIBP" style:CtlButtonQuiet color:nil frame:CGRectMake(12, 102, 76, 52) target:self action:@selector(measureNibp)];
    _muteBtn = [CtlButton buttonWithTitle:@"Silenzia" style:CtlButtonQuiet color:nil frame:CGRectMake(94, 102, 76, 52) target:self action:@selector(toggleMute)];
    _touchBtn = [CtlButton buttonWithTitle:@"Tocco" style:CtlButtonQuiet color:nil frame:CGRectMake(176, 102, 76, 52) target:self action:@selector(touchPatient)];
    NSArray *ids = @[@"act.cpr", @"act.vent", @"act.nibp", @"act.mute", @"act.touch"]; NSUInteger i = 0;
    NSArray *icons = @[@"cpr", @"lungs", @"gauge", @"bell.slash", @"tap"];
    for (CtlButton *b in @[_cprBtn, _ventBtn, _nibpBtn, _muteBtn, _touchBtn]) { b.titleLabel.font = [UIFont boldSystemFontOfSize:i < 2 ? 13 : 12]; b.accessibilityIdentifier = ids[i]; [b setIcon:icons[i] above:YES]; i++; [a addSubview:b]; }
    // impostazioni del monitor: layout (anche da qui) e il pannello allarmi/audio/movimenti
    _layoutBtn = [CtlButton buttonWithTitle:@"Layout del monitor" style:CtlButtonTinted color:CTL_TINT frame:CGRectMake(12, 162, 240, 34) target:self action:@selector(layoutMenu)];
    _layoutBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13]; _layoutBtn.maxLines = 1; _layoutBtn.accessibilityIdentifier = @"act.layout"; [_layoutBtn setIcon:@"monitor" above:NO]; [a addSubview:_layoutBtn];
    _moreBtn = [CtlButton buttonWithTitle:@"Allarmi, audio, movimenti" style:CtlButtonQuiet color:nil frame:CGRectMake(12, 202, 240, 34) target:self action:@selector(openMonitorPanel)];
    _moreBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13]; _moreBtn.maxLines = 1; _moreBtn.accessibilityIdentifier = @"act.more"; [_moreBtn setIcon:@"bell" above:NO]; [a addSubview:_moreBtn];
    // batteria di QUESTO iPad (il controller), in alto a destra come nella barra di stato di iOS
    _batt = CtlLabel(CGRectMake(150, 8, 70, 18), @"", 11, YES, CTL_INK2); _batt.textAlignment = NSTextAlignmentRight; _batt.font = CtlDigits(11, YES); [s addSubview:_batt];
    _battBody = [[UIView alloc] initWithFrame:CGRectMake(224, 10, 24, 12)]; _battBody.layer.borderColor = CTL_INK2.CGColor; _battBody.layer.borderWidth = 1.2; _battBody.layer.cornerRadius = 3; [s addSubview:_battBody];
    UIView *tip = [[UIView alloc] initWithFrame:CGRectMake(249, 13, 2, 6)]; tip.backgroundColor = CTL_INK2; [s addSubview:tip];
    _battFill = [[UIView alloc] initWithFrame:CGRectMake(2, 2, 20, 8)]; _battFill.backgroundColor = CTL_GREEN; _battFill.layer.cornerRadius = 1.5; [_battBody addSubview:_battFill];
}

- (void)buildBar {
    _bar = CtlCard(CGRectMake(8, 704, 1008, 56)); [self.view addSubview:_bar];
    _clock = CtlLabel(CGRectMake(14, 2, 92, 36), @"00:00", 28, YES, CTL_INK); _clock.font = CtlDigits(28, YES); [_bar addSubview:_clock];
    UILabel *cz = CtlLabel(CGRectMake(14, 36, 92, 14), @"TIMER · azzera", 10, YES, CTL_TINT); [_bar addSubview:cz];
    _clockBtn = [[UIControl alloc] initWithFrame:CGRectMake(4, 0, 102, 56)]; _clockBtn.accessibilityIdentifier = @"bar.clock";
    [_clockBtn addTarget:self action:@selector(clockMenu) forControlEvents:UIControlEventTouchUpInside]; [_bar addSubview:_clockBtn];
    _pauseBtn = [CtlButton buttonWithTitle:@"Pausa" style:CtlButtonQuiet color:nil frame:CGRectMake(108, 8, 96, 40) target:self action:@selector(togglePause)];
    _pauseBtn.accessibilityIdentifier = @"bar.pause"; [_bar addSubview:_pauseBtn];
    [_bar addSubview:CtlLabel(CGRectMake(220, 4, 200, 14), @"APPLICA LE MODIFICHE", 10, YES, CTL_INK3)];
    _modeSeg = [[UISegmentedControl alloc] initWithItems:@[@"Subito", @"10 s", @"30 s", @"1 min", @"2 min"]];
    _modeSeg.frame = CGRectMake(220, 20, 300, 30); _modeSeg.tintColor = CTL_TINT; _modeSeg.selectedSegmentIndex = 0;
    _modeSeg.accessibilityIdentifier = @"bar.mode";
    [_modeSeg addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    [_bar addSubview:_modeSeg];
    _pendLabel = CtlLabel(CGRectMake(532, 0, 150, 56), @"", 12, NO, CTL_YELLOW); _pendLabel.numberOfLines = 3; [_bar addSubview:_pendLabel];
    _applyBtn = [CtlButton buttonWithTitle:@"Applica" style:CtlButtonFilled color:CTL_TINT frame:CGRectMake(680, 8, 124, 40) target:self action:@selector(applyPending)];
    _applyBtn.accessibilityIdentifier = @"bar.apply"; _applyBtn.maxLines = 1; [_bar addSubview:_applyBtn];
    _cancelBtn = [CtlButton buttonWithTitle:@"Annulla" style:CtlButtonQuiet color:nil frame:CGRectMake(810, 8, 68, 40) target:self action:@selector(cancelPending)];
    _cancelBtn.titleLabel.font = [UIFont systemFontOfSize:14]; _cancelBtn.accessibilityIdentifier = @"bar.cancel"; [_bar addSubview:_cancelBtn];
    _monBtn = [CtlButton buttonWithTitle:@"Monitor" style:CtlButtonTinted color:CTL_GREEN frame:CGRectMake(900, 8, 100, 40) target:self action:@selector(monitorMenu)];
    _monBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12]; _monBtn.accessibilityIdentifier = @"bar.monitor"; [_bar addSubview:_monBtn];
    _monBtn.frame = CGRectMake(884, 8, 116, 40); _monBtn.maxLines = 1; [_monBtn setIcon:@"monitor" above:NO];
    // un altro controller sta comandando: al posto della barra di regia
    _busyBar = CtlCard(CGRectMake(8, 704, 1008, 56)); _busyBar.backgroundColor = CtlRGB(0.30, 0.20, 0.02); _busyBar.hidden = YES;
    _busyText = CtlLabel(CGRectMake(18, 0, 720, 56), @"", 16, YES, CtlRGB(1, 0.85, 0.5)); _busyText.numberOfLines = 2; [_busyBar addSubview:_busyText];
    CtlButton *take = [CtlButton buttonWithTitle:@"Prendi il comando" style:CtlButtonFilled color:CTL_ORANGE frame:CGRectMake(1008 - 220, 8, 204, 40) target:self action:@selector(takeControl)];
    take.accessibilityIdentifier = @"busy.take"; [_busyBar addSubview:take]; _takeBtn = take;
    [self.view addSubview:_busyBar];
}

// Schermata di avvio (stesso stile del Monitor): la barra segue il caricamento vero e l'ultima fase aspetta
// il monitor già abbinato; se non risponde entro qualche secondo si passa alla scelta del monitor.
- (void)showSplash:(BOOL)staticOnly {
    [[self.view viewWithTag:7777] removeFromSuperview];
    CtlSplashView *sp = [[CtlSplashView alloc] initWithFrame:self.view.bounds version:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
    sp.tag = 7777; [self.view addSubview:sp];
    if (staticOnly) { [sp makeStatic]; return; }
    CtlViewController *me = self; CtlModel *m = _m;
    BOOL paired = [[NSUserDefaults standardUserDefaults] stringForKey:@"sf_monitor"].length > 0;
    [sp runStages:@[
        @[@"Pannelli di regolazione", ^{ for (NSString *t in @[@"bp", @"spo2", @"resp", @"exam", @"defib", @"monitor", @"hr"]) { me->_sel = t; [me buildEditor]; } }],
        @[@"Stati e scenari", ^{ me->_leftSig = nil; [me refreshLeft]; }],
        @[@"Collegamento diretto", ^{ [m start]; }],
        @[paired ? @"Cerco il monitor abbinato" : @"Cerco i monitor vicini", [NSNull null],
          ^BOOL { return paired ? m.stage == CtlStageReady || m.stage == CtlStageNeedPin : m.link.monitors.count > 0; }, @(paired ? 7.0 : 3.0)],
    ] minStage:1.1 completion:nil];
}

#pragma mark - Aggiornamento

- (void)flash:(NSString *)t { _flash = [t copy]; _flashUntil = CACurrentMediaTime() + 4; [self refreshMsg]; }
- (void)refreshMsg {
    if (_m.lastMessage.length) { _msg.text = _m.lastMessage; _msg.textColor = CTL_RED; }
    else if (_flash && CACurrentMediaTime() < _flashUntil) { _msg.text = _flash; _msg.textColor = CTL_GREEN; }
    else { _msg.text = @""; }
}

- (id)valueFor:(NSString *)key { id v = _m.state[key]; return [v isKindOfClass:[NSNumber class]] ? v : nil; }

// Aggiornamento disponibile sul monitor: lo si propone una volta per versione (mai a metà scenario senza chiederlo)
- (void)offerUpdate {
    NSString *v = _m.updateVersion;
    if (!v || [v isEqualToString:_updAsked] || self.presentedViewController) return;
    _updAsked = [v copy];
    NSString *name = @"similFranz Controller";
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

- (void)refresh {
    if (_m.updateVersion && _m.updateProgress < 0) [self offerUpdate];
    if (_m.updateProgress >= 0 && (NSInteger)(_m.updateProgress * 10) != _updPct) { _updPct = (NSInteger)(_m.updateProgress * 10); [self flash:[NSString stringWithFormat:@"Scarico l'aggiornamento dal monitor: %ld%%", (long)lround(_m.updateProgress * 100)]]; }
    if (!self.isViewLoaded) return;
    BOOL ready = _m.stage == CtlStageReady;
    _pairing.hidden = ready;
    if (!ready) { [_pairing refresh]; [self.view bringSubviewToFront:_pairing]; UIView *sp = [self.view viewWithTag:7777]; if (sp) [self.view bringSubviewToFront:sp]; return; }
    NSDictionary *st = _m.state ?: @{};
    NSDictionary *sens = [st[@"sensors"] isKindOfClass:[NSDictionary class]] ? st[@"sensors"] : @{};

    // --- tessere: valore vero + che cosa vede il discente ---
    BOOL pulse = [st[@"pulse_present"] boolValue];
    _tileValue[@"rhythm"].text = CtlRhythmName(st[@"rhythm"]);
    _tileSub[@"rhythm"].text = pulse ? @"con polso" : @"SENZA POLSO";
    _tileSub[@"rhythm"].textColor = pulse ? CTL_INK3 : CTL_RED;
    _tileValue[@"hr"].text = Num(st[@"heart_rate_bpm"], 0);
    _tileSub[@"hr"].text = [sens[@"ecg"] boolValue] ? [@"monitor: " stringByAppendingString:Num(st[@"displayed_heart_rate_bpm"], 0)] : @"monitor: senza ECG";
    _tileValue[@"bp"].text = [NSString stringWithFormat:@"%@/%@", Num(st[@"systolic_mmhg"], 0), Num(st[@"diastolic_mmhg"], 0)];
    NSMutableArray *bp = [NSMutableArray array];
    if ([sens[@"art"] boolValue]) [bp addObject:[NSString stringWithFormat:@"ART %@/%@", Num(st[@"art_displayed_systolic_mmhg"], 0), Num(st[@"art_displayed_diastolic_mmhg"], 0)]];
    if ([st[@"nibp_last_systolic_mmhg"] isKindOfClass:[NSNumber class]]) [bp addObject:[NSString stringWithFormat:@"NIBP %@/%@", Num(st[@"nibp_last_systolic_mmhg"], 0), Num(st[@"nibp_last_diastolic_mmhg"], 0)]];
    _tileSub[@"bp"].text = bp.count ? [@"monitor: " stringByAppendingString:[bp componentsJoinedByString:@" · "]] : @"monitor: --";
    _tileValue[@"spo2"].text = Num(st[@"spo2_percent"], 0);
    _tileSub[@"spo2"].text = [@"monitor: " stringByAppendingString:Num(st[@"spo2_displayed"], 0)];
    _tileValue[@"resp"].text = [NSString stringWithFormat:@"%@ · %@", Num(st[@"respiratory_rate_rpm"], 0), Num(st[@"etco2_mmhg"], 0)];
    _tileSub[@"resp"].text = ![sens[@"etco2"] boolValue] ? @"monitor: senza CO₂"
        : ([st[@"ventilation_manual"] boolValue] ? [NSString stringWithFormat:@"monitor: FR %@ · EtCO₂ %@ (ventilazioni)", Num(st[@"respiratory_rate_measured"], 0), Num(st[@"etco2_displayed"], 0)]
                                                 : [@"monitor: EtCO₂ " stringByAppendingString:Num(st[@"etco2_displayed"], 0)]);
    _tileValue[@"exam"].text = [NSString stringWithFormat:@"%@° · %@ s", Num(st[@"temperature_c"], 1), Num(st[@"crt_s"], 1)];
    _tileSub[@"exam"].text = ([sens[@"temp"] boolValue] ? @"monitor: temperatura visibile" : @"monitor: temp senza sonda");
    {   // defibrillatore: che cosa stanno facendo i partecipanti
        NSDictionary *df = [st[@"defib"] isKindOfClass:[NSDictionary class]] ? st[@"defib"] : @{};
        NSString *md = df[@"mode"] ?: @"off";
        NSString *ch = @{@"charging": @" · in carica", @"ready": @" · CARICO"}[df[@"charge"] ?: @""] ?: @"";
        _tileValue[@"defib"].text = [md isEqualToString:@"off"] ? @"Spento" : ([md isEqualToString:@"aed"] ? @"DAE" : ([md isEqualToString:@"pacer"] ? @"Pacer" : [NSString stringWithFormat:@"Manuale %@ J", df[@"energy_j"] ?: @"--"]));
        _tileSub[@"defib"].text = [df[@"outcome_pending"] boolValue] ? @"ATTENDE LA TUA DECISIONE" : [NSString stringWithFormat:@"%@ scariche%@", df[@"shock_count"] ?: @0, ch];
        _tileSub[@"defib"].textColor = [df[@"outcome_pending"] boolValue] ? CTL_YELLOW : CTL_INK3;
    }
    for (NSString *k in _tiles) {
        BOOL heartSel = [_sel isEqualToString:@"rhythm"] || [_sel isEqualToString:@"hr"];
        BOOL on = [k isEqualToString:_sel] || (heartSel && ([k isEqualToString:@"rhythm"] || [k isEqualToString:@"hr"]));   // ritmo e FC: stesso pannello
        _tiles[k].layer.borderColor = (on ? CTL_TINT : [UIColor clearColor]).CGColor;
        _tiles[k].backgroundColor = on ? CTL_CARD2 : CTL_CARD;
    }

    [self refreshEditor];
    [self refreshLeft];

    // --- sonde (non si corregge l'interruttore appena toccato: il monitor risponde dopo un attimo) ---
    NSTimeInterval now = CACurrentMediaTime();
    for (NSString *k in [_sw allKeys]) {
        if (!_sw[k].window) { if ([k hasPrefix:@"spo2."] || [k hasPrefix:@"exam."]) [_sw removeObjectForKey:k]; continue; }
        if (now - _swTouched[k].doubleValue < 1.5) continue;
        BOOL on = [k isEqualToString:@"spo2.lowperf"] ? [st[@"spo2_low_perfusion_flag"] boolValue]
                : ([k isEqualToString:@"spo2.nosignal"] ? ![st[@"spo2_signal_valid"] boolValue] : [sens[k] boolValue]);
        if (_sw[k].on != on) [_sw[k] setOn:on animated:YES];
    }
    NSDictionary *sites = [st[@"sensor_sites"] isKindOfClass:[NSDictionary class]] ? st[@"sensor_sites"] : @{};
    for (NSString *k in _siteBtn) {
        CtlButton *sb = _siteBtn[k]; BOOL on = [sens[k] boolValue];
        if (sb.hidden == on) sb.hidden = !on;
        NSString *site = sites[k] ?: @{@"spo2": @"finger_l2", @"nibp": @"upper_arm_r", @"art": @"radial_l"}[k];
        NSString *t = [site rangeOfString:@"_r"].location != NSNotFound ? @"dx" : @"sx";
        if (![[sb titleForState:UIControlStateNormal] isEqualToString:t]) [sb setTitle:t forState:UIControlStateNormal];
    }
    BOOL cpr = [st[@"cpr_active"] boolValue];
    [_cprBtn setStyle:cpr ? CtlButtonFilled : CtlButtonQuiet color:CTL_ORANGE];
    [_cprBtn setTitle:cpr ? @"Ferma la RCP" : @"RCP in corso" forState:UIControlStateNormal];
    NSInteger mute = [st[@"alarms_muted_remaining_s"] integerValue];
    [_muteBtn setStyle:mute > 0 ? CtlButtonFilled : CtlButtonQuiet color:CTL_ORANGE];
    NSString *mt = mute > 0 ? [NSString stringWithFormat:@"%ld s", (long)mute] : @"Silenzia";
    if (![[_muteBtn titleForState:UIControlStateNormal] isEqualToString:mt]) [_muteBtn setTitle:mt forState:UIControlStateNormal];
    if (mute > 0 != _muteShown) { _muteShown = mute > 0; [_muteBtn setIcon:mute > 0 ? @"bell" : @"bell.slash" above:YES]; }
    BOOL measuring = [st[@"nibp_status"] isEqual:@"measuring"];
    // ventilazioni: attive con l'RCP in corso o in apnea (il paziente non respira da solo)
    BOOL vm = [st[@"ventilation_manual"] boolValue]; NSInteger br = [st[@"breaths_last_min"] integerValue];
    if (_ventBtn.enabled != vm) _ventBtn.enabled = vm;
    NSString *vt = !vm ? @"Ventila" : (br ? [NSString stringWithFormat:@"Ventila · %ld/min", (long)br] : @"Ventila");
    if (![[_ventBtn titleForState:UIControlStateNormal] isEqualToString:vt]) [_ventBtn setTitle:vt forState:UIControlStateNormal];
    // batteria del controller
    UIDevice *dev = [UIDevice currentDevice]; if (!dev.batteryMonitoringEnabled) dev.batteryMonitoringEnabled = YES;
    float lvl = dev.batteryLevel; BOOL chg = dev.batteryState == UIDeviceBatteryStateCharging || dev.batteryState == UIDeviceBatteryStateFull;
    NSString *bt = lvl < 0 ? @"iPad" : [NSString stringWithFormat:@"%@%ld%%", chg ? @"⚡︎ " : @"", (long)lroundf(lvl * 100)];
    if (![_batt.text isEqualToString:bt]) _batt.text = bt;
    UIColor *bc = (lvl >= 0 && lvl < 0.2 && !chg) ? CTL_RED : (lvl >= 0 && lvl < 0.4 && !chg ? CTL_ORANGE : CTL_GREEN);
    _battFill.backgroundColor = bc; _batt.textColor = bc == CTL_GREEN ? CTL_INK2 : bc;
    _battFill.frame = CGRectMake(2, 2, 20 * MAX(0.08, lvl < 0 ? 1 : lvl), 8);
    NSString *nt = measuring ? @"In corso" : @"NIBP";
    if (![[_nibpBtn titleForState:UIControlStateNormal] isEqualToString:nt]) [_nibpBtn setTitle:nt forState:UIControlStateNormal];
    _nibpBtn.enabled = !measuring;
    NSString *lt = [NSString stringWithFormat:@"Layout: %@", [self layoutName:st[@"layout"]]];
    if (![[_layoutBtn titleForState:UIControlStateNormal] isEqualToString:lt]) [_layoutBtn setTitle:lt forState:UIControlStateNormal];

    // --- regia ---
    BOOL running = [st[@"simulation_running"] boolValue];
    _clock.text = Clock([st[@"scenario_time_s"] integerValue]);
    _clock.textColor = running ? CTL_INK : CTL_ORANGE;
    if (running == _pauseShown || ![_pauseBtn titleForState:UIControlStateNormal].length || !_pauseInit) {
        _pauseInit = YES; _pauseShown = !running;
        [_pauseBtn setTitle:running ? @"Pausa" : @"Riprendi" forState:UIControlStateNormal];
        [_pauseBtn setStyle:running ? CtlButtonQuiet : CtlButtonFilled color:CTL_ORANGE];
        [_pauseBtn setIcon:running ? @"pause" : @"play" above:NO];
    }
    NSUInteger n = _pending.count + (_pendingRhythm ? 1 : 0);
    _applyBtn.hidden = _cancelBtn.hidden = n == 0;
    if (n) {
        NSMutableArray *a = [NSMutableArray array];
        if (_pendingRhythm) [a addObject:CtlRhythmName(_pendingRhythm)];
        for (NSString *k in _pending) [a addObject:[NSString stringWithFormat:@"%@ %@", PShort(k), _pending[k]]];
        _pendLabel.text = [NSString stringWithFormat:@"In attesa: %@", [a componentsJoinedByString:@", "]];
        [_applyBtn setTitle:[NSString stringWithFormat:@"Applica in %@", Dur(_modeSec)] forState:UIControlStateNormal];
    } else {
        NSDictionary *run = _m.scenario;
        if ([run[@"active"] boolValue]) _pendLabel.text = [NSString stringWithFormat:@"Scenario · fase %ld di %@\n%@", (long)[run[@"phase"] integerValue] + 1, run[@"phases"], run[@"phase_name"]];
        else if (_lastState) _pendLabel.text = [NSString stringWithFormat:@"Ultimo stato attivato\n%@", _lastState];
        else _pendLabel.text = @"";
    }
    _pendLabel.textColor = n ? CTL_YELLOW : CTL_INK2;
    _pendLabel.frame = CGRectMake(532, 0, n ? 144 : 344, 56);
    NSString *mn = [_m.monitorName stringByReplacingOccurrencesOfString:@"similFranz " withString:@""] ?: @"Monitor";
    if (![[_monBtn titleForState:UIControlStateNormal] isEqualToString:mn]) [_monBtn setTitle:mn forState:UIControlStateNormal];
    // Un solo controller alla volta (regole sul monitor): si vede sempre chi comanda, con che cosa e da dove.
    // Chi comanda attivamente è protetto (barra arancione, «Prendi il comando»); chi è fermo da più di un minuto
    // non blocca: si comanda normalmente e il primo comando passa da solo (lo si dice una volta).
    NSDictionary *c = _m.controller;
    BOOL other = [c[@"active"] boolValue] && ![c[@"mine"] boolValue], idle = other && [c[@"protected"] isEqual:@NO];
    BOOL busy = other && !idle, mineNow = [c[@"mine"] boolValue];
    _busyBar.hidden = !busy; _bar.hidden = busy;
    if (other) {
        NSString *who = [NSString stringWithFormat:@"«%@» (%@, %@)", c[@"name"] ?: @"un altro controller", CtlKindName(c[@"kind"]),
                         [c[@"transport"] isEqual:@"direct"] ? @"collegamento diretto" : @"Wi-Fi"];
        if (busy) _busyText.text = c[@"lost_to"] ? [NSString stringWithFormat:@"%@ ha preso il comando: da qui ora si osserva.", who]
                                                 : [NSString stringWithFormat:@"Comanda %@: da qui si può solo osservare.", who];
        [_takeBtn setTitle:c[@"lost_to"] ? @"Riprendi il comando" : @"Prendi il comando" forState:UIControlStateNormal];
        if (idle && !_wasIdle) [self flash:[NSString stringWithFormat:@"%@ è fermo da %@: il tuo primo comando prende il comando.", who, CtlAgo([c[@"action_idle_s"] integerValue])]];
    }
    if (_wasMine && other && c[@"lost_to"]) [self flash:[NSString stringWithFormat:@"«%@» ha preso il comando", c[@"lost_to"]]];
    _wasMine = mineNow; _wasIdle = idle;
    [self refreshMsg];
}

#pragma mark - Tessere e pannello centrale

- (void)tileTapped:(UIControl *)t {
    _sel = [t.accessibilityIdentifier substringFromIndex:5];
    [self refresh];
}

- (void)buildEditor {
    for (UIView *v in [_edBody.subviews copy]) [v removeFromSuperview];
    [_rows removeAllObjects]; [_rhythmBtn removeAllObjects]; _nibpInfo = nil;
    CGFloat W = _edBody.bounds.size.width;
    NSDictionary *titles = @{@"rhythm": @"Ritmo e frequenza", @"hr": @"Ritmo e frequenza", @"bp": @"Pressione arteriosa", @"spo2": @"Saturazione", @"resp": @"Respiro", @"exam": @"Esame clinico"};
    BOOL heart = [_sel isEqualToString:@"rhythm"] || [_sel isEqualToString:@"hr"];
    [_updaters removeAllObjects];
    if ([_sel isEqualToString:@"defib"] || [_sel isEqualToString:@"monitor"]) { [self buildSettings]; _edBuilt = [_sel copy]; return; }
    _edTitle.text = titles[_sel];
    {
        NSArray *keys = TileParams(_sel);
        _edSub.text = [_sel isEqualToString:@"exam"] ? @"Temperatura e refill si applicano subito. Il refill il partecipante lo valuta toccando il monitor, oppure lo fai valutare tu."
                    : (heart ? @"I ritmi di arresto si applicano sempre subito, gli altri seguono «Applica le modifiche»."
                             : @"Cursore, − e + (tenere premuto per scorrere) oppure un valore rapido.");
        CGFloat y = 0;
        for (NSString *k in keys) {
            NSDictionary *d = PDef(k);
            CtlParamRow *r = [[CtlParamRow alloc] initWithFrame:CGRectMake(0, y, W, 108) title:d[@"title"] unit:d[@"unit"] color:PColor(k)
                                                            min:[d[@"min"] doubleValue] max:[d[@"max"] doubleValue] step:[d[@"step"] doubleValue] decimals:[d[@"dec"] integerValue]];
            r.accessibilityIdentifier = [@"row." stringByAppendingString:k];
            CtlViewController *me = self;
            r.onChange = ^(double v, BOOL final) { [me param:k changed:v final:final]; };
            [_edBody addSubview:r]; _rows[k] = r;
            y += 116;
            NSArray *q = d[@"quick"];
            if (q.count) {
                CGFloat cw = (W - (q.count - 1) * 8) / q.count; NSUInteger i = 0;
                for (NSNumber *v in q) {
                    CtlButton *b = [CtlButton buttonWithTitle:Num(v, [d[@"dec"] integerValue]) style:CtlButtonTinted color:PColor(k) frame:CGRectMake(i * (cw + 8), y, cw, 44) target:nil action:NULL];
                    b.titleLabel.font = CtlDigits(17, YES);
                    b.accessibilityIdentifier = [NSString stringWithFormat:@"quick.%@.%@", k, v];
                    b.onTap = ^{ [me.view endEditing:YES]; [me->_rows[k] debugSet:v.doubleValue]; };
                    [_edBody addSubview:b]; i++;
                }
                y += 60;
            }
        }
        if ([_sel isEqualToString:@"bp"]) {
            NSArray *presets = @[@[@"Shock", @70, @40], @[@"Ipotesa", @90, @55], @[@"Normale", @120, @80], @[@"Ipertesa", @170, @100], @[@"Crisi", @220, @125]];
            CGFloat cw = (W - 4 * 8) / 5; NSUInteger i = 0;
            CtlViewController *me = self;
            for (NSArray *p in presets) {
                CtlButton *b = [CtlButton buttonWithTitle:[NSString stringWithFormat:@"%@\n%@/%@", p[0], p[1], p[2]] style:CtlButtonTinted color:CTL_BP frame:CGRectMake(i * (cw + 8), y, cw, 52) target:nil action:NULL];
                b.titleLabel.font = [UIFont boldSystemFontOfSize:13]; b.accessibilityIdentifier = [@"bp." stringByAppendingString:p[0]];
                b.onTap = ^{ [me setBP:[p[1] integerValue] dia:[p[2] integerValue]]; };
                [_edBody addSubview:b]; i++;
            }
            y += 68;
            UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, y, W, 64)]; box.backgroundColor = CTL_CARD2; box.layer.cornerRadius = 10; [_edBody addSubview:box];
            _nibpInfo = CtlLabel(CGRectMake(14, 0, W - 180, 64), @"", 14, NO, CTL_INK); _nibpInfo.numberOfLines = 3; [box addSubview:_nibpInfo];
            CtlButton *mb = [CtlButton buttonWithTitle:@"Misura ora" style:CtlButtonFilled color:CTL_TINT frame:CGRectMake(W - 150, 12, 138, 40) target:self action:@selector(measureNibp)];
            mb.accessibilityIdentifier = @"bp.measure"; [box addSubview:mb];
        }
        if (heart) {                 // ritmo e frequenza vanno insieme: sotto la FC la scelta del ritmo
            CGFloat bw = (W - 16) / 3, bh = 50; NSUInteger i = 0;
            [_edBody addSubview:CtlLabel(CGRectMake(0, y, W, 16), @"SINUSALI E SOPRAVENTRICOLARI", 11, YES, CTL_INK3)];
            [_edBody addSubview:CtlLabel(CGRectMake(0, y + 22 + 2 * (bh + 6) + 6, W, 16), @"VENTRICOLARI E ARRESTO", 11, YES, CTL_INK3)];
            for (NSString *r in RhythmOrder()) {
                NSUInteger row = i < 4 ? i / 3 : 2 + (i - 4) / 3, col = i < 4 ? i % 3 : (i - 4) % 3;
                CGFloat by = y + 22 + row * (bh + 6) + (i >= 4 ? 28 : 0);
                CtlButton *b = [CtlButton buttonWithTitle:CtlRhythmName(r) style:CtlButtonQuiet color:nil frame:CGRectMake(col * (bw + 8), by, bw, bh) target:self action:@selector(rhythmTapped:)];
                b.titleLabel.font = [UIFont boldSystemFontOfSize:14]; b.accessibilityIdentifier = [@"rhythm." stringByAppendingString:r];
                [_edBody addSubview:b]; _rhythmBtn[r] = b; i++;
            }
        }
        if ([_sel isEqualToString:@"exam"]) {      // il partecipante chiede il refill a voce: lo fai misurare tu
            UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, y, W, 62)]; box.backgroundColor = CTL_CARD2; box.layer.cornerRadius = 10; [_edBody addSubview:box];
            [box addSubview:CtlLabel(CGRectMake(14, 8, W - 210, 22), @"Refill chiesto a voce?", 16, NO, CTL_INK)];
            UILabel *d = CtlLabel(CGRectMake(14, 30, W - 210, 26), @"Sul monitor parte la valutazione, dopo 3 s compare il tempo.", 11.5, NO, CTL_INK3); d.numberOfLines = 2; [box addSubview:d];
            CtlButton *b = [CtlButton buttonWithTitle:@"Fai valutare" style:CtlButtonFilled color:CTL_TEMP frame:CGRectMake(W - 184, 10, 172, 42) target:self action:@selector(assessCrt)];
            b.titleLabel.font = [UIFont boldSystemFontOfSize:15]; b.maxLines = 1; b.accessibilityIdentifier = @"exam.assess"; [box addSubview:b];
            y += 70;
        }
        if ([_sel isEqualToString:@"spo2"]) {      // qualità del segnale: quello che il saturimetro riesce a leggere
            NSArray *opts = @[@[@"Bassa perfusione / artefatti", @"«?» alternato al valore e onda disturbata, anche con pressione normale", @"spo2.lowperf"],
                              @[@"Segnale assente (sonda che non legge)", @"il monitor non mostra il valore anche con la sonda applicata", @"spo2.nosignal"]];
            for (NSArray *o in opts) {
                UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, y, W, 62)]; box.backgroundColor = CTL_CARD2; box.layer.cornerRadius = 10; [_edBody addSubview:box];
                [box addSubview:CtlLabel(CGRectMake(14, 8, W - 90, 22), o[0], 16, NO, CTL_INK)];
                UILabel *d = CtlLabel(CGRectMake(14, 30, W - 90, 26), o[1], 11.5, NO, CTL_INK3); d.numberOfLines = 2; [box addSubview:d];
                UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(W - 65, 15, 51, 31)]; sw.onTintColor = CTL_ORANGE; sw.accessibilityIdentifier = o[2];
                [sw addTarget:self action:@selector(spo2Option:) forControlEvents:UIControlEventValueChanged];
                [box addSubview:sw]; _sw[o[2]] = sw;
                y += 70;
            }
        }
    }
    _edBuilt = [_sel copy];
}

- (void)refreshEditor {
    if (![_edBuilt isEqualToString:_sel]) [self buildEditor];
    for (void (^u)(void) in _updaters) u();
    [self refreshOutcome];
    // bracciale in misura sullo stesso braccio di SpO2 o arteria: il monitor perde il segnale, la regia lo dice
    if ([_m.state[@"spo2_cuff_occluded"] boolValue] && !_occlSaid) { _occlSaid = YES; [self flash:@"Bracciale sullo stesso braccio della SpO₂: segnale perso durante la misura"]; }
    else if ([_m.state[@"art_cuff_occluded"] boolValue] && !_occlSaid) { _occlSaid = YES; [self flash:@"Bracciale sullo stesso braccio dell'arteria: curva smorzata durante la misura"]; }
    else if (![_m.state[@"spo2_cuff_occluded"] boolValue] && ![_m.state[@"art_cuff_occluded"] boolValue]) _occlSaid = NO;
    NSDictionary *st = _m.state ?: @{};
    NSDictionary *tr = [st[@"transitions"] isKindOfClass:[NSDictionary class]] ? st[@"transitions"] : @{};
    for (NSString *k in _rows) {
        NSNumber *p = _pending[k]; id v = p ?: [self valueFor:k];
        if (v) [_rows[k] showValue:[v doubleValue] pending:p != nil];
        NSDictionary *t = [tr[k] isKindOfClass:[NSDictionary class]] ? tr[k] : nil;
        if (p) [_rows[k] setNote:[NSString stringWithFormat:@"in attesa · ora %@", Num([self valueFor:k], [PDef(k)[@"dec"] integerValue])]];
        else if (t) [_rows[k] setNote:[NSString stringWithFormat:@"in transizione verso %@ · ancora %@ s", t[@"to"], t[@"remaining_s"]]];
        else [_rows[k] setNote:@""];
    }
    NSString *cur = st[@"rhythm"];
    for (NSString *r in _rhythmBtn) {
        BOOL on = [r isEqualToString:cur], pend = [r isEqualToString:_pendingRhythm];
        [_rhythmBtn[r] setStyle:on ? CtlButtonFilled : (pend ? CtlButtonTinted : CtlButtonQuiet) color:pend && !on ? CTL_YELLOW : CTL_TINT];
    }
    if (_nibpInfo) {
        NSString *last = [st[@"nibp_last_systolic_mmhg"] isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"%@/%@", st[@"nibp_last_systolic_mmhg"], st[@"nibp_last_diastolic_mmhg"]] : @"nessuna";
        NSDictionary *stt = @{@"idle": @"", @"measuring": @" · misura in corso", @"complete": @"", @"error": @" · misura non riuscita"};
        _nibpInfo.text = [NSString stringWithFormat:@"Ultima NIBP a monitor: %@%@%@", last, stt[st[@"nibp_status"] ?: @""] ?: @"",
                          [st[@"sensors"][@"nibp"] boolValue] ? @"" : @"\nBracciale non applicato"];
    }
}

#pragma mark - Pannelli a impostazioni: Defibrillatore, Monitor e allarmi

// Righe di impostazione dentro un elenco che scorre. Ogni riga registra un blocco che la tiene allineata allo stato
// del monitor (saltato per un attimo dopo un tocco, così il valore non "torna indietro" prima della risposta).
- (BOOL)justTouched:(NSString *)key { return CACurrentMediaTime() - _setTouched[key].doubleValue < 1.5; }
- (void)touched:(NSString *)key { _setTouched[key] = @(CACurrentMediaTime()); }

- (CGFloat)header:(NSString *)t in:(UIView *)v y:(CGFloat)y {
    [v addSubview:CtlLabel(CGRectMake(0, y + 6, v.bounds.size.width, 16), t, 11, YES, CTL_INK3)]; return y + 28;
}
- (UIView *)rowIn:(UIView *)v y:(CGFloat)y title:(NSString *)title sub:(NSString *)sub { return [self rowIn:v y:y title:title sub:sub reserve:232]; }
// reserve = larghezza occupata a destra dai comandi della riga: il testo si ferma prima
- (UIView *)rowIn:(UIView *)v y:(CGFloat)y title:(NSString *)title sub:(NSString *)sub reserve:(CGFloat)reserve {
    CGFloat W = v.bounds.size.width;
    UIView *r = [[UIView alloc] initWithFrame:CGRectMake(0, y, W, 50)]; r.backgroundColor = CTL_CARD2; r.layer.cornerRadius = 10;
    UILabel *t = CtlLabel(CGRectMake(14, sub ? 6 : 0, W - 14 - reserve, sub ? 22 : 50), title, 15, NO, CTL_INK); t.adjustsFontSizeToFitWidth = YES; t.minimumScaleFactor = 0.75; [r addSubview:t];
    if (sub) { UILabel *d = CtlLabel(CGRectMake(14, 27, W - 14 - reserve, 17), sub, 11, NO, CTL_INK3); d.adjustsFontSizeToFitWidth = YES; d.minimumScaleFactor = 0.8; [r addSubview:d]; }
    [v addSubview:r];
    return r;
}
// numero con − e +: get legge il valore dallo stato, set manda il comando
- (CGFloat)stepRow:(NSString *)title sub:(NSString *)sub key:(NSString *)key in:(UIView *)v y:(CGFloat)y step:(NSInteger)step min:(NSInteger)min max:(NSInteger)max unit:(NSString *)unit
               get:(NSNumber *(^)(void))get set:(void (^)(NSInteger))set {
    UIView *r = [self rowIn:v y:y title:title sub:sub]; CGFloat W = r.bounds.size.width;
    UILabel *val = CtlLabel(CGRectMake(W - 168, 0, 74, 50), @"--", 19, YES, CTL_INK); val.font = CtlDigits(19, YES); val.textAlignment = NSTextAlignmentCenter; val.adjustsFontSizeToFitWidth = YES; val.minimumScaleFactor = 0.6; [r addSubview:val];
    CtlViewController *me = self; __block NSInteger cur = 0;
    for (int dir = -1; dir <= 1; dir += 2) {
        CtlButton *b = [CtlButton buttonWithTitle:dir < 0 ? @"−" : @"+" style:CtlButtonQuiet color:nil frame:CGRectMake(dir < 0 ? W - 214 : W - 52, 6, 44, 38) target:nil action:NULL];
        b.backgroundColor = CTL_CARD; b.titleLabel.font = [UIFont systemFontOfSize:24]; b.accessibilityIdentifier = [NSString stringWithFormat:@"set.%@.%@", key, dir < 0 ? @"meno" : @"piu"];
        b.onTap = ^{ NSInteger n = MAX(min, MIN(max, cur + dir * step)); if (n == cur) return; cur = n; [me touched:key]; val.text = [NSString stringWithFormat:@"%ld%@", (long)n, unit]; set(n); };
        [r addSubview:b];
    }
    [_updaters addObject:^{ if ([me justTouched:key]) return; NSNumber *n = get(); if (!n) return; cur = n.integerValue; NSString *t = [NSString stringWithFormat:@"%ld%@", (long)cur, unit]; if (![val.text isEqualToString:t]) val.text = t; }];
    return y + 56;
}
- (CGFloat)switchRow:(NSString *)title sub:(NSString *)sub key:(NSString *)key in:(UIView *)v y:(CGFloat)y color:(UIColor *)color get:(BOOL (^)(void))get set:(void (^)(BOOL))set {
    UIView *r = [self rowIn:v y:y title:title sub:sub reserve:80]; CGFloat W = r.bounds.size.width;
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(W - 65, 9, 51, 31)]; sw.onTintColor = color ?: CTL_TINT; sw.accessibilityIdentifier = [@"set." stringByAppendingString:key];
    [r addSubview:sw];
    CtlViewController *me = self;
    CtlButton *proxy = [CtlButton buttonWithTitle:@"" style:CtlButtonQuiet color:nil frame:CGRectZero target:nil action:NULL]; proxy.hidden = YES; [r addSubview:proxy];
    proxy.onTap = ^{ [me touched:key]; set(sw.on); };
    [sw addTarget:proxy action:@selector(fire) forControlEvents:UIControlEventValueChanged];
    [_updaters addObject:^{ if ([me justTouched:key]) return; BOOL on = get(); if (sw.on != on) [sw setOn:on animated:YES]; }];
    return y + 56;
}
- (CGFloat)segRow:(NSString *)title key:(NSString *)key items:(NSArray<NSString *> *)items in:(UIView *)v y:(CGFloat)y get:(NSInteger (^)(void))get set:(void (^)(NSInteger))set {
    CGFloat W = v.bounds.size.width;
    if (title) { [v addSubview:CtlLabel(CGRectMake(0, y, W, 20), title, 14, NO, CTL_INK)]; y += 24; }
    UISegmentedControl *sg = [[UISegmentedControl alloc] initWithItems:items]; sg.frame = CGRectMake(0, y, W, 34); sg.tintColor = CTL_TINT; sg.accessibilityIdentifier = [@"set." stringByAppendingString:key];
    [v addSubview:sg];
    CtlViewController *me = self;
    CtlButton *proxy = [CtlButton buttonWithTitle:@"" style:CtlButtonQuiet color:nil frame:CGRectZero target:nil action:NULL]; proxy.hidden = YES; [v addSubview:proxy];
    proxy.onTap = ^{ [me touched:key]; set(sg.selectedSegmentIndex); };
    [sg addTarget:proxy action:@selector(fire) forControlEvents:UIControlEventValueChanged];
    [_updaters addObject:^{ if ([me justTouched:key]) return; NSInteger i = get(); if (sg.selectedSegmentIndex != i) sg.selectedSegmentIndex = i; }];
    return y + 44;
}

- (void)buildSettings {
    for (UIView *v in [_edBody.subviews copy]) [v removeFromSuperview];
    [_rows removeAllObjects]; [_rhythmBtn removeAllObjects]; _nibpInfo = nil;
    CtlScrollView *sc = [[CtlScrollView alloc] initWithFrame:_edBody.bounds]; sc.indicatorStyle = UIScrollViewIndicatorStyleWhite; [_edBody addSubview:sc];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _edBody.bounds.size.width - 6, 10)]; [sc addSubview:v];
    CtlViewController *me = self; CtlModel *m = _m; CGFloat y = 0;
    NSDictionary *(^df)(void) = ^NSDictionary *{ NSDictionary *d = m.state[@"defib"]; return [d isKindOfClass:[NSDictionary class]] ? d : @{}; };
    NSDictionary *(^cfg)(void) = ^NSDictionary *{ NSDictionary *d = df()[@"config"]; return [d isKindOfClass:[NSDictionary class]] ? d : @{}; };
    void (^setCfg)(NSString *, id) = ^(NSString *k, id val) { [m command:@"set_defib_config" value:@{k: val}]; };
    if ([_sel isEqualToString:@"defib"]) {
        _edTitle.text = @"Defibrillatore";
        _edSub.text = @"Il defibrillatore lo usano i partecipanti sul monitor. Qui decidi che cosa succede dopo le scariche e con il pacing.";
        // stato dal vivo
        UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, y, v.bounds.size.width, 58)]; box.backgroundColor = CTL_CARD2; box.layer.cornerRadius = 10; [v addSubview:box];
        UILabel *live = CtlLabel(CGRectMake(14, 0, box.bounds.size.width - 28, 58), @"", 14, NO, CTL_INK); live.numberOfLines = 3; [box addSubview:live];
        [_updaters addObject:^{
            NSDictionary *d = df(); NSDictionary *pc = [d[@"pacer"] isKindOfClass:[NSDictionary class]] ? d[@"pacer"] : @{};
            NSString *md = @{@"off": @"spento", @"aed": @"modo DAE", @"manual": @"modo manuale", @"pacer": @"modo pacer"}[d[@"mode"] ?: @""] ?: @"--";
            NSString *t = [NSString stringWithFormat:@"Adesso: %@ · %@ J · %@ scariche%@%@", md, d[@"energy_j"] ?: @"--", d[@"shock_count"] ?: @0,
                           [d[@"pads_connected"] boolValue] ? @" · piastre applicate" : @" · piastre non applicate",
                           [pc[@"running"] boolValue] ? [NSString stringWithFormat:@"\nPacing %@ ppm, %@ mA%@", pc[@"rate_ppm"], pc[@"output_ma"], [pc[@"capture"] boolValue] ? @" — cattura" : @" — senza cattura"] : @""];
            if ([d[@"message"] length]) t = [t stringByAppendingFormat:@"\n«%@»", d[@"message"]];
            if (![live.text isEqualToString:t]) live.text = t;
        }];
        y += 66;
        y = [self header:@"ESITO DELLE SCARICHE" in:v y:y];
        y = [self segRow:nil key:@"outcome_mode" items:@[@"Decido io dopo ogni scarica", @"Regole automatiche"] in:v y:y
                     get:^NSInteger { return [cfg()[@"outcome_mode"] isEqual:@"auto"] ? 1 : 0; } set:^(NSInteger i) { setCfg(@"outcome_mode", i ? @"auto" : @"instructor"); }];
        y = [self stepRow:@"Scariche per convertire" sub:@"FV / TV senza polso · 0 = mai" key:@"shocks_to_convert" in:v y:y step:1 min:0 max:9 unit:@""
                      get:^NSNumber *{ return cfg()[@"shocks_to_convert"]; } set:^(NSInteger n) { setCfg(@"shocks_to_convert", @(n)); }];
        y = [self stepRow:@"Energia minima efficace" sub:@"sotto, la scarica non conta" key:@"min_energy_j" in:v y:y step:10 min:10 max:360 unit:@" J"
                      get:^NSNumber *{ return cfg()[@"min_energy_j"]; } set:^(NSInteger n) { setCfg(@"min_energy_j", @(n)); }];
        UIView *r = [self rowIn:v y:y title:@"Ritmo dopo la scarica" sub:nil];
        CtlButton *rb = [CtlButton buttonWithTitle:@"--" style:CtlButtonTinted color:CTL_TINT frame:CGRectMake(r.bounds.size.width - 196, 6, 188, 38) target:nil action:NULL];
        rb.titleLabel.font = [UIFont boldSystemFontOfSize:13]; rb.maxLines = 1; rb.accessibilityIdentifier = @"set.post_shock_rhythm"; [r addSubview:rb];
        __weak CtlButton *wrb = rb;
        rb.onTap = ^{ [me pickRhythm:@"Ritmo dopo la scarica efficace" from:wrb done:^(NSString *rh) { setCfg(@"post_shock_rhythm", rh); }]; };
        [_updaters addObject:^{ NSString *t = CtlRhythmName(cfg()[@"post_shock_rhythm"]); if (![[rb titleForState:UIControlStateNormal] isEqualToString:t]) [rb setTitle:t forState:UIControlStateNormal]; }];
        y += 56;
        y = [self switchRow:@"Scarica non sincronizzata → FV" sub:@"su un ritmo con polso (R su T): l'errore ha una conseguenza" key:@"unsync_shock_vf" in:v y:y color:CTL_ORANGE
                        get:^BOOL { return [cfg()[@"unsync_shock_vf"] boolValue]; } set:^(BOOL on) { setCfg(@"unsync_shock_vf", @((BOOL)on)); }];
        y = [self header:@"PACING" in:v y:y];
        y = [self stepRow:@"Soglia di cattura" sub:@"sotto, il pacing non cattura" key:@"capture_threshold_ma" in:v y:y step:5 min:0 max:200 unit:@" mA"
                      get:^NSNumber *{ return cfg()[@"capture_threshold_ma"]; } set:^(NSInteger n) { setCfg(@"capture_threshold_ma", @(n)); }];
        y = [self switchRow:@"La cattura è possibile" sub:nil key:@"capture_possible" in:v y:y color:nil get:^BOOL { return [cfg()[@"capture_possible"] boolValue]; } set:^(BOOL on) { setCfg(@"capture_possible", @((BOOL)on)); }];
        y = [self switchRow:@"La cattura genera polso e pressione" sub:@"spento: cattura solo elettrica" key:@"mechanical_capture" in:v y:y color:nil get:^BOOL { return [cfg()[@"mechanical_capture"] boolValue]; } set:^(BOOL on) { setCfg(@"mechanical_capture", @((BOOL)on)); }];
        y = [self header:@"DAE" in:v y:y];
        y = [self stepRow:@"RCP fra le analisi" sub:nil key:@"aed_cpr_s" in:v y:y step:30 min:30 max:300 unit:@" s"
                      get:^NSNumber *{ return cfg()[@"aed_cpr_s"]; } set:^(NSInteger n) { setCfg(@"aed_cpr_s", @(n)); }];
        y = [self switchRow:@"Istruzioni vocali" sub:nil key:@"voice_prompts" in:v y:y color:nil get:^BOOL { return [cfg()[@"voice_prompts"] boolValue]; } set:^(BOOL on) { setCfg(@"voice_prompts", @((BOOL)on)); }];
    } else {
        _edTitle.text = @"Monitor, allarmi e paziente";
        _edSub.text = @"Movimenti del paziente, audio del monitor, NIBP automatica e limiti di allarme.";
        y = [self header:@"MOVIMENTI DEL PAZIENTE (solo con un ritmo con polso)" in:v y:y];
        y = [self segRow:nil key:@"motion" items:@[@"Fermo", @"Lievi", @"Marcati"] in:v y:y
                     get:^NSInteger { return (NSInteger)[@[@"off", @"light", @"strong"] indexOfObject:m.state[@"patient_motion"] ?: @"off"]; }
                     set:^(NSInteger i) { [m command:@"set_patient_motion" value:@[@"off", @"light", @"strong"][i]]; }];
        y = [self switchRow:@"Fisiologia automatica" sub:@"in arresto SpO₂, FR ed EtCO₂ scendono da soli" key:@"auto_physiology" in:v y:y color:nil
                        get:^BOOL { return [m.state[@"auto_physiology"] boolValue]; } set:^(BOOL on) { [m command:@"set_auto_physiology" value:@((BOOL)on)]; }];
        y = [self header:@"AUDIO DEL MONITOR" in:v y:y];
        y = [self stepRow:@"Volume generale" sub:nil key:@"volume" in:v y:y step:10 min:0 max:100 unit:@"%" get:^NSNumber *{ return m.state[@"volume_percent"]; } set:^(NSInteger n) { [m command:@"set_volume" value:@(n)]; }];
        y = [self switchRow:@"Bip a ogni battito" sub:nil key:@"qrs_beep" in:v y:y color:nil get:^BOOL { return [m.state[@"qrs_beep_enabled"] boolValue]; } set:^(BOOL on) { [m command:@"set_qrs_beep" value:@((BOOL)on)]; }];
        y = [self header:@"NIBP AUTOMATICA (minuti fra le misure)" in:v y:y];
        NSArray *iv = @[@0, @1, @2, @3, @5, @10, @15];
        y = [self segRow:nil key:@"nibp_interval" items:@[@"No", @"1", @"2", @"3", @"5", @"10", @"15"] in:v y:y
                     get:^NSInteger { NSUInteger i = [iv indexOfObject:@([m.state[@"nibp_interval_min"] integerValue])]; return i == NSNotFound ? UISegmentedControlNoSegment : (NSInteger)i; }
                     set:^(NSInteger i) { [m command:@"set_nibp_interval" value:iv[i]]; }];
        y = [self header:@"LIMITI DI ALLARME" in:v y:y];
        NSArray *lim = @[@[@"hr_high", @"FC alta", @5, @" bpm"], @[@"hr_low", @"FC bassa", @5, @" bpm"], @[@"spo2_low", @"SpO₂ bassa", @1, @"%"],
                         @[@"sys_high", @"Sistolica alta", @5, @" mmHg"], @[@"sys_low", @"Sistolica bassa", @5, @" mmHg"],
                         @[@"rr_high", @"FR alta", @1, @"/min"], @[@"rr_low", @"FR bassa", @1, @"/min"], @[@"etco2_high", @"EtCO₂ alta", @1, @" mmHg"], @[@"etco2_low", @"EtCO₂ bassa", @1, @" mmHg"]];
        for (NSArray *l in lim) {
            NSString *k = l[0];
            y = [self stepRow:l[1] sub:nil key:k in:v y:y step:[l[2] integerValue] min:1 max:300 unit:l[3]
                          get:^NSNumber *{ NSDictionary *al = m.state[@"alarm_limits"]; return [al isKindOfClass:[NSDictionary class]] ? al[k] : nil; }
                          set:^(NSInteger n) { [m command:@"set_alarm_limits" value:@{k: @(n)}]; }];
        }
        CtlButton *rs = [CtlButton buttonWithTitle:@"Ripristina i limiti predefiniti" style:CtlButtonQuiet color:nil frame:CGRectMake(0, y + 2, v.bounds.size.width, 42) target:nil action:NULL];
        rs.backgroundColor = CTL_CARD2; rs.titleLabel.font = [UIFont systemFontOfSize:14]; rs.accessibilityIdentifier = @"set.limits.reset";
        rs.onTap = ^{ [m command:@"reset_alarm_limits" value:nil]; [me flash:@"Limiti di allarme ripristinati"]; };
        [v addSubview:rs]; y += 52;
    }
    v.frame = CGRectMake(0, 0, v.bounds.size.width, y + 4);
    sc.contentSize = CGSizeMake(sc.bounds.size.width, y + 4);
}

- (void)pickRhythm:(NSString *)title from:(UIView *)src done:(void (^)(NSString *))done {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *r in @[@"sinus", @"sinus_tachycardia", @"sinus_bradycardia", @"afib", @"asystole", @"pea"])
        [a addAction:[UIAlertAction actionWithTitle:CtlRhythmName(r) style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { done(r); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = src; a.popoverPresentationController.sourceRect = src.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

// "Decido io": dopo una scarica il monitor aspetta l'istruttore. La domanda compare sopra il pannello centrale,
// qualunque cosa si stia guardando, finché non si risponde.
- (void)refreshOutcome {
    NSDictionary *d = [_m.state[@"defib"] isKindOfClass:[NSDictionary class]] ? _m.state[@"defib"] : @{};
    BOOL pending = [d[@"outcome_pending"] boolValue];
    NSString *from = [d[@"outcome_from"] isKindOfClass:[NSString class]] ? d[@"outcome_from"] : nil;
    NSString *sig = pending ? [NSString stringWithFormat:@"%@|%@", from, d[@"shock_count"]] : nil;
    if ((sig == _outcomeSig) || [sig isEqualToString:_outcomeSig]) return;
    _outcomeSig = sig;
    [_outcome removeFromSuperview]; _outcome = nil;
    if (!pending) return;
    CGFloat W = _center.bounds.size.width;
    _outcome = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 254)];
    _outcome.backgroundColor = CtlRGB(0.26, 0.19, 0.02); _outcome.layer.cornerRadius = 12; _outcome.layer.borderWidth = 2; _outcome.layer.borderColor = CTL_YELLOW.CGColor;
    BOOL sync = [d[@"outcome_sync"] boolValue]; NSInteger joule = [d[@"outcome_energy_j"] integerValue];
    [_outcome addSubview:CtlLabel(CGRectMake(20, 12, W - 40, 26), sync ? @"Cardioversione erogata: che cosa succede adesso?" : @"Scarica erogata: che cosa succede adesso?", 20, YES, CTL_INK)];
    UILabel *sub = CtlLabel(CGRectMake(20, 38, W - 40, 20), [NSString stringWithFormat:@"%@ n. %@%@ · il paziente è ancora in %@", sync ? @"Sincronizzata" : @"Scarica",
                                                            d[@"outcome_shock"] ?: d[@"shock_count"] ?: @"", joule > 0 ? [NSString stringWithFormat:@" · %ld J", (long)joule] : @"", [CtlRhythmName(from) lowercaseString]], 13, NO, CtlRGB(1, 0.88, 0.6));
    [_outcome addSubview:sub];
    // le scelte più frequenti a un tocco; «Altro ritmo…» apre tutti i ritmi
    NSArray *opts = @[@[@"stay", [NSString stringWithFormat:@"Resta in %@", [CtlRhythmName(from) lowercaseString]]], @[@"sinus", @"Sinusale (ROSC)"], @[@"sinus_tachycardia", @"Tachicardia sinusale (ROSC)"],
                      @[@"vf", @"Fibrillazione ventricolare"], @[@"asystole", @"Asistolia"], @[@"pea", @"PEA"], @[@"other", @"Altro ritmo…"]];
    CGFloat bw = (W - 40 - 2 * 8) / 3; NSUInteger i = 0; CtlModel *m = _m;
    for (NSArray *o in opts) {
        CtlButton *b = [CtlButton buttonWithTitle:o[1] style:i == 0 ? CtlButtonQuiet : CtlButtonFilled color:[o[0] hasPrefix:@"sinus"] ? CTL_GREEN : CTL_TINT frame:CGRectMake(20 + (i % 3) * (bw + 8), 68 + (i / 3) * 58, bw, 50) target:nil action:NULL];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:13]; b.accessibilityIdentifier = [@"outcome." stringByAppendingString:o[0]];
        __weak CtlButton *wb = b; __weak typeof(self) me = self;
        b.onTap = [o[0] isEqualToString:@"other"] ? ^{ [me outcomeOtherFrom:wb]; } : ^{ [m command:@"defib_outcome" value:o[0]]; };
        if ([o[0] isEqualToString:@"other"]) b.frame = CGRectMake(20, 68 + 2 * 58, W - 40, 50);
        [_outcome addSubview:b]; i++;
    }
    [_center addSubview:_outcome];
}

// «Altro ritmo…»: tutti i ritmi del monitor
- (void)outcomeOtherFrom:(UIView *)src {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Dopo la scarica il paziente passa a" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    CtlModel *m = _m;
    for (NSString *r in @[@"sinus", @"sinus_tachycardia", @"sinus_bradycardia", @"afib", @"vt_pulse", @"vt", @"vf", @"asystole", @"pea"])
        [a addAction:[UIAlertAction actionWithTitle:CtlRhythmName(r) style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [m command:@"defib_outcome" value:r]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = src; a.popoverPresentationController.sourceRect = src.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

// sede della sonda (lato destro/sinistro): conta, perché il bracciale sullo stesso braccio della SpO₂ la fa sparire
- (void)siteTapped:(CtlButton *)b {
    NSString *k = [b.accessibilityIdentifier substringFromIndex:5];
    NSDictionary *sites = [_m.state[@"sensor_sites"] isKindOfClass:[NSDictionary class]] ? _m.state[@"sensor_sites"] : @{};
    NSDictionary *def = @{@"spo2": @"finger_l2", @"nibp": @"upper_arm_r", @"art": @"radial_l"};
    NSString *cur = sites[k] ?: def[k];
    NSString *nw = [cur rangeOfString:@"_r"].location != NSNotFound ? [cur stringByReplacingOccurrencesOfString:@"_r" withString:@"_l"] : [cur stringByReplacingOccurrencesOfString:@"_l" withString:@"_r"];
    _swTouched[k] = @(CACurrentMediaTime());
    // la sonda spostata va tolta e rimessa: il monitor riparte da capo, come nella realtà
    CtlModel *m = _m;
    [m command:@"set_sensor" value:@{@"sensor": k, @"connected": @NO} done:^(BOOL ok, NSString *e) { [m command:@"set_sensor" value:@{@"sensor": k, @"connected": @YES, @"site": nw}]; }];
    [self flash:[NSString stringWithFormat:@"%@ spostata a %@", @{@"spo2": @"Sonda SpO₂", @"nibp": @"Bracciale", @"art": @"Linea arteriosa"}[k], [nw rangeOfString:@"_r"].location != NSNotFound ? @"destra" : @"sinistra"]];
}
- (void)openMonitorPanel { _sel = @"monitor"; [self refresh]; }

- (void)assessCrt {
    [_m command:@"assess_crt" value:nil done:^(BOOL ok, NSString *e) { if (ok) [self flash:@"Refill: valutazione in corso sul monitor"]; }];
}
- (void)spo2Option:(UISwitch *)sw {
    _swTouched[sw.accessibilityIdentifier] = @(CACurrentMediaTime());
    if ([sw.accessibilityIdentifier isEqualToString:@"spo2.lowperf"]) [_m command:@"set_spo2_low_perfusion" value:@((BOOL)sw.on)];
    else [_m command:@"set_spo2_signal_valid" value:@((BOOL)!sw.on)];
}

- (BOOL)isArrest:(NSString *)r { return [@[@"vt", @"vf", @"asystole", @"pea", @"vt_pulse"] containsObject:r]; }

- (void)rhythmTapped:(CtlButton *)b {
    NSString *r = [b.accessibilityIdentifier substringFromIndex:7];
    if (_modeSec == 0 || [self isArrest:r] || [self isArrest:_m.state[@"rhythm"]]) {
        _pendingRhythm = nil;
        [_m command:@"set_rhythm" value:r];
        [self flash:[NSString stringWithFormat:@"Ritmo: %@", CtlRhythmName(r)]];
    } else {
        _pendingRhythm = [r isEqualToString:_m.state[@"rhythm"]] ? nil : r;
    }
    [self refresh];
}

- (void)param:(NSString *)k changed:(double)v final:(BOOL)final {
    if (!final) return;
    NSString *now = PDef(k)[@"now"];
    if (now.length) { [_m command:now value:@(v)]; return; }
    NSInteger iv = (NSInteger)lround(v);
    // la diastolica resta sotto la sistolica
    if ([k isEqualToString:@"systolic_mmhg"] || [k isEqualToString:@"diastolic_mmhg"]) {
        NSInteger s = [k hasPrefix:@"sys"] ? iv : [(_pending[@"systolic_mmhg"] ?: [self valueFor:@"systolic_mmhg"]) integerValue];
        NSInteger d = [k hasPrefix:@"dia"] ? iv : [(_pending[@"diastolic_mmhg"] ?: [self valueFor:@"diastolic_mmhg"]) integerValue];
        if (d >= s) { if ([k hasPrefix:@"sys"]) d = MAX(20, s - 10); else s = d + 10; }
        if (_modeSec == 0) { [_m command:@"transition" value:@{@"params": @{@"systolic_mmhg": @(s), @"diastolic_mmhg": @(d)}, @"duration_s": @0}]; }
        else { _pending[@"systolic_mmhg"] = @(s); _pending[@"diastolic_mmhg"] = @(d); }
        [self refresh]; return;
    }
    if (_modeSec == 0) [_m command:@"transition" value:@{@"params": @{k: @(iv)}, @"duration_s": @0}];
    else _pending[k] = @(iv);
    [self refresh];
}

- (void)setBP:(NSInteger)s dia:(NSInteger)d {
    if (_modeSec == 0) [_m command:@"transition" value:@{@"params": @{@"systolic_mmhg": @(s), @"diastolic_mmhg": @(d)}, @"duration_s": @0}];
    else { _pending[@"systolic_mmhg"] = @(s); _pending[@"diastolic_mmhg"] = @(d); }
    [self refresh];
}

#pragma mark - Regia

- (void)modeChanged {
    _modeSec = [@[@0, @10, @30, @60, @120][_modeSeg.selectedSegmentIndex] integerValue];
    if (_modeSec == 0 && (_pending.count || _pendingRhythm)) [self applyPending];     // tornando a "Subito" le modifiche in attesa partono
    [self refresh];
}
- (void)applyPending {
    if (!_pending.count && !_pendingRhythm) return;
    NSMutableDictionary *v = [@{@"params": [_pending copy], @"duration_s": @(_modeSec)} mutableCopy];
    if (_pendingRhythm) v[@"rhythm"] = _pendingRhythm;
    NSString *what = _pendLabel.text;
    CtlViewController *me = self;
    [_m command:@"transition" value:v done:^(BOOL ok, NSString *e) { if (ok) [me flash:[NSString stringWithFormat:@"Avviato (%@). %@", Dur(me->_modeSec), [what stringByReplacingOccurrencesOfString:@"In attesa: " withString:@""]]]; }];
    [_pending removeAllObjects]; _pendingRhythm = nil;
    [self refresh];
}
- (void)cancelPending { [_pending removeAllObjects]; _pendingRhythm = nil; [self refresh]; }
// NB: i sì/no vanno sempre scritti @((BOOL)...): @(!x) in Objective-C è un intero e il monitor lo rifiuta
- (void)togglePause { [_m command:@"set_simulation_running" value:@((BOOL)![_m.state[@"simulation_running"] boolValue])]; }
- (void)clockMenu {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Timer di scenario"
        message:@"Conta il tempo di scenario (le pause non contano). Riparte da solo quando avvii uno scenario." preferredStyle:UIAlertControllerStyleActionSheet];
    CtlViewController *me = self;
    [a addAction:[UIAlertAction actionWithTitle:@"Azzera il timer" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [me->_m command:@"reset_clock" value:nil done:^(BOOL ok, NSString *e) { if (ok) [me flash:@"Timer azzerato: parametri e sonde restano come sono"]; }];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = _clockBtn; a.popoverPresentationController.sourceRect = _clockBtn.bounds;
    [self presentViewController:a animated:YES completion:nil];
}
- (void)takeControl { [_m takeControl]; }

- (void)monitorMenu {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:_m.monitorName
        message:@"Collegamento diretto fra iPad" preferredStyle:UIAlertControllerStyleActionSheet];
    CtlViewController *me = self;
    [a addAction:[UIAlertAction actionWithTitle:@"Azzera lo scenario e spegni il monitor…" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [me confirmReset]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Scollega e scegli un altro monitor" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [me->_m forgetMonitor]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = _monBtn; a.popoverPresentationController.sourceRect = _monBtn.bounds;
    [self presentViewController:a animated:YES completion:nil];
}
- (void)confirmReset {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Azzerare lo scenario?"
        message:@"Parametri, sonde, contatori e orologio tornano all'inizio e il monitor si spegne. Gli scenari salvati restano." preferredStyle:UIAlertControllerStyleAlert];
    CtlViewController *me = self;
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Azzera" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        CtlViewController *s = me; if (!s) return;
        [s->_pending removeAllObjects]; s->_pendingRhythm = nil; s->_lastState = nil;
        [s->_m command:@"reset_scenario" value:nil];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Sonde e azioni

// Layout del monitor: stesso comando della web app (set_layout); la scelta resta salvata sul monitor
// elenco e nomi dei layout arrivano dal monitor (campo "layouts" dello stato): qui non è scritto nessun nome
- (NSString *)layoutName:(NSString *)lid {
    for (NSDictionary *l in _m.state[@"layouts"]) if ([l isKindOfClass:[NSDictionary class]] && [l[@"id"] isEqual:lid]) return l[@"name"];
    return lid ?: @"--";
}
- (void)layoutMenu {
    NSString *cur = _m.state[@"layout"];
    NSArray *list = [_m.state[@"layouts"] isKindOfClass:[NSArray class]] ? _m.state[@"layouts"] : @[];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Layout del monitor" message:@"Che cosa vede il discente sull'altro iPad" preferredStyle:UIAlertControllerStyleActionSheet];
    CtlViewController *me = self;
    for (NSDictionary *item in list) {
        NSString *l = item[@"id"], *nm = item[@"name"] ?: l;
        NSString *t = [l isEqualToString:cur] ? [@"✓  " stringByAppendingString:nm] : nm;
        [a addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [me->_m command:@"set_layout" value:l done:^(BOOL ok, NSString *e) { if (ok) [me flash:[@"Layout del monitor: " stringByAppendingString:nm]]; }];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = _layoutBtn; a.popoverPresentationController.sourceRect = _layoutBtn.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)sensorChanged:(UISwitch *)sw {
    NSString *k = [sw.accessibilityIdentifier substringFromIndex:3];
    _swTouched[k] = @(CACurrentMediaTime());
    [_m command:@"set_sensor" value:@{@"sensor": k, @"connected": @((BOOL)sw.on)}];
}
- (void)ventilate {
    [_m command:@"ventilate" value:nil];
    [UIView animateWithDuration:0.12 animations:^{ self->_ventBtn.backgroundColor = [CTL_GREEN colorWithAlphaComponent:0.45]; }
                     completion:^(BOOL f) { [UIView animateWithDuration:0.35 animations:^{ self->_ventBtn.backgroundColor = CTL_CARD2; }]; }];
}
- (void)toggleCpr { [_m command:@"set_cpr" value:@((BOOL)![_m.state[@"cpr_active"] boolValue])]; }
- (void)measureNibp { [_m startNibp]; }
- (void)toggleMute { [_m command:@"mute_alarms" value:@((BOOL)([_m.state[@"alarms_muted_remaining_s"] integerValue] <= 0))]; }
- (void)touchPatient { [_m command:@"patient_touch" value:nil]; [self flash:@"Tocco operatore: 3 s di artefatto"]; }

#pragma mark - Colonna sinistra: stati e scenario

- (void)leftChanged {
    [[NSUserDefaults standardUserDefaults] setInteger:_leftSeg.selectedSegmentIndex forKey:@"sf_left"];
    _open = -1; _leftSig = nil;
    if (_leftSeg.selectedSegmentIndex == 1) [_m refreshScenarios];
    [self refresh];
}

- (NSArray<NSDictionary *> *)allStates { return [PresetStates() arrayByAddingObjectsFromArray:_custom]; }

// riga dell'elenco: titolo + dettaglio a destra; se aperta, sotto compaiono testo e pulsanti
- (CGFloat)addRow:(NSString *)title detail:(NSString *)detail marked:(BOOL)marked index:(NSInteger)idx y:(CGFloat)y
             body:(NSString *)body buttons:(NSArray<CtlButton *> *)buttons {
    CGFloat W = 252; BOOL open = idx == _open;
    UIControl *row = [[UIControl alloc] initWithFrame:CGRectMake(6, y, W - 12, 50)];
    row.backgroundColor = open ? CTL_CARD2 : [UIColor clearColor]; row.layer.cornerRadius = 9; row.tag = idx;
    row.accessibilityIdentifier = [NSString stringWithFormat:@"left.row.%ld", (long)idx];
    [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    if (marked) {       // "siamo qui": barra verde + freccia, mai solo colore
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 8, 4, 34)]; bar.backgroundColor = CTL_GREEN; bar.layer.cornerRadius = 2; bar.userInteractionEnabled = NO; [row addSubview:bar];
    }
    UILabel *t = CtlLabel(CGRectMake(12, 0, W - 12 - 24 - 62, 50), marked ? [@"▸ " stringByAppendingString:title] : title, 15, marked, marked ? CTL_GREEN : CTL_INK);
    t.numberOfLines = 2; t.adjustsFontSizeToFitWidth = YES; t.minimumScaleFactor = 0.8; t.userInteractionEnabled = NO; [row addSubview:t];
    UILabel *d = CtlLabel(CGRectMake(W - 12 - 66, 0, 58, 50), detail, 12, NO, CTL_INK3); d.textAlignment = NSTextAlignmentRight; d.font = CtlDigits(12, NO); d.userInteractionEnabled = NO; [row addSubview:d];
    [_leftScroll addSubview:row];
    y += 52;
    if (!open) return y;
    UIView *ex = [[UIView alloc] initWithFrame:CGRectMake(6, y - 2, W - 12, 10)]; ex.backgroundColor = CTL_CARD2; ex.layer.cornerRadius = 9;
    UILabel *b = CtlLabel(CGRectMake(12, 4, W - 36, 10), body, 12.5, NO, CTL_INK2); b.numberOfLines = 0;
    CGSize sz = [b sizeThatFits:CGSizeMake(W - 36, 400)]; b.frame = CGRectMake(12, 4, W - 36, MIN(sz.height, 170)); [ex addSubview:b];
    CGFloat by = CGRectGetMaxY(b.frame) + 8;
    for (CtlButton *btn in buttons) { btn.frame = CGRectMake(10, by, W - 32, btn.frame.size.height ?: 42); [ex addSubview:btn]; by += btn.frame.size.height + 6; }
    ex.frame = CGRectMake(6, y - 2, W - 12, by + 4);
    [_leftScroll addSubview:ex];
    _openRect = CGRectMake(0, row.frame.origin.y - 4, W, CGRectGetMaxY(ex.frame) - row.frame.origin.y + 12);
    return CGRectGetMaxY(ex.frame) + 6;
}

- (void)rowTapped:(UIControl *)row { _open = _open == row.tag ? -1 : row.tag; _leftSig = nil; [self refresh]; }

- (void)setFooter:(NSArray<UIView *> *)views height:(CGFloat)h {
    for (UIView *v in [_leftFooter.subviews copy]) [v removeFromSuperview];
    _leftFooter.frame = CGRectMake(0, 546 - h, 252, h);
    _leftScroll.frame = CGRectMake(0, 0, 252, 546 - h);
    if (h > 0) { UIView *ln = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 252, 0.5)]; ln.backgroundColor = CTL_LINE; [_leftFooter addSubview:ln]; }
    for (UIView *v in views) [_leftFooter addSubview:v];
}

- (void)refreshLeft {
    BOOL scen = _leftSeg.selectedSegmentIndex == 1, reg = _leftSeg.selectedSegmentIndex == 2;
    if (_debrief.presentingViewController) [_debrief reload];
    if (_m.logSession != _quickSession) { _quickSession = _m.logSession; [_quickCount removeAllObjects]; if (reg) _leftSig = nil; }
    if (reg) { [self refreshRegistro]; return; }
    NSDictionary *run = _m.scenario ?: @{};
    BOOL active = [run[@"active"] boolValue];
    // si ricostruisce solo quando cambia qualcosa che si vede (non a ogni lettura dello stato)
    NSString *sig = scen ? [NSString stringWithFormat:@"S|%d|%@|%@|%ld|%lu|%@|%d", active, run[@"id"], run[@"phase"], (long)_open, (unsigned long)_m.scenarios.hash, _m.scenarios ? @"y" : @"n", (int)(CACurrentMediaTime() < _endArmed)]
                         : [NSString stringWithFormat:@"T|%ld|%@|%lu", (long)_open, _lastState, (unsigned long)_custom.count];
    if (scen && active) _phaseClock.text = Clock([run[@"phase_time_s"] integerValue]);
    if ([sig isEqualToString:_leftSig]) return;
    _leftSig = sig; _openRect = CGRectZero;
    for (UIView *v in [_leftScroll.subviews copy]) [v removeFromSuperview];
    _phaseClock = nil;
    CGFloat y = 6; CtlViewController *me = self;

    if (!scen) {
        // ----- Stati: pacchetti di parametri attivabili con un tocco -----
        NSArray *sts = [self allStates]; NSInteger i = 0;
        for (NSDictionary *st in sts) {
            NSInteger idx = i; BOOL custom = i >= (NSInteger)PresetStates().count;
            CtlButton *go = [CtlButton buttonWithTitle:[NSString stringWithFormat:@"Attiva · %@", Dur([st[@"d"] integerValue])] style:CtlButtonFilled color:CTL_TINT frame:CGRectMake(0, 0, 0, 44) target:nil action:NULL];
            go.accessibilityIdentifier = @"state.go"; go.onTap = ^{ [me activateState:idx]; };
            NSMutableArray *btns = [NSMutableArray arrayWithObject:go];
            if (custom) {
                CtlButton *del = [CtlButton buttonWithTitle:@"Elimina questo stato" style:CtlButtonTinted color:CTL_RED frame:CGRectMake(0, 0, 0, 36) target:nil action:NULL];
                del.titleLabel.font = [UIFont systemFontOfSize:13]; del.onTap = ^{ [me deleteState:idx]; };
                [btns addObject:del];
            }
            y = [self addRow:st[@"n"] detail:Dur([st[@"d"] integerValue]) marked:[st[@"n"] isEqualToString:_lastState] index:i y:y
                        body:CtlDescribeBlock(st[@"r"], st[@"p"], st[@"now"]) buttons:btns];
            i++;
        }
        CtlButton *save = [CtlButton buttonWithTitle:@"Salva lo stato attuale" style:CtlButtonTinted color:CTL_TINT frame:CGRectMake(10, 8, 232, 40) target:self action:@selector(saveState)];
        save.titleLabel.font = [UIFont boldSystemFontOfSize:14]; save.accessibilityIdentifier = @"state.save"; [save setIcon:@"plus" above:NO];
        [self setFooter:@[save] height:56];
    } else if (!_m.scenarios) {
        UILabel *l = CtlLabel(CGRectMake(16, 16, 220, 120), @"Questo monitor non ha ancora gli scenari: va aggiornato similFranz Monitor (versione 0.12 o successiva).", 14, NO, CTL_INK2);
        l.numberOfLines = 0; [_leftScroll addSubview:l]; y = 140;
        [self setFooter:@[] height:0];
    } else if (!active) {
        // ----- Scenari salvati sul monitor -----
        NSInteger i = 0;
        for (NSDictionary *sc in _m.scenarios) {
            NSArray *ph = sc[@"phases"]; NSString *sid = sc[@"id"];
            NSMutableString *body = [NSMutableString string];
            if ([sc[@"notes"] length]) [body appendFormat:@"%@\n\n", sc[@"notes"]];
            NSInteger n = 1; for (NSDictionary *p in ph) [body appendFormat:@"%ld. %@\n", (long)n++, p[@"name"]];
            CtlButton *go = [CtlButton buttonWithTitle:@"Avvia lo scenario" style:CtlButtonFilled color:CTL_GREEN frame:CGRectMake(0, 0, 0, 44) target:nil action:NULL];
            go.accessibilityIdentifier = @"scen.start"; go.onTap = ^{ [me scenario:@{@"action": @"start", @"id": sid, @"phase": @0} flash:@"Scenario avviato: fase 1"]; };
            CtlButton *ed = [CtlButton buttonWithTitle:@"Modifica" style:CtlButtonQuiet color:nil frame:CGRectMake(0, 0, 0, 38) target:nil action:NULL];
            ed.accessibilityIdentifier = @"scen.edit"; ed.onTap = ^{ [me editScenario:sc]; };
            y = [self addRow:sc[@"name"] detail:[NSString stringWithFormat:@"%lu fasi", (unsigned long)ph.count] marked:NO index:i y:y body:body buttons:@[go, ed]];
            i++;
        }
        CtlButton *nw = [CtlButton buttonWithTitle:@"Nuovo scenario" style:CtlButtonTinted color:CTL_TINT frame:CGRectMake(10, 8, 232, 40) target:nil action:NULL];
        nw.titleLabel.font = [UIFont boldSystemFontOfSize:14]; nw.accessibilityIdentifier = @"scen.new"; [nw setIcon:@"plus" above:NO]; nw.onTap = ^{ [me editScenario:nil]; };
        [self setFooter:@[nw] height:56];
    } else {
        // ----- Scenario in corso: le fasi avanzano solo quando lo dice l'istruttore -----
        NSDictionary *sc = nil; for (NSDictionary *s in _m.scenarios) if ([s[@"id"] isEqual:run[@"id"]]) sc = s;
        UILabel *nm = CtlLabel(CGRectMake(16, y + 2, 220, 36), run[@"name"], 13, YES, CTL_INK2); nm.numberOfLines = 2; [_leftScroll addSubview:nm];
        y += 42;
        NSInteger cur = [run[@"phase"] integerValue], i = 0;
        for (NSDictionary *p in sc[@"phases"]) {
            NSInteger idx = i; BOOL here = i == cur;
            NSString *body = [NSString stringWithFormat:@"%@\nTransizione: %@%@", CtlDescribeBlock(p[@"rhythm"], p[@"params"], p),
                              Dur([p[@"duration_s"] integerValue]), [p[@"note"] length] ? [@"\n\n" stringByAppendingString:p[@"note"]] : @""];
            NSMutableArray *btns = [NSMutableArray array];
            CtlButton *go = [CtlButton buttonWithTitle:here ? @"Riapplica questa fase" : @"Vai a questa fase" style:here ? CtlButtonQuiet : CtlButtonFilled color:CTL_TINT frame:CGRectMake(0, 0, 0, 42) target:nil action:NULL];
            go.accessibilityIdentifier = @"scen.goto";
            go.onTap = ^{ me->_open = -1; [me scenario:@{@"action": @"goto", @"phase": @(idx)} flash:[NSString stringWithFormat:@"Fase %ld: %@", (long)idx + 1, p[@"name"]]]; };
            [btns addObject:go];
            CGFloat y0 = y;
            y = [self addRow:[NSString stringWithFormat:@"%ld. %@", (long)i + 1, p[@"name"]] detail:here ? Clock([run[@"phase_time_s"] integerValue]) : ([p[@"duration_s"] integerValue] > 0 ? Dur([p[@"duration_s"] integerValue]) : @"")
                      marked:here index:i y:y body:body buttons:btns];
            if (here) {
                for (UIView *v in _leftScroll.subviews) if (v.tag == i && [v isKindOfClass:[UIControl class]] && fabs(v.frame.origin.y - y0) < 1)
                    for (UILabel *l in v.subviews) if ([l isKindOfClass:[UILabel class]] && l.textAlignment == NSTextAlignmentRight) { _phaseClock = l; l.textColor = CTL_GREEN; }
                if ([p[@"note"] length] && _open != i) {          // la nota della fase corrente è sempre in vista
                    UILabel *note = CtlLabel(CGRectMake(22, y - 2, 214, 10), p[@"note"], 12, NO, CTL_INK2); note.numberOfLines = 0;
                    CGSize sz = [note sizeThatFits:CGSizeMake(214, 300)]; note.frame = CGRectMake(22, y - 2, 214, sz.height); [_leftScroll addSubview:note];
                    y += sz.height + 8;
                }
            }
            i++;
        }
        NSString *next = run[@"next_name"];
        CtlButton *nx = [CtlButton buttonWithTitle:next ? [NSString stringWithFormat:@"Fase successiva\n%@", next] : @"Ultima fase raggiunta" style:CtlButtonFilled color:CTL_GREEN frame:CGRectMake(10, 8, 232, 64) target:nil action:NULL];
        nx.enabled = next != nil; nx.accessibilityIdentifier = @"scen.next";
        nx.onTap = ^{ me->_open = -1; [me scenario:@{@"action": @"next"} flash:[@"Fase successiva: " stringByAppendingString:next ?: @""]]; };
        BOOL armed = CACurrentMediaTime() < _endArmed;
        CtlButton *end = [CtlButton buttonWithTitle:armed ? @"Tocca di nuovo per terminare" : @"Termina lo scenario" style:armed ? CtlButtonFilled : CtlButtonQuiet color:CTL_RED frame:CGRectMake(10, 80, 232, 36) target:self action:@selector(endScenario)];
        end.titleLabel.font = [UIFont systemFontOfSize:13]; end.accessibilityIdentifier = @"scen.end";
        [self setFooter:@[nx, end] height:124];
    }
    _leftScroll.contentSize = CGSizeMake(252, y + 6);
    if (_open >= 0 && !CGRectIsEmpty(_openRect)) [_leftScroll scrollRectToVisible:_openRect animated:NO];
}

#pragma mark - Colonna sinistra: registro (osservazioni dell'istruttore) e piano di debriefing

// Menu rapido: un tocco = una voce nel registro del monitor, con il tempo di scenario. Stesso elenco della web app.
// @[categoria, testo, tag] ; il testo che finisce con "…" chiede di scrivere due parole.
static NSArray<NSArray *> *QuickMenu(void) {
    return @[ @[@"RICONOSCIMENTO"],
              @[@"action", @"Riconosciuto l'arresto cardiaco", @"ac"], @[@"action", @"Chiamato aiuto / attivato il team", @"help"],
              @[@"action", @"Valutazione ABCDE", @""], @[@"action", @"Valutato il ritmo", @""],
              @[@"RCP"],
              @[@"action", @"Iniziate le compressioni", @"cpr_start"], @[@"action", @"Cambio dell'operatore alle compressioni", @""], @[@"action", @"Ventilazioni", @""],
              @[@"VIE AEREE E ACCESSI"],
              @[@"action", @"Ossigeno", @""], @[@"action", @"Presidio sovraglottico", @""], @[@"action", @"Intubazione", @""],
              @[@"action", @"Accesso venoso", @""], @[@"action", @"Accesso intraosseo", @""],
              @[@"FARMACI"],
              @[@"drug", @"Adrenalina 1 mg", @""], @[@"drug", @"Amiodarone 300 mg", @""], @[@"drug", @"Amiodarone 150 mg", @""],
              @[@"drug", @"Atropina 0,5 mg", @""], @[@"drug", @"Liquidi 500 ml", @""], @[@"drug", @"Altro farmaco…", @""],
              @[@"PER IL DEBRIEFING"],
              @[@"plus", @"Punto di forza…", @""], @[@"minus", @"Da discutere…", @""], @[@"note", @"Nota libera…", @""] ];
}

- (void)refreshRegistro {
    NSDictionary *last = _m.log.lastObject;
    NSString *lastText = last ? [NSString stringWithFormat:@"%@  %@", Clock([last[@"t"] integerValue]), last[@"text"]] : @"Registro di questa sessione: vuoto";
    NSString *debTitle = [NSString stringWithFormat:@"Piano di debriefing · %lu voci", (unsigned long)_m.log.count];
    NSString *sig = [NSString stringWithFormat:@"R|%d|%@|%d", (int)_m.logAvailable, _quickCount, (int)(CACurrentMediaTime() < _quickFlashUntil)];
    if ([sig isEqualToString:_leftSig]) {          // niente da ricostruire: si aggiornano solo le due scritte in fondo
        if (![_regLast.text isEqualToString:lastText]) _regLast.text = lastText;
        if (![[_regDeb titleForState:UIControlStateNormal] isEqualToString:debTitle]) [_regDeb setTitle:debTitle forState:UIControlStateNormal];
        return;
    }
    if (_leftScroll.dragging || _leftScroll.decelerating) return;       // mai ricostruire sotto il dito: si rifà al prossimo giro
    _leftSig = sig; _openRect = CGRectZero; _phaseClock = nil;
    CGFloat keep = _leftScroll.contentOffset.y;
    for (UIView *v in [_leftScroll.subviews copy]) [v removeFromSuperview];
    CGFloat y = 4; NSInteger idx = 0; CtlViewController *me = self;
    if (!_m.logAvailable) {
        UILabel *l = CtlLabel(CGRectMake(16, 16, 220, 120), @"Questo monitor non ha ancora il registro: va aggiornato similFranz Monitor.", 14, NO, CTL_INK2); l.numberOfLines = 0; [_leftScroll addSubview:l];
        [self setFooter:@[] height:0]; return;
    }
    for (NSArray *q in QuickMenu()) {
        if (q.count == 1) { [_leftScroll addSubview:CtlLabel(CGRectMake(14, y + 8, 224, 16), q[0], 10.5, YES, CTL_INK3)]; y += 28; continue; }
        NSString *kind = q[0], *text = q[1], *tag = [q[2] length] ? q[2] : nil;
        UIColor *col = CtlLogKindColor(kind);
        BOOL just = [text isEqualToString:_quickFlash] && CACurrentMediaTime() < _quickFlashUntil;
        UIControl *row = [[UIControl alloc] initWithFrame:CGRectMake(6, y, 240, 40)];
        row.backgroundColor = just ? [col colorWithAlphaComponent:0.30] : CTL_CARD2; row.layer.cornerRadius = 9;
        row.accessibilityIdentifier = [NSString stringWithFormat:@"quick.%ld", (long)idx];
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 7, 4, 26)]; bar.backgroundColor = col; bar.layer.cornerRadius = 2; bar.userInteractionEnabled = NO; [row addSubview:bar];
        NSInteger n = _quickCount[text].integerValue;
        UILabel *t = CtlLabel(CGRectMake(14, 0, n ? 186 : 218, 40), just ? [@"✓ " stringByAppendingString:text] : text, 14, NO, CTL_INK);
        t.numberOfLines = 2; t.adjustsFontSizeToFitWidth = YES; t.minimumScaleFactor = 0.85; t.userInteractionEnabled = NO; [row addSubview:t];
        if (n) { UILabel *c = CtlLabel(CGRectMake(204, 0, 28, 40), [NSString stringWithFormat:@"%ld", (long)n], 14, YES, col); c.font = CtlDigits(14, YES); c.textAlignment = NSTextAlignmentRight; c.userInteractionEnabled = NO; [row addSubview:c]; }
        [row addTarget:self action:@selector(quickTapped:) forControlEvents:UIControlEventTouchUpInside]; row.tag = idx;
        [_leftScroll addSubview:row];
        (void)tag; y += 44; idx++;
    }
    _leftScroll.contentSize = CGSizeMake(252, y + 6);
    _leftScroll.contentOffset = CGPointMake(0, MIN(keep, MAX(0, y + 6 - _leftScroll.bounds.size.height)));
    // in fondo: l'ultima voce del registro e il piano di debriefing
    UILabel *lastL = CtlLabel(CGRectMake(12, 6, 228, 34), lastText, 11.5, NO, CTL_INK2);
    lastL.numberOfLines = 2; _regLast = lastL;
    CtlButton *deb = [CtlButton buttonWithTitle:debTitle style:CtlButtonFilled color:CTL_TINT frame:CGRectMake(10, 44, 232, 44) target:nil action:NULL];
    deb.titleLabel.font = [UIFont boldSystemFontOfSize:14]; deb.maxLines = 1; deb.accessibilityIdentifier = @"log.debrief"; deb.onTap = ^{ [me openDebrief]; }; _regDeb = deb;
    [self setFooter:@[lastL, deb] height:96];
}

- (void)quickTapped:(UIControl *)row {
    NSInteger idx = 0; NSArray *hit = nil;
    for (NSArray *q in QuickMenu()) { if (q.count == 1) continue; if (idx == row.tag) { hit = q; break; } idx++; }
    if (!hit) return;
    NSString *kind = hit[0], *text = hit[1], *tag = [hit[2] length] ? hit[2] : nil;
    if ([text hasSuffix:@"…"]) { [self askQuick:kind title:[text substringToIndex:text.length - 1]]; return; }
    [self logQuick:kind text:text tag:tag key:text];
}
- (void)logQuick:(NSString *)kind text:(NSString *)text tag:(NSString *)tag key:(NSString *)key {
    [_m logAdd:kind text:text tag:tag];
    _quickCount[key] = @(_quickCount[key].integerValue + 1);
    _quickFlash = [key copy]; _quickFlashUntil = CACurrentMediaTime() + 1.6; _leftSig = nil;
    [self flash:[NSString stringWithFormat:@"Registrato a %@: %@", Clock([_m.state[@"scenario_time_s"] integerValue]), text]];
    [self refresh];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ self->_leftSig = nil; [self refresh]; });
}
// voce con testo libero: due parole dell'istruttore (il tempo registrato è quello del tocco di conferma)
- (void)askQuick:(NSString *)kind title:(NSString *)title {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:@"Scrivi due parole: finiscono nel registro con il tempo di scenario." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.autocapitalizationType = UITextAutocapitalizationTypeSentences; tf.placeholder = [kind isEqualToString:@"drug"] ? @"es. Midazolam 2 mg" : @"es. Comunicazione a circuito chiuso"; }];
    CtlViewController *me = self; __weak UIAlertController *wa = a;
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Registra" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *t = [wa.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (t.length) [me logQuick:kind text:t tag:nil key:[title stringByAppendingString:@"…"]];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)openDebrief {
    _debrief = [[CtlDebriefView alloc] initWithModel:_m];
    _debrief.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:_debrief animated:YES completion:nil];
}

- (void)scenario:(NSDictionary *)body flash:(NSString *)text {
    CtlViewController *me = self;
    [_m scenarioAction:body done:^(BOOL ok, NSString *e, NSDictionary *r) {
        CtlViewController *s = me; if (!s) return;
        if (ok) { [s->_pending removeAllObjects]; s->_pendingRhythm = nil; [s flash:text]; }
        s->_leftSig = nil; [s refresh];
    }];
}
- (void)endScenario {
    if (CACurrentMediaTime() < _endArmed) { _endArmed = 0; _open = -1; [self scenario:@{@"action": @"stop"} flash:@"Scenario terminato: il paziente resta com'è"]; return; }
    _endArmed = CACurrentMediaTime() + 4; _leftSig = nil; [self refresh];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ self->_leftSig = nil; [self refresh]; });
}

- (void)activateState:(NSInteger)idx {
    NSDictionary *st = [self allStates][idx];
    NSDictionary *p = st[@"p"] ?: @{};
    if (p.count || st[@"r"]) {
        NSMutableDictionary *v = [@{@"params": p, @"duration_s": st[@"d"] ?: @0} mutableCopy];
        if (st[@"r"]) v[@"rhythm"] = st[@"r"];
        [_m command:@"transition" value:v];
    }
    NSDictionary *now = st[@"now"];
    if (now[@"crt_s"]) [_m command:@"set_crt" value:now[@"crt_s"]];
    if (now[@"temperature_c"]) [_m command:@"set_temperature" value:now[@"temperature_c"]];
    [_m logAdd:@"phase" text:[NSString stringWithFormat:@"Stato «%@» attivato · %@", st[@"n"], Dur([st[@"d"] integerValue])] tag:nil];
    _lastState = [st[@"n"] copy]; _open = -1; [_pending removeAllObjects]; _pendingRhythm = nil;
    [self flash:[NSString stringWithFormat:@"Stato «%@» attivato · %@", st[@"n"], Dur([st[@"d"] integerValue])]];
    _leftSig = nil; [self refresh];
}
- (void)deleteState:(NSInteger)idx {
    NSInteger i = idx - (NSInteger)PresetStates().count;
    if (i < 0 || i >= (NSInteger)_custom.count) return;
    [_custom removeObjectAtIndex:i]; [[NSUserDefaults standardUserDefaults] setObject:_custom forKey:@"sf_states"];
    _open = -1; _leftSig = nil; [self refresh];
}
- (NSDictionary *)currentBlock {
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    for (NSString *k in @[@"heart_rate_bpm", @"systolic_mmhg", @"diastolic_mmhg", @"spo2_percent", @"respiratory_rate_rpm", @"etco2_mmhg"]) { id v = [self valueFor:k]; if (v) p[k] = v; }
    NSMutableDictionary *b = [@{@"params": p} mutableCopy];
    if ([_m.state[@"rhythm"] isKindOfClass:[NSString class]]) b[@"rhythm"] = _m.state[@"rhythm"];
    if ([self valueFor:@"temperature_c"]) b[@"temperature_c"] = [self valueFor:@"temperature_c"];
    if ([self valueFor:@"crt_s"]) b[@"crt_s"] = [self valueFor:@"crt_s"];
    return b;
}
- (void)saveState {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Salva lo stato attuale"
        message:@"I valori veri del paziente in questo momento diventano uno stato richiamabile con un tocco." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"Nome dello stato"; tf.autocapitalizationType = UITextAutocapitalizationTypeSentences; }];
    CtlViewController *me = self; __weak UIAlertController *wa = a;
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Salva" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        CtlViewController *s = me; if (!s) return;
        NSString *n = [wa.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!n.length) n = [NSString stringWithFormat:@"Stato %lu", (unsigned long)s->_custom.count + 1];
        NSDictionary *b = [s currentBlock];
        NSMutableDictionary *now = [NSMutableDictionary dictionary];
        if (b[@"crt_s"]) now[@"crt_s"] = b[@"crt_s"];
        if (b[@"temperature_c"]) now[@"temperature_c"] = b[@"temperature_c"];
        [s->_custom addObject:@{@"n": n, @"d": @30, @"r": b[@"rhythm"] ?: @"sinus", @"p": b[@"params"], @"now": now}];
        [[NSUserDefaults standardUserDefaults] setObject:s->_custom forKey:@"sf_states"];
        s->_leftSig = nil; [s refresh];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)editScenario:(NSDictionary *)sc {
    CtlScenarioEditor *ed = [[CtlScenarioEditor alloc] initWithScenario:sc currentBlock:[self currentBlock]];
    CtlViewController *me = self; __weak CtlScenarioEditor *wed = ed;
    ed.onSave = ^(NSDictionary *scenario) {
        [me->_m scenarioAction:@{@"action": @"save", @"scenario": scenario} done:^(BOOL ok, NSString *e, NSDictionary *r) {
            if (ok) { [wed dismissViewControllerAnimated:YES completion:nil]; me->_open = -1; me->_leftSig = nil; [me flash:@"Scenario salvato sul monitor"]; [me refresh]; }
            else [wed showError:e];
        }];
    };
    ed.onDelete = ^(NSString *sid) {
        [me->_m scenarioAction:@{@"action": @"delete", @"id": sid} done:^(BOOL ok, NSString *e, NSDictionary *r) {
            if (ok) { [wed dismissViewControllerAnimated:YES completion:nil]; me->_open = -1; me->_leftSig = nil; [me refresh]; }
            else [wed showError:e];
        }];
    };
    ed.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:ed animated:YES completion:nil];
}

#pragma mark - Verifica da Mac

static UIView *FindId(UIView *root, NSString *ident) {
    if ([root.accessibilityIdentifier isEqualToString:ident] && !root.hidden) return root;
    for (UIView *v in root.subviews) { if (v.hidden) continue; UIView *f = FindId(v, ident); if (f) return f; }
    return nil;
}
static void ListIds(UIView *root, NSMutableArray *out) {
    if (root.hidden) return;
    if (root.accessibilityIdentifier.length) [out addObject:root.accessibilityIdentifier];
    for (UIView *v in root.subviews) ListIds(v, out);
}

// Controllo dei testi a schermo: troncati (puntini), parole spezzate a metà, righe con una o due lettere sole.
static void AuditText(UIView *root, NSString *owner, NSMutableArray<NSString *> *out, NSInteger *count) {
    if (root.hidden || root.alpha < 0.05) return;
    if (root.accessibilityIdentifier.length) owner = root.accessibilityIdentifier;
    if ([root isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)root; NSString *t = l.text;
        if (t.length && l.bounds.size.width > 1 && l.tag != 4242) {      // 4242 = testo con più caratteri diversi (marchio): verificato a vista
            (*count)++;
            UIFont *f = l.font;
            if (l.adjustsFontSizeToFitWidth) f = [f fontWithSize:f.pointSize * (l.minimumScaleFactor > 0 ? l.minimumScaleFactor : 0.5)];   // può rimpicciolirsi fin qui
            NSTextStorage *ts = [[NSTextStorage alloc] initWithString:t attributes:@{NSFontAttributeName: f}];
            NSLayoutManager *lm = [NSLayoutManager new]; [ts addLayoutManager:lm];
            NSTextContainer *tc = [[NSTextContainer alloc] initWithSize:CGSizeMake(l.bounds.size.width + 0.5, CGFLOAT_MAX)]; tc.lineFragmentPadding = 0; [lm addTextContainer:tc];
            NSMutableArray<NSValue *> *lines = [NSMutableArray array];
            [lm enumerateLineFragmentsForGlyphRange:NSMakeRange(0, lm.numberOfGlyphs) usingBlock:^(CGRect r, CGRect used, NSTextContainer *c, NSRange gr, BOOL *stop) {
                [lines addObject:[NSValue valueWithRange:[lm characterRangeForGlyphRange:gr actualGlyphRange:NULL]]];
            }];
            CGFloat height = [lm usedRectForTextContainer:tc].size.height;
            NSString *problem = nil;
            NSInteger allowed = l.numberOfLines;
            if ((allowed > 0 && (NSInteger)lines.count > allowed) || height > l.bounds.size.height + 3) problem = @"TRONCATO";
            NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
            for (NSUInteger i = 0; !problem && i < lines.count; i++) {
                NSRange r = lines[i].rangeValue;
                NSString *line = [[t substringWithRange:r] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (lines.count > 1 && line.length > 0 && line.length <= 2 && [letters characterIsMember:[line characterAtIndex:0]]) problem = @"RIGA DI UNA-DUE LETTERE";
                if (i + 1 < lines.count && r.length && NSMaxRange(r) < t.length) {
                    unichar a = [t characterAtIndex:NSMaxRange(r) - 1], b = [t characterAtIndex:NSMaxRange(r)];
                    if ([letters characterIsMember:a] && [letters characterIsMember:b]) problem = @"PAROLA SPEZZATA";
                }
            }
            if (problem) [out addObject:[NSString stringWithFormat:@"%@ [%@] «%@» (%.0fx%.0f, %.1f pt)", problem, owner ?: @"?", [t stringByReplacingOccurrencesOfString:@"\n" withString:@" / "], l.bounds.size.width, l.bounds.size.height, l.font.pointSize]];
        }
    }
    for (UIView *v in root.subviews) AuditText(v, owner, out, count);
}

- (void)debug:(NSString *)host query:(NSDictionary<NSString *, NSString *> *)q {
    UIWindow *w = [UIApplication sharedApplication].delegate.window;      // anche con una schermata modale aperta
    UIView *root = self.presentedViewController ? self.presentedViewController.view : self.view;
    if ([host isEqualToString:@"shot"]) {
        UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 1.0);
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
    if ([host isEqualToString:@"fitlog"]) { extern BOOL CtlFitLog; CtlFitLog = YES; _edBuilt = nil; [self refresh]; [self.view layoutIfNeeded]; CtlFitLog = NO; return; }
    if ([host isEqualToString:@"logadd"]) { [self logQuick:q[@"k"] ?: @"note" text:q[@"t"] ?: @"prova" tag:q[@"tag"] key:q[@"t"] ?: @"prova"]; return; }
    if ([host isEqualToString:@"cmd"]) {        // comando qualsiasi al monitor: cmd?n=nome&v=<JSON del valore>
        id v = q[@"v"] ? [NSJSONSerialization JSONObjectWithData:[q[@"v"] dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingAllowFragments error:NULL] : nil;
        [_m command:q[@"n"] ?: @"" value:v]; return;
    }
    if ([host isEqualToString:@"forget"]) { [_m forgetMonitor]; return; }
    if ([host isEqualToString:@"list"]) { NSMutableArray *a = [NSMutableArray array]; ListIds(root, a); SFLog(@"ID visibili: %@", [a componentsJoinedByString:@" "]); return; }
    if ([host isEqualToString:@"layout"]) { [_m command:@"set_layout" value:q[@"v"] ?: @"generic_icu"]; return; }
    if ([host isEqualToString:@"pin"]) { [_m submitPin:q[@"v"] ?: @""]; return; }
    if ([host isEqualToString:@"dismiss"]) { [self.presentedViewController dismissViewControllerAnimated:NO completion:nil]; return; }
    UIView *v = q[@"id"] ? FindId(root, q[@"id"]) : nil;
    if (!v) { SFLog(@"debug %@: elemento \"%@\" non trovato", host, q[@"id"]); return; }
    // stesso controllo di un dito: l'elemento deve essere quello che riceve il tocco al suo centro
    CGPoint c = [v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), CGRectGetMidY(v.bounds)) toView:v.window];
    UIView *hit = [v.window hitTest:c withEvent:nil];
    BOOL reach = hit == v || [hit isDescendantOfView:v];
    SFLog(@"debug %@ %@ %@", host, q[@"id"], reach ? @"ok" : [NSString stringWithFormat:@"COPERTO da %@ (%@)", NSStringFromClass(hit.class), hit.accessibilityIdentifier]);
    if (!reach) return;
    if ([host isEqualToString:@"tap"] && [v isKindOfClass:[UIControl class]]) [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
    else if ([host isEqualToString:@"seg"] && [v isKindOfClass:[UISegmentedControl class]]) { ((UISegmentedControl *)v).selectedSegmentIndex = [q[@"i"] integerValue]; [(UIControl *)v sendActionsForControlEvents:UIControlEventValueChanged]; }
    else if ([host isEqualToString:@"sw"] && [v isKindOfClass:[UISwitch class]]) { [(UISwitch *)v setOn:[q[@"on"] boolValue] animated:YES]; [(UIControl *)v sendActionsForControlEvents:UIControlEventValueChanged]; }
    else if ([host isEqualToString:@"val"] && [v isKindOfClass:[CtlParamRow class]]) [(CtlParamRow *)v debugSet:[q[@"v"] doubleValue]];
    else if ([host isEqualToString:@"text"] && [v respondsToSelector:@selector(setText:)]) { [(UITextField *)v setText:q[@"v"] ?: @""]; if ([v isKindOfClass:[UIControl class]]) [(UIControl *)v sendActionsForControlEvents:UIControlEventEditingChanged]; }
}
@end
