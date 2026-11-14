#import "DefibDrawerView.h"
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import "SimulationState.h"
#import "WaveformEngine.h"
#import "SoundEngine.h"
#import "TraceView.h"
#import "SFLog.h"
#import "AltLayout.h"

#define DF_GREEN  [UIColor colorWithRed:0.20 green:1.00 blue:0.35 alpha:1]
#define DF_YELLOW [UIColor colorWithRed:1.00 green:0.88 blue:0.20 alpha:1]
#define DF_ORANGE [UIColor colorWithRed:1.00 green:0.45 blue:0.05 alpha:1]
#define DF_RED    [UIColor colorWithRed:0.95 green:0.15 blue:0.15 alpha:1]
#define DF_WHITE  [UIColor colorWithWhite:0.92 alpha:1]
#define DF_GREY   [UIColor colorWithWhite:0.45 alpha:1]
#define DF_CYAN   [UIColor colorWithRed:0.20 green:0.90 blue:1.00 alpha:1]
#define DF_BG     [UIColor colorWithWhite:0.05 alpha:1]

@implementation DefibDrawerView {
    SimulationState *_state;
    WaveformEngine *_engine;
    SoundEngine *_sound;
    SLSnapshot *_snap;
    AVSpeechSynthesizer *_speech;

    UISegmentedControl *_modeSeg;
    UIButton *_padsButton, *_closeButton;
    TraceView *_trace;
    UILabel *_hrTitle, *_hrValue, *_infoLabel, *_message, *_events;
    TraceView *_pulse; UILabel *_pulseTitle, *_pulseValue; NSInteger _pulseSrc;   // onda di polso: 0 nessuna, 1 ART, 2 pleth
    UIView *_offView, *_aedView, *_manualView, *_pacerView;
    // DAE
    UIButton *_analyzeButton, *_aedShock; UILabel *_aedCount, *_aedEnergy; UIView *_aedBar, *_aedBarFill;
    // manuale
    UILabel *_energyValue; UIButton *_chargeButton, *_shockButton, *_disarmButton, *_syncButton;
    UIView *_chargeTrack, *_chargeFill;
    // pacer
    UILabel *_rateValue, *_outValue; UISegmentedControl *_paceModeSeg; UIButton *_paceButton;

    NSUInteger _lastPrompt;
    NSInteger _lastShockCount;
    NSTimeInterval _lastSyncBeat, _lastMetronome;
    NSTimer *_repeat;
    BOOL _built;
}

- (instancetype)initWithFrame:(CGRect)frame state:(SimulationState *)state engine:(WaveformEngine *)engine sound:(SoundEngine *)sound {
    if ((self = [super initWithFrame:frame])) {
        _state = state; _engine = engine; _sound = sound;
        self.backgroundColor = DF_BG;
        self.layer.borderColor = DF_ORANGE.CGColor; self.layer.borderWidth = 2;
        _speech = [AVSpeechSynthesizer new];
        _lastShockCount = -1;
        [self build];
    }
    return self;
}

#pragma mark - Costruzione

- (UILabel *)label:(CGRect)f in:(UIView *)v size:(CGFloat)size bold:(BOOL)bold color:(UIColor *)c align:(NSTextAlignment)a {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.backgroundColor = [UIColor clearColor]; l.textColor = c; l.textAlignment = a;
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.5;
    [v addSubview:l];
    return l;
}

- (UIButton *)button:(NSString *)title frame:(CGRect)f in:(UIView *)v color:(UIColor *)c size:(CGFloat)size action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:c forState:UIControlStateNormal];
    [b setTitleColor:[UIColor blackColor] forState:UIControlStateHighlighted];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:size];
    b.titleLabel.adjustsFontSizeToFitWidth = YES; b.titleLabel.numberOfLines = 2; b.titleLabel.textAlignment = NSTextAlignmentCenter;
    b.layer.borderColor = c.CGColor; b.layer.borderWidth = 2; b.layer.cornerRadius = 8;
    b.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1];
    if (sel) [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:b];
    return b;
}

// pulsanti +/- con ripetizione tenendo premuto
- (UIButton *)stepButton:(NSString *)title frame:(CGRect)f in:(UIView *)v tag:(NSInteger)tag {
    UIButton *b = [self button:title frame:f in:v color:DF_WHITE size:34 action:nil];
    b.tag = tag;
    [b addTarget:self action:@selector(stepDown:) forControlEvents:UIControlEventTouchDown];
    [b addTarget:self action:@selector(stepUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return b;
}

- (void)build {
    CGFloat W = self.bounds.size.width;
    [self label:CGRectMake(12, 10, 190, 30) in:self size:19 bold:YES color:DF_ORANGE align:NSTextAlignmentLeft].text = @"DEFIBRILLATORE";
    _modeSeg = [[UISegmentedControl alloc] initWithItems:@[@"SPENTO", @"DAE", @"MANUALE", @"PACER"]];
    _modeSeg.frame = CGRectMake(210, 8, 440, 36);
    _modeSeg.tintColor = DF_ORANGE;
    [_modeSeg setTitleTextAttributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:15]} forState:UIControlStateNormal];
    [_modeSeg addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    [self addSubview:_modeSeg];
    _padsButton = [self button:@"" frame:CGRectMake(665, 8, 235, 36) in:self color:DF_CYAN size:15 action:@selector(togglePads)];
    _closeButton = [self button:@"▼ CHIUDI" frame:CGRectMake(W - 112, 8, 102, 36) in:self color:DF_GREY size:15 action:@selector(closeTapped)];

    __weak WaveformEngine *eng = _engine;
    __weak DefibDrawerView *weakSelf = self;
    _trace = [[TraceView alloc] initWithFrame:CGRectMake(2, 48, 700, 96)];
    _trace.traceColor = DF_GREEN; _trace.label = @"Piastre"; _trace.minValue = -0.8; _trace.maxValue = 1.6; _trace.sweepSpeed = 160;
    _trace.sampler = ^double(NSTimeInterval t) {
        DefibDrawerView *me = weakSelf; if (!me) return 0;
        SLSnapshot *s = me->_snap;
        return s.padsConnected ? [eng ecgAt:t lead:SLLeadPads] : 0;   // solo piastre: gli elettrodi sono del monitor
    };
    _trace.markerSampler = ^NSInteger(NSTimeInterval t0, NSTimeInterval t1) {
        DefibDrawerView *me = weakSelf; if (!me) return 0;
        SLSnapshot *s = me->_snap;
        if (!s.padsConnected) return 0;
        return [eng markersFrom:t0 to:t1 sync:(s.defib.mode == SLDefibManual && s.defib.sync)];
    };
    [self addSubview:_trace];
    // curva ART: mostra se la cattura del pacing genera pressione
    _pulse = [[TraceView alloc] initWithFrame:CGRectMake(2, 144, 700, 78)];
    _pulse.sweepSpeed = 160; _pulse.traceColor = [UIColor colorWithRed:1.00 green:0.23 blue:0.19 alpha:1];
    _pulse.label = @"ART  mmHg"; _pulse.disconnected = YES;
    _pulse.sampler = ^double(NSTimeInterval t) {
        DefibDrawerView *me = weakSelf; if (!me) return 0;
        return me->_pulseSrc == 1 ? [eng artAt:t] : (me->_pulseSrc == 2 ? [eng plethAt:t] : 0);
    };
    [self addSubview:_pulse];
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(704, 48, 1, 174)]; sep.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    [self addSubview:sep];
    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(0, 144, W, 1)]; sep2.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    [self addSubview:sep2];
    _hrTitle = [self label:CGRectMake(712, 50, 150, 18) in:self size:14 bold:YES color:DF_GREEN align:NSTextAlignmentLeft];
    _hrValue = [self label:CGRectMake(706, 64, 160, 80) in:self size:64 bold:YES color:DF_GREEN align:NSTextAlignmentCenter];
    _infoLabel = [self label:CGRectMake(872, 50, W - 882, 92) in:self size:14 bold:NO color:DF_WHITE align:NSTextAlignmentLeft];
    _infoLabel.numberOfLines = 4;
    _pulseTitle = [self label:CGRectMake(712, 148, 300, 18) in:self size:14 bold:YES color:DF_RED align:NSTextAlignmentLeft];
    _pulseValue = [self label:CGRectMake(706, 164, W - 716, 56) in:self size:42 bold:YES color:DF_RED align:NSTextAlignmentCenter];

    _message = [self label:CGRectMake(10, 226, W - 20, 38) in:self size:21 bold:YES color:DF_YELLOW align:NSTextAlignmentCenter];
    _message.layer.backgroundColor = [UIColor blackColor].CGColor;
    _message.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1].CGColor; _message.layer.borderWidth = 1; _message.layer.cornerRadius = 6;

    CGRect area = CGRectMake(0, 268, W, 152);
    _offView = [[UIView alloc] initWithFrame:area]; _aedView = [[UIView alloc] initWithFrame:area];
    _manualView = [[UIView alloc] initWithFrame:area]; _pacerView = [[UIView alloc] initWithFrame:area];
    for (UIView *v in @[_offView, _aedView, _manualView, _pacerView]) { v.backgroundColor = [UIColor clearColor]; [self addSubview:v]; }

    // spento
    UILabel *off = [self label:CGRectMake(40, 10, W - 80, 120) in:_offView size:19 bold:NO color:DF_GREY align:NSTextAlignmentCenter];
    off.numberOfLines = 0;
    off.text = @"DAE: semiautomatico con istruzioni vocali (analisi, carica, shock, RCP 2 minuti).\n"
                "MANUALE: scelta dell'energia, carica, shock e SYNC per la cardioversione.\n"
                "PACER: pacing transcutaneo (frequenza, corrente in mA, demand o fisso).";

    // DAE
    _analyzeButton = [self button:@"ANALIZZA" frame:CGRectMake(10, 12, 240, 100) in:_aedView color:DF_YELLOW size:28 action:@selector(dfAnalyze)];
    _aedShock = [self button:@"SHOCK" frame:CGRectMake(270, 12, 260, 100) in:_aedView color:DF_ORANGE size:34 action:@selector(dfShock)];
    _aedCount = [self label:CGRectMake(550, 12, 300, 100) in:_aedView size:46 bold:YES color:DF_WHITE align:NSTextAlignmentCenter];
    _aedEnergy = [self label:CGRectMake(860, 12, W - 870, 100) in:_aedView size:20 bold:YES color:DF_GREY align:NSTextAlignmentCenter];
    _aedEnergy.numberOfLines = 2;
    _aedBar = [[UIView alloc] initWithFrame:CGRectMake(560, 58, 280, 12)];
    _aedBar.backgroundColor = [DF_YELLOW colorWithAlphaComponent:0.2]; _aedBar.layer.cornerRadius = 4; _aedBar.hidden = YES;
    _aedBarFill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 12)]; _aedBarFill.backgroundColor = DF_YELLOW; _aedBarFill.layer.cornerRadius = 4;
    [_aedBar addSubview:_aedBarFill]; [_aedView addSubview:_aedBar];

    // manuale
    [self label:CGRectMake(82, 14, 156, 20) in:_manualView size:14 bold:YES color:DF_GREY align:NSTextAlignmentCenter].text = @"ENERGIA";
    [self stepButton:@"−" frame:CGRectMake(10, 12, 70, 96) in:_manualView tag:1];
    _energyValue = [self label:CGRectMake(82, 32, 156, 70) in:_manualView size:46 bold:YES color:DF_WHITE align:NSTextAlignmentCenter];
    [self stepButton:@"+" frame:CGRectMake(240, 12, 70, 96) in:_manualView tag:2];
    _chargeButton = [self button:@"CARICA" frame:CGRectMake(330, 12, 200, 96) in:_manualView color:DF_YELLOW size:28 action:@selector(dfCharge)];
    _chargeTrack = [[UIView alloc] initWithFrame:CGRectMake(330, 112, 200, 6)];
    _chargeTrack.backgroundColor = [DF_YELLOW colorWithAlphaComponent:0.2];
    _chargeFill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 6)]; _chargeFill.backgroundColor = DF_YELLOW;
    [_chargeTrack addSubview:_chargeFill]; [_manualView addSubview:_chargeTrack];
    _shockButton = [self button:@"SHOCK" frame:CGRectMake(550, 12, 230, 96) in:_manualView color:DF_ORANGE size:30 action:@selector(dfShock)];
    _disarmButton = [self button:@"ANNULLA\nCARICA" frame:CGRectMake(800, 12, 100, 96) in:_manualView color:DF_GREY size:16 action:@selector(dfDisarm)];
    _syncButton = [self button:@"SYNC" frame:CGRectMake(912, 12, W - 922, 96) in:_manualView color:DF_WHITE size:24 action:@selector(toggleSync)];
    UILabel *hint = [self label:CGRectMake(10, 120, W - 20, 22) in:_manualView size:13 bold:NO color:DF_GREY align:NSTextAlignmentCenter];
    hint.text = @"SYNC: lo shock parte sulla prossima onda R (▼). Senza QRS riconoscibili (FV) lo shock sincronizzato non viene erogato.";

    // pacer
    [self label:CGRectMake(10, 0, 280, 22) in:_pacerView size:15 bold:YES color:DF_WHITE align:NSTextAlignmentCenter].text = @"FREQUENZA  ppm";
    [self stepButton:@"−" frame:CGRectMake(10, 24, 70, 84) in:_pacerView tag:3];
    _rateValue = [self label:CGRectMake(82, 24, 136, 84) in:_pacerView size:46 bold:YES color:DF_WHITE align:NSTextAlignmentCenter];
    [self stepButton:@"+" frame:CGRectMake(220, 24, 70, 84) in:_pacerView tag:4];
    [self label:CGRectMake(310, 0, 280, 22) in:_pacerView size:15 bold:YES color:DF_WHITE align:NSTextAlignmentCenter].text = @"CORRENTE  mA";
    [self stepButton:@"−" frame:CGRectMake(310, 24, 70, 84) in:_pacerView tag:5];
    _outValue = [self label:CGRectMake(382, 24, 136, 84) in:_pacerView size:46 bold:YES color:DF_WHITE align:NSTextAlignmentCenter];
    [self stepButton:@"+" frame:CGRectMake(520, 24, 70, 84) in:_pacerView tag:6];
    _paceModeSeg = [[UISegmentedControl alloc] initWithItems:@[@"DEMAND", @"FISSO"]];
    _paceModeSeg.frame = CGRectMake(610, 44, 200, 44);
    _paceModeSeg.tintColor = DF_WHITE;
    [_paceModeSeg setTitleTextAttributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:16]} forState:UIControlStateNormal];
    [_paceModeSeg addTarget:self action:@selector(paceModeChanged) forControlEvents:UIControlEventValueChanged];
    [_pacerView addSubview:_paceModeSeg];
    _paceButton = [self button:@"AVVIA\nPACING" frame:CGRectMake(830, 12, W - 840, 96) in:_pacerView color:DF_GREEN size:24 action:@selector(togglePacing)];
    UILabel *phint = [self label:CGRectMake(10, 120, W - 20, 22) in:_pacerView size:13 bold:NO color:DF_GREY align:NSTextAlignmentCenter];
    phint.text = @"Aumentare i mA fino alla cattura elettrica (QRS largo + onda T dopo ogni spike), poi verificare il polso (cattura meccanica).";

    _events = [self label:CGRectMake(12, 422, W - 24, 36) in:self size:14 bold:NO color:DF_GREY align:NSTextAlignmentLeft];
    _events.numberOfLines = 2;
    _built = YES;
}

#pragma mark - Aggiornamento

static NSString *DFTime(NSInteger s) { return [NSString stringWithFormat:@"%ld:%02ld", (long)MAX(0, s) / 60, (long)MAX(0, s) % 60]; }

- (void)updateWithSnapshot:(SLSnapshot *)s {
    _snap = s;
    SLDefibInfo *d = s.defib;
    if (_modeSeg.selectedSegmentIndex != d.mode) _modeSeg.selectedSegmentIndex = d.mode;
    _offView.hidden = d.mode != SLDefibOff; _aedView.hidden = d.mode != SLDefibAED;
    _manualView.hidden = d.mode != SLDefibManual; _pacerView.hidden = d.mode != SLDefibPacer;
    [_padsButton setTitle:d.padsConnected ? @"PIASTRE COLLEGATE ✓" : @"APPLICA LE PIASTRE" forState:UIControlStateNormal];
    UIColor *pc = d.padsConnected ? DF_GREEN : DF_CYAN;
    [_padsButton setTitleColor:pc forState:UIControlStateNormal]; _padsButton.layer.borderColor = pc.CGColor;

    // traccia e FC dal monitoraggio del defibrillatore (piastre, altrimenti elettrodi)
    BOOL src = s.padsConnected;
    _trace.label = @"Piastre";
    _trace.disconnected = !src;
    _trace.noSignalText = src ? nil : @"PIASTRE NON APPLICATE";
    _hrTitle.text = @"FC  (piastre)";
    NSString *hr = @"---";
    if (src) {
        NSString *r = s.rhythm;
        if (d.paceCapture) hr = [NSString stringWithFormat:@"%ld", (long)d.paceRate];
        else if ([r isEqualToString:SLRhythmVentricularFib]) hr = @"FV";
        else if ([r isEqualToString:SLRhythmVentricularTachy] || [r isEqualToString:SLRhythmVentricularTachyPulse]) hr = @"TV";
        else if ([r isEqualToString:SLRhythmAsystole]) hr = @"Asy";
        else hr = [NSString stringWithFormat:@"%ld", (long)s.heartRate];
    }
    _hrValue.text = hr;

    _message.text = d.message;
    [self updatePulse:s];
    // manuale
    _energyValue.text = [NSString stringWithFormat:@"%ld J", (long)d.energy];
    BOOL sync = d.sync;
    [_syncButton setTitle:sync ? @"SYNC\nON" : @"SYNC\noff" forState:UIControlStateNormal];
    UIColor *sc = sync ? DF_GREEN : DF_GREY;
    [_syncButton setTitleColor:sc forState:UIControlStateNormal]; _syncButton.layer.borderColor = sc.CGColor;
    _syncButton.backgroundColor = sync ? [DF_GREEN colorWithAlphaComponent:0.15] : [UIColor colorWithWhite:0.10 alpha:1];
    _disarmButton.alpha = d.charge != SLChargeNone ? 1.0 : 0.4;
    _chargeButton.alpha = d.padsConnected ? 1.0 : 0.5;
    // DAE
    _aedEnergy.text = [NSString stringWithFormat:@"%ld J\nbifasico", (long)d.energy];
    // pacer
    _rateValue.text = [NSString stringWithFormat:@"%ld", (long)d.paceRate];
    _outValue.text = [NSString stringWithFormat:@"%ld", (long)d.paceOutput];
    _paceModeSeg.selectedSegmentIndex = d.paceDemand ? 0 : 1;
    [_paceButton setTitle:d.paceRunning ? @"FERMA\nPACING" : @"AVVIA\nPACING" forState:UIControlStateNormal];
    UIColor *pb = d.paceRunning ? DF_RED : DF_GREEN;
    [_paceButton setTitleColor:pb forState:UIControlStateNormal]; _paceButton.layer.borderColor = pb.CGColor;

    // registro: ultimi due eventi visibili al discente
    NSMutableArray *lines = [NSMutableArray array];
    for (NSDictionary *e in [d.events reverseObjectEnumerator]) {
        if ([e[@"instructor"] boolValue]) continue;
        [lines insertObject:[NSString stringWithFormat:@"%@  (%@)  %@", e[@"time"], e[@"elapsed"], e[@"text"]] atIndex:0];
        if (lines.count == 2) break;
    }
    _events.text = [lines componentsJoinedByString:@"\n"];
}

- (void)updatePulse:(SLSnapshot *)s {
    NSInteger src = s.artConnected ? 1 : 0;          // solo pressione arteriosa cruenta (la pleth resta sul monitor)
    if (src != _pulseSrc) {
        _pulseSrc = src;
        UIColor *c = src == 2 ? DF_CYAN : DF_RED;
        _pulse.traceColor = c; _pulseTitle.textColor = c; _pulseValue.textColor = c;
        if (src == 1) { _pulse.label = @"ART  mmHg"; _pulse.autoScale = 3; _pulse.showScaleLabels = YES; _pulse.minValue = 0; _pulse.maxValue = 160; }
        else { _pulse.label = @"Pleth"; _pulse.autoScale = 1; _pulse.showScaleLabels = NO; _pulse.minValue = -0.05; _pulse.maxValue = 1.05; _pulse.minSpan = 0.15; }
        [_pulse resetAtTime:CACurrentMediaTime()];
    }
    _pulse.disconnected = src == 0;
    _pulse.noSignalText = src == 0 ? @"ART NON COLLEGATA" : nil;
    if (src == 1) {
        _pulseTitle.text = @"ART  mmHg";
        NSInteger a = s.artDisplayedSystolic, b = s.artDisplayedDiastolic;
        _pulseValue.text = [NSString stringWithFormat:@"%ld/%ld (%ld)", (long)a, (long)b, (long)((a + 2 * b) / 3)];
    } else if (src == 2) {
        _pulseTitle.text = @"SpO2 %  ·  PR";
        _pulseValue.text = s.spo2Displayable ? [NSString stringWithFormat:@"%ld  ·  %ld", (long)s.spo2, (long)s.pulseRate] : @"--  ·  --";
    } else { _pulseTitle.text = @"ART  mmHg"; _pulseValue.text = @"--/--"; }
}

- (void)tick:(NSTimeInterval)now snapshot:(SLSnapshot *)s visible:(BOOL)visible {
    _snap = s;
    SLDefibInfo *d = s.defib;

    // voce del DAE
    if (d.promptSeq != _lastPrompt) {
        _lastPrompt = d.promptSeq;
        if (d.mode == SLDefibAED && d.voiceEnabled && d.voicePrompt.length) {
            [_speech stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
            AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:SFAedVoiceText(s.layout, d.voicePrompt)];   // voce nello stile del layout
            u.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"it-IT"];
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.0;
            u.volume = (float)(MAX(0.3, _sound.volume) * [_sound gainFor:SFVolVoice]);   // volume "Istruzioni vocali"
            [_speech speakUtterance:u];
            SFLog(@"voce DAE (%@): %@", s.layout, u.speechString);
        }
    }
    if (d.mode == SLDefibOff && _speech.speaking) [_speech stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];

    // suoni di carica / pronto / scarica
    if (d.charge == SLChargeCharging) [_sound setDefibTone:1 progress:d.chargeProgress];
    else if (d.charge == SLChargeReady && !d.syncPending) [_sound setDefibTone:2 progress:1];
    else [_sound setDefibTone:0 progress:0];
    if (_lastShockCount >= 0 && d.shockCount > _lastShockCount) [_sound shockSound];
    _lastShockCount = d.shockCount;

    // shock sincronizzato: erogato sulla prima onda R rilevata dopo la pressione
    if (d.syncPending) {
        NSTimeInterval b = [_engine lastBeatAtOrBefore:now];
        if (b > 0 && b >= d.syncPendingSince && b > _lastSyncBeat) { _lastSyncBeat = b; [_state defibRWaveAt:b]; }
    }

    // metronomo RCP del DAE (100/min)
    if (d.mode == SLDefibAED && d.aedPhase == SLAedCPR && now - _lastMetronome >= 60.0 / 100.0) {
        if (now - _lastMetronome > 2.0) SFLog(@"metronomo RCP 100/min avviato (%@)", s.layout);
        _lastMetronome = now; [_sound metronomeTick];
    }

    if (!visible) return;
    if (s.simulationRunning) { [_trace advanceTo:now]; [_pulse advanceTo:now]; }
    else { [_trace resetAtTime:now]; [_pulse resetAtTime:now]; }

    BOOL blink = fmod(now, 0.5) < 0.25;
    // pulsanti SHOCK lampeggianti quando carichi
    BOOL ready = d.charge == SLChargeReady && !d.syncPending;
    for (UIButton *b in @[_shockButton, _aedShock]) {
        b.alpha = ready ? 1.0 : 0.35;
        b.backgroundColor = (ready && blink) ? DF_ORANGE : [UIColor colorWithWhite:0.10 alpha:1];
        [b setTitleColor:(ready && blink) ? [UIColor blackColor] : DF_ORANGE forState:UIControlStateNormal];
    }
    _chargeTrack.hidden = d.charge == SLChargeNone;      // la barra compare solo durante la carica / da carico
    CGRect f = _chargeTrack.bounds; f.size.width *= d.chargeProgress; _chargeFill.frame = f;
    _chargeFill.backgroundColor = d.charge == SLChargeReady ? DF_ORANGE : DF_YELLOW;
    _message.text = d.message;

    // conto alla rovescia del DAE
    if (d.mode == SLDefibAED) {
        if (d.aedPhase == SLAedCPR) _aedCount.text = [NSString stringWithFormat:@"RCP  %@", DFTime(d.aedRemaining)];
        else if (d.aedPhase == SLAedAnalyzing) _aedCount.text = @"ANALISI…";
        else if (d.aedPhase == SLAedCharging) _aedCount.text = @"";            // solo la barra di carica
        else if (d.aedPhase == SLAedReady) _aedCount.text = @"PREMERE SHOCK";
        else _aedCount.text = @"";
        _aedCount.textColor = d.aedPhase == SLAedReady && blink ? DF_ORANGE : DF_WHITE;
        _aedBar.hidden = d.aedPhase != SLAedCharging;
        _aedBarFill.frame = CGRectMake(0, 0, 280 * d.chargeProgress, 12);
    }
    // riquadro informazioni: shock, ultimo shock, tempo dall'accensione
    NSInteger el = d.sessionStart > 0 ? (NSInteger)(now - d.sessionStart) : 0;
    _infoLabel.text = [NSString stringWithFormat:@"Shock: %ld\nUltimo: %@\nTempo: %@%@",
                       (long)d.shockCount,
                       d.shockCount ? [NSString stringWithFormat:@"%ld J%@", (long)d.lastShockEnergy, d.lastShockSynced ? @" sync" : @""] : @"—",
                       d.sessionStart > 0 ? DFTime(el) : @"—",
                       d.lastShockAt > 0 ? [NSString stringWithFormat:@"\nda ultimo: %@", DFTime((NSInteger)(now - d.lastShockAt))] : @""];
}

- (void)resetTraceAt:(NSTimeInterval)t { [_trace resetAtTime:t]; [_pulse resetAtTime:t]; }

#pragma mark - Azioni

- (void)cmd:(NSString *)name value:(id)value {
    if (!self.active) { SFLog(@"cassetto: %@ IGNORATO (cassetto chiuso o in chiusura)", name); return; }
    NSMutableDictionary *c = [@{@"command": name} mutableCopy];
    if (value) c[@"value"] = value;
    BOOL ok = [_state applyCommand:c error:NULL];       // gli errori diventano messaggi sul display (modello)
    SFLog(@"cassetto: %@ %@ -> %@", name, value ?: @"", ok ? @"ok" : @"rifiutato");
}

- (void)modeChanged {
    NSArray *m = @[@"off", @"aed", @"manual", @"pacer"];
    [self cmd:@"defib_mode" value:m[(NSUInteger)_modeSeg.selectedSegmentIndex]];
}
- (void)togglePads { [self cmd:@"set_sensor" value:@{@"sensor": @"pads", @"connected": @((BOOL)!_snap.padsConnected)}]; }
- (void)closeTapped { if (self.onClose) self.onClose(); }
// NB: nomi con prefisso "df": su iOS 9 UIKit invoca da solo -charge sulle viste durante i tocchi
// (proprietà delle dinamiche), e un'azione chiamata "charge" faceva caricare il defibrillatore a ogni tocco nel cassetto.
- (void)dfAnalyze { [self cmd:@"defib_analyze" value:nil]; }
- (void)dfCharge { [self cmd:@"defib_charge" value:nil]; }
- (void)dfShock { [self cmd:@"defib_shock" value:nil]; }
- (void)dfDisarm { [self cmd:@"defib_disarm" value:nil]; }
- (void)toggleSync { [self cmd:@"defib_sync" value:@((BOOL)!_snap.defib.sync)]; }
- (void)togglePacing { [self cmd:@"defib_pacer" value:@{@"running": @((BOOL)!_snap.defib.paceRunning)}]; }
- (void)paceModeChanged { [self cmd:@"defib_pacer" value:@{@"demand": @((BOOL)(_paceModeSeg.selectedSegmentIndex == 0))}]; }

- (void)stepTag:(NSInteger)tag {
    SLDefibInfo *d = _snap.defib;
    if (tag == 1 || tag == 2) {
        NSArray<NSNumber *> *list = [SimulationState defibEnergies];
        NSInteger i = (NSInteger)[list indexOfObject:@(d.energy)];
        if (i == NSNotFound) i = (NSInteger)[list indexOfObject:@150];
        i = MAX(0, MIN((NSInteger)list.count - 1, i + (tag == 2 ? 1 : -1)));
        [self cmd:@"defib_energy" value:list[(NSUInteger)i]];
    } else if (tag == 3 || tag == 4) {
        [self cmd:@"defib_pacer" value:@{@"rate": @(MAX(30, MIN(180, d.paceRate + (tag == 4 ? 5 : -5))))}];
    } else if (tag == 5 || tag == 6) {
        [self cmd:@"defib_pacer" value:@{@"output_ma": @(MAX(0, MIN(200, d.paceOutput + (tag == 6 ? 5 : -5))))}];
    }
    _snap = [_state snapshot];
    [self updateWithSnapshot:_snap];
}

- (void)stepDown:(UIButton *)b {
    [self stepTag:b.tag];
    [_repeat invalidate];
    _repeat = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(repeatStart:) userInfo:@(b.tag) repeats:NO];
}
- (void)repeatStart:(NSTimer *)t {
    NSNumber *tag = t.userInfo;
    _repeat = [NSTimer scheduledTimerWithTimeInterval:0.12 target:self selector:@selector(repeatStep:) userInfo:tag repeats:YES];
}
- (void)repeatStep:(NSTimer *)t {
    if (!self.window || self.hidden) { [t invalidate]; _repeat = nil; return; }
    [self stepTag:[t.userInfo integerValue]];
}
- (void)willMoveToWindow:(UIWindow *)w { if (!w) { [_repeat invalidate]; _repeat = nil; } }
- (void)stepUp:(UIButton *)b { [_repeat invalidate]; _repeat = nil; }

#pragma mark - Autotest

// Tocco simulato: hit-test della finestra nel centro del controllo atteso, poi azioni del controllo colpito
- (BOOL)tap:(UIView *)target name:(NSString *)name {
    UIWindow *w = self.window;
    CGPoint p = [target convertPoint:CGPointMake(CGRectGetMidX(target.bounds), CGRectGetMidY(target.bounds)) toView:w];
    UIView *hit = [w hitTest:p withEvent:nil];
    UIView *c = hit; while (c && ![c isKindOfClass:[UIControl class]]) c = c.superview;
    BOOL ok = c == target;
    SFLog(@"SELFTEST tocco %@ @(%.0f,%.0f) -> %@ %@", name, p.x, p.y, NSStringFromClass([hit class]),
          ok ? @"OK" : [NSString stringWithFormat:@"SBAGLIATO (controllo colpito: %@ '%@')", NSStringFromClass([c class]),
                        [c isKindOfClass:[UIButton class]] ? [(UIButton *)c titleForState:UIControlStateNormal] : @""]);
    if ([c isKindOfClass:[UIControl class]]) {
        [(UIControl *)c sendActionsForControlEvents:UIControlEventTouchDown];
        [(UIControl *)c sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
    _snap = [_state snapshot]; [self updateWithSnapshot:_snap];
    return ok;
}

- (BOOL)tapNamed:(NSString *)n {
    NSDictionary *m = @{ @"CARICA": _chargeButton, @"SHOCK": (_snap.defib.mode == SLDefibAED ? _aedShock : _shockButton),
                         @"ANALIZZA": _analyzeButton, @"ANNULLA": _disarmButton, @"SYNC": _syncButton,
                         @"PIASTRE": _padsButton, @"CHIUDI": _closeButton, @"PACING": _paceButton };
    if ([n hasPrefix:@"MODO:"]) {
        NSUInteger i = [@[@"off", @"aed", @"manual", @"pacer"] indexOfObject:[n substringFromIndex:5]];
        return i != NSNotFound && [self tapSegment:_modeSeg index:(NSInteger)i name:n];
    }
    UIView *t = m[n]; if (!t) { SFLog(@"tap: tasto del cassetto sconosciuto %@ (noti: %@)", n, [m.allKeys componentsJoinedByString:@","]); return NO; }
    return [self tap:t name:n];
}

- (BOOL)tapSegment:(UISegmentedControl *)seg index:(NSInteger)i name:(NSString *)name {
    UIWindow *w = self.window;
    CGFloat sw = seg.bounds.size.width / seg.numberOfSegments;
    CGPoint p = [seg convertPoint:CGPointMake(sw * (i + 0.5), CGRectGetMidY(seg.bounds)) toView:w];
    UIView *hit = [w hitTest:p withEvent:nil];
    UIView *c = hit; while (c && ![c isKindOfClass:[UIControl class]]) c = c.superview;
    BOOL ok = c == seg;
    SFLog(@"SELFTEST segmento %@ -> %@", name, ok ? @"OK" : NSStringFromClass([c class]));
    if (ok) { seg.selectedSegmentIndex = i; [seg sendActionsForControlEvents:UIControlEventValueChanged]; }
    _snap = [_state snapshot]; [self updateWithSnapshot:_snap];
    return ok;
}

- (void)runSelfTestWithShot:(void (^)(NSString *))shot done:(void (^)(NSInteger))done {
    __block NSInteger fails = 0;
    DefibDrawerView *me = self;          // autotest breve: riferimento forte, rilasciato a fine sequenza
    SimulationState *st = _state;
    void (^check)(BOOL, NSString *) = ^(BOOL c, NSString *what) {
        if (!c) fails++;
        SFLog(@"SELFTEST %@ %@", c ? @"PASS" : @"FAIL", what);
    };
    void (^set)(NSString *, id) = ^(NSString *cmd, id v) {
        NSMutableDictionary *d = [@{@"command": cmd} mutableCopy]; if (v) d[@"value"] = v; [st applyCommand:d error:NULL];
    };
    SLDefibInfo *(^D)(void) = ^SLDefibInfo *{ return [st snapshot].defib; };
    // passi: {ritardo dal passo precedente, azione}
    NSMutableArray *steps = [NSMutableArray array];
    void (^step)(double, dispatch_block_t) = ^(double delay, dispatch_block_t b) { [steps addObject:@[@(delay), [b copy]]]; };

    step(0.6, ^{ shot(@"01-cassetto-spento"); check(D().mode == SLDefibOff, @"cassetto aperto, spento"); });
    step(0.3, ^{ check([me tap:me->_padsButton name:@"PIASTRE"] && D().padsConnected, @"piastre applicate"); });
    step(0.3, ^{ check([me tapSegment:me->_modeSeg index:2 name:@"MANUALE"] && D().mode == SLDefibManual, @"modalità manuale"); });
    step(0.3, ^{ check([me tap:me->_syncButton name:@"SYNC (da scarico)"] && D().sync && D().charge == SLChargeNone, @"SYNC ON da scarico: nessuna carica"); });
    step(3.0, ^{ check(D().sync && D().charge == SLChargeNone, @"SYNC ON: dopo 3 s ancora scarico"); shot(@"02a-sync-on-scarico");
                 check([me tap:me->_syncButton name:@"SYNC off"] && !D().sync && D().charge == SLChargeNone, @"SYNC off: nessuna carica"); });
    step(0.3, ^{ set(@"set_rhythm", @"afib"); check([me tap:me->_chargeButton name:@"CARICA"] && D().charge == SLChargeCharging, @"CARICA avvia la carica"); });
    step(6.5, ^{ check(D().charge == SLChargeReady, @"carico dopo ~4 s"); shot(@"02-manuale-carico"); });
    step(0.3, ^{ check([me tap:me->_syncButton name:@"SYNC"] && D().sync && D().charge == SLChargeReady, @"SYNC attiva il sync e NON ricarica"); });
    step(0.3, ^{ check([me tap:me->_disarmButton name:@"ANNULLA CARICA"] && D().charge == SLChargeNone, @"ANNULLA CARICA disarma"); });
    step(0.3, ^{ check([me tap:me->_chargeButton name:@"CARICA"] && D().charge == SLChargeCharging, @"seconda carica"); });
    step(6.5, ^{ check([me tap:me->_shockButton name:@"SHOCK"], @"SHOCK premuto (sync)"); });
    step(3.5, ^{ SLDefibInfo *d = D(); check(d.shockCount == 1 && d.lastShockSynced && !d.syncPending, @"scarica sincronizzata erogata sull'onda R"); shot(@"03-dopo-sync"); });
    step(0.3, ^{ set(@"defib_sync", @NO); set(@"set_rhythm", @"vf");
                 check([me tap:me->_chargeButton name:@"CARICA"], @"carica per FV"); });
    step(6.5, ^{ check([me tap:me->_shockButton name:@"SHOCK"] && D().shockCount == 2 && !D().lastShockSynced, @"SHOCK asincrono erogato subito"); });
    step(0.3, ^{ NSInteger e0 = D().energy; [me stepTag:2]; [me stepTag:2];
                 check(D().energy > e0, @"energia +"); [me stepTag:1]; [me stepTag:1]; check(D().energy == e0, @"energia −"); });
    step(0.3, ^{ check([me tapSegment:me->_modeSeg index:3 name:@"PACER"] && D().mode == SLDefibPacer, @"modalità pacer"); shot(@"04-pacer"); });
    step(0.3, ^{ set(@"set_rhythm", @"sinus_bradycardia"); set(@"set_sensor", @{@"sensor": @"art", @"connected": @YES});
                 for (int i = 0; i < 16; i++) [me stepTag:6];
                 check(D().paceOutput == 80, [NSString stringWithFormat:@"corrente 80 mA (%ld)", (long)D().paceOutput]);
                 check([me tap:me->_paceButton name:@"AVVIA PACING"] && D().paceRunning, @"AVVIA PACING"); });
    step(0.5, ^{ SLDefibInfo *d = D(); check(d.paceActive && d.paceCapture && d.paceMechanical && [st snapshot].displayedHeartRate == 70,
                 @"pacing attivo con cattura a 70"); });
    step(4.0, ^{ shot(@"05-pacing-cattura"); check([st snapshot].pulsePresent && me->_pulseSrc == 1, @"cattura meccanica: polso e onda ART nel cassetto"); });
    step(0.3, ^{ set(@"set_defib_config", @{@"mechanical_capture": @NO}); set(@"set_rhythm", @"asystole");
                 check(D().paceCapture && ![st snapshot].pulsePresent, @"solo cattura elettrica: nessun polso"); });
    step(4.0, ^{ shot(@"05b-pacing-solo-elettrica"); set(@"set_defib_config", @{@"mechanical_capture": @YES});
                 check([me tap:me->_paceButton name:@"FERMA PACING"] && !D().paceRunning, @"FERMA PACING"); });
    step(0.3, ^{ set(@"set_rhythm", @"vf"); check([me tapSegment:me->_modeSeg index:1 name:@"DAE"] && D().aedPhase == SLAedAnalyzing, @"DAE: analisi"); });
    step(4.0, ^{ shot(@"06-dae-analisi"); });
    step(12.0, ^{ check(D().charge == SLChargeReady && D().aedPhase == SLAedReady, @"DAE: shock consigliato e carico"); shot(@"07-dae-pronto"); });
    step(0.3, ^{ check([me tap:me->_aedShock name:@"SHOCK DAE"] && D().aedPhase == SLAedCPR, @"DAE: scarica e RCP"); });
    step(1.5, ^{ shot(@"08-dae-rcp"); check([me tapSegment:me->_modeSeg index:0 name:@"SPENTO"] && D().mode == SLDefibOff, @"spento"); });

    // tutti i passi programmati in anticipo a tempi cumulativi (nessun blocco ricorsivo)
    double at = 0;
    for (NSArray *sp in steps) {
        at += [sp[0] doubleValue];
        dispatch_block_t b = sp[1];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(at * NSEC_PER_SEC)), dispatch_get_main_queue(), b);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((at + 0.2) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SFLog(@"SELFTEST FINE: %ld errori", (long)fails);
        done(fails);
    });
}

@end
