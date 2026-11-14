#import "MonitorViewController.h"
#import "AltLayout.h"
#import <QuartzCore/QuartzCore.h>
#import "SimulationState.h"
#import "WaveformEngine.h"
#import "TraceView.h"
#import "AlarmManager.h"
#import "SoundEngine.h"
#import "NetworkInfo.h"
#import "SFBolt.h"
#import <AVFoundation/AVFoundation.h>
#import "SFLog.h"
#import "SFConnectPanel.h"
#import "SFSplashView.h"
#import "SFWifi.h"
#import "DefibDrawerView.h"
#import "ExtraHView.h"
#import "GenericAedView.h"

// Palette clinica (sfondo nero, colori per parametro)
#define SL_GREEN  [UIColor colorWithRed:0.20 green:1.00 blue:0.35 alpha:1]
#define SL_CYAN   [UIColor colorWithRed:0.20 green:0.90 blue:1.00 alpha:1]
#define SL_YELLOW [UIColor colorWithRed:1.00 green:0.88 blue:0.20 alpha:1]
#define SL_NIBP   [UIColor colorWithRed:0.94 green:0.33 blue:0.48 alpha:1]   // rosso-lampone (diverso dall'ART)
#define SL_RED    [UIColor colorWithRed:1.00 green:0.23 blue:0.19 alpha:1]   // rosso arterioso
#define SL_WHITE  [UIColor colorWithWhite:0.92 alpha:1]
#define SL_GREY   [UIColor colorWithWhite:0.45 alpha:1]
#define SL_AMBER  [UIColor colorWithRed:1.00 green:0.62 blue:0.10 alpha:1]
#define SL_ALARM  [UIColor colorWithRed:0.95 green:0.15 blue:0.15 alpha:1]
#define SL_LINE   [UIColor colorWithWhite:0.18 alpha:1]
#define SL_TEMP   [UIColor colorWithRed:0.80 green:0.62 blue:1.00 alpha:1]   // lilla (temperatura)

@implementation MonitorViewController {
    SimulationState *_state;
    WaveformEngine *_engine;
    SoundEngine *_sound;
    CADisplayLink *_link;
    NSUInteger _lastRevision;
    SLSnapshot *_snap;

    TraceView *_ecg2, *_ecgV, *_pleth, *_art, *_capno;
    UILabel *_hrValue, *_hrHeart, *_hrLimits, *_spo2Value, *_spo2Limits, *_prValue;
    UILabel *_artValue, *_artMap, *_artLimits, *_etco2Value, *_etco2Limits, *_rrValue, *_rrLabel, *_rrLimits;
    UILabel *_nibpValue, *_nibpMap, *_nibpStatus, *_nibpLimits;
    UILabel *_banner, *_clock, *_netLabel, *_titleLabel;
    UIButton *_muteButton, *_nibpButton, *_infoButton;
    UIView *_infoPanel; SFConnectPanel *_connect;      // _infoPanel = _connect (pannello Collegamento)

    NSTimeInterval _lastSlowTick, _lastNetCheck, _infoShownAt;
    NSTimeInterval _lastBeepBeat;
    SLNibpPhase _lastNibpPhase; NSInteger _lastNibpStep;
    NSString *_ip;
    BOOL _flashOn;
    int _tick;
    SLAlarmResult *_alarmResult;
    NSDateFormatter *_clockFmt, *_nibpFmt;
    double _frameCostAvg;
    NSInteger _frameInterval;
    NSMutableDictionary<NSString *, UIView *> *_alarmBoxes;   // celle dei parametri che lampeggiano in allarme
    NSMutableDictionary<NSString *, NSValue *> *_cellRects;    // area di ogni cella numerica (GENERIC ICU)
    NSMutableDictionary<NSString *, NSArray *> *_cellLabels;   // etichette contenute in ogni cella, con il colore normale
    UIButton *_altFooter; UILabel *_altFooterText;
    UIView *_volPanel;                                       // pannello dei volumi per canale
    NSTimeInterval _volAlarmPreviewUntil;
    UIView *_battBody, *_battFill; UILabel *_battPct; CAShapeLayer *_battBolt;   // batteria dell'iPad nella barra inferiore            // piè di pagina dei layout dei dispositivi: indirizzo + (i)
    // menu parametro (tocco sul valore)
    UIView *_menuDim, *_menuPanel;
    NSString *_menuParam;
    NSMutableDictionary<NSString *, UIStepper *> *_menuSteppers;
    NSMutableDictionary<NSString *, UILabel *> *_menuValues;
    UISwitch *_menuSwitch; UILabel *_menuSwitchText, *_menuError;
    UISegmentedControl *_menuInterval;
    // variabilità fisiologica dei numeri mostrati (deriva lenta, aggiornata ogni ~2 s)
    double _jHR, _jSpO2, _jSys, _jDia; NSTimeInterval _lastJitter;
    NSTimeInterval _lowPerfSince;      // inizio della bassa perfusione (ciclo del "?" SpO2)
    // NIBP automatica
    UILabel *_nibpAutoLabel; UIView *_nibpBarTrack, *_nibpBarFill;
    // temperatura e refill capillare
    UILabel *_tempValue, *_crtValue;
    NSInteger _crtShown; NSTimeInterval _crtAssessAt; NSInteger _crtSeqSeen;   // refill: valore "valutato" e inizio della valutazione
    UILabel *_crtTitle; UIView *_crtLine; UIButton *_crtHit;
    // layout del monitor
    UIView<SFAltLayout> *_alt; NSString *_layoutShown; UIView *_layoutMenu;   // _alt = layout alternativo attivo
    NSString *_altKind;
    UIView *_pauseCover;                                       // "Scenario in PAUSA" a tutto schermo
    NSMutableArray<UIView *> *_icuHidden;                     // viste ICU nascoste sotto un layout di dispositivo
    UIView *_standby; BOOL _powerPushed;                       // GENERIC ICU in standby + ultimo stato di accensione inviato al layout attivo
    // cassetto del defibrillatore
    DefibDrawerView *_drawer; UIButton *_drawerTab; BOOL _drawerOpen; CGFloat _drawerY;
}

// Configurazione del menu di ciascun parametro: titolo, colore, limiti (chiave, etichetta, passo, min, max)
static NSDictionary *SFMenuConfig(void) {
    return @{
      @"hr":    @{@"title": @"FC", @"limits": @[@[@"hr_high", @"Limite alto", @5, @20, @300], @[@"hr_low", @"Limite basso", @5, @15, @250]]},
      @"spo2":  @{@"title": @"SpO₂", @"limits": @[@[@"spo2_low", @"Limite basso", @1, @50, @99]]},
      @"art":   @{@"title": @"ART (sistolica)", @"limits": @[@[@"sys_high", @"Limite alto", @5, @50, @300], @[@"sys_low", @"Limite basso", @5, @30, @250]]},
      @"nibp":  @{@"title": @"NIBP (sistolica)", @"limits": @[@[@"sys_high", @"Limite alto", @5, @50, @300], @[@"sys_low", @"Limite basso", @5, @30, @250]]},
      @"etco2": @{@"title": @"EtCO₂", @"limits": @[@[@"etco2_high", @"Limite alto", @1, @10, @150], @[@"etco2_low", @"Limite basso", @1, @1, @90]]},
      @"rr":    @{@"title": @"FR", @"limits": @[@[@"rr_high", @"Limite alto", @1, @5, @60], @[@"rr_low", @"Limite basso", @1, @1, @50]]},
    };
}

- (instancetype)initWithState:(SimulationState *)state {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _state = state;
        _engine = [[WaveformEngine alloc] initWithSeed:(unsigned int)time(NULL)];
        _sound = [SoundEngine new];
        _clockFmt = [NSDateFormatter new]; _clockFmt.dateFormat = @"HH:mm:ss";
        _nibpFmt = [NSDateFormatter new]; _nibpFmt.dateFormat = @"HH:mm";
        _serverPort = 8080;
        _frameInterval = 2;   // 60/2 = 30 fps
        _lastNibpStep = -1;
        _crtShown = -1;
    }
    return self;
}

#pragma mark - Orientamento / schermo intero

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

#pragma mark - Costruzione UI

- (UILabel *)label:(CGRect)f size:(CGFloat)size bold:(BOOL)bold color:(UIColor *)c align:(NSTextAlignment)a {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = c;
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.textAlignment = a;
    l.adjustsFontSizeToFitWidth = YES;
    l.minimumScaleFactor = 0.5;
    [self.view addSubview:l];
    return l;
}

- (UILabel *)limits:(CGRect)f color:(UIColor *)c {
    UILabel *l = [self label:f size:12 bold:NO color:c align:NSTextAlignmentRight];
    l.numberOfLines = 2; l.alpha = 0.8;
    return l;
}

- (void)line:(CGRect)f {
    UIView *v = [[UIView alloc] initWithFrame:f];
    v.backgroundColor = SL_LINE;
    [self.view addSubview:v];
}

- (UIButton *)button:(NSString *)title frame:(CGRect)f color:(UIColor *)c action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:c forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.layer.borderColor = c.CGColor; b.layer.borderWidth = 1.5; b.layer.cornerRadius = 6;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];
    return b;
}

- (TraceView *)trace:(CGRect)f color:(UIColor *)c label:(NSString *)label min:(double)mn max:(double)mx speed:(double)sp
             sampler:(double (^)(NSTimeInterval))sampler {
    TraceView *t = [[TraceView alloc] initWithFrame:f];
    t.traceColor = c; t.label = label; t.minValue = mn; t.maxValue = mx; t.sweepSpeed = sp; t.sampler = sampler;
    [self.view addSubview:t];
    return t;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (_ecg2) return;          // layout fisso landscape, costruito una volta
    [self buildUI];
}

- (void)buildUI {
    CGFloat W = MAX(self.view.bounds.size.width, self.view.bounds.size.height);   // 1024
    CGFloat H = MIN(self.view.bounds.size.width, self.view.bounds.size.height);   // 768
    CGFloat top = 56, bottom = H - 34;               // intestazione più alta: SILENZIA e DEFIB a portata di mano
    CGFloat traceW = round(W * 0.684);                // ~700
    CGFloat numX = traceW + 4, numW = W - numX - 6;
    // righe: ECG II, ECG V, Pleth, ART, CO2, NIBP
    CGFloat yII = top, hII = 118, yV = yII + hII, hV = 100, yPl = yV + hV, hPl = 104;
    CGFloat yArt = yPl + hPl, hArt = 118, yCO2 = yArt + hArt, hCO2 = 98;
    CGFloat yNibp = yCO2 + hCO2, hNibp = bottom - yNibp;

    // --- barra superiore ---
    _titleLabel = [self label:CGRectMake(10, 6, 200, 44) size:15 bold:YES color:SL_GREY align:NSTextAlignmentLeft];
    _titleLabel.numberOfLines = 2;
    _titleLabel.text = [NSString stringWithFormat:@"similFranz Monitor %@\nICU  ·  %@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"", _state.deviceId];
    _banner = [self label:CGRectMake(214, 6, 426, 44) size:21 bold:YES color:[UIColor blackColor] align:NSTextAlignmentCenter];
    _banner.layer.cornerRadius = 6; _banner.hidden = YES;   // sfondo sul layer: arrotondato senza ritaglio
    _muteButton = [self button:@"SILENZIA" frame:CGRectMake(648, 6, 150, 44) color:SL_AMBER action:@selector(toggleMute)];
    _drawerTab = [self button:@"DEFIB  ▲" frame:CGRectMake(806, 6, 132, 44) color:[UIColor colorWithRed:1.00 green:0.45 blue:0.05 alpha:1]
                       action:@selector(toggleDrawer)];
    _clock = [self label:CGRectMake(W - 82, 6, 76, 44) size:18 bold:NO color:SL_WHITE align:NSTextAlignmentRight];
    [self line:CGRectMake(0, top - 1, W, 1)];

    // --- tracciati ---
    __weak WaveformEngine *eng = _engine;
    _ecg2  = [self trace:CGRectMake(0, yII, traceW, hII) color:SL_GREEN label:@"II" min:-0.7 max:1.5 speed:160
                 sampler:^double(NSTimeInterval t) { return [eng ecgAt:t lead:SLLeadII]; }];
    _ecgV  = [self trace:CGRectMake(0, yV, traceW, hV) color:SL_GREEN label:@"V5" min:-0.6 max:1.9 speed:160
                 sampler:^double(NSTimeInterval t) { return [eng ecgAt:t lead:SLLeadV]; }];
    NSInteger (^spikes)(NSTimeInterval, NSTimeInterval) = ^NSInteger(NSTimeInterval t0, NSTimeInterval t1) {
        return [eng markersFrom:t0 to:t1 sync:NO];
    };
    _ecg2.markerSampler = spikes; _ecgV.markerSampler = spikes;
    _pleth = [self trace:CGRectMake(0, yPl, traceW, hPl) color:SL_CYAN label:@"Pleth" min:-0.05 max:1.05 speed:160
                 sampler:^double(NSTimeInterval t) { return [eng plethAt:t]; }];
    _pleth.autoScale = 1; _pleth.minSpan = 0.15;           // la curva si riadatta all'ampiezza del polso
    _art   = [self trace:CGRectMake(0, yArt, traceW, hArt) color:SL_RED label:@"ART  mmHg" min:0 max:160 speed:160
                 sampler:^double(NSTimeInterval t) { return [eng artAt:t]; }];
    _art.autoScale = 3; _art.showScaleLabels = YES;         // scala "ottimale" attorno alla pressione, come in TI
    _capno = [self trace:CGRectMake(0, yCO2, traceW, hCO2) color:SL_WHITE label:@"CO2  mmHg" min:-2 max:60 speed:40
                 sampler:^double(NSTimeInterval t) { return [eng capnoAt:t]; }];
    _capno.filled = YES;                                     // capnogramma pieno (area sotto la curva)
    [self line:CGRectMake(0, yV, traceW, 1)];      // tra II e V: solo sui tracciati (il valore FC occupa entrambe le righe)
    for (NSNumber *y in @[@(yPl), @(yArt), @(yCO2), @(yNibp)]) [self line:CGRectMake(0, y.doubleValue, W, 1)];
    [self line:CGRectMake(traceW + 1, top, 1, yNibp - top)];

    // --- numerici: FC (sulle due derivazioni ECG) ---
    CGFloat limW = 52;
    [self label:CGRectMake(numX + 6, yII + 4, 120, 20) size:15 bold:YES color:SL_GREEN align:NSTextAlignmentLeft].text = @"FC  bpm";
    _hrHeart = [self label:CGRectMake(numX + 110, yII + 2, 30, 26) size:22 bold:YES color:SL_GREEN align:NSTextAlignmentLeft];
    _hrHeart.text = @""; _hrHeart.alpha = 0.15;
    CAShapeLayer *hl = [CAShapeLayer layer];                   // cuore disegnato, verde come il numero (niente emoji)
    UIBezierPath *hp = [UIBezierPath bezierPath];
    CGFloat hw = 20, hx = 4, hy = 5;
    [hp moveToPoint:CGPointMake(hx + hw / 2, hy + hw * 0.9)];
    [hp addCurveToPoint:CGPointMake(hx, hy + hw * 0.3) controlPoint1:CGPointMake(hx + hw * 0.2, hy + hw * 0.7) controlPoint2:CGPointMake(hx, hy + hw * 0.5)];
    [hp addArcWithCenter:CGPointMake(hx + hw * 0.25, hy + hw * 0.27) radius:hw * 0.25 startAngle:M_PI endAngle:0 clockwise:YES];
    [hp addArcWithCenter:CGPointMake(hx + hw * 0.75, hy + hw * 0.27) radius:hw * 0.25 startAngle:M_PI endAngle:0 clockwise:YES];
    [hp addCurveToPoint:CGPointMake(hx + hw / 2, hy + hw * 0.9) controlPoint1:CGPointMake(hx + hw, hy + hw * 0.5) controlPoint2:CGPointMake(hx + hw * 0.8, hy + hw * 0.7)];
    [hp closePath];
    hl.path = hp.CGPath; hl.fillColor = SL_GREEN.CGColor;
    [_hrHeart.layer addSublayer:hl];
    _hrLimits = [self limits:CGRectMake(numX + numW - limW - 4, yII + 6, limW, 34) color:SL_GREEN];
    _hrValue = [self label:CGRectMake(numX, yII + 30, numW, hII + hV - 40) size:130 bold:YES color:SL_GREEN align:NSTextAlignmentCenter];

    // SpO2 + PR
    [self label:CGRectMake(numX + 6, yPl + 4, 120, 20) size:15 bold:YES color:SL_CYAN align:NSTextAlignmentLeft].text = @"SpO2  %";
    _spo2Limits = [self limits:CGRectMake(numX + numW * 0.66 - limW - 6, yPl + 6, limW, 18) color:SL_CYAN];
    _spo2Value = [self label:CGRectMake(numX, yPl + 20, numW * 0.66, hPl - 24) size:76 bold:YES color:SL_CYAN align:NSTextAlignmentCenter];
    [self label:CGRectMake(numX + numW * 0.66, yPl + 22, numW * 0.34, 18) size:13 bold:YES color:SL_CYAN align:NSTextAlignmentCenter].text = @"FC  bpm";
    _prValue = [self label:CGRectMake(numX + numW * 0.66, yPl + 40, numW * 0.34, 50) size:36 bold:YES color:SL_CYAN align:NSTextAlignmentCenter];

    // ART
    [self label:CGRectMake(numX + 6, yArt + 4, 120, 20) size:15 bold:YES color:SL_RED align:NSTextAlignmentLeft].text = @"ART  mmHg";
    _artLimits = [self limits:CGRectMake(numX + numW - limW - 4, yArt + 6, limW, 34) color:SL_RED];
    _artValue = [self label:CGRectMake(numX + 4, yArt + 26, numW * 0.72, hArt - 34) size:56 bold:YES color:SL_RED align:NSTextAlignmentCenter];
    _artMap = [self label:CGRectMake(numX + numW * 0.72, yArt + 50, numW * 0.28, 44) size:30 bold:YES color:SL_RED align:NSTextAlignmentCenter];

    // EtCO2 + FR
    [self label:CGRectMake(numX + 6, yCO2 + 4, 130, 20) size:15 bold:YES color:SL_WHITE align:NSTextAlignmentLeft].text = @"EtCO2  mmHg";
    _etco2Limits = [self limits:CGRectMake(numX + numW * 0.55 - limW - 4, yCO2 + 6, limW, 34) color:SL_WHITE];
    _etco2Value = [self label:CGRectMake(numX, yCO2 + 24, numW * 0.55, hCO2 - 28) size:60 bold:YES color:SL_WHITE align:NSTextAlignmentCenter];
    _rrLabel = [self label:CGRectMake(numX + numW * 0.57, yCO2 + 4, 90, 20) size:15 bold:YES color:SL_WHITE align:NSTextAlignmentLeft];
    _rrLimits = [self limits:CGRectMake(numX + numW - limW - 4, yCO2 + 6, limW, 34) color:SL_WHITE];
    _rrValue = [self label:CGRectMake(numX + numW * 0.55, yCO2 + 24, numW * 0.45, hCO2 - 28) size:48 bold:YES color:SL_WHITE align:NSTextAlignmentCenter];

    // celle numeriche: in allarme lampeggia l'intera cella (sfondo), non solo il numero
    _cellRects = [@{ @"hr": [NSValue valueWithCGRect:CGRectMake(numX - 1, yII + 1, numW + 6, hII + hV - 1)],
                     @"spo2": [NSValue valueWithCGRect:CGRectMake(numX - 1, yPl + 1, numW * 0.66 + 1, hPl - 1)],   // senza la FC del saturimetro
                     @"art": [NSValue valueWithCGRect:CGRectMake(numX - 1, yArt + 1, numW + 6, hArt - 1)],
                     @"etco2": [NSValue valueWithCGRect:CGRectMake(numX - 1, yCO2 + 1, numW * 0.56, hCO2 - 1)],
                     @"rr": [NSValue valueWithCGRect:CGRectMake(numX + numW * 0.56, yCO2 + 1, numW * 0.44 + 6, hCO2 - 1)],
                     @"nibp": [NSValue valueWithCGRect:CGRectMake(124, yNibp + 1, traceW - 124, hNibp - 1)] } mutableCopy];

    // --- NIBP + pulsanti ---
    // AVVIA NIBP a sinistra del valore; poi valore, PAM, stato del bracciale
    CGFloat nx = 128;
    [self label:CGRectMake(nx, yNibp + 6, 200, 20) size:15 bold:YES color:SL_NIBP align:NSTextAlignmentLeft].text = @"NIBP  mmHg";
    _nibpLimits = [self limits:CGRectMake(nx + 200, yNibp + 6, limW, 34) color:SL_NIBP];
    _nibpValue = [self label:CGRectMake(nx, yNibp + 24, 255, hNibp - 30) size:66 bold:YES color:SL_NIBP align:NSTextAlignmentLeft];
    _nibpMap = [self label:CGRectMake(nx + 258, yNibp + 34, 96, 46) size:32 bold:YES color:SL_NIBP align:NSTextAlignmentLeft];
    CGFloat sx = nx + 358, sw = traceW - sx - 8;
    _nibpStatus = [self label:CGRectMake(sx, yNibp + 84, sw, 24) size:16 bold:NO color:SL_NIBP align:NSTextAlignmentLeft];

    // NIBP automatica: etichetta + barra che si accorcia fino alla prossima misura
    _nibpAutoLabel = [self label:CGRectMake(sx, yNibp + 8, sw, 20) size:14 bold:YES color:SL_NIBP align:NSTextAlignmentLeft];
    _nibpAutoLabel.numberOfLines = 2; _nibpAutoLabel.frame = CGRectMake(sx, yNibp + 6, sw, 40);
    _nibpBarTrack = [[UIView alloc] initWithFrame:CGRectMake(sx, yNibp + hNibp - 12, sw, 5)];
    _nibpBarTrack.backgroundColor = [SL_NIBP colorWithAlphaComponent:0.2]; _nibpBarTrack.hidden = YES;
    _nibpBarFill = [[UIView alloc] initWithFrame:_nibpBarTrack.bounds];
    _nibpBarFill.backgroundColor = SL_NIBP;
    [_nibpBarTrack addSubview:_nibpBarFill]; [self.view addSubview:_nibpBarTrack];

    // aree toccabili sui valori: aprono il menu del parametro
    NSDictionary *hits = @{ @"hr": [NSValue valueWithCGRect:CGRectMake(numX, yII, numW, hII + hV)],
                            @"spo2": [NSValue valueWithCGRect:CGRectMake(numX, yPl, numW, hPl)],
                            @"art": [NSValue valueWithCGRect:CGRectMake(numX, yArt, numW, hArt)],
                            @"etco2": [NSValue valueWithCGRect:CGRectMake(numX, yCO2, numW * 0.55, hCO2)],
                            @"rr": [NSValue valueWithCGRect:CGRectMake(numX + numW * 0.55, yCO2, numW * 0.45, hCO2)],
                            @"nibp": [NSValue valueWithCGRect:CGRectMake(nx, yNibp, sx - nx, hNibp)] };   // solo valore + PAM
    NSArray *order = @[@"hr", @"spo2", @"art", @"etco2", @"rr", @"nibp"];
    for (NSUInteger i = 0; i < order.count; i++) {
        UIButton *hb = [UIButton buttonWithType:UIButtonTypeCustom];
        hb.frame = [hits[order[i]] CGRectValue]; hb.tag = (NSInteger)i;
        [hb addTarget:self action:@selector(hitParam:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:hb];
    }

    // tocco sulle tracce = collegare il sensore al paziente (solo collegare: un nuovo tocco non scollega)
    NSArray *traceHits = @[ @[_ecg2, @"ecg"], @[_ecgV, @"ecg"], @[_pleth, @"spo2"], @[_art, @"art"], @[_capno, @"etco2"] ];
    for (NSArray *th in traceHits) {
        UIButton *tb = [UIButton buttonWithType:UIButtonTypeCustom];
        tb.frame = [th[0] frame];
        tb.accessibilityIdentifier = th[1];
        [tb addTarget:self action:@selector(connectSensor:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:tb];
    }
    // bracciale: si mette toccando la colonna delle scritte di stato della NIBP (non apre mai il menu allarmi)
    UIButton *cuff = [UIButton buttonWithType:UIButtonTypeCustom];
    cuff.frame = CGRectMake(sx - 4, yNibp, sw + 8, hNibp);
    cuff.accessibilityIdentifier = @"nibp";
    [cuff addTarget:self action:@selector(connectSensor:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:cuff];

    // temperatura e refill capillare (sopra i pulsanti)
    [self label:CGRectMake(numX + 6, yNibp + 6, 130, 18) size:15 bold:YES color:SL_TEMP align:NSTextAlignmentLeft].text = @"TEMP  °C";
    _tempValue = [self label:CGRectMake(numX, yNibp + 28, numW * 0.5, hNibp - 36) size:56 bold:YES color:SL_TEMP align:NSTextAlignmentCenter];
    _crtTitle = [self label:CGRectMake(numX + numW * 0.5 + 6, yNibp + 6, 140, 18) size:15 bold:YES color:SL_WHITE align:NSTextAlignmentLeft];
    _crtTitle.text = @"REFILL  s";
    _crtValue = [self label:CGRectMake(numX + numW * 0.5, yNibp + 28, numW * 0.5, hNibp - 36) size:56 bold:YES color:SL_WHITE align:NSTextAlignmentCenter];
    _crtLine = [[UIView alloc] initWithFrame:CGRectMake(numX + numW * 0.5, yNibp + 8, 1, hNibp - 16)];
    _crtLine.backgroundColor = SL_LINE; [self.view addSubview:_crtLine];
    // refill: è un esame clinico, non una misura del monitor -> si vede solo dopo averlo "eseguito" (tocco sul valore)
    UIButton *crtHit = [UIButton buttonWithType:UIButtonTypeCustom];
    crtHit.frame = CGRectMake(numX + numW * 0.5, yNibp, numW * 0.5, hNibp);
    [crtHit addTarget:self action:@selector(assessCrt) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:crtHit]; _crtHit = crtHit;
    // titolo in alto a sinistra: menu dei layout del monitor
    UIButton *titleHit = [UIButton buttonWithType:UIButtonTypeCustom];
    titleHit.frame = CGRectMake(0, 0, 210, top - 2);
    [titleHit addTarget:self action:@selector(showLayoutMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:titleHit];
    UIButton *tempHit = [UIButton buttonWithType:UIButtonTypeCustom];      // sonda: si collega toccando il valore
    tempHit.frame = CGRectMake(numX, yNibp, numW * 0.5, hNibp); tempHit.accessibilityIdentifier = @"temp";
    [tempHit addTarget:self action:@selector(connectSensor:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:tempHit];
    _nibpButton = [self button:@"AVVIA\nNIBP" frame:CGRectMake(8, yNibp + 14, nx - 18, hNibp - 26) color:SL_NIBP action:@selector(startNibp)];
    _nibpButton.titleLabel.numberOfLines = 2; _nibpButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    _nibpButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];

    // --- barra inferiore ---
    [self line:CGRectMake(0, bottom, W, 1)];
    UILabel *sim = [self label:CGRectMake(10, bottom + 5, 420, 24) size:16 bold:YES color:SL_AMBER align:NSTextAlignmentLeft];
    sim.text = @"SIMULAZIONE — NON PER USO CLINICO";
    // batteria (vera, dell'iPad): icona che si riempie col livello, percentuale, fulmine se in carica
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    CGFloat bx = 470, by = bottom + 9;
    _battBody = [[UIView alloc] initWithFrame:CGRectMake(bx, by, 38, 17)];
    _battBody.layer.borderWidth = 1.5; _battBody.layer.borderColor = SL_GREY.CGColor; _battBody.layer.cornerRadius = 3;
    [self.view addSubview:_battBody];
    UIView *nub = [[UIView alloc] initWithFrame:CGRectMake(bx + 38, by + 5, 3, 7)]; nub.backgroundColor = SL_GREY; [self.view addSubview:nub];
    _battFill = [[UIView alloc] initWithFrame:CGRectMake(2.5, 2.5, 33, 12)]; _battFill.layer.cornerRadius = 1.5;
    [_battBody addSubview:_battFill];
    _battBolt = [CAShapeLayer layer];
    _battBolt.path = SFBoltPath(CGRectMake(0, 0, 14, 20)).CGPath; _battBolt.frame = CGRectMake(bx + 46, by - 2, 14, 20);
    _battBolt.fillColor = SL_YELLOW.CGColor; _battBolt.hidden = YES;
    [self.view.layer addSublayer:_battBolt];
    _battPct = [self label:CGRectMake(bx + 64, bottom + 5, 70, 24) size:16 bold:YES color:SL_WHITE align:NSTextAlignmentLeft];
    _netLabel = [self label:CGRectMake(W - 380, bottom + 6, 330, 22) size:13 bold:NO color:SL_GREY align:NSTextAlignmentRight];
    _infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
    _infoButton.tintColor = SL_GREY;
    _infoButton.frame = CGRectMake(W - 44, bottom + 1, 40, 32);
    [_infoButton addTarget:self action:@selector(toggleInfo) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_infoButton];
    // piè di pagina dei layout dei dispositivi (in basso a sinistra, zona libera in tutti i modelli): indirizzo + (i)
    _altFooter = [UIButton buttonWithType:UIButtonTypeCustom];
    _altFooter.frame = CGRectMake(4, H - 46, 116, 42);
    _altFooter.layer.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.11 alpha:0.88].CGColor;
    _altFooter.layer.cornerRadius = 8; _altFooter.layer.borderWidth = 1; _altFooter.layer.borderColor = [UIColor colorWithWhite:0.45 alpha:1].CGColor;
    _altFooter.accessibilityIdentifier = @"FOOTER-INFO"; _altFooter.hidden = YES;
    [_altFooter addTarget:self action:@selector(toggleInfo) forControlEvents:UIControlEventTouchUpInside];
    UIButton *fi = [UIButton buttonWithType:UIButtonTypeInfoLight];
    fi.tintColor = [UIColor colorWithWhite:0.85 alpha:1]; fi.userInteractionEnabled = NO;
    fi.frame = CGRectMake(2, 9, 24, 24);
    [_altFooter addSubview:fi];
    _altFooterText = [[UILabel alloc] initWithFrame:CGRectMake(27, 3, 86, 36)];
    _altFooterText.numberOfLines = 2; _altFooterText.font = [UIFont boldSystemFontOfSize:10.5];
    _altFooterText.textColor = [UIColor colorWithWhite:0.92 alpha:1]; _altFooterText.adjustsFontSizeToFitWidth = YES; _altFooterText.minimumScaleFactor = 0.6;
    _altFooterText.userInteractionEnabled = NO;
    [_altFooter addSubview:_altFooterText];
    [self.view addSubview:_altFooter];

    // pannello "Collegamento del controller" (tasto (i) di ogni layout): rete Wi-Fi / diretto, PIN, reti, volumi
    _connect = [[SFConnectPanel alloc] initWithFrame:CGRectMake(0, 0, W, H)];
    _infoPanel = _connect;
    _infoPanel.hidden = YES;
    __weak MonitorViewController *weakPanel = self;
    _connect.info = ^NSDictionary *{ return [weakPanel connectInfo]; };
    _connect.onClose = ^{ MonitorViewController *m = weakPanel; if (m) m->_infoPanel.hidden = YES; };
    _connect.onVolumes = ^{ [weakPanel showVolumes]; };
    [self.view addSubview:_infoPanel];

    // cassetto del defibrillatore: pulsante DEFIB nell'intestazione, si apre sopra Pleth/ART/CO2/NIBP
    _drawerTab.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    _muteButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    _drawerY = yPl;
    _drawer = [[DefibDrawerView alloc] initWithFrame:CGRectMake(0, H, W, bottom - yPl) state:_state engine:_engine sound:_sound];
    _drawer.hidden = YES;
    __weak MonitorViewController *weakSelf = self;
    _drawer.onClose = ^{ [weakSelf toggleDrawer]; };
    [self.view addSubview:_drawer];

    // i limiti di allarme stanno SOPRA i riquadri colorati dei valori in allarme
    for (UILabel *l in @[_hrLimits, _spo2Limits, _artLimits, _etco2Limits, _rrLimits, _nibpLimits]) [self.view bringSubviewToFront:l];
    [self.view bringSubviewToFront:_drawer];
    [self.view bringSubviewToFront:_drawerTab];
    [self.view bringSubviewToFront:_infoPanel];

    NSTimeInterval now = CACurrentMediaTime();
    for (TraceView *t in [self traces]) [t resetAtTime:now];
    _snap = [_state snapshot];
    [_engine updateWithSnapshot:_snap];
    _lastRevision = _snap.revision;
    [_drawer updateWithSnapshot:_snap];
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"sf_layout"];
    if (saved && ![saved isEqualToString:_snap.layout]) [_state applyCommand:@{@"command": @"set_layout", @"value": saved} error:NULL];
    _layoutShown = @"generic_icu";

    // All'avvio dello scenario il monitor è SPENTO: GENERIC ICU mostra lo standby,
    // un tocco accende il monitoraggio. Lo stato di accensione è condiviso tra i layout.
    _standby = [[UIView alloc] initWithFrame:self.view.bounds];
    _standby.backgroundColor = [UIColor blackColor];
    UIButton *sbHit = [UIButton buttonWithType:UIButtonTypeCustom];
    sbHit.frame = _standby.bounds; sbHit.accessibilityIdentifier = @"STANDBY";
    [sbHit addTarget:self action:@selector(standbyTapped) forControlEvents:UIControlEventTouchUpInside];
    [_standby addSubview:sbHit];
    UILabel *sbT = [[UILabel alloc] initWithFrame:CGRectMake(0, H / 2 - 76, W, 64)];
    sbT.text = @"Standby"; sbT.font = [UIFont boldSystemFontOfSize:54];
    sbT.textColor = [UIColor colorWithWhite:0.85 alpha:1]; sbT.textAlignment = NSTextAlignmentCenter;
    sbT.userInteractionEnabled = NO; [_standby addSubview:sbT];
    UILabel *sbS = [[UILabel alloc] initWithFrame:CGRectMake(0, H / 2 + 2, W, 30)];
    sbS.text = @"tocca per iniziare il monitoraggio"; sbS.font = [UIFont systemFontOfSize:21];
    sbS.textColor = [UIColor colorWithWhite:0.52 alpha:1]; sbS.textAlignment = NSTextAlignmentCenter;
    sbS.userInteractionEnabled = NO; [_standby addSubview:sbS];
    [_standby addSubview:SFLayoutButton(CGRectMake(8, 8, 150, 40), self, @selector(showLayoutMenu))];
    UIButton *sbInfo = [UIButton buttonWithType:UIButtonTypeInfoLight];
    sbInfo.tintColor = [UIColor colorWithWhite:0.6 alpha:1];
    sbInfo.frame = CGRectMake(10, H - 46, 36, 36);
    [sbInfo addTarget:self action:@selector(toggleInfo) forControlEvents:UIControlEventTouchUpInside];
    [_standby addSubview:sbInfo];
    _standby.hidden = _state.devicePowered;
    [self.view addSubview:_standby];
    [self.view bringSubviewToFront:_infoPanel];

    [self showSplash:NO];

    [self refreshNetwork];
    [self updateNumerics];
    [self slowTick:now];
}

- (NSArray<TraceView *> *)traces { return @[_ecg2, _ecgV, _pleth, _art, _capno]; }

#pragma mark - Ciclo di rendering

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startRendering];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopRendering];
}

- (void)startRendering {
    if (!_sound.running && ![_sound start]) SFLog(@"audio non disponibile: %@", _sound.lastError);
    if (_link) return;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
    _link.frameInterval = _frameInterval;      // API iOS 3.1+ (preferredFramesPerSecond è iOS 10)
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopRendering {
    [_link invalidate]; _link = nil;
    [_sound setPumpRunning:NO pressure:0];
    [_sound setAlarm:SFAlarmSoundNone];
}

- (void)frame:(CADisplayLink *)link {
    NSTimeInterval now = CACurrentMediaTime();
    [_state tickAtTime:now];
    SLSnapshot *s = [_state snapshot];
    _snap = s;
    if (s.revision != _lastRevision) {
        _lastRevision = s.revision;
        [_engine updateWithSnapshot:s];
        [self updateNumerics];
        [_drawer updateWithSnapshot:s];
        if (![s.layout isEqualToString:_layoutShown]) [self applyLayout:s.layout];
        if (_alt && !_alt.hidden) [_alt updateWithSnapshot:s];
    }
    [_drawer tick:now snapshot:s visible:_drawerOpen];
    BOOL lp = _alt && !_alt.hidden;
    if (lp && _state.devicePowered != _powerPushed) [_alt setDevicePowered:_state.devicePowered];   // reset o comando esterno
    _powerPushed = _state.devicePowered;
    if (_standby) _standby.hidden = lp || _state.devicePowered;
    if (lp) [_alt tick:now snapshot:s];
    if (lp) {
        if (![_alt poweredOff]) [self beatSoundsAt:now snapshot:s];   // le tracce GENERIC ICU sono nascoste: non si disegnano
    } else if (s.simulationRunning && _state.devicePowered) {
        for (TraceView *t in [self traces]) [t advanceTo:now];
        [self beatSoundsAt:now snapshot:s];
    } else {
        for (TraceView *t in [self traces]) [t resetAtTime:now];
    }
    [self nibpSoundsAt:now snapshot:s];
    if (now - _lastSlowTick >= 0.25) [self slowTick:now];

    double cost = CACurrentMediaTime() - now;
    _frameCostAvg = _frameCostAvg * 0.95 + cost * 0.05;
    if (_frameInterval == 2 && _frameCostAvg > 0.024) {
        _frameInterval = 3; link.frameInterval = 3;
        SFLog(@"rendering ridotto a 20 fps (costo medio frame %.1f ms)", _frameCostAvg * 1000);
    } else if (_frameInterval == 3 && _frameCostAvg < 0.014) {      // carico passato: si torna a 30 fps
        _frameInterval = 2; link.frameInterval = 2;
        SFLog(@"rendering di nuovo a 30 fps (costo medio frame %.1f ms)", _frameCostAvg * 1000);
    }
}

#pragma mark - Suoni sincronizzati

// Bip a ogni battito: sorgente ECG (QRS) se gli elettrodi sono collegati, altrimenti polso SpO2.
// Tono legato alla SpO2 quando è misurabile, fisso altrimenti (come i monitor reali).
- (void)beatSoundsAt:(NSTimeInterval)now snapshot:(SLSnapshot *)s {
    NSTimeInterval beat = -1;
    // il bip parte con un piccolo anticipo pari alla latenza dell'audio, così si sente quando il QRS compare sullo schermo
    const NSTimeInterval kAudioLead = 0.04;
    if (s.ecgConnected && s.ecgOrganized) {
        beat = [_engine lastBeatAtOrBefore:now + kAudioLead];
    } else if (s.spo2Displayable) {
        NSTimeInterval b = [_engine lastPerfusedBeatAtOrBefore:now + kAudioLead - 0.22];   // arrivo del polso al dito
        beat = b >= 0 ? b + 0.22 : -1;
    }
    BOOL isNew = beat > 0 && beat > _lastBeepBeat + 0.05;
    if (isNew) {
        _lastBeepBeat = beat;
        _hrHeart.alpha = 1.0;
        if (s.qrsBeepEnabled && now - beat < 0.2) {
            double f = s.spo2Displayable ? [SoundEngine beepFrequencyForSpO2:s.spo2] : 660.0;
            [_sound beepWithFrequency:f fromECG:(s.ecgConnected && s.ecgOrganized)];
        }
    } else if (now - _lastBeepBeat > 0.15) {
        _hrHeart.alpha = 0.15;
    }
}

- (void)nibpSoundsAt:(NSTimeInterval)now snapshot:(SLSnapshot *)s {
    double p = 0; NSInteger step = -1;
    SLNibpPhase ph = [s nibpPhaseAt:now pressure:&p step:&step];
    [_sound setPumpRunning:(ph == SLNibpPhaseInflating) pressure:p];
    if (ph == SLNibpPhaseDeflating && step != _lastNibpStep) [_sound valveStep];
    if (ph == SLNibpPhaseDumping && _lastNibpPhase != SLNibpPhaseDumping) [_sound valveDump];
    _lastNibpPhase = ph; _lastNibpStep = (ph == SLNibpPhaseDeflating) ? step : -1;
}

#pragma mark - Aggiornamenti

static NSString *SLLim(NSInteger hi, NSInteger lo) {
    if (hi >= 0 && lo >= 0) return [NSString stringWithFormat:@"%ld\n%ld", (long)hi, (long)lo];
    return [NSString stringWithFormat:@"%ld", (long)(hi >= 0 ? hi : lo)];
}

- (void)updateNumerics {
    SLSnapshot *s = _snap;
    _sound.volume = s.volume / 100.0;

    // ECG
    NSInteger hr = s.displayedHeartRate;
    // ritmi di arresto riconosciuti dall'ECG: sigla al posto del numero
    NSString *code = nil;
    if (s.ecgConnected) {
        if ([s.rhythm isEqualToString:SLRhythmVentricularTachy] || [s.rhythm isEqualToString:SLRhythmVentricularTachyPulse]) code = @"TV";
        else if ([s.rhythm isEqualToString:SLRhythmVentricularFib]) code = @"FV";
        else if ([s.rhythm isEqualToString:SLRhythmAsystole] && !s.defib.paceCapture) code = @"Asy";
    }
    if (hr > 0 && !code) hr = MAX(1, hr + lround(_jHR * ([s.rhythm isEqualToString:SLRhythmAtrialFibrillation] ? 2.5 : 1.0)));
    _hrValue.text = code ?: (hr < 0 ? @"---" : [NSString stringWithFormat:@"%ld", (long)hr]);
    _hrLimits.text = [s alarmOn:@"hr"] ? SLLim([s limit:@"hr_high"], [s limit:@"hr_low"]) : @"OFF";
    NSString *leadsOff = s.ecgConnected ? nil : @"ELETTRODI SCOLLEGATI";
    _ecg2.noSignalText = leadsOff; _ecg2.disconnected = !s.ecgConnected;
    _ecgV.noSignalText = leadsOff; _ecgV.disconnected = !s.ecgConnected;

    // SpO2
    BOOL spo2ok = s.spo2Displayable;
    _spo2Value.text = [self spo2TextAt:CACurrentMediaTime() snapshot:s];
    _prValue.text = spo2ok ? [NSString stringWithFormat:@"%ld", (long)MAX(1, s.pulseRate + lround(_jHR))] : @"--";
    _spo2Limits.text = [s alarmOn:@"spo2"] ? SLLim(-1, [s limit:@"spo2_low"]) : @"OFF";
    _pleth.disconnected = !s.spo2Connected;
    _pleth.flatWhenNoSignal = s.spo2Connected && (!s.pulsePresent || s.spo2Searching);   // collegata ma senza polso: linea piatta
    _pleth.noSignalText = !s.spo2Connected ? @"SONDA SpO2 SCOLLEGATA"
                        : (s.spo2Searching ? @"RICERCA POLSO…" : (!s.pulsePresent ? @"NESSUN POLSO" : nil));

    // ART
    if (s.artConnected) {
        NSInteger as = s.artDisplayedSystolic, ad = s.artDisplayedDiastolic;
        if (s.pulsePresent) { as = MAX(1, as + lround(_jSys)); ad = MAX(0, MIN(as - 5, ad + lround(_jDia))); }
        _artValue.text = [NSString stringWithFormat:@"%ld/%ld", (long)as, (long)ad];
        _artMap.text = [NSString stringWithFormat:@"(%ld)", (long)((as + 2 * ad) / 3)];
    } else { _artValue.text = @"--/--"; _artMap.text = @""; }
    _artLimits.text = [s alarmOn:@"art"] ? SLLim([s limit:@"sys_high"], [s limit:@"sys_low"]) : @"OFF";
    _art.noSignalText = s.artConnected ? nil : @"TRASDUTTORE ART NON COLLEGATO"; _art.disconnected = !s.artConnected;

    // CO2 / FR (FR da capnografia; se CO2 assente, da impedenza toracica ECG)
    _etco2Value.text = (s.etco2Connected && s.respRate > 0) ? [NSString stringWithFormat:@"%ld", (long)s.etco2] : @"--";
    _etco2Limits.text = [s alarmOn:@"etco2"] ? SLLim([s limit:@"etco2_high"], [s limit:@"etco2_low"]) : @"OFF";
    _rrLabel.text = @"FR  atti/min";   // misurata: da capnografia oppure, senza CO2, dall'impedenza toracica degli elettrodi ECG
    _rrValue.text = (s.etco2Connected || s.ecgConnected) ? [NSString stringWithFormat:@"%ld", (long)s.respRate] : @"--";
    _rrLimits.text = [s alarmOn:@"rr"] ? SLLim([s limit:@"rr_high"], [s limit:@"rr_low"]) : @"OFF";
    _capno.noSignalText = s.etco2Connected ? nil : @"SENSORE CO2 NON COLLEGATO"; _capno.disconnected = !s.etco2Connected;

    // NIBP
    if (s.nibpLastSystolic >= 0) {
        _nibpValue.text = [NSString stringWithFormat:@"%ld/%ld", (long)s.nibpLastSystolic, (long)s.nibpLastDiastolic];
        _nibpMap.text = [NSString stringWithFormat:@"(%ld)", (long)s.meanArterialPressure];
    } else if (s.nibpStatus == SLNibpError && [s.nibpError isEqualToString:@"no_pulse"]) {
        _nibpValue.text = @"?/?"; _nibpMap.text = @"";             // misura fallita: nessun polso rilevato
    } else { _nibpValue.text = @"---/---"; _nibpMap.text = @""; }
    _nibpLimits.text = [s alarmOn:@"nibp"] ? SLLim([s limit:@"sys_high"], [s limit:@"sys_low"]) : @"OFF";

    // temperatura (solo con la sonda) e refill capillare (valutazione clinica impostata dall'istruttore)
    _tempValue.text = s.tempConnected ? [NSString stringWithFormat:@"%.1f", s.temperatureTenths / 10.0] : @"--.-";
    [self updateCrt];
    if (_menuPanel && !_menuDim.hidden) [self refreshMenu];

}

- (void)slowTick:(NSTimeInterval)now {
    [self updateBattery];
    _lastSlowTick = now;
    _tick++;
    if (_tick % 2 == 0) _flashOn = !_flashOn;       // lampeggio a 1 Hz
    _clock.text = [_clockFmt stringFromDate:[NSDate date]];

    // stato NIBP con pressione del bracciale in tempo reale
    SLSnapshot *s = _snap;
    double p = 0; NSInteger step = -1;
    SLNibpPhase ph = [s nibpPhaseAt:now pressure:&p step:&step];
    if (s.nibpStatus == SLNibpMeasuring) {
        NSString *what = ph == SLNibpPhaseInflating ? @"Gonfiaggio" : ph == SLNibpPhaseDumping ? @"Sgonfiaggio" : @"Misurazione";
        _nibpStatus.text = [NSString stringWithFormat:@"%@…  bracciale %ld mmHg", what, (long)lround(p)];
    } else if (s.nibpStatus == SLNibpError) {
        _nibpStatus.text = [s.nibpError isEqualToString:@"cuff"] ? @"Errore: bracciale non collegato / perdita"
                         : ([s.nibpError isEqualToString:@"motion"] ? @"Artefatto da movimento: misura non riuscita" : @"Nessun polso rilevato");
    } else if (s.nibpStatus == SLNibpComplete && s.nibpMeasuredAt) {
        _nibpStatus.text = [NSString stringWithFormat:@"Ultima misura %@", [_nibpFmt stringFromDate:s.nibpMeasuredAt]];
    } else {
        _nibpStatus.text = s.nibpConnected ? @"Nessuna misura" : @"Bracciale non collegato";
    }

    // SpO2 in bassa perfusione: il "?" SOSTITUISCE il valore a intermittenza (come i monitor reali)
    // ciclo di 3 s: "?" per 2 s, valore per 1 s
    // variabilità fisiologica: piccola deriva casuale limitata, aggiornata ogni ~2 s (come i numerici dei monitor reali)
    if (now - _lastJitter >= 2.0) {
        _lastJitter = now;
        double (^walk)(double, double) = ^double(double v, double lim) {
            v += ((double)arc4random_uniform(1001) / 1000.0 - 0.5) * lim * 0.9;
            return MAX(-lim, MIN(lim, v * 0.85));
        };
        _jHR = walk(_jHR, 2.0); _jSpO2 = walk(_jSpO2, 1.0); _jSys = walk(_jSys, 3.0); _jDia = walk(_jDia, 2.0);
        [self updateNumerics];
        if (_alt && !_alt.hidden) { _snap = [_state snapshot]; [_alt updateWithSnapshot:_snap]; }   // anche i dispositivi: valori non fissi (stato attuale, mai una copia vecchia)
    }
    _spo2Value.text = [self spo2TextAt:now snapshot:s];
    if (_crtAssessAt > 0) [self updateCrt];

    // NIBP automatica: etichetta e barra che si accorcia
    if (s.nibpIntervalMin > 0) {
        double rem = MAX(0, s.nibpNextAt - now), tot = s.nibpIntervalMin * 60.0;
        _nibpAutoLabel.text = [NSString stringWithFormat:@"AUTO ogni %ld min\nprossima tra %ld:%02ld",
                               (long)s.nibpIntervalMin, (long)rem / 60, (long)rem % 60];
        _nibpBarTrack.hidden = NO;
        CGRect f = _nibpBarTrack.bounds; f.size.width = f.size.width * MIN(1.0, rem / tot);
        _nibpBarFill.frame = f;
    } else {
        _nibpAutoLabel.text = @""; _nibpBarTrack.hidden = YES;
    }

    // allarmi
    _alarmResult = [AlarmManager evaluate:s];
    SFAlarmSound snd = SFAlarmSoundNone;
    if (!s.alarmsMuted) {
        if (_alarmResult.level == SLAlarmHigh) snd = SFAlarmSoundHigh;
        else if (_alarmResult.level == SLAlarmMedium) snd = SFAlarmSoundMedium;
        else if (_alarmResult.level == SLAlarmTechnical) snd = SFAlarmSoundLow;
    }
    BOOL altOff = (_alt && !_alt.hidden) ? [_alt poweredOff] : !_state.devicePowered;
    if (altOff) snd = SFAlarmSoundNone;                         // dispositivo spento o in standby: nessun allarme sonoro
    if (CACurrentMediaTime() < _volAlarmPreviewUntil && snd == SFAlarmSoundNone) snd = SFAlarmSoundMedium;   // prova del volume allarmi
    [_sound setAlarm:snd];
    [self updatePauseCover:s];
    if (_alt && !_alt.hidden) {
        NSString *msg = _alarmResult.messages.firstObject;
        if (_alarmResult.messages.count > 1) msg = [msg stringByAppendingFormat:@"  (+%lu)", (unsigned long)_alarmResult.messages.count - 1];
        msg = SFAlarmText(s.layout, msg);                            // testi nello stile del dispositivo
        [_alt setAlarmText:msg level:_alarmResult.level severity:_alarmResult.severity muted:s.alarmsMuted remaining:s.alarmsMutedRemaining];
    }
    [_muteButton setTitle:s.alarmsMuted ? [NSString stringWithFormat:@"SILENZIATO %ld s", (long)s.alarmsMutedRemaining] : @"SILENZIA 20 s"
                 forState:UIControlStateNormal];
    if (_alarmResult.level == SLAlarmNone) {
        _banner.hidden = YES;
    } else {
        _banner.hidden = NO;
        // più allarmi attivi: il banner li mostra a rotazione, 5 secondi ciascuno, con l'indice (es. "2/3")
        NSUInteger n = _alarmResult.messages.count;
        NSUInteger idx = n > 1 ? (NSUInteger)floor(CACurrentMediaTime() / 5.0) % n : 0;
        NSString *msg = n ? _alarmResult.messages[idx] : @"";
        if (n > 1) msg = [msg stringByAppendingFormat:@"   %lu/%lu", (unsigned long)idx + 1, (unsigned long)n];
        // (nessun "SILENZIO n s" nel banner: il tempo residuo si vede sul pulsante SILENZIATO)
        _banner.text = msg;
        UIColor *c = _alarmResult.level == SLAlarmHigh ? SL_ALARM : (_alarmResult.level == SLAlarmMedium ? SL_YELLOW : SL_CYAN);
        BOOL on = _alarmResult.level == SLAlarmHigh ? (_tick % 2 == 0) : _flashOn;   // rosso lampeggia a 2 Hz
        _banner.layer.backgroundColor = (on ? c : [UIColor colorWithWhite:0.15 alpha:1]).CGColor;
        _banner.textColor = on ? [UIColor blackColor] : c;
    }
    // valori in allarme: lampeggia TUTTA la cella del parametro (titolo, limiti e valori)
    //   medio  -> cella GIALLA con testi NERI, alternata all'aspetto normale (1 Hz)
    //   alto   -> cella ROSSA con testi BIANCHI, alternata all'aspetto normale (2 Hz)
    NSDictionary *sev = _alarmResult.severity;
    if (!_alarmBoxes) _alarmBoxes = [NSMutableDictionary dictionary];
    if (!_cellLabels) _cellLabels = [NSMutableDictionary dictionary];
    for (NSString *k in @[@"hr", @"spo2", @"art", @"etco2", @"rr", @"nibp"]) {
        CGRect cell = [_cellRects[k] CGRectValue];
        UIView *box = _alarmBoxes[k];
        if (!box) {
            box = [[UIView alloc] initWithFrame:cell];
            box.hidden = YES; box.userInteractionEnabled = NO;
            [self.view insertSubview:box atIndex:0];                // dietro a tutto il contenuto della cella
            _alarmBoxes[k] = box;
            NSMutableArray *ls = [NSMutableArray array];            // etichette della cella e loro colore normale
            for (UIView *v in self.view.subviews)
                if ([v isKindOfClass:[UILabel class]] && CGRectContainsPoint(cell, CGPointMake(CGRectGetMidX(v.frame), CGRectGetMidY(v.frame))))
                    [ls addObject:@[v, ((UILabel *)v).textColor ?: SL_WHITE]];
            _cellLabels[k] = ls;
        }
        if (_icuHidden) { box.hidden = YES; continue; }              // sotto un layout di dispositivo: niente lampeggi invisibili
        NSInteger lvl = [sev[k] integerValue];
        BOOL on = lvl == SLAlarmHigh ? (_tick % 2 == 0) : (lvl == SLAlarmMedium ? _flashOn : NO);
        box.hidden = !on;
        if (on) box.backgroundColor = lvl == SLAlarmHigh ? SL_ALARM : SL_YELLOW;
        UIColor *ink = lvl == SLAlarmHigh ? [UIColor whiteColor] : [UIColor blackColor];
        for (NSArray *pair in _cellLabels[k]) { UILabel *l = pair[0]; l.backgroundColor = [UIColor clearColor]; l.textColor = on ? ink : pair[1]; }
        if ([k isEqualToString:@"hr"]) {                          // anche il cuore cambia colore con la cella
            CAShapeLayer *heart = (CAShapeLayer *)_hrHeart.layer.sublayers.firstObject;
            if ([heart isKindOfClass:[CAShapeLayer class]]) heart.fillColor = (on ? ink : SL_GREEN).CGColor;
        }
    }

    if (now - _lastNetCheck >= 3.0) [self refreshNetwork];
    if (!_infoPanel.hidden) {
        [self updateInfoText];
        if (!_connect.busy && now - MAX(_infoShownAt, _connect.lastInteraction) > 45) _infoPanel.hidden = YES;   // il PIN non resta in vista
    }
}


// Testo SpO2 (unico punto di decisione, niente sfarfallii):
// bassa perfusione -> "?" per 4 s e valore per 2 s, ciclo che parte sempre dal "?"
- (NSString *)spo2TextAt:(NSTimeInterval)now snapshot:(SLSnapshot *)s {
    if (!s.spo2Displayable) { _lowPerfSince = 0; return @"--"; }
    NSString *val = [NSString stringWithFormat:@"%ld", (long)[self shownSpO2:s]];
    if (!s.lowPerfusion) { _lowPerfSince = 0; return val; }
    if (_lowPerfSince == 0) _lowPerfSince = now;
    return fmod(now - _lowPerfSince, 6.0) < 4.0 ? @"?" : val;
}

// SpO2 mostrata: valore impostato ± 1 (mai oltre 100)
- (NSInteger)shownSpO2:(SLSnapshot *)s {
    return MAX(0, MIN(100, s.spo2 + lround(_jSpO2)));
}

- (void)updateBattery {
    UIDevice *d = [UIDevice currentDevice];
    float lvl = d.batteryLevel;
    BOOL chg = d.batteryState == UIDeviceBatteryStateCharging, full = d.batteryState == UIDeviceBatteryStateFull;
    double f = lvl < 0 ? 1.0 : MAX(0.04, lvl);
    UIColor *c = (lvl >= 0 && lvl <= 0.2 && !chg && !full) ? SL_RED : (lvl >= 0 && lvl <= 0.4 && !chg && !full ? SL_AMBER : SL_GREEN);
    _battFill.frame = CGRectMake(2.5, 2.5, 33 * f, 12); _battFill.backgroundColor = c;
    _battPct.text = lvl < 0 ? @"--%" : [NSString stringWithFormat:@"%ld%%", (long)lroundf(lvl * 100)];
    _battPct.textColor = c == SL_GREEN ? SL_WHITE : c;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _battBolt.hidden = !(chg || full);
    [CATransaction commit];
}

- (void)refreshNetwork {
    _lastNetCheck = CACurrentMediaTime();
    _ip = [NetworkInfo wifiIPv4Address];
    _netLabel.text = _ip ? [NSString stringWithFormat:@"http://%@:%u", _ip, self.serverPort]
                         : @"Nessuna rete — collegamento diretto disponibile";
    _altFooterText.text = _ip ? [NSString stringWithFormat:@"Controller\n%@:%u", _ip, self.serverPort] : @"Controller\nsenza rete";
}

// dati del pannello "Collegamento": quelli dell'app (server, canale diretto, controller attivo) + rete e audio
- (NSDictionary *)connectInfo {
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:self.linkInfo ? self.linkInfo() : @{}];
    if (_ip) d[@"ip"] = _ip;
    d[@"port"] = @(self.serverPort);
    d[@"pin"] = self.pinProvider ? self.pinProvider() : @"?";
    d[@"serverStatus"] = self.serverStatus ?: @"?";
    d[@"audio"] = _sound.running ? @"attivo" : (_sound.lastError ?: @"non attivo");
    d[@"deviceId"] = _state.deviceId;
    return d;
}

- (void)updateInfoText { [_connect refresh]; }

#pragma mark - Menu del parametro

- (void)connectSensor:(UIButton *)b {
    NSString *k = b.accessibilityIdentifier;
    NSDictionary *on = @{ @"ecg": @(_snap.ecgConnected), @"spo2": @(_snap.spo2Connected), @"art": @(_snap.artConnected),
                          @"etco2": @(_snap.etco2Connected), @"nibp": @(_snap.nibpConnected), @"temp": @(_snap.tempConnected) };
    if ([on[k] boolValue]) return;                                    // mai scollegare con un tocco
    [_state applyCommand:@{@"command": @"set_sensor", @"value": @{@"sensor": k, @"connected": @YES}} error:NULL];
}

- (void)hitParam:(UIButton *)b {
    NSArray *order = @[@"hr", @"spo2", @"art", @"etco2", @"rr", @"nibp"];
    [self openMenu:order[(NSUInteger)b.tag]];
}

- (UIColor *)colorFor:(NSString *)k {
    NSDictionary *c = @{ @"hr": SL_GREEN, @"spo2": SL_CYAN, @"art": SL_RED, @"nibp": SL_NIBP, @"etco2": SL_WHITE, @"rr": SL_WHITE };
    return c[k] ?: SL_WHITE;
}

- (void)openMenu:(NSString *)param {
    [_menuDim removeFromSuperview];
    _menuParam = param;
    NSDictionary *cfg = SFMenuConfig()[param];
    NSArray *limits = cfg[@"limits"];
    UIColor *col = [self colorFor:param];
    BOOL nibp = [param isEqualToString:@"nibp"];

    _menuDim = [[UIView alloc] initWithFrame:self.view.bounds];
    _menuDim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    UIButton *closeArea = [UIButton buttonWithType:UIButtonTypeCustom];
    closeArea.frame = _menuDim.bounds; [closeArea addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [_menuDim addSubview:closeArea];

    CGFloat W = 420, rowH = 52, H = 70 + rowH * (limits.count + 1) + (nibp ? 120 : 0) + 70;
    _menuPanel = [[UIView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width - W) / 2, (self.view.bounds.size.height - H) / 2, W, H)];
    _menuPanel.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.98];
    _menuPanel.layer.cornerRadius = 10; _menuPanel.layer.borderWidth = 2; _menuPanel.layer.borderColor = col.CGColor;
    [_menuDim addSubview:_menuPanel];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 14, W - 40, 30)];
    title.text = [NSString stringWithFormat:@"%@ \u2014 allarmi", cfg[@"title"]];
    title.textColor = col; title.font = [UIFont boldSystemFontOfSize:22];
    [_menuPanel addSubview:title];

    CGFloat y = 60;
    // interruttore allarme
    UILabel *swl = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 200, 30)];
    swl.text = @"Allarme"; swl.textColor = SL_WHITE; swl.font = [UIFont systemFontOfSize:18];
    [_menuPanel addSubview:swl];
    _menuSwitch = [[UISwitch alloc] init];
    _menuSwitch.frame = CGRectMake(W - 20 - _menuSwitch.bounds.size.width, y, 0, 0);
    _menuSwitch.onTintColor = col;
    [_menuSwitch addTarget:self action:@selector(menuSwitchChanged) forControlEvents:UIControlEventValueChanged];
    [_menuPanel addSubview:_menuSwitch];
    _menuSwitchText = [[UILabel alloc] initWithFrame:CGRectMake(20, y + 28, W - 40, 18)];
    _menuSwitchText.textColor = SL_GREY; _menuSwitchText.font = [UIFont systemFontOfSize:12];
    [_menuPanel addSubview:_menuSwitchText];
    y += rowH + 4;

    // limiti
    _menuSteppers = [NSMutableDictionary dictionary]; _menuValues = [NSMutableDictionary dictionary];
    for (NSArray *l in limits) {
        UILabel *n = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 160, 30)];
        n.text = l[1]; n.textColor = SL_WHITE; n.font = [UIFont systemFontOfSize:18];
        [_menuPanel addSubview:n];
        UILabel *v = [[UILabel alloc] initWithFrame:CGRectMake(180, y - 4, 80, 38)];
        v.textColor = col; v.font = [UIFont boldSystemFontOfSize:28]; v.textAlignment = NSTextAlignmentRight;
        [_menuPanel addSubview:v];
        UIStepper *st = [[UIStepper alloc] init];
        st.frame = CGRectMake(W - 20 - st.bounds.size.width, y, 0, 0);
        st.stepValue = [l[2] doubleValue]; st.minimumValue = [l[3] doubleValue]; st.maximumValue = [l[4] doubleValue];
        st.tintColor = col; st.accessibilityIdentifier = l[0];
        [st addTarget:self action:@selector(menuStepperChanged:) forControlEvents:UIControlEventValueChanged];
        [_menuPanel addSubview:st];
        _menuSteppers[l[0]] = st; _menuValues[l[0]] = v;
        y += rowH;
    }
    if ([param isEqualToString:@"art"] || nibp) {
        UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(20, y - 10, W - 40, 16)];
        note.text = @"I limiti di sistolica sono comuni ad ART e NIBP.";
        note.textColor = SL_GREY; note.font = [UIFont systemFontOfSize:12];
        [_menuPanel addSubview:note]; y += 10;
    }

    // NIBP: misura automatica a intervalli
    _menuInterval = nil;
    if (nibp) {
        UILabel *ni = [[UILabel alloc] initWithFrame:CGRectMake(20, y, W - 40, 26)];
        ni.text = @"Misura automatica ogni (minuti)"; ni.textColor = SL_WHITE; ni.font = [UIFont systemFontOfSize:18];
        [_menuPanel addSubview:ni];
        NSMutableArray *items = [NSMutableArray array];
        for (NSNumber *m in [SimulationState nibpIntervals]) [items addObject:m.integerValue ? m.stringValue : @"Off"];
        _menuInterval = [[UISegmentedControl alloc] initWithItems:items];
        _menuInterval.frame = CGRectMake(20, y + 32, W - 40, 34);
        _menuInterval.tintColor = col;
        [_menuInterval addTarget:self action:@selector(menuIntervalChanged) forControlEvents:UIControlEventValueChanged];
        [_menuPanel addSubview:_menuInterval];
        UIButton *now = [UIButton buttonWithType:UIButtonTypeSystem];
        now.frame = CGRectMake(20, y + 74, W - 40, 36);
        [now setTitle:@"Avvia misura adesso" forState:UIControlStateNormal];
        now.tintColor = col; now.titleLabel.font = [UIFont boldSystemFontOfSize:17];
        now.layer.borderColor = col.CGColor; now.layer.borderWidth = 1.5; now.layer.cornerRadius = 6;
        [now addTarget:self action:@selector(startNibp) forControlEvents:UIControlEventTouchUpInside];
        [_menuPanel addSubview:now];
        y += 120;
    }

    _menuError = [[UILabel alloc] initWithFrame:CGRectMake(20, y, W - 40, 18)];
    _menuError.textColor = SL_AMBER; _menuError.font = [UIFont systemFontOfSize:13];
    [_menuPanel addSubview:_menuError];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(W - 140, H - 52, 120, 38);
    [close setTitle:@"Chiudi" forState:UIControlStateNormal];
    close.tintColor = SL_WHITE; close.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    close.layer.borderColor = SL_GREY.CGColor; close.layer.borderWidth = 1; close.layer.cornerRadius = 6;
    [close addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [_menuPanel addSubview:close];

    [self.view addSubview:_menuDim];
    [self refreshMenu];
}

- (void)refreshMenu {
    if (!_menuParam) return;
    SLSnapshot *s = _snap;
    BOOL on = [s alarmOn:_menuParam];
    _menuSwitch.on = on;
    _menuSwitchText.text = on ? @"attivo" : ([_menuParam isEqualToString:@"hr"]
        ? @"DISATTIVATO \u2014 FV, TV e asistolia danno comunque allarme" : @"DISATTIVATO finch\u00E9 non lo riattivi");
    for (NSString *k in _menuSteppers) {
        _menuSteppers[k].value = [s limit:k];
        _menuValues[k].text = [NSString stringWithFormat:@"%ld", (long)[s limit:k]];
    }
    if (_menuInterval) {
        NSUInteger idx = [[SimulationState nibpIntervals] indexOfObject:@(s.nibpIntervalMin)];
        _menuInterval.selectedSegmentIndex = idx == NSNotFound ? 0 : (NSInteger)idx;
    }
}

- (void)menuSwitchChanged {
    [_state applyCommand:@{@"command": @"set_alarm_enabled", @"value": @{@"param": _menuParam, @"enabled": @(_menuSwitch.on)}} error:NULL];
}

- (void)menuStepperChanged:(UIStepper *)st {
    NSString *err = nil;
    if (![_state applyCommand:@{@"command": @"set_alarm_limits", @"value": @{st.accessibilityIdentifier: @((NSInteger)st.value)}} error:&err]) {
        _menuError.text = [err containsString:@"lower"] ? @"Il limite basso deve restare sotto quello alto" : err;
        st.value = [_snap limit:st.accessibilityIdentifier];
    } else {
        _menuError.text = @"";
        _menuValues[st.accessibilityIdentifier].text = [NSString stringWithFormat:@"%ld", (long)st.value];
    }
}

- (void)menuIntervalChanged {
    NSNumber *m = [SimulationState nibpIntervals][(NSUInteger)_menuInterval.selectedSegmentIndex];
    [_state applyCommand:@{@"command": @"set_nibp_interval", @"value": m} error:NULL];
}

- (void)closeMenu {
    [_menuDim removeFromSuperview]; _menuDim = nil; _menuPanel = nil; _menuParam = nil;
}

#pragma mark - Azioni locali

- (void)toggleMute {
    BOOL muted = _snap.alarmsMuted;
    [_state applyCommand:@{@"command": @"mute_alarms", @"value": @((BOOL)!muted)} error:NULL];
}

- (void)startNibp {
    [_state startNibpMeasurementError:NULL];
}

// Refill capillare: "--" finché non lo si valuta; tocco = pressione sul letto ungueale (~3 s), poi il tempo.
// Se l'istruttore cambia il valore, va rivalutato.
- (void)assessCrt { _crtAssessAt = CACurrentMediaTime(); [self updateCrt]; }
- (void)updateCrt {
    SLSnapshot *s = _snap;
    if (s.crtAssessSeq != _crtSeqSeen) {                       // valutazione chiesta dall'istruttore dal controller
        _crtSeqSeen = s.crtAssessSeq; if (s.crtAssessSeq > 0) _crtAssessAt = CACurrentMediaTime();
    }
    BOOL on = s.crtEnabled;                                    // disattivabile dall'istruttore
    _crtTitle.hidden = !on; _crtValue.hidden = !on; _crtLine.hidden = !on; _crtHit.hidden = !on;
    if (!on) return;
    NSTimeInterval now = CACurrentMediaTime();
    if (_crtAssessAt > 0 && now - _crtAssessAt >= 3.0) { _crtShown = s.crtTenths; _crtAssessAt = 0; }
    if (_crtAssessAt > 0) { _crtValue.text = @"…"; return; }
    if (_crtShown != s.crtTenths) { _crtShown = -1; _crtValue.text = @"--"; return; }
    _crtValue.text = (s.crtTenths % 10) ? [NSString stringWithFormat:@"%.1f", s.crtTenths / 10.0]
                                        : [NSString stringWithFormat:@"%ld", (long)(s.crtTenths / 10)];
}

#pragma mark - Layout del monitor

// classe della vista di un layout di dispositivo (nil = layout ICU o layout non disponibile in questa versione)
- (Class)classForLayout:(NSString *)layout {
    if ([layout isEqualToString:@"extrah"]) return [ExtraHView class];
    if ([layout isEqualToString:@"dae"]) return [GenericAedView class];
    return Nil;
}

- (void)applyLayout:(NSString *)layout {
    if (![layout isEqualToString:@"generic_icu"] && ![self classForLayout:layout]) layout = @"generic_icu";   // layout non disponibile: si torna a ICU
    _layoutShown = [layout copy];
    [[NSUserDefaults standardUserDefaults] setObject:layout forKey:@"sf_layout"];
    BOOL lp = ![layout isEqualToString:@"generic_icu"];
    if (lp && ![_altKind isEqualToString:layout]) {             // crea la vista del layout richiesto (una alla volta)
        [_alt removeFromSuperview];
        Class cls = [self classForLayout:layout];
        _alt = [[cls alloc] initWithFrame:self.view.bounds state:_state engine:_engine sound:_sound];
        _altKind = [layout copy];
        __weak MonitorViewController *me = self;
        _alt.onLayoutMenu = ^{ [me showLayoutMenu]; };
        _alt.onInfo = ^{ [me toggleInfo]; };
        _alt.onVolumes = ^{ [me showVolumes]; };
        [self.view addSubview:_alt];
    }
    if (lp && _drawerOpen) [self toggleDrawer];
    _alt.hidden = !lp;
    NSTimeInterval now = CACurrentMediaTime();
    if (lp) { [_alt setDevicePowered:_state.devicePowered]; _powerPushed = _state.devicePowered;
              [_alt resetTracesAt:now]; [_alt updateWithSnapshot:_snap]; [self.view bringSubviewToFront:_alt];
              UIView *sp = [self.view viewWithTag:7777]; if (sp) [self.view bringSubviewToFront:sp]; }
    else for (TraceView *t in [self traces]) [t resetAtTime:now];
    if (_standby) _standby.hidden = lp || _state.devicePowered;
    _altFooter.hidden = !lp;
    if (lp) [self.view bringSubviewToFront:_altFooter];
    [self.view bringSubviewToFront:_infoPanel];
    [self hideIcuUnder:lp];
    SFLog(@"layout: %@", layout);
}

// Con un layout di dispositivo a schermo, la schermata ICU sotto non si vede ma continuava ad aggiornarsi (allarmi
// che lampeggiano, valori): il compositore di sistema la ricomponeva lo stesso a ogni fotogramma. Ora le sue viste
// vengono nascoste finché è attivo il dispositivo, e ripristinate esattamente com'erano quando si torna a ICU.
- (void)hideIcuUnder:(BOOL)hide {
    if (hide) {
        if (_icuHidden) return;
        _icuHidden = [NSMutableArray array];
        NSArray *keep = @[_alt ?: [NSNull null], _altFooter ?: [NSNull null], _infoPanel ?: [NSNull null]];
        for (UIView *v in self.view.subviews) {
            if ([keep containsObject:v] || v.hidden || v == _volPanel || v == _layoutMenu || v == _pauseCover || v == _drawer || v.tag == 7777) continue;
            v.hidden = YES; [_icuHidden addObject:v];
        }
    } else {
        for (UIView *v in _icuHidden) v.hidden = NO;
        _icuHidden = nil;
    }
}

- (void)showLayoutMenu {
    [_layoutMenu removeFromSuperview];
    CGRect b = self.view.bounds;
    _layoutMenu = [[UIView alloc] initWithFrame:b];
    _layoutMenu.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    UIButton *bg = [UIButton buttonWithType:UIButtonTypeCustom]; bg.frame = b;
    [bg addTarget:self action:@selector(closeLayoutMenu) forControlEvents:UIControlEventTouchUpInside];
    [_layoutMenu addSubview:bg];
    NSArray<NSDictionary *> *items = [SimulationState layoutCatalog];
    CGFloat rowH = items.count > 5 ? 52 : 62, listEnd = 58 + items.count * rowH, ph = listEnd + 8 + 46 + 14 + 44 + 12;
    UIView *p = [[UIView alloc] initWithFrame:CGRectMake(b.size.width / 2 - 210, floor((b.size.height - ph) / 2), 420, ph)];
    p.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.98]; p.layer.cornerRadius = 10; p.layer.borderWidth = 2; p.layer.borderColor = SL_GREY.CGColor;
    [_layoutMenu addSubview:p];
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(20, 14, 380, 30)];
    t.text = @"Layout del monitor"; t.textColor = SL_WHITE; t.font = [UIFont boldSystemFontOfSize:22];
    [p addSubview:t];
    for (NSUInteger i = 0; i < items.count; i++) {
        UIButton *o = [UIButton buttonWithType:UIButtonTypeCustom];
        o.frame = CGRectMake(20, 58 + i * rowH, 380, rowH - 10);
        BOOL cur = [_layoutShown isEqualToString:items[i][@"id"]];
        [o setTitle:items[i][@"name"] forState:UIControlStateNormal];      // solo il nome (il layout attivo è evidenziato in verde)
        o.titleLabel.font = [UIFont boldSystemFontOfSize:20];
        [o setTitleColor:cur ? SL_GREEN : SL_WHITE forState:UIControlStateNormal];
        o.layer.borderWidth = cur ? 2 : 1; o.layer.borderColor = (cur ? SL_GREEN : SL_GREY).CGColor; o.layer.cornerRadius = 8;
        o.accessibilityIdentifier = items[i][@"id"];
        [o addTarget:self action:@selector(layoutChosen:) forControlEvents:UIControlEventTouchUpInside];
        [p addSubview:o];
    }
    UIButton *rst = [UIButton buttonWithType:UIButtonTypeCustom];
    rst.frame = CGRectMake(20, listEnd + 8, 380, 46);
    [rst setTitle:@"Azzera lo scenario e spegni" forState:UIControlStateNormal];
    rst.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [rst setTitleColor:[UIColor colorWithRed:1 green:0.45 blue:0.4 alpha:1] forState:UIControlStateNormal];
    rst.layer.borderWidth = 1; rst.layer.borderColor = [UIColor colorWithRed:0.75 green:0.25 blue:0.2 alpha:1].CGColor;
    rst.layer.cornerRadius = 8; rst.accessibilityIdentifier = @"RESET-SCENARIO";
    [rst addTarget:self action:@selector(confirmResetScenario) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:rst];
    UILabel *vl = [[UILabel alloc] initWithFrame:CGRectMake(20, ph - 46, 250, 24)];
    vl.text = [NSString stringWithFormat:@"similFranz Monitor v%@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @""];
    vl.textColor = SL_GREY; vl.font = [UIFont systemFontOfSize:13];
    [p addSubview:vl];
    UIButton *c = [UIButton buttonWithType:UIButtonTypeSystem];
    c.frame = CGRectMake(280, ph - 54, 120, 40); [c setTitle:@"Chiudi" forState:UIControlStateNormal];
    c.tintColor = SL_WHITE; c.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [c addTarget:self action:@selector(closeLayoutMenu) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:c];
    [self.view addSubview:_layoutMenu];
}
- (void)closeLayoutMenu { [_layoutMenu removeFromSuperview]; _layoutMenu = nil; }
- (void)standbyTapped {
    _state.devicePowered = YES;
    _standby.hidden = YES;
}
// Azzera contatori, stati e sonde e spegne il monitor (stessa azione del "Reset scenario" della web app).
- (void)confirmResetScenario {
    [self closeLayoutMenu];
    SimulationState *st = _state;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Azzerare lo scenario?"
        message:@"Il paziente torna alle condizioni iniziali, le sonde vengono staccate, contatori e registro si azzerano e il monitor si spegne."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Annulla" style:UIAlertActionStyleCancel handler:nil]];
    void (^onReset)(void) = self.onResetScenario;
    [a addAction:[UIAlertAction actionWithTitle:@"Azzera e spegni" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        if (onReset) onReset(); else [st applyCommand:@{@"command": @"reset_scenario"} error:NULL];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)layoutChosen:(UIButton *)b {
    [_state applyCommand:@{@"command": @"set_layout", @"value": b.accessibilityIdentifier} error:NULL];
    [self closeLayoutMenu];
}


#pragma mark - Audit di sovrapposizioni (pulsanti, etichette, testi tagliati)

static BOOL SFVisible(UIView *v) {
    for (UIView *c = v; c; c = c.superview) if (c.hidden || c.alpha < 0.05) return NO;
    return YES;
}
static NSString *SFName(UIView *v) {
    if ([v isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)v;
        NSString *t = b.currentAttributedTitle.string ?: b.currentTitle;
        if (t.length) return [NSString stringWithFormat:@"tasto '%@'", [t stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
        return b.accessibilityIdentifier.length ? [NSString stringWithFormat:@"tasto %@", b.accessibilityIdentifier] : @"tasto (senza testo)";
    }
    if ([v isKindOfClass:[UILabel class]]) return [NSString stringWithFormat:@"etichetta '%@'", [[(UILabel *)v text] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
    return NSStringFromClass([v class]);
}
- (void)collect:(UIView *)v into:(NSMutableArray *)out {
    if (!SFVisible(v)) return;
    if ([v isKindOfClass:[UIButton class]]) {
        UIButton *b = (UIButton *)v;
        BOOL hasText = (b.currentAttributedTitle.string.length || b.currentTitle.length);
        if (hasText || b.allTargets.count) [out addObject:v];
        return;                                      // il titleLabel interno non conta a parte
    }
    if ([v isKindOfClass:[UILabel class]] && [(UILabel *)v text].length) [out addObject:v];
    for (UIView *c in v.subviews) [self collect:c into:out];
}
- (NSInteger)auditOverlapsIn:(UIView *)root name:(NSString *)name {
    NSMutableArray *els = [NSMutableArray array];
    [self collect:root into:els];
    NSInteger issues = 0;
    CGRect screen = self.view.bounds;
    NSMutableArray *frames = [NSMutableArray array];
    for (UIView *v in els) [frames addObject:[NSValue valueWithCGRect:[v convertRect:v.bounds toView:self.view]]];
    for (NSUInteger i = 0; i < els.count; i++) {
        UIView *a = els[i]; CGRect fa = [frames[i] CGRectValue];
        if (!CGRectContainsRect(CGRectInset(screen, -1, -1), fa)) { issues++; SFLog(@"AUDIT %@ fuori schermo: %@ %@", name, SFName(a), NSStringFromCGRect(fa)); }
        // testo che non ci sta
        UILabel *l = [a isKindOfClass:[UIButton class]] ? [(UIButton *)a titleLabel] : (UILabel *)a;
        if (l.text.length && !l.adjustsFontSizeToFitWidth) {
            CGSize avail = [a isKindOfClass:[UIButton class]] ? UIEdgeInsetsInsetRect(a.bounds, [(UIButton *)a titleEdgeInsets]).size : a.bounds.size;
            CGRect need = [(l.attributedText ?: [[NSAttributedString alloc] initWithString:l.text attributes:@{NSFontAttributeName: l.font}])
                           boundingRectWithSize:CGSizeMake(l.numberOfLines == 1 ? CGFLOAT_MAX : avail.width, CGFLOAT_MAX)
                           options:NSStringDrawingUsesLineFragmentOrigin context:nil];
            if (need.size.width > avail.width + 1.5 || (l.numberOfLines != 1 && need.size.height > avail.height + 2))
                { issues++; SFLog(@"AUDIT %@ testo tagliato: %@ serve %.0fx%.0f, ha %.0fx%.0f", name, SFName(a), need.size.width, need.size.height, avail.width, avail.height); }
        }
        for (NSUInteger j = i + 1; j < els.count; j++) {
            UIView *b = els[j]; CGRect fb = [frames[j] CGRectValue];
            if ([a isDescendantOfView:b] || [b isDescendantOfView:a]) continue;
            CGRect x = CGRectIntersection(CGRectInset(fa, 1, 1), CGRectInset(fb, 1, 1));
            if (CGRectIsNull(x) || x.size.width < 2 || x.size.height < 2) continue;
            BOOL bothButtons = [a isKindOfClass:[UIButton class]] && [b isKindOfClass:[UIButton class]];
            BOOL bothLabels = [a isKindOfClass:[UILabel class]] && [b isKindOfClass:[UILabel class]];
            // etichetta sopra un tasto senza testo = scritta del tasto (voluta); tasto invisibile su testo = area di tocco (voluta)
            if (!bothButtons && !bothLabels) {
                UIButton *btn = (UIButton *)([a isKindOfClass:[UIButton class]] ? a : b);
                BOOL titled = btn.currentAttributedTitle.string.length || btn.currentTitle.length;
                if (!titled) continue;
            }
            if (bothButtons) {
                UIButton *ba = (UIButton *)a, *bb = (UIButton *)b;
                BOOL ta = ba.currentAttributedTitle.string.length || ba.currentTitle.length, tb = bb.currentAttributedTitle.string.length || bb.currentTitle.length;
                if (!ta && !tb && CGRectEqualToRect(fa, fb)) continue;
            }
            issues++;
            SFLog(@"AUDIT %@ sovrapposti: %@ %@ / %@ %@", name, SFName(a), NSStringFromCGRect(fa), SFName(b), NSStringFromCGRect(fb));
        }
    }
    SFLog(@"AUDIT %@: %ld elementi, %ld segnalazioni", name, (long)els.count, (long)issues);
    return issues;
}
- (void)checkLayoutKeyNamed:(NSString *)name {
    UIView *k = nil; NSMutableArray *st = [NSMutableArray arrayWithObject:_alt ?: self.view];
    while (st.count && !k) { UIView *v = st.lastObject; [st removeLastObject]; if ([v.accessibilityIdentifier isEqualToString:@"LAYOUT"] && [v isKindOfClass:[UIButton class]]) k = v; else [st addObjectsFromArray:v.subviews]; }
    BOOL ok = NO;
    if (k) { CGPoint p = [k convertPoint:CGPointMake(CGRectGetMidX(k.bounds), CGRectGetMidY(k.bounds)) toView:self.view.window];
             UIView *h = [self.view.window hitTest:p withEvent:nil]; while (h && ![h isKindOfClass:[UIControl class]]) h = h.superview; ok = (h == k); }
    BOOL aedLike = [name isEqualToString:@"dae"];
    if (aedLike) SFLog(@"SELFTEST %@ tasto Layout raggiungibile (%@)", ok ? @"PASS" : @"FAIL", name);
    [self auditOverlapsIn:_alt ?: self.view name:name];
}

// autotest di un layout di dispositivo: stesso schema per tutti (azzeramento, layout, esito "decide l'istruttore", voce spenta)
- (void)runDeviceSelfTest:(NSString *)layout title:(NSString *)title after:(NSDictionary *)restore {
    [[self.view viewWithTag:7777] removeFromSuperview];
    SFLog(@"SELFTEST inizio %@", title);
    [_state resetScenario];
    [_state applyCommand:@{@"command": @"set_layout", @"value": layout} error:NULL];
    [_state applyCommand:@{@"command": @"set_defib_config", @"value": @{@"outcome_mode": @"instructor", @"voice_prompts": @NO}} error:NULL];
    [self applyLayout:layout];
    [self checkLayoutKeyNamed:layout];
    __weak MonitorViewController *me = self;
    [_alt runSelfTestWithShot:^(NSString *name) { [me saveShot:name]; } done:^(NSInteger fails) {
        MonitorViewController *m = me; if (!m) return;
        NSMutableDictionary *cfg = [@{@"outcome_mode": @"instructor", @"voice_prompts": @YES} mutableCopy]; [cfg addEntriesFromDictionary:restore ?: @{}];
        [m->_state applyCommand:@{@"command": @"set_defib_config", @"value": cfg} error:NULL];
        [m->_state resetScenario];
    }];
}
- (void)runSelfTestExtraH { [self runDeviceSelfTest:@"extrah" title:@"EXTRAH" after:nil]; }
- (void)runSelfTestDae { [self runDeviceSelfTest:@"dae" title:@"DAE" after:@{@"aed_energy_j": @150}]; }


// Schermata di avvio: montata PRIMA del primo frame (stesso disegno dell'immagine di avvio, quindi il passaggio non si vede).
// La barra segue il caricamento vero: ogni fase prepara ciò che al primo uso è lento sull'A5.
- (void)showSplash:(BOOL)staticOnly {
    [[self.view viewWithTag:7777] removeFromSuperview];
    SFSplashView *sp = [[SFSplashView alloc] initWithFrame:self.view.bounds
                                                   version:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
    sp.tag = 7777;
    [self.view addSubview:sp];
    if (staticOnly) { [sp makeStatic]; return; }
    __weak MonitorViewController *me = self;
    [sp runStages:@[
        @[@"Tracciati e parametri vitali", ^{ MonitorViewController *m = me; if (!m) return;
            m->_snap = [m->_state snapshot]; [m->_engine updateWithSnapshot:m->_snap]; [m updateNumerics]; }],
        @[@"Audio e istruzioni vocali", ^{ (void)[AVSpeechSynthesisVoice voiceWithLanguage:@"it-IT"]; }],
        @[@"Rete Wi-Fi", ^{ (void)[[SFWifi shared] currentSSID]; [me refreshNetwork]; }],
        @[@"Collegamento del controller", ^{ MonitorViewController *m = me; if (m) [m->_connect refresh]; }],   // aggiorna rete, indirizzo e PIN
    ] minStage:1.25 completion:nil];
}
// verifica da Mac: splash?static=1 (fotogramma fisso per l'immagine di avvio), splash?off=1, splash (animazione completa)
- (void)debugSplash:(NSString *)query {
    if ([query containsString:@"off=1"]) { [[self.view viewWithTag:7777] removeFromSuperview]; return; }
    [self showSplash:[query containsString:@"static=1"]];
}

- (void)saveShot:(NSString *)name {
    UIWindow *w = self.view.window;
    UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 1.0);
    [w drawViewHierarchyInRect:w.bounds afterScreenUpdates:YES];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"selftest"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    [UIImagePNGRepresentation(img) writeToFile:[dir stringByAppendingFormat:@"/%@.png", name] atomically:YES];
}

- (void)runSelfTest {
    [[self.view viewWithTag:7777] removeFromSuperview];          // niente splash durante l'autotest
    SFLog(@"SELFTEST inizio");
    [_state resetScenario];
    [_state applyCommand:@{@"command": @"set_layout", @"value": @"generic_icu"} error:NULL];
    [self applyLayout:@"generic_icu"];
    [self standbyTapped];                                         // il reset spegne il monitor: l'autotest lavora a monitor acceso
    [self auditOverlapsIn:self.view name:@"generic_icu"];
    for (NSString *k in @[@"ecg", @"spo2", @"nibp"]) [_state applyCommand:@{@"command": @"set_sensor", @"value": @{@"sensor": k, @"connected": @YES}} error:NULL];
    [_state applyCommand:@{@"command": @"set_defib_config", @"value": @{@"outcome_mode": @"instructor", @"voice_prompts": @NO}} error:NULL];
    for (UIButton *b in @[_muteButton, _drawerTab]) {
        CGPoint p = [b convertPoint:CGPointMake(CGRectGetMidX(b.bounds), CGRectGetMidY(b.bounds)) toView:self.view.window];
        UIView *hit = [self.view.window hitTest:p withEvent:nil];
        SFLog(@"SELFTEST %@ pulsante intestazione %@", hit == b ? @"PASS" : @"FAIL", [b titleForState:UIControlStateNormal]);
    }
    [self toggleMute];
    SFLog(@"SELFTEST %@ SILENZIA dall'intestazione", _state.snapshot.alarmsMuted ? @"PASS" : @"FAIL");
    [self toggleMute];
    if (!_drawerOpen) [self toggleDrawer];
    __weak MonitorViewController *me = self;
    [_drawer runSelfTestWithShot:^(NSString *name) { [me saveShot:name]; } done:^(NSInteger fails) {
        [me toggleDrawer];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [me saveShot:@"09-monitor"];
            MonitorViewController *mm = me;
            if (mm) { [mm assessCrt]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [mm updateCrt]; SFLog(@"SELFTEST %@ refill dopo la valutazione: %@", [mm->_crtValue.text isEqualToString:@"2"] ? @"PASS" : @"FAIL", mm->_crtValue.text);
                [mm saveShot:@"10-refill"]; }); }
            MonitorViewController *m = me; if (!m) return;
            [m->_state applyCommand:@{@"command": @"set_defib_config", @"value": @{@"outcome_mode": @"instructor", @"voice_prompts": @YES}} error:NULL];
            [m->_state resetScenario];
        });
    }];
}

// Pausa dal controller: schermata a tutto schermo sopra qualsiasi layout
- (void)updatePauseCover:(SLSnapshot *)s {
    BOOL paused = !s.simulationRunning;
    if (paused && !_pauseCover) {
        _pauseCover = [[UIView alloc] initWithFrame:self.view.bounds];
        _pauseCover.backgroundColor = [UIColor colorWithWhite:0 alpha:0.86];
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectInset(_pauseCover.bounds, 40, 200)];
        l.numberOfLines = 2; l.textAlignment = NSTextAlignmentCenter; l.textColor = [UIColor whiteColor];
        l.font = [UIFont boldSystemFontOfSize:88]; l.adjustsFontSizeToFitWidth = YES;
        l.text = @"Scenario in\nPAUSA";
        [_pauseCover addSubview:l];
        UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(0, _pauseCover.bounds.size.height - 150, _pauseCover.bounds.size.width, 40)];
        sub.textAlignment = NSTextAlignmentCenter; sub.textColor = [UIColor colorWithWhite:0.7 alpha:1]; sub.font = [UIFont systemFontOfSize:22];
        sub.text = @"La simulazione riprende dal controller";
        [_pauseCover addSubview:sub];
        [self.view addSubview:_pauseCover];
    }
    _pauseCover.hidden = !paused;
    if (paused) [self.view bringSubviewToFront:_pauseCover];
}

- (void)debugTap:(NSString *)k {
    if ([k isEqualToString:@"VOLUMI"]) { [self showVolumes]; return; }          // verifica da Mac: pannello volumi
    if ([k isEqualToString:@"INFO"]) { [self toggleInfo]; return; }
    if ([k isEqualToString:@"WIFI"]) { if (_infoPanel.hidden) [self toggleInfo]; [_connect showWifi]; return; }     // pagina Reti Wi-Fi
    if ([k hasPrefix:@"JOIN:"]) {                                                                                   // JOIN:nome[:password]
        NSArray<NSString *> *a = [[k substringFromIndex:5] componentsSeparatedByString:@":"];
        [_connect debugJoin:a[0] password:a.count > 1 ? a[1] : nil]; return;
    }
    if ([k isEqualToString:@"STANDBY"]) { [self standbyTapped]; return; }       // verifica da Mac: accende dallo standby
    if (_alt && !_alt.hidden && [_alt respondsToSelector:@selector(tapKey:)]) {
        NSDictionary *keys = [_alt valueForKey:@"_keys"];
        if (!keys[k]) { SFLog(@"tap %@: tasto non trovato. Tasti: %@", k, [[keys.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]); return; }
        ((BOOL (*)(id, SEL, NSString *))[_alt methodForSelector:@selector(tapKey:)])(_alt, @selector(tapKey:), k);
        return;
    }
    if ([k isEqualToString:@"DEFIB"]) { [self toggleDrawer]; return; }
    if ([k isEqualToString:@"SILENZIA"]) { [_muteButton sendActionsForControlEvents:UIControlEventTouchUpInside]; return; }
    if ([k isEqualToString:@"NIBP"]) { [_nibpButton sendActionsForControlEvents:UIControlEventTouchUpInside]; return; }
    if (!_drawerOpen) [self toggleDrawer];
    [_drawer tapNamed:k];
}

- (void)toggleDrawer {
    _drawerOpen = !_drawerOpen;
    CGFloat H = MIN(self.view.bounds.size.width, self.view.bounds.size.height);
    CGRect f = _drawer.frame;
    [_drawerTab setTitle:_drawerOpen ? @"DEFIB  ▼" : @"DEFIB  ▲" forState:UIControlStateNormal];
    _drawer.active = _drawerOpen;                      // in chiusura: nessun tocco arriva più ai pulsanti del cassetto
    _drawer.userInteractionEnabled = _drawerOpen;
    SFLog(@"cassetto %@ (modo %ld, piastre %d, carica %ld)", _drawerOpen ? @"aperto" : @"chiuso",
          (long)_snap.defib.mode, (int)_snap.padsConnected, (long)_snap.defib.charge);
    if (_drawerOpen) {
        [_drawer resetTraceAt:CACurrentMediaTime()];
        [_drawer updateWithSnapshot:_snap];
        _drawer.hidden = NO;
        f.origin.y = H; _drawer.frame = f; f.origin.y = _drawerY;
        [UIView animateWithDuration:0.25 animations:^{ self->_drawer.frame = f; }];
    } else {
        f.origin.y = H;
        [UIView animateWithDuration:0.25 animations:^{ self->_drawer.frame = f; }
                         completion:^(BOOL done) { if (!self->_drawerOpen) self->_drawer.hidden = YES; }];
    }
}

// Volumi per canale (salvati): bip ECG, bip SpO2, allarmi, suoni del monitor, istruzioni vocali
- (void)showVolumes {
    _infoPanel.hidden = YES;
    [_volPanel removeFromSuperview];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height, pw = 580, ph = 64 + SFVolCount * 56 + 60;
    _volPanel = [[UIView alloc] initWithFrame:CGRectMake((W - pw) / 2, (H - ph) / 2, pw, ph)];
    _volPanel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.97];
    _volPanel.layer.borderColor = SL_GREY.CGColor; _volPanel.layer.borderWidth = 1; _volPanel.layer.cornerRadius = 8;
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(20, 12, pw - 40, 28)];
    t.text = @"Volumi  (relativi al volume generale; salvati)"; t.textColor = SL_WHITE; t.font = [UIFont boldSystemFontOfSize:19];
    [_volPanel addSubview:t];
    for (NSInteger c = 0; c < SFVolCount; c++) {
        CGFloat y = 56 + c * 56;
        UILabel *n = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 230, 40)];
        n.text = [SoundEngine nameForChannel:(SFVolChannel)c]; n.textColor = SL_WHITE; n.font = [UIFont systemFontOfSize:15];
        n.numberOfLines = 2; n.adjustsFontSizeToFitWidth = YES; n.minimumScaleFactor = 0.7;
        [_volPanel addSubview:n];
        UISlider *sl = [[UISlider alloc] initWithFrame:CGRectMake(256, y + 4, 230, 32)];
        sl.minimumValue = 0; sl.maximumValue = 1; sl.value = (float)[_sound gainFor:(SFVolChannel)c]; sl.tag = c;
        sl.minimumTrackTintColor = SL_CYAN;
        [sl addTarget:self action:@selector(volChanged:) forControlEvents:UIControlEventValueChanged];
        [sl addTarget:self action:@selector(volPreview:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [_volPanel addSubview:sl];
        UILabel *pct = [[UILabel alloc] initWithFrame:CGRectMake(496, y, 64, 40)];
        pct.tag = 100 + c; pct.textColor = SL_CYAN; pct.font = [UIFont boldSystemFontOfSize:17]; pct.textAlignment = NSTextAlignmentRight;
        pct.text = [NSString stringWithFormat:@"%ld%%", (long)lround(sl.value * 100)];
        [_volPanel addSubview:pct];
    }
    UIButton *close = [self button:@"Chiudi" frame:CGRectMake(pw - 150, ph - 52, 130, 40) color:SL_GREY action:@selector(hideVolumes)];
    [close removeFromSuperview]; [_volPanel addSubview:close];
    [self.view addSubview:_volPanel];
}
- (void)hideVolumes { [_volPanel removeFromSuperview]; _volPanel = nil; }
- (void)volChanged:(UISlider *)sl {
    [_sound setGain:sl.value forChannel:(SFVolChannel)sl.tag];
    ((UILabel *)[_volPanel viewWithTag:100 + sl.tag]).text = [NSString stringWithFormat:@"%ld%%", (long)lround(sl.value * 100)];
}
- (void)volPreview:(UISlider *)sl {                            // prova del suono al rilascio del cursore
    switch ((SFVolChannel)sl.tag) {
        case SFVolBeepECG: [_sound beepWithFrequency:880 fromECG:YES]; break;
        case SFVolBeepSpO2: [_sound beepWithFrequency:880 fromECG:NO]; break;
        case SFVolAlarm: {
            _volAlarmPreviewUntil = CACurrentMediaTime() + 1.6;
            break;
        }
        case SFVolMonitor: [_sound valveStep]; break;
        case SFVolVoice: {
            static AVSpeechSynthesizer *sp; if (!sp) sp = [AVSpeechSynthesizer new];
            AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:@"Prova istruzioni vocali."];
            u.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"it-IT"];
            u.volume = (float)(MAX(0.3, _sound.volume) * [_sound gainFor:SFVolVoice]);
            [sp speakUtterance:u];
            break;
        }
        default: break;
    }
}

- (void)toggleInfo {
    _infoPanel.hidden = !_infoPanel.hidden;
    if (!_infoPanel.hidden) [self refreshNetwork];
    [_connect showMain];
    if (!_infoPanel.hidden) { _infoShownAt = CACurrentMediaTime(); [self updateInfoText]; [self.view bringSubviewToFront:_infoPanel]; }
}

@end
