#import "SimulationState.h"

NSString *const SLRhythmSinus              = @"sinus";
NSString *const SLRhythmSinusTachycardia   = @"sinus_tachycardia";
NSString *const SLRhythmSinusBradycardia   = @"sinus_bradycardia";
NSString *const SLRhythmAtrialFibrillation = @"afib";
NSString *const SLRhythmVentricularTachy   = @"vt";
NSString *const SLRhythmVentricularTachyPulse = @"vt_pulse";
NSString *const SLRhythmVentricularFib     = @"vf";
NSString *const SLRhythmAsystole           = @"asystole";
NSString *const SLRhythmPEA                = @"pea";

NSString *const SLSensorECG   = @"ecg";
NSString *const SLSensorSpO2  = @"spo2";
NSString *const SLSensorOxi   = @"oxi";
NSString *const SLSensorNIBP  = @"nibp";
NSString *const SLSensorEtCO2 = @"etco2";
NSString *const SLSensorART   = @"art";
NSString *const SLSensorTemp  = @"temp";
NSString *const SLSensorPads  = @"pads";

// Defibrillatore: tempi (s)
static const double kAedAnalysisTime = 8.0;     // analisi del ritmo del DAE
static const double kAedReadyTimeout = 60.0;    // DAE carico: se non si preme SHOCK entro 60 s, carica annullata
static const double kManualReadyTimeout = 60.0; // manuale carico: scarica interna dopo 60 s
static double SLChargeTime(NSInteger j) { return 1.0 + j * 0.02; }   // 150 J ~4 s, 200 J ~5 s

// Range di validazione (valori simulati)
static const NSInteger kHRMin = 0,    kHRMax = 300;
static const NSInteger kSpO2Min = 0,  kSpO2Max = 100;
static const NSInteger kRRMin = 0,    kRRMax = 60;
static const NSInteger kEtCO2Min = 0, kEtCO2Max = 150;
static const NSInteger kSysMin = 0,   kSysMax = 300;
static const NSInteger kDiaMin = 0,   kDiaMax = 200;

// Profilo NIBP (oscillometrico simulato)
static const double kNibpStep = 8.0;        // mmHg per gradino
static const double kNibpStepTime = 1.1;    // s per gradino
static const double kNibpDumpTime = 1.6;    // s scarico finale
static const double kNibpLeakTime = 5.0;    // s di tentativo con bracciale non collegato

// validatori (definiti più avanti)
static BOOL SLIntValue(id v, NSInteger min, NSInteger max, NSInteger *out, NSString *name, NSString **err);
static BOOL SLBoolValue(id v, BOOL *out, NSString *name, NSString **err);

// lato del corpo di una posizione: "upper_arm_r" / "finger_r3" / "radial_l" -> "r" / "l"; nil se centrale
static NSString *SLSiteSide(NSString *site) {
    if (![site isKindOfClass:[NSString class]]) return nil;
    for (NSString *tok in [site componentsSeparatedByString:@"_"]) {
        if (tok.length >= 1 && ([tok hasPrefix:@"r"] || [tok hasPrefix:@"l"]) &&
            (tok.length == 1 || [[tok substringFromIndex:1] rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound))
            return [tok substringToIndex:1];
    }
    return nil;
}

// posizione di serie quando una regia collega il sensore senza dire dove (uguale in tutte le regie)
static NSString *SLDefaultSite(NSString *sensor) {
    return @{ @"spo2": @"finger_l2", @"nibp": @"upper_arm_r", @"art": @"radial_l", @"oxi": @"finger_r2" }[sensor];
}
// la linea arteriosa è a valle di un bracciale sul braccio dello stesso lato (radiale, ulnare, brachiale)
static BOOL SLArmArterySite(NSString *site) {
    return [site isKindOfClass:[NSString class]] && ([site hasPrefix:@"radial"] || [site hasPrefix:@"ulnar"] || [site hasPrefix:@"brachial"]);
}

#pragma mark - Snapshot

@interface SLSnapshot ()
@property (nonatomic, readwrite) NSUInteger revision;
@property (nonatomic, readwrite, copy) NSString *rhythm;
@property (nonatomic, readwrite) NSInteger heartRate, spo2, respRate, etco2, systolic, diastolic;
@property (nonatomic, readwrite) BOOL spo2SignalValid, spo2SignalSetting, spo2CuffOccluded, artCuffOccluded;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSString *> *sensorSites;
@property (nonatomic, readwrite) BOOL ecgConnected, spo2Connected, nibpConnected, etco2Connected, artConnected;
@property (nonatomic, readwrite) BOOL oxiConnected, oxiCuffOccluded, oxiPower, oxiOnline;
@property (nonatomic, readwrite) NSTimeInterval oxiSensorSince;
@property (nonatomic, readwrite) NSInteger oxiVolume, oxiMutedRemaining;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSNumber *> *oxiLimits;
@property (nonatomic, readwrite) BOOL tempConnected, padsConnected;
@property (nonatomic, readwrite) NSInteger spo2DelaySec, temperatureTenths, crtTenths;
@property (nonatomic, readwrite) BOOL spo2Searching, spo2Acquiring, spo2LowPerfusionFlag, crtEnabled;
@property (nonatomic, readwrite) NSInteger crtAssessSeq;
@property (nonatomic, readwrite) NSInteger patientMotion, patientMotionRemaining;
@property (nonatomic, readwrite) BOOL operatorTouch;
@property (nonatomic, readwrite, copy) NSString *layout;
@property (nonatomic, readwrite) BOOL devicePowered;
@property (nonatomic, readwrite, strong) SLDefibInfo *defib;
@property (nonatomic, readwrite) SLNibpStatus nibpStatus;
@property (nonatomic, readwrite, copy) NSString *nibpError;
@property (nonatomic, readwrite) NSInteger nibpLastSystolic, nibpLastDiastolic;
@property (nonatomic, readwrite) NSTimeInterval nibpStartedAt;
@property (nonatomic, readwrite) NSDate *nibpMeasuredAt;
@property (nonatomic, readwrite) BOOL alarmsMuted, qrsBeepEnabled, simulationRunning;
@property (nonatomic, readwrite) NSTimeInterval scenarioTime;
@property (nonatomic, readwrite) NSInteger volume;
@property (nonatomic, readwrite) NSInteger alarmsMutedRemaining;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSNumber *> *alarmLimits;
@property (nonatomic, readwrite) BOOL autoPhysiology;
@property (nonatomic, readwrite) BOOL cprActive, ventilationManual;
@property (nonatomic, readwrite, copy) NSArray<NSNumber *> *breathTimes;
@property (nonatomic, readwrite) double respRateSet;
@property (nonatomic, readwrite) NSInteger etco2Set;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSNumber *> *alarmEnabled;
@property (nonatomic, readwrite) NSInteger nibpIntervalMin;
@property (nonatomic, readwrite) NSTimeInterval nibpNextAt;
@property (nonatomic, readwrite, copy) NSDictionary *transitions, *chain;
// parametri del ciclo NIBP fissati all'avvio
@property (nonatomic) double nibpTarget, nibpEnd;
@property (nonatomic) BOOL nibpCuffOK;
@end

@interface SLDefibInfo ()
@property (nonatomic, readwrite) SLDefibMode mode;
@property (nonatomic, readwrite) BOOL pacePaused, paceLeadsOff;
@property (nonatomic, readwrite) NSInteger paceSetRate;
@property (nonatomic, readwrite) BOOL padsConnected, sync, syncPending, aedShockAdvised, lastShockSynced, paceDemand, paceRunning,
                                 paceActive, paceCapture, paceMechanical, voiceEnabled;
@property (nonatomic, readwrite) NSInteger energy, chargedEnergy, aedRemaining, shockCount, lastShockEnergy, paceRate, paceOutput;
@property (nonatomic, readwrite) SLDefibCharge charge;
@property (nonatomic, readwrite) double chargeProgress;
@property (nonatomic, readwrite) NSTimeInterval syncPendingSince, lastShockAt, sessionStart;
@property (nonatomic, readwrite) SLAedPhase aedPhase;
@property (nonatomic, readwrite, copy) NSString *message, *voicePrompt;
@property (nonatomic, readwrite) NSUInteger promptSeq;
@property (nonatomic, readwrite, copy) NSArray<NSDictionary *> *events;
@end
@implementation SLDefibInfo
@end

@implementation SLSnapshot
- (NSInteger)limit:(NSString *)key { return [self.alarmLimits[key] integerValue]; }
- (NSInteger)pulseRate {
    if (self.defib.paceMechanical) return self.defib.paceRate;   // pacing con cattura meccanica
    // FA rapida: alcuni battiti non generano un polso periferico valido (deficit di polso)
    if ([self.rhythm isEqualToString:SLRhythmAtrialFibrillation] && self.heartRate > 100)
        return (NSInteger)lround(self.heartRate * (1.0 - MIN(0.25, (self.heartRate - 100) / 400.0)));
    return self.heartRate;
}
- (BOOL)alarmOn:(NSString *)param { NSNumber *n = self.alarmEnabled[param]; return n ? n.boolValue : YES; }
// Polso: dal ritmo; durante il pacing con cattura decide la cattura meccanica (QRS stimolati che generano pressione o no)
- (BOOL)pulsePresent { return self.defib.paceCapture ? self.defib.paceMechanical : [SimulationState rhythmHasPulse:self.rhythm]; }
- (BOOL)ecgOrganized {
    return !([self.rhythm isEqualToString:SLRhythmVentricularFib] || [self.rhythm isEqualToString:SLRhythmAsystole]);
}
- (BOOL)spo2Displayable { return self.spo2Connected && self.spo2SignalValid && self.pulsePresent && !self.spo2Acquiring; }
- (BOOL)lowPerfusion { return self.spo2Displayable && (self.systolic < 70 || self.spo2LowPerfusionFlag || self.patientMotion == 2); }
- (NSInteger)displayedHeartRate {
    if (!self.ecgConnected) return -1;                       // elettrodi staccati
    if (self.defib.paceCapture) return self.defib.paceRate;  // il monitor conta i battiti stimolati
    if ([self.rhythm isEqualToString:SLRhythmVentricularFib]) return -1;
    if ([self.rhythm isEqualToString:SLRhythmAsystole]) return 0;
    return self.heartRate;
}
- (NSInteger)meanArterialPressure {
    if (self.nibpLastSystolic < 0 || self.nibpLastDiastolic < 0) return -1;
    return (self.nibpLastSystolic + 2 * self.nibpLastDiastolic) / 3;
}
- (NSInteger)artDisplayedSystolic {
    if (!self.artConnected) return -1;
    if (self.artCuffOccluded) return 26;                     // bracciale chiuso a monte: curva piatta, nessuna pulsatilità
    return self.pulsePresent ? self.systolic : 20;           // arresto: pressione di riempimento sistemico
}
- (NSInteger)artDisplayedDiastolic {
    if (!self.artConnected) return -1;
    if (self.artCuffOccluded) return 24;
    return self.pulsePresent ? self.diastolic : 18;
}

static double SLNibpTotalDuration(SLSnapshot *s) {
    if (!s.nibpCuffOK) return kNibpLeakTime;
    double inflate = 2.0 + s.nibpTarget / 40.0;
    double steps = ceil((s.nibpTarget - s.nibpEnd) / kNibpStep);
    return inflate + steps * kNibpStepTime + kNibpDumpTime;
}

- (SLNibpPhase)nibpPhaseAt:(NSTimeInterval)t pressure:(double *)pressure step:(NSInteger *)step {
    if (pressure) *pressure = 0;
    if (step) *step = -1;
    if (self.nibpStatus != SLNibpMeasuring) return SLNibpPhaseNone;
    double el = t - self.nibpStartedAt;
    if (el < 0) el = 0;
    if (!self.nibpCuffOK) {                                   // bracciale staccato: la pompa gira a vuoto
        if (pressure) *pressure = MIN(4.0, el * 2.0);
        return el < kNibpLeakTime ? SLNibpPhaseInflating : SLNibpPhaseDone;
    }
    double inflate = 2.0 + self.nibpTarget / 40.0;
    if (el < inflate) {
        if (pressure) *pressure = self.nibpTarget * pow(el / inflate, 0.85);
        return SLNibpPhaseInflating;
    }
    el -= inflate;
    NSInteger steps = (NSInteger)ceil((self.nibpTarget - self.nibpEnd) / kNibpStep);
    if (el < steps * kNibpStepTime) {
        NSInteger k = (NSInteger)floor(el / kNibpStepTime);
        double within = el - k * kNibpStepTime;
        double hi = self.nibpTarget - k * kNibpStep, lo = MAX(self.nibpEnd, hi - kNibpStep);
        double p = within < 0.18 ? hi - (hi - lo) * (within / 0.18) : lo;   // la valvola scarica in ~180 ms
        if (pressure) *pressure = p;
        if (step) *step = k;
        return SLNibpPhaseDeflating;
    }
    el -= steps * kNibpStepTime;
    if (el < kNibpDumpTime) {
        if (pressure) *pressure = self.nibpEnd * exp(-el * 3.0);
        return SLNibpPhaseDumping;
    }
    return SLNibpPhaseDone;
}
@end

#pragma mark - SimulationState

@implementation SimulationState {
    NSUInteger _revision;
    NSString *_rhythm;
    NSInteger _hr, _spo2, _rr, _etco2, _sys, _dia, _volume;
    BOOL _spo2Valid, _muted, _running, _qrsBeep;
    double _scenAccum;                         // secondi di scenario accumulati nelle fasi "in corsa"
    NSTimeInterval _scenSince;                 // clock dell'ultima ripresa (0 = in pausa)
    BOOL _ecgOn, _spo2On, _nibpOn, _etco2On, _artOn;
    NSMutableDictionary<NSString *, NSString *> *_sites;   // sensore -> posizione sul paziente
    NSTimeInterval _mutedUntil;
    SLNibpStatus _nibpStatus;
    NSString *_nibpError;
    NSTimeInterval _nibpStartedAt;
    double _nibpTarget, _nibpEnd;
    BOOL _nibpCuffOK;
    NSInteger _nibpLastSys, _nibpLastDia;
    NSDate *_nibpMeasuredAt;
    NSMutableDictionary<NSString *, NSNumber *> *_limits;
    // transizioni (rampe lineari) e catene
    NSMutableDictionary<NSString *, NSDictionary *> *_ramps;   // param -> {from,to,start,dur}
    BOOL _autoPhysio;
    NSDictionary<NSString *, NSNumber *> *_baseline;           // valori pre-arresto per il ROSC
    NSArray<NSDictionary *> *_chainSteps;
    NSString *_chainName;
    NSInteger _chainIndex;
    NSTimeInterval _chainPhaseStart;
    BOOL _chainActive, _chainWaiting;
    NSTimeInterval _rampStartOverride;
    NSMutableDictionary<NSString *, NSNumber *> *_alarmOn;   // configurazione del monitor (non si azzera col reset)
    NSInteger _nibpInterval;
    NSTimeInterval _nibpNext;
    BOOL _cpr;
    NSInteger _dEvSeq;                            // numero progressivo degli eventi del defibrillatore
    NSMutableArray<NSNumber *> *_breaths;          // insufflazioni segnalate dall'istruttore (ventilazione manuale)
    NSMutableArray<NSDictionary *> *_scheduled;      // rampe programmate nel futuro (es. picco EtCO2 al ROSC)
    NSTimeInterval _apneaSince; NSInteger _spo2PreApnea;
    // sonde aggiuntive, acquisizione SpO2, temperatura, refill
    BOOL _tempOn, _padsOn, _spo2LowPerf;
    // saturimetro palmare (SimulaFranz_Saturimetro): sensore, accensione, limiti, volume, silenziamento, ultimo contatto
    BOOL _oxiOn, _oxiPower; NSTimeInterval _oxiConnAt, _oxiMutedUntil, _oxiSeenAt; NSInteger _oxiVolume;
    NSMutableDictionary<NSString *, NSNumber *> *_oxiLimits;
    NSInteger _motion; NSTimeInterval _motionUntil, _aedMotionSaidAt, _touchUntil; BOOL _nibpMotionHit;
    NSInteger _spo2Delay, _spo2Stage;            // stage: 1 ricerca, 2 acquisizione, 3 valore pronto
    NSTimeInterval _spo2ConnAt;
    NSInteger _tempT, _crtT;
    BOOL _crtOn; NSString *_layout; NSInteger _crtSeq;              // impostazioni del monitor: non si azzerano con il reset
    // defibrillatore
    SLDefibMode _dMode;
    NSInteger _dEnergy, _dChargedEnergy;
    SLDefibCharge _dCharge;
    NSTimeInterval _dChargeStart, _dChargeDur, _dReadyAt;
    BOOL _dSync, _dSyncPending; NSTimeInterval _dSyncSince;
    SLAedPhase _aedPhase; NSTimeInterval _aedPhaseStart; BOOL _aedAdvised, _aedMotion;
    NSString *_dNote; NSTimeInterval _dNoteAt;   // messaggio transitorio (shock erogato, carica annullata...)
    NSString *_dVoice; NSUInteger _dPromptSeq;
    NSInteger _dShocks, _dLastEnergy; NSTimeInterval _dLastShock, _dSession; BOOL _dLastSync;
    NSInteger _pRate, _pOut; BOOL _pDemand, _pRun, _pPaused;
    NSMutableArray<NSDictionary *> *_dEvents;
    NSString *_dEpisode; NSInteger _dEff, _cvEff;
    BOOL _dDecision; NSString *_dDecisionFrom; NSInteger _dDecisionShock, _dDecisionEnergy; BOOL _dDecisionSync;   // esito dello shock in attesa dell'istruttore
    NSMutableDictionary *_dCfg;                  // configurazione dell'istruttore (non si azzera col reset)
}

+ (NSArray<NSNumber *> *)nibpIntervals { return @[@0, @1, @2, @3, @5, @10, @15, @30, @60]; }
// Energie selezionabili (bifasico; 300/360 J come i alcuni dispositivi)
// Layout con il nome mostrato nei menu (monitor e controller): i controller leggono questo elenco dallo stato,
// così i nomi stanno in un posto solo. I primi tre sono i layout ORIGINALI di similFranz; quelli che seguono
// (repliche di dispositivi in commercio) esistono solo nella versione privata: con SF_PUBLIC non vengono compilati.
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)layoutCatalog {
    NSMutableArray *a = [@[@{@"id": @"generic_icu", @"name": @"ICU"}, @{@"id": @"extrah", @"name": @"extraH"}, @{@"id": @"dae", @"name": @"DAE"}] mutableCopy];
    return a;
}
+ (NSArray<NSString *> *)supportedLayouts { return [[self layoutCatalog] valueForKey:@"id"]; }

+ (NSArray<NSNumber *> *)defibEnergies {
    // unione delle energie dei layout (GENERIC ICU, alcuni dispositivi, alcuni dispositivi: 1-10, 15, 20, 30, 50, 70, 100, 150, 170, 200, 300, 360)
    // + scala alcuni dispositivi (125, 175, 225, 250, 275, 325) e alcuni dispositivi (75)
    return @[@1, @2, @3, @4, @5, @6, @7, @8, @9, @10, @15, @20, @30, @50, @70, @75, @85, @100, @120, @125, @150, @170, @175,
             @200, @225, @250, @275, @300, @325, @360];
}
static NSDictionary *SLDefibDefaultConfig(void) {
    return @{ @"shocks_to_convert": @1, @"min_energy_j": @120, @"post_shock_rhythm": @"sinus",
              @"cv_shocks_to_convert": @1, @"cv_min_energy_j": @100, @"cv_post_rhythm": @"sinus",
              @"unsync_shock_vf": @YES, @"sync_stays_on": @NO,
              @"capture_threshold_ma": @70, @"capture_possible": @YES, @"mechanical_capture": @YES,
              @"aed_energy_j": @150, @"aed_cpr_s": @120, @"voice_prompts": @YES,
              @"outcome_mode": @"instructor" };   // instructor (di serie) = dopo ogni shock, anche sincronizzato, decide l'istruttore; auto = regole qui sopra
}

// Parametri modificabili con transizioni temporizzate e relativi range
static NSDictionary *SLParamRanges(void) {
    return @{ @"heart_rate_bpm": @[@0, @300], @"spo2_percent": @[@0, @100], @"respiratory_rate_rpm": @[@0, @60],
              @"etco2_mmhg": @[@0, @150], @"systolic_mmhg": @[@0, @300], @"diastolic_mmhg": @[@0, @200] };
}

// Limiti predefiniti (adulto) e range ammessi per ciascun limite
+ (NSDictionary<NSString *, NSNumber *> *)defaultAlarmLimits {
    return @{ @"hr_low": @50, @"hr_high": @120, @"spo2_low": @90, @"rr_low": @8, @"rr_high": @30,
              @"etco2_low": @25, @"etco2_high": @50, @"sys_low": @90, @"sys_high": @180 };
}
+ (NSDictionary<NSString *, NSNumber *> *)defaultOximeterLimits {
    return @{ @"spo2_low": @85, @"spo2_high": @100, @"pr_low": @30, @"pr_high": @170 };   // come il PM10N di riferimento
}
static NSDictionary *SLOxiLimitRanges(void) {
    return @{ @"spo2_low": @[@20, @99], @"spo2_high": @[@21, @100], @"pr_low": @[@20, @240], @"pr_high": @[@25, @250] };
}
static NSDictionary *SLLimitRanges(void) {
    return @{ @"hr_low": @[@15, @250], @"hr_high": @[@20, @300], @"spo2_low": @[@50, @99],
              @"rr_low": @[@1, @50], @"rr_high": @[@5, @60], @"etco2_low": @[@1, @90], @"etco2_high": @[@10, @150],
              @"sys_low": @[@30, @250], @"sys_high": @[@50, @300] };
}

+ (NSArray<NSString *> *)supportedRhythms {
    return @[SLRhythmSinus, SLRhythmSinusTachycardia, SLRhythmSinusBradycardia,
             SLRhythmAtrialFibrillation, SLRhythmVentricularTachyPulse, SLRhythmVentricularTachy, SLRhythmVentricularFib,
             SLRhythmAsystole, SLRhythmPEA];
}

+ (NSArray<NSString *> *)supportedSensors {
    return @[SLSensorECG, SLSensorSpO2, SLSensorNIBP, SLSensorEtCO2, SLSensorART, SLSensorTemp, SLSensorPads, SLSensorOxi];
}

+ (BOOL)rhythmHasPulse:(NSString *)rhythm {
    // VT trattata come senza polso (scenario ACLS); PEA = attività elettrica senza polso.
    return !([rhythm isEqualToString:SLRhythmVentricularFib] ||
             [rhythm isEqualToString:SLRhythmVentricularTachy] ||
             [rhythm isEqualToString:SLRhythmAsystole] ||
             [rhythm isEqualToString:SLRhythmPEA]);
}

- (instancetype)initWithDeviceId:(NSString *)deviceId {
    if ((self = [super init])) {
        _deviceId = [deviceId copy] ?: @"monitor-01";
        _muteDuration = 20.0;
        _clock = ^NSTimeInterval { return [NSProcessInfo processInfo].systemUptime; };
        [self resetValues];
        _limits = [[SimulationState defaultAlarmLimits] mutableCopy];   // configurazione del monitor:
        _autoPhysio = YES;
        _alarmOn = [@{ @"hr": @YES, @"spo2": @YES, @"art": @YES, @"nibp": @YES, @"rr": @YES, @"etco2": @YES } mutableCopy];
        _dCfg = [SLDefibDefaultConfig() mutableCopy];
        _spo2Delay = 0; _crtOn = YES; _layout = @"generic_icu";
        _revision = 1;                                                   // NON si azzera con reset_scenario
    }
    return self;
}

- (instancetype)init { return [self initWithDeviceId:@"monitor-01"]; }

- (void)resetValues {
    _rhythm = SLRhythmSinus;
    _hr = 82; _spo2 = 98; _rr = 16; _etco2 = 35; _sys = 120; _dia = 80;
    _spo2Valid = YES; _muted = NO; _running = YES; _qrsBeep = YES; _volume = 70;
    _scenAccum = 0; _scenSince = self.clock ? self.clock() : 0;    // il timer di scenario riparte da zero
    // Avvio (e reset): paziente appena arrivato, NESSUN sensore collegato; si collegano uno alla volta
    _ecgOn = NO; _spo2On = NO; _nibpOn = NO; _etco2On = NO; _artOn = NO;
    _sites = [NSMutableDictionary dictionary];
    _mutedUntil = 0;
    _nibpStatus = SLNibpIdle; _nibpError = nil; _nibpStartedAt = 0;
    _nibpLastSys = -1; _nibpLastDia = -1; _nibpMeasuredAt = nil;
    _ramps = [NSMutableDictionary dictionary];
    _scheduled = [NSMutableArray array];
    _baseline = nil; _cpr = NO; _apneaSince = 0; _breaths = [NSMutableArray array];
    _chainActive = NO; _chainSteps = nil; _chainName = nil; _chainIndex = 0;
    _oxiOn = NO; _oxiPower = NO; _oxiConnAt = 0; _oxiMutedUntil = 0;
    if (!_oxiLimits) { _oxiLimits = [[SimulationState defaultOximeterLimits] mutableCopy]; _oxiVolume = 70; }
    _tempOn = NO; _padsOn = NO; _spo2LowPerf = NO; _motion = 0; _motionUntil = 0; _touchUntil = 0; _nibpMotionHit = NO; _spo2Stage = 3; _spo2ConnAt = 0;
    _tempT = 368; _crtT = 20;
    _dMode = SLDefibOff; _dEnergy = 150; _dChargedEnergy = 0; _dCharge = SLChargeNone;
    _dSync = NO; _dSyncPending = NO; _aedPhase = SLAedPads; _aedAdvised = NO; _aedMotion = NO;
    _dNote = nil; _dVoice = nil; _dPromptSeq = 0;
    _dShocks = 0; _dLastEnergy = 0; _dLastShock = 0; _dSession = 0; _dLastSync = NO;
    _pRate = 70; _pOut = 0; _pDemand = YES; _pRun = NO; _pPaused = NO;
    _dEvents = [NSMutableArray array];
    _dEpisode = nil; _dEff = 0; _cvEff = 0;
    _dDecision = NO; _dDecisionFrom = nil; _dDecisionShock = 0; _dDecisionEnergy = 0; _dDecisionSync = NO;
}

#pragma mark Parametri e rampe (chiamare con @synchronized già acquisito)

- (NSInteger)param:(NSString *)k {
    if ([k isEqualToString:@"heart_rate_bpm"]) return _hr;
    if ([k isEqualToString:@"spo2_percent"]) return _spo2;
    if ([k isEqualToString:@"respiratory_rate_rpm"]) return _rr;
    if ([k isEqualToString:@"etco2_mmhg"]) return _etco2;
    if ([k isEqualToString:@"systolic_mmhg"]) return _sys;
    if ([k isEqualToString:@"diastolic_mmhg"]) return _dia;
    return 0;
}

- (void)setParam:(NSString *)k value:(NSInteger)v {
    if ([k isEqualToString:@"heart_rate_bpm"]) _hr = v;
    else if ([k isEqualToString:@"spo2_percent"]) _spo2 = v;
    else if ([k isEqualToString:@"respiratory_rate_rpm"]) _rr = v;
    else if ([k isEqualToString:@"etco2_mmhg"]) _etco2 = v;
    else if ([k isEqualToString:@"systolic_mmhg"]) _sys = v;
    else if ([k isEqualToString:@"diastolic_mmhg"]) _dia = v;
}

- (void)rampParam:(NSString *)k to:(NSInteger)to duration:(double)dur {
    if (dur <= 0) { [_ramps removeObjectForKey:k]; [self setParam:k value:to]; return; }
    // inizio della rampa: istante programmato (catene) oppure adesso
    NSTimeInterval start = _rampStartOverride > 0 ? _rampStartOverride : self.clock();
    _ramps[k] = @{ @"from": @([self param:k]), @"to": @(to), @"start": @(start), @"dur": @(dur) };
}

// Cambio ritmo con preset di FC e reazioni fisiologiche automatiche (arresto / ROSC)
- (void)applyRhythm:(NSString *)rhythm {
    BOOL wasPulse = [SimulationState rhythmHasPulse:_rhythm];
    _rhythm = [rhythm copy];
    BOOL nowPulse = [SimulationState rhythmHasPulse:_rhythm];
    if ([_rhythm isEqualToString:SLRhythmSinusTachycardia] && _hr <= 100) _hr = 130;
    if ([_rhythm isEqualToString:SLRhythmSinusBradycardia] && _hr >= 60) _hr = 45;
    if ([_rhythm isEqualToString:SLRhythmSinus] && (_hr < 60 || _hr > 100)) _hr = 80;
    if ([_rhythm isEqualToString:SLRhythmVentricularTachy] && _hr < 120) _hr = 180;
    if ([_rhythm isEqualToString:SLRhythmVentricularTachyPulse] && _hr < 120) _hr = 170;
    if ([_rhythm isEqualToString:SLRhythmAtrialFibrillation] && _hr < 60) _hr = 110;
    if ([_rhythm isEqualToString:SLRhythmPEA] && (_hr < 20 || _hr > 150)) _hr = 60;
    if (!_autoPhysio) return;
    if (wasPulse && !nowPulse) {
        // ARRESTO: desaturazione, apnea, crollo EtCO2 (senza RCP)
        if (!_baseline) _baseline = @{ @"spo2_percent": @(_spo2), @"respiratory_rate_rpm": @(_rr), @"etco2_mmhg": @(_etco2),
                                       @"systolic_mmhg": @(_sys), @"diastolic_mmhg": @(_dia) };
        [self rampParam:@"systolic_mmhg" to:45 duration:15];      // crollo della pressione del paziente
        [self rampParam:@"diastolic_mmhg" to:25 duration:15];
        if (_cpr) { [self rampParam:@"respiratory_rate_rpm" to:10 duration:5]; [self rampParam:@"etco2_mmhg" to:15 duration:10]; }
        else { [self rampParam:@"respiratory_rate_rpm" to:0 duration:8]; [self rampParam:@"etco2_mmhg" to:0 duration:25]; }
        [self rampParam:@"spo2_percent" to:0 duration:40];
    } else if (!wasPulse && nowPulse && _baseline) {
        // ROSC: recupero graduale verso i valori pre-arresto
        [self rampParam:@"respiratory_rate_rpm" to:[_baseline[@"respiratory_rate_rpm"] integerValue] duration:15];
        // EtCO2: picco da wash-out (CO2 accumulata) nei primi secondi, poi ritorno al valore pre-arresto
        NSInteger be = [_baseline[@"etco2_mmhg"] integerValue];
        [self rampParam:@"etco2_mmhg" to:MIN(90, be + 15) duration:6];
        [_scheduled addObject:@{ @"at": @(self.clock() + 6), @"key": @"etco2_mmhg", @"to": @(be), @"dur": @40 }];
        _cpr = NO;                                                // al ROSC le compressioni si fermano
        [self rampParam:@"spo2_percent" to:[_baseline[@"spo2_percent"] integerValue] duration:45];
        // pressione: riparte bassa (ipotensione post-ROSC) e risale gradualmente in ~2 minuti
        NSInteger bs = [_baseline[@"systolic_mmhg"] integerValue], bd = [_baseline[@"diastolic_mmhg"] integerValue];
        if (bs > 0) {
            _sys = MIN(_sys, MAX(50, bs / 2)); _dia = MIN(_dia, MAX(28, bd / 2)); if (_dia >= _sys) _dia = _sys - 10;
            [self rampParam:@"systolic_mmhg" to:bs duration:120];
            [self rampParam:@"diastolic_mmhg" to:bd duration:120];
        }
        _baseline = nil;
    }
}

// Ventilazione alveolare: a parità di produzione di CO2, EtCO2 ~ inversamente proporzionale alla FR
- (void)coupleEtCO2FromRR:(NSInteger)oldRR to:(NSInteger)newRR duration:(double)dur {
    if (!_autoPhysio || ![SimulationState rhythmHasPulse:_rhythm] || oldRR <= 0 || newRR <= 0 || oldRR == newRR || _etco2 <= 0) return;
    NSInteger target = (NSInteger)lround(MAX(15.0, MIN(90.0, (double)_etco2 * oldRR / newRR)));
    [self rampParam:@"etco2_mmhg" to:target duration:MAX(30, dur)];
}

// Apnea con polso: dopo ~20 s la SpO2 scende progressivamente (~0,35 %/s); alla ripresa del respiro risale
- (void)apneaPhysiologyAt:(NSTimeInterval)now {
    BOOL pulse = [SimulationState rhythmHasPulse:_rhythm];
    if (_autoPhysio && pulse && _rr == 0 && !_ramps[@"respiratory_rate_rpm"]) {
        if (_apneaSince == 0) { _apneaSince = now; _spo2PreApnea = _spo2; }
        double el = now - _apneaSince;
        if (el > 20 && !_ramps[@"spo2_percent"]) {
            NSInteger v = MAX(40, _spo2PreApnea - (NSInteger)floor((el - 20) * 0.35));
            if (v < _spo2) { _spo2 = v; _revision++; }
        }
    } else if (_apneaSince > 0) {
        if (pulse && _rr > 0 && _autoPhysio && _spo2 < _spo2PreApnea) [self rampParam:@"spo2_percent" to:_spo2PreApnea duration:40];
        _apneaSince = 0;
    }
}

// FC 0 in un ritmo organizzato = asistolia (non una linea piatta artificiale)
- (void)asystoleIfZeroRate {
    BOOL organized = !([_rhythm isEqualToString:SLRhythmVentricularFib] || [_rhythm isEqualToString:SLRhythmAsystole]);
    if (_hr == 0 && organized) [self applyRhythm:SLRhythmAsystole];
}

// Valida una transizione {params:{...}, duration_s, rhythm?}; se apply, la esegue.
- (BOOL)transition:(id)value apply:(BOOL)apply error:(NSString **)error {
    if (![value isKindOfClass:[NSDictionary class]]) { if (error) *error = @"transition: value must be an object"; return NO; }
    NSDictionary *params = value[@"params"] ?: @{};
    if (![params isKindOfClass:[NSDictionary class]]) { if (error) *error = @"transition: params must be an object"; return NO; }
    NSInteger dur = 0;
    if (value[@"duration_s"] && !SLIntValue(value[@"duration_s"], 0, 3600, &dur, @"duration_s", error)) return NO;
    id rhythm = value[@"rhythm"];
    if (rhythm && ![rhythm isKindOfClass:[NSNull class]] &&
        (![rhythm isKindOfClass:[NSString class]] || ![[SimulationState supportedRhythms] containsObject:rhythm])) {
        if (error) *error = @"transition: unsupported rhythm"; return NO;
    }
    if (params.count == 0 && (!rhythm || [rhythm isKindOfClass:[NSNull class]])) { if (error) *error = @"transition: nothing to change"; return NO; }
    NSDictionary *ranges = SLParamRanges();
    NSMutableDictionary *targets = [NSMutableDictionary dictionary];
    for (NSString *k in params) {
        NSArray *r = ranges[k];
        if (!r) { if (error) *error = [NSString stringWithFormat:@"transition: unknown parameter '%@'", k]; return NO; }
        NSInteger v; if (!SLIntValue(params[k], [r[0] integerValue], [r[1] integerValue], &v, k, error)) return NO;
        targets[k] = @(v);
    }
    NSInteger s = targets[@"systolic_mmhg"] ? [targets[@"systolic_mmhg"] integerValue] : _sys;
    NSInteger d = targets[@"diastolic_mmhg"] ? [targets[@"diastolic_mmhg"] integerValue] : _dia;
    if (apply && d >= s && s > 0) { if (error) *error = @"transition: diastolic must be lower than systolic"; return NO; }
    if (!apply) return YES;
    if ([rhythm isKindOfClass:[NSString class]]) {
        // tra ritmi sinusali (sinusale / tachicardia / bradicardia) la frequenza cambia gradualmente nel tempo scelto:
        // il ritmo cambia subito, la FC va verso il valore tipico del nuovo ritmo con una rampa (non a scatto)
        NSArray *gradual = @[SLRhythmSinus, SLRhythmSinusTachycardia, SLRhythmSinusBradycardia];
        BOOL wasGradual = [gradual containsObject:_rhythm];
        BOOL ramp = dur > 0 && !targets[@"heart_rate_bpm"] && [gradual containsObject:_rhythm] && [gradual containsObject:rhythm];
        NSInteger hr0 = _hr;
        [self applyRhythm:rhythm];
        if (ramp && _hr != hr0) { NSInteger to = _hr; _hr = hr0; targets[@"heart_rate_bpm"] = @(to); }
        // ritmo sinusale -> sinusale con una FC di arrivo e una durata: la rampa parte dalla FC di adesso,
        // non dal valore tipico del nuovo ritmo (prima faceva 96 -> 130 di scatto -> 122)
        else if (dur > 0 && targets[@"heart_rate_bpm"] && [gradual containsObject:rhythm] && wasGradual && hr0 > 0) _hr = hr0;
    }
    NSInteger oldRR = _rr;
    for (NSString *k in targets) [self rampParam:k to:[targets[k] integerValue] duration:dur];
    if (targets[@"respiratory_rate_rpm"] && !targets[@"etco2_mmhg"])
        [self coupleEtCO2FromRR:oldRR to:[targets[@"respiratory_rate_rpm"] integerValue] duration:dur];
    return YES;
}

- (void)advanceRampsAt:(NSTimeInterval)now {
    BOOL changed = NO;
    for (NSString *k in [_ramps allKeys]) {
        NSDictionary *r = _ramps[k];
        double x = ([r[@"dur"] doubleValue] > 0) ? (now - [r[@"start"] doubleValue]) / [r[@"dur"] doubleValue] : 1;
        x = MAX(0, MIN(1, x));
        double from = [r[@"from"] doubleValue], to = [r[@"to"] doubleValue];
        NSInteger v = lround(from + (to - from) * x);
        if (v != [self param:k]) { [self setParam:k value:v]; changed = YES; }
        if (x >= 1) [_ramps removeObjectForKey:k];
    }
    if (_dia >= _sys && _sys > 0) { _dia = MAX(0, _sys - 1); changed = YES; }
    if (changed) { [self asystoleIfZeroRate]; _revision++; }
}

- (void)advanceChainAt:(NSTimeInterval)now {
    for (int guard = 0; _chainActive && guard < 64; guard++) {
        if (_chainIndex >= (NSInteger)_chainSteps.count) { _chainActive = NO; _revision++; return; }
        NSDictionary *st = _chainSteps[_chainIndex];
        double wait = [st[@"wait_s"] doubleValue], dur = [st[@"duration_s"] doubleValue];
        if (_chainWaiting) {
            if (now - _chainPhaseStart < wait) return;
            _chainPhaseStart = _chainPhaseStart + wait;
            _rampStartOverride = _chainPhaseStart;
            [self transition:st apply:YES error:NULL];
            _rampStartOverride = 0;
            _chainWaiting = NO; _revision++;
        } else {
            if (now - _chainPhaseStart < dur) return;
            _chainIndex++; _chainWaiting = YES; _chainPhaseStart = _chainPhaseStart + dur; _revision++;
        }
    }
}

#pragma mark Defibrillatore (chiamare con @synchronized già acquisito)

static NSString *SLRhythmName(NSString *r) {
    NSDictionary *n = @{ SLRhythmSinus: @"sinusale", SLRhythmSinusTachycardia: @"tachicardia sinusale",
                         SLRhythmSinusBradycardia: @"bradicardia sinusale", SLRhythmAtrialFibrillation: @"FA",
                         SLRhythmVentricularTachyPulse: @"TV con polso", SLRhythmVentricularTachy: @"TV senza polso",
                         SLRhythmVentricularFib: @"FV", SLRhythmAsystole: @"asistolia", SLRhythmPEA: @"PEA" };
    return n[r] ?: r;
}

- (NSInteger)cfg:(NSString *)k { return [_dCfg[k] integerValue]; }

- (void)defibLog:(NSString *)text instructor:(BOOL)instr {
    NSTimeInterval now = self.clock();
    static NSDateFormatter *f; static dispatch_once_t once; dispatch_once(&once, ^{ f = [NSDateFormatter new]; f.dateFormat = @"HH:mm:ss"; });
    NSInteger el = _dSession > 0 ? (NSInteger)MAX(0, now - _dSession) : 0;
    [_dEvents addObject:@{ @"time": [f stringFromDate:[NSDate date]],
                           @"elapsed": [NSString stringWithFormat:@"%02ld:%02ld", (long)el / 60, (long)el % 60],
                           @"text": text, @"instructor": @(instr), @"seq": @(++_dEvSeq) }];
    while (_dEvents.count > 60) [_dEvents removeObjectAtIndex:0];
}

- (void)defibNote:(NSString *)note { _dNote = [note copy]; _dNoteAt = self.clock(); }

// Messaggio vocale del DAE: nuovo prompt (la UI lo pronuncia quando cambia promptSeq)
- (void)aedSay:(NSString *)text { _dVoice = [text copy]; _dPromptSeq++; }

- (void)aedPhase:(SLAedPhase)ph say:(NSString *)voice {
    _aedPhase = ph; _aedPhaseStart = self.clock(); _aedMotion = NO;
    if (voice) [self aedSay:voice];
}

- (void)defibDisarm:(NSString *)why {
    if (_dCharge == SLChargeNone && !_dSyncPending) return;
    _dCharge = SLChargeNone; _dSyncPending = NO; _dChargedEnergy = 0;
    if (why) { [self defibNote:why]; [self defibLog:why instructor:NO]; }
}

- (void)defibStartChargeEnergy:(NSInteger)j {
    _dCharge = SLChargeCharging; _dChargeStart = self.clock(); _dChargeDur = SLChargeTime(j); _dChargedEnergy = j;
    _dSyncPending = NO; _dNote = nil;
}

// Pacing: attivo, cattura elettrica e meccanica (derivati dallo stato corrente)
- (BOOL)brandRulesA { return NO; }
- (NSInteger)paceEffRate { return _pPaused ? MAX(1, _pRate / 4) : _pRate; }   // PAUSE: 25% della frequenza
// alcuni dispositivi: il demand usa gli elettrodi ECG; senza elettrodi passa a stimolazione fissa (ECG LEADS OFF)
- (BOOL)paceDemandEff { return _pDemand && !([self brandRulesA] && !_ecgOn); }

- (void)pacingActive:(BOOL *)active capture:(BOOL *)capture mechanical:(BOOL *)mech {
    BOOL on = _dMode == SLDefibPacer && _pRun && _padsOn;
    NSInteger rate = [self paceEffRate];
    BOOL organized = !([_rhythm isEqualToString:SLRhythmVentricularFib] || [_rhythm isEqualToString:SLRhythmAsystole]);
    BOOL inhibited = on && [self paceDemandEff] && organized && _hr >= rate;   // demand: ritmo proprio sufficiente
    BOOL act = on && !inhibited;
    BOOL ventricular = [_rhythm isEqualToString:SLRhythmVentricularFib] || [_rhythm isEqualToString:SLRhythmVentricularTachy]
                    || [_rhythm isEqualToString:SLRhythmVentricularTachyPulse];
    BOOL cap = act && [_dCfg[@"capture_possible"] boolValue] && _pOut >= [self cfg:@"capture_threshold_ma"] && _pOut > 0
               && !ventricular && (!organized || rate > _hr);
    if (active) *active = act;
    if (capture) *capture = cap;
    if (mech) *mech = cap && [_dCfg[@"mechanical_capture"] boolValue];   // istruttore: la cattura genera polso o no
}

- (BOOL)effectivePulse {
    BOOL cap, mech; [self pacingActive:NULL capture:&cap mechanical:&mech];
    return cap ? mech : [SimulationState rhythmHasPulse:_rhythm];
}

- (void)defibConvertTo:(NSString *)rhythm {
    if (![[SimulationState supportedRhythms] containsObject:rhythm]) return;
    [self defibLog:[NSString stringWithFormat:@"Ritmo dopo lo shock: %@", SLRhythmName(rhythm)] instructor:YES];
    [self applyRhythm:rhythm];
    _dEpisode = _rhythm; _dEff = 0; _cvEff = 0;
}

// Erogazione dello shock con l'esito configurato dall'istruttore
- (void)defibDeliverSynced:(BOOL)synced {
    NSInteger j = _dChargedEnergy;
    NSTimeInterval now = self.clock();
    _dShocks++; _dLastShock = now; _dLastEnergy = j; _dLastSync = synced;
    _dCharge = SLChargeNone; _dSyncPending = NO; _dChargedEnergy = 0;
    NSString *what = [NSString stringWithFormat:@"Shock %ld: %ld J%@%@", (long)_dShocks, (long)j, synced ? @" SYNC" : @"",
                      _dMode == SLDefibAED ? @" (DAE)" : @""];
    [self defibNote:[NSString stringWithFormat:@"SHOCK EROGATO  %ld J%@", (long)j, synced ? @" (SYNC)" : @""]];
    [self defibLog:what instructor:NO];
    [self defibLog:[NSString stringWithFormat:@"Ritmo al momento dello shock: %@", SLRhythmName(_rhythm)] instructor:YES];

    if ([_dCfg[@"outcome_mode"] isEqualToString:@"instructor"]) {
        // il ritmo resta quello pre-shock finché l'istruttore non sceglie l'esito (defib_outcome)
        _dDecision = YES; _dDecisionFrom = _rhythm; _dDecisionShock = _dShocks; _dDecisionEnergy = j; _dDecisionSync = synced;
        [self defibLog:@"In attesa della decisione dell'istruttore" instructor:YES];
    } else {
    if (![_dEpisode isEqualToString:_rhythm]) { _dEpisode = _rhythm; _dEff = 0; _cvEff = 0; }
    NSString *r = _rhythm;
    BOOL defibRhythm = [r isEqualToString:SLRhythmVentricularFib] || [r isEqualToString:SLRhythmVentricularTachy];
    BOOL cvRhythm = [r isEqualToString:SLRhythmAtrialFibrillation] || [r isEqualToString:SLRhythmVentricularTachyPulse];
    BOOL sinusLike = [r isEqualToString:SLRhythmSinus] || [r isEqualToString:SLRhythmSinusTachycardia]
                  || [r isEqualToString:SLRhythmSinusBradycardia];
    BOOL rOnT = [_dCfg[@"unsync_shock_vf"] boolValue];
    if (defibRhythm) {
        if (j >= [self cfg:@"min_energy_j"]) _dEff++;
        NSInteger n = [self cfg:@"shocks_to_convert"];
        if (n > 0 && _dEff >= n) [self defibConvertTo:_dCfg[@"post_shock_rhythm"]];
        else [self defibLog:[NSString stringWithFormat:@"Nessuna conversione (shock efficaci %ld/%ld)", (long)_dEff, (long)n] instructor:YES];
    } else if (cvRhythm) {
        if (!synced && rOnT && [r isEqualToString:SLRhythmAtrialFibrillation]) {
            [self defibLog:@"Shock NON sincronizzato su ritmo con polso: R su T" instructor:YES];
            [self defibConvertTo:SLRhythmVentricularFib];
        } else {
            if (j >= [self cfg:@"cv_min_energy_j"]) _cvEff++;
            NSInteger n = [self cfg:@"cv_shocks_to_convert"];
            if (n > 0 && _cvEff >= n) [self defibConvertTo:_dCfg[@"cv_post_rhythm"]];
            else [self defibLog:[NSString stringWithFormat:@"Cardioversione senza effetto (%ld/%ld)", (long)_cvEff, (long)n] instructor:YES];
        }
    } else if (sinusLike && !synced && rOnT) {
        [self defibLog:@"Shock NON sincronizzato su ritmo con polso: R su T" instructor:YES];
        [self defibConvertTo:SLRhythmVentricularFib];
    }
    }
    if (synced && ![_dCfg[@"sync_stays_on"] boolValue]) _dSync = NO;   // dopo lo shock torna asincrono (configurabile)
    if (_dMode == SLDefibAED) {
        [self aedPhase:SLAedCPR say:@"Shock erogato. Iniziare subito la RCP."];
    }
}

// GENERIC ICU: il cassetto vede solo le piastre. alcuni dispositivi: anche gli elettrodi ECG del dispositivo (sync in II, come da manuale)
- (BOOL)defibEcgAvailable { return _padsOn || (![_layout isEqualToString:@"generic_icu"] && _ecgOn); }
- (BOOL)brandRulesB { return NO; }

- (void)defibSetMode:(SLDefibMode)m {
    if (m == _dMode) return;
    [self defibDisarm:nil];
    if (_dMode == SLDefibPacer && _pRun) { _pRun = NO; [self defibLog:@"Pacing interrotto (cambio modalità)" instructor:NO]; }
    SLDefibMode old = _dMode;
    _dMode = m; _dNote = nil;
    if (old == SLDefibOff && m != SLDefibOff && _dSession == 0) _dSession = self.clock();
    NSArray *names = @[@"spento", @"DAE", @"manuale", @"pacer"];
    [self defibLog:[NSString stringWithFormat:@"Modalità: %@", names[m]] instructor:NO];
    if (m == SLDefibAED) {
        _dSync = NO;
        if (_padsOn) [self aedPhase:SLAedAnalyzing say:@"Analisi del ritmo in corso. Non toccare il paziente."];
        else [self aedPhase:SLAedPads say:@"Applicare le piastre sul torace nudo del paziente."];
    }
    if (m == SLDefibOff) { _dSync = NO; _dVoice = nil; }
}

- (void)defibPadsChanged {
    if (_padsOn) {
        [self defibLog:@"Piastre applicate" instructor:NO];
        if (_dMode == SLDefibAED && _aedPhase == SLAedPads) {
            [self aedPhase:SLAedAnalyzing say:@"Analisi del ritmo in corso. Non toccare il paziente."];
        }
    } else {
        [self defibLog:@"Piastre staccate" instructor:NO];
        [self defibDisarm:nil];
        if (_pRun) { _pRun = NO; [self defibNote:@"PIASTRE STACCATE: PACING INTERROTTO"]; }
        if (_dMode == SLDefibAED) [self aedPhase:SLAedPads say:@"Controllare le piastre."];
    }
}

- (void)defibTickAt:(NSTimeInterval)now {
    BOOL changed = NO;
    if (_dCharge == SLChargeCharging && now - _dChargeStart >= _dChargeDur) {
        _dCharge = SLChargeReady; _dReadyAt = now; changed = YES;
        if (_dMode == SLDefibAED) [self aedPhase:SLAedReady say:@"Allontanarsi dal paziente. Premere ora il pulsante di scarica."];
    }
    if (_dCharge == SLChargeReady) {
        double limit = _dMode == SLDefibAED ? kAedReadyTimeout : kManualReadyTimeout;
        if (now - _dReadyAt >= limit) {
            [self defibDisarm:@"SCARICA INTERNA: shock non erogato"];
            if (_dMode == SLDefibAED) [self aedPhase:SLAedCPR say:@"Shock non erogato. Iniziare la RCP."];
            changed = YES;
        }
    }
    if (_dMode == SLDefibAED) {
        double el = now - _aedPhaseStart;
        if (_aedPhase == SLAedAnalyzing) {
            if (_cpr) {                                    // compressioni durante l'analisi: artefatto da movimento
                if (!_aedMotion) { [self aedSay:@"Movimento rilevato. Sospendere la RCP."]; _aedMotion = YES; _aedMotionSaidAt = now; changed = YES; }
                _aedPhaseStart = now;
            } else if (_motion || _touchUntil > now) {     // paziente che si muove / viene toccato: analisi interrotta
                if (!_aedMotion) { [self defibLog:@"DAE: analisi interrotta (movimento)" instructor:NO]; }
                if (!_aedMotion || now - _aedMotionSaidAt >= 6) {                 // il messaggio si ripete finché il movimento continua
                    [self aedSay:@"Movimento rilevato. Fermare il movimento."]; _aedMotionSaidAt = now; changed = YES;
                }
                _aedMotion = YES; _aedPhaseStart = now;   // l'analisi riparte da capo quando il paziente è fermo
            } else if (_aedMotion) {
                _aedMotion = NO; _aedPhaseStart = now;
                [self aedSay:@"Analisi del ritmo in corso. Non toccare il paziente."]; changed = YES;
            } else if (el >= kAedAnalysisTime) {
                BOOL shockable = [_rhythm isEqualToString:SLRhythmVentricularFib] || [_rhythm isEqualToString:SLRhythmVentricularTachy]
                    || ([_rhythm isEqualToString:SLRhythmVentricularTachyPulse] && _hr >= 150);   // il DAE non sente il polso
                _aedAdvised = shockable;
                [self defibLog:shockable ? @"DAE: shock consigliato" : @"DAE: shock non consigliato" instructor:NO];
                if (shockable) {
                    [self aedPhase:SLAedCharging say:@"Shock consigliato. Carica in corso. Allontanarsi dal paziente."];
                    [self defibStartChargeEnergy:[self cfg:@"aed_energy_j"]];
                } else {
                    [self aedPhase:SLAedCPR say:@"Shock non consigliato. Iniziare subito la RCP."];
                }
                changed = YES;
            }
        } else if (_aedPhase == SLAedCPR && el >= [self cfg:@"aed_cpr_s"]) {
            [self aedPhase:SLAedAnalyzing say:@"Sospendere la RCP. Analisi del ritmo in corso. Non toccare il paziente."];
            changed = YES;
        }
    }
    if (_dNote && now - _dNoteAt > 5) { _dNote = nil; changed = YES; }
    // alcuni dispositivi: elettrodi ECG staccati durante il pacing demand -> pacing arrestato
    if ([self brandRulesB] && _dMode == SLDefibPacer && _pRun && _pDemand && !_ecgOn) {
        _pRun = NO; _pPaused = NO;
        [self defibNote:@"PACING ARRESTATO: DERIVAZIONI ECG SCOLLEGATE"];
        [self defibLog:@"Pacing arrestato: derivazioni ECG scollegate" instructor:NO];
        changed = YES;
    }
    if (changed) _revision++;
}

- (void)defibRWaveAt:(NSTimeInterval)t {
    @synchronized (self) {
        if (_dSyncPending && _dCharge == SLChargeReady && t >= _dSyncSince) { [self defibDeliverSynced:YES]; _revision++; }
    }
}

// Testo del display per la modalità corrente
- (NSString *)defibMessageAt:(NSTimeInterval)now {
    if (_dNote) return _dNote;
    switch (_dMode) {
        case SLDefibOff: return @"Defibrillatore spento: scegliere DAE, MANUALE o PACER";
        case SLDefibAED: {
            switch (_aedPhase) {
                case SLAedPads: return @"APPLICARE LE PIASTRE";
                case SLAedAnalyzing: return _aedMotion ? (_cpr ? @"MOVIMENTO RILEVATO — SOSPENDERE LA RCP" : @"MOVIMENTO RILEVATO — FERMARE IL MOVIMENTO") : @"ANALISI IN CORSO — NON TOCCARE IL PAZIENTE";
                case SLAedCharging: return @"SHOCK CONSIGLIATO — CARICA IN CORSO";
                case SLAedReady: return @"ALLONTANARSI — PREMERE SHOCK";
                case SLAedCPR: return @"RCP IN CORSO";
            }
            return @"";
        }
        case SLDefibManual: {
            if (!_padsOn) return @"COLLEGARE LE PIASTRE";
            if (_dSyncPending) return @"SYNC: SHOCK IN ATTESA DELL'ONDA R…";
            if (_dCharge == SLChargeCharging) return [NSString stringWithFormat:@"CARICA IN CORSO  %ld J", (long)_dChargedEnergy];
            if (_dCharge == SLChargeReady) return [NSString stringWithFormat:@"%ld J PRONTI — PREMERE SHOCK", (long)_dChargedEnergy];
            return [NSString stringWithFormat:@"MANUALE%@ — ENERGIA %ld J", _dSync ? @" SYNC" : @"", (long)_dEnergy];
        }
        case SLDefibPacer: {
            if (!_padsOn) return @"COLLEGARE LE PIASTRE";
            if (!_pRun) return @"PACER PRONTO — premere AVVIA PACING";
            BOOL act; [self pacingActive:&act capture:NULL mechanical:NULL];
            if (!act) return [NSString stringWithFormat:@"DEMAND INIBITO: FC propria %ld ≥ %ld ppm — alzare la frequenza o passare a FISSO",
                              (long)_hr, (long)_pRate];
            if (_pPaused) return [NSString stringWithFormat:@"PAUSA: STIMOLAZIONE AL 25%% (%ld ppm)", (long)[self paceEffRate]];
            if (_pDemand && ![self paceDemandEff]) return @"ECG LEADS OFF — STIMOLAZIONE NON-DEMAND";
            return [NSString stringWithFormat:@"PACING %@ IN CORSO  %ld ppm · %ld mA%@", _pDemand ? @"DEMAND" : @"FISSO", (long)_pRate, (long)_pOut,
                    _pOut == 0 ? @" — AUMENTARE LA CORRENTE" : @""];
        }
    }
    return @"";
}

- (SLDefibInfo *)defibInfoAt:(NSTimeInterval)now {
    SLDefibInfo *d = [SLDefibInfo new];
    d.mode = _dMode; d.padsConnected = _padsOn;
    d.energy = _dMode == SLDefibAED ? [self cfg:@"aed_energy_j"] : _dEnergy;
    d.charge = _dCharge; d.chargedEnergy = _dChargedEnergy;
    d.chargeProgress = _dCharge == SLChargeCharging ? MIN(1.0, (now - _dChargeStart) / MAX(0.1, _dChargeDur)) : (_dCharge == SLChargeReady ? 1 : 0);
    d.sync = _dSync; d.syncPending = _dSyncPending; d.syncPendingSince = _dSyncSince;
    d.aedPhase = _aedPhase; d.aedShockAdvised = _aedAdvised;
    double len = _aedPhase == SLAedCPR ? [self cfg:@"aed_cpr_s"] : (_aedPhase == SLAedAnalyzing ? kAedAnalysisTime : 0);
    d.aedRemaining = len > 0 ? (NSInteger)ceil(MAX(0, _aedPhaseStart + len - now)) : 0;
    d.message = [self defibMessageAt:now];
    d.voicePrompt = _dVoice; d.promptSeq = _dPromptSeq;
    d.shockCount = _dShocks; d.lastShockAt = _dLastShock; d.lastShockEnergy = _dLastEnergy; d.lastShockSynced = _dLastSync;
    d.sessionStart = _dSession;
    d.paceRate = [self paceEffRate]; d.paceSetRate = _pRate; d.pacePaused = _pPaused;
    d.paceOutput = _pOut; d.paceDemand = _pDemand; d.paceRunning = _pRun;
    d.paceLeadsOff = _dMode == SLDefibPacer && _pRun && _pDemand && [self brandRulesA] && !_ecgOn;
    BOOL a, c, m; [self pacingActive:&a capture:&c mechanical:&m];
    d.paceActive = a; d.paceCapture = c; d.paceMechanical = m;
    d.voiceEnabled = [_dCfg[@"voice_prompts"] boolValue];
    d.events = [_dEvents copy];
    return d;
}

// Comandi del defibrillatore. Ritorna YES se il comando è suo (*handled), NO + error se invalido.
- (BOOL)defibCommand:(NSString *)name value:(id)value handled:(BOOL *)handled error:(NSString **)error {
    *handled = YES;
    if ([name isEqualToString:@"defib_mode"]) {
        NSArray *modes = @[@"off", @"aed", @"manual", @"pacer"];
        if (![value isKindOfClass:[NSString class]] || ![modes containsObject:value]) {
            if (error) *error = @"defib_mode: allowed off, aed, manual, pacer"; return NO;
        }
        [self defibSetMode:(SLDefibMode)[modes indexOfObject:value]];
    } else if ([name isEqualToString:@"defib_energy"]) {
        NSInteger v; if (!SLIntValue(value, 1, 360, &v, @"energy_j", error)) return NO;
        if (![[SimulationState defibEnergies] containsObject:@(v)]) { if (error) *error = @"energy_j: not a selectable energy"; return NO; }
        if (_dMode == SLDefibAED) { if (error) *error = @"defib_energy: not available in AED mode"; return NO; }
        if (v != _dEnergy) {
            _dEnergy = v;
            if (_dCharge != SLChargeNone) [self defibDisarm:@"ENERGIA CAMBIATA: CARICA ANNULLATA"];
        }
    } else if ([name isEqualToString:@"defib_charge"]) {
        if (_dMode != SLDefibManual) { if (error) *error = @"defib_charge: manual mode only"; return NO; }
        if (!_padsOn) { [self defibNote:@"COLLEGARE LE PIASTRE"]; if (error) *error = @"defib_charge: pads not connected"; return NO; }
        if (_dCharge != SLChargeNone) return YES;          // già in carica o carico: nessuna nuova carica
        [self defibStartChargeEnergy:_dEnergy];
        [self defibLog:[NSString stringWithFormat:@"Carica %ld J%@", (long)_dEnergy, _dSync ? @" (SYNC)" : @""] instructor:NO];
    } else if ([name isEqualToString:@"defib_disarm"]) {
        [self defibDisarm:@"CARICA ANNULLATA"];
    } else if ([name isEqualToString:@"defib_shock"]) {
        if (_dCharge != SLChargeReady) { if (error) *error = @"defib_shock: not charged"; return NO; }
        if (!_padsOn) { [self defibDisarm:@"COLLEGARE LE PIASTRE"]; if (error) *error = @"defib_shock: pads not connected"; return NO; }
        if (_dMode == SLDefibManual && _dSync) {
            if (![self defibEcgAvailable]) { [self defibNote:@"SYNC: NESSUN ECG DALLE PIASTRE"]; if (error) *error = @"defib_shock: sync needs pads ECG"; return NO; }
            _dSyncPending = YES; _dSyncSince = self.clock();     // si eroga alla prossima onda R (defibRWaveAt:)
        } else {
            [self defibDeliverSynced:NO];
        }
    } else if ([name isEqualToString:@"defib_sync"]) {
        BOOL b; if (!SLBoolValue(value, &b, @"sync", error)) return NO;
        if (_dMode != SLDefibManual) { if (error) *error = @"defib_sync: manual mode only"; return NO; }
        if (b != _dSync) { _dSync = b; _dSyncPending = NO; [self defibLog:b ? @"SYNC attivato" : @"SYNC disattivato" instructor:NO]; }
    } else if ([name isEqualToString:@"defib_analyze"]) {
        if (_dMode != SLDefibAED) { if (error) *error = @"defib_analyze: AED mode only"; return NO; }
        if (_aedPhase == SLAedCharging || _aedPhase == SLAedReady) return YES;
        if (!_padsOn) [self aedPhase:SLAedPads say:@"Applicare le piastre sul torace nudo del paziente."];
        else [self aedPhase:SLAedAnalyzing say:@"Analisi del ritmo in corso. Non toccare il paziente."];
    } else if ([name isEqualToString:@"defib_aed_cpr"]) {
        // DAE: "Pausa per RCP": toglie la carica e passa alla RCP
        if (_dMode != SLDefibAED) { if (error) *error = @"defib_aed_cpr: AED mode only"; return NO; }
        [self defibDisarm:nil];
        [self aedPhase:SLAedCPR say:@"Pausa. Se necessario, iniziare la RCP."];
    } else if ([name isEqualToString:@"defib_pacer"]) {
        // {"rate":70,"output_ma":60,"demand":true,"running":true} (anche parziale)
        if (![value isKindOfClass:[NSDictionary class]] || [value count] == 0) { if (error) *error = @"defib_pacer: value must be an object"; return NO; }
        NSInteger rate = _pRate, out = _pOut; BOOL demand = _pDemand, run = _pRun, paused = _pPaused;
        if (value[@"rate"] && !SLIntValue(value[@"rate"], 30, 210, &rate, @"rate", error)) return NO;
        if (value[@"output_ma"] && !SLIntValue(value[@"output_ma"], 0, 200, &out, @"output_ma", error)) return NO;
        if (value[@"demand"] && !SLBoolValue(value[@"demand"], &demand, @"demand", error)) return NO;
        if (value[@"running"] && !SLBoolValue(value[@"running"], &run, @"running", error)) return NO;
        if (value[@"paused"] && !SLBoolValue(value[@"paused"], &paused, @"paused", error)) return NO;
        if (run && _dMode != SLDefibPacer) { if (error) *error = @"defib_pacer: pacer mode only"; return NO; }
        if (run && !_padsOn) { [self defibNote:@"COLLEGARE LE PIASTRE"]; if (error) *error = @"defib_pacer: pads not connected"; return NO; }
        // alcuni dispositivi: in demand il pacing non parte senza gli elettrodi ECG (manuale, 9.5.1)
        if (run && !_pRun && [self brandRulesB] && demand && !_ecgOn) {
            [self defibNote:@"DERIVAZIONI ECG SCOLLEGATE: PACING NON AVVIATO"]; if (error) *error = @"defib_pacer: demand pacing needs ECG leads"; return NO;
        }
        if (run != _pRun) [self defibLog:run ? [NSString stringWithFormat:@"Pacing avviato %ld ppm %ld mA %@", (long)rate, (long)out, demand ? @"demand" : @"fisso"]
                                         : @"Pacing fermato" instructor:NO];
        else if (run && (rate != _pRate || out != _pOut)) [self defibLog:[NSString stringWithFormat:@"Pacing %ld ppm %ld mA", (long)rate, (long)out] instructor:NO];
        _pRate = rate; _pOut = out; _pDemand = demand; _pRun = run; _pPaused = run && paused;
    } else if ([name isEqualToString:@"defib_event"]) {
        // tasto EVENT: segna un evento nel registro (testo opzionale)
        NSString *t = [value isKindOfClass:[NSString class]] && [value length] ? [value substringToIndex:MIN([value length], (NSUInteger)60)] : @"Evento marcato";
        if (_dSession == 0) _dSession = self.clock();
        [self defibLog:t instructor:NO];
    } else if ([name isEqualToString:@"defib_outcome"]) {
        // esito dell'ultimo shock: "stay" (resta nel ritmo pre-shock) oppure un ritmo
        if (![value isKindOfClass:[NSString class]] || !([value isEqualToString:@"stay"] || [[SimulationState supportedRhythms] containsObject:value])) {
            if (error) *error = @"defib_outcome: value must be \"stay\" or a rhythm"; return NO;
        }
        if ([value isEqualToString:@"stay"]) [self defibLog:[NSString stringWithFormat:@"Esito: resta in %@", SLRhythmName(_rhythm)] instructor:YES];
        else [self defibConvertTo:value];
        _dDecision = NO; _dDecisionFrom = nil;
    } else if ([name isEqualToString:@"set_defib_config"]) {
        if (![value isKindOfClass:[NSDictionary class]] || [value count] == 0) { if (error) *error = @"set_defib_config: value must be an object"; return NO; }
        NSDictionary *ints = @{ @"shocks_to_convert": @[@0, @10], @"min_energy_j": @[@0, @360], @"cv_shocks_to_convert": @[@0, @10],
                                @"cv_min_energy_j": @[@0, @360], @"capture_threshold_ma": @[@0, @200], @"aed_energy_j": @[@50, @360],
                                @"aed_cpr_s": @[@30, @300] };
        NSArray *bools = @[@"unsync_shock_vf", @"sync_stays_on", @"capture_possible", @"mechanical_capture", @"voice_prompts"];
        NSArray *rhythms = @[@"post_shock_rhythm", @"cv_post_rhythm"];
        id om = value[@"outcome_mode"];
        if (om && !([om isEqual:@"instructor"] || [om isEqual:@"auto"])) { if (error) *error = @"outcome_mode: allowed instructor, auto"; return NO; }
        NSMutableDictionary *next = [_dCfg mutableCopy];
        for (NSString *k in value) {
            if (ints[k]) { NSInteger v; if (!SLIntValue(value[k], [ints[k][0] integerValue], [ints[k][1] integerValue], &v, k, error)) return NO; next[k] = @(v); }
            else if ([bools containsObject:k]) { BOOL b; if (!SLBoolValue(value[k], &b, k, error)) return NO; next[k] = @(b); }
            else if ([rhythms containsObject:k]) {
                if (![value[k] isKindOfClass:[NSString class]] || ![[SimulationState supportedRhythms] containsObject:value[k]]) {
                    if (error) *error = [NSString stringWithFormat:@"%@: unsupported rhythm", k]; return NO;
                }
                next[k] = value[k];
            } else if ([k isEqualToString:@"outcome_mode"]) { next[k] = value[k]; }
            else { if (error) *error = [NSString stringWithFormat:@"set_defib_config: unknown key '%@'", k]; return NO; }
        }
        _dCfg = next;
    } else {
        *handled = NO;
    }
    return YES;
}

- (NSDictionary *)defibDictionary:(SLDefibInfo *)d {
    NSArray *modes = @[@"off", @"aed", @"manual", @"pacer"];
    NSArray *phases = @[@"pads", @"analyzing", @"charging", @"ready", @"cpr"];
    NSArray *charges = @[@"none", @"charging", @"ready"];
    return @{ @"mode": modes[d.mode], @"pads_connected": @(d.padsConnected), @"energy_j": @(d.energy),
              @"charge": charges[d.charge], @"charge_progress": @(round(d.chargeProgress * 100) / 100),
              @"charged_energy_j": @(d.chargedEnergy), @"sync": @(d.sync), @"sync_pending": @(d.syncPending),
              @"aed_phase": phases[d.aedPhase], @"aed_remaining_s": @(d.aedRemaining), @"aed_shock_advised": @(d.aedShockAdvised),
              @"message": d.message ?: @"", @"shock_count": @(d.shockCount), @"last_shock_energy_j": @(d.lastShockEnergy),
              @"pacer": @{ @"rate_ppm": @(d.paceRate), @"output_ma": @(d.paceOutput), @"demand": @(d.paceDemand),
                           @"running": @(d.paceRunning), @"paused": @(d.pacePaused), @"active": @(d.paceActive), @"capture": @(d.paceCapture),
                           @"mechanical_capture": @(d.paceMechanical) },
              @"outcome_pending": @(_dDecision), @"outcome_shock": @(_dDecisionShock),
              @"outcome_from": _dDecisionFrom ?: [NSNull null], @"outcome_sync": @(_dDecisionSync), @"outcome_energy_j": @(_dDecisionEnergy),
              @"config": [_dCfg copy], @"energies": [SimulationState defibEnergies], @"events": d.events ?: @[] };
}

- (void)noteOximeterSeen { @synchronized (self) { _oxiSeenAt = self.clock(); } }

- (void)resetScenario {
    @synchronized (self) { [self resetValues]; _devicePowered = NO; _revision++; }
}

- (SLSnapshot *)snapshot {
    SLSnapshot *s = [SLSnapshot new];
    @synchronized (self) {
        s.revision = _revision; s.rhythm = _rhythm;
        s.heartRate = _hr; s.spo2 = _spo2; s.respRate = _rr; s.etco2 = _etco2;
        s.systolic = _sys; s.diastolic = _dia;
        s.spo2SignalSetting = _spo2Valid;
        // posizioni effettive: quelle indicate dalle regie, altrimenti quelle di serie per i sensori collegati
        NSMutableDictionary *sites = [_sites mutableCopy];
        NSDictionary *on = @{ SLSensorSpO2: @(_spo2On), SLSensorNIBP: @(_nibpOn), SLSensorART: @(_artOn), SLSensorOxi: @(_oxiOn) };
        for (NSString *k in on) if ([on[k] boolValue] && !sites[k] && SLDefaultSite(k)) sites[k] = SLDefaultSite(k);
        s.sensorSites = sites;
        // bracciale in misura sullo stesso braccio della sonda: il dito non è perfuso, niente pletismo
        NSString *cuffSide = SLSiteSide(sites[SLSensorNIBP]), *spo2Side = SLSiteSide(sites[SLSensorSpO2]);
        s.spo2CuffOccluded = _spo2On && _nibpOn && _nibpStatus == SLNibpMeasuring && cuffSide && spo2Side &&
                             [sites[SLSensorNIBP] hasPrefix:@"upper_arm"] && [sites[SLSensorSpO2] hasPrefix:@"finger"] && [cuffSide isEqualToString:spo2Side];
        s.spo2SignalValid = _spo2Valid && !s.spo2CuffOccluded;
        // linea arteriosa sullo stesso braccio del bracciale in misura: a valle del bracciale chiuso la curva perde la pulsatilità
        NSString *artSide = SLSiteSide(sites[SLSensorART]);
        s.artCuffOccluded = _artOn && _nibpOn && _nibpStatus == SLNibpMeasuring && cuffSide && artSide &&
                            [sites[SLSensorNIBP] hasPrefix:@"upper_arm"] && SLArmArterySite(sites[SLSensorART]) && [cuffSide isEqualToString:artSide];
        s.ecgConnected = _ecgOn; s.spo2Connected = _spo2On; s.nibpConnected = _nibpOn;
        s.etco2Connected = _etco2On; s.artConnected = _artOn;
        s.tempConnected = _tempOn; s.padsConnected = _padsOn;
        s.oxiConnected = _oxiOn; s.oxiPower = _oxiPower; s.oxiVolume = _oxiVolume; s.oxiLimits = _oxiLimits;
        s.oxiSensorSince = _oxiOn ? MAX(0, self.clock() - _oxiConnAt) : -1;
        s.oxiOnline = _oxiSeenAt > 0 && self.clock() - _oxiSeenAt < 6;
        s.oxiMutedRemaining = (NSInteger)ceil(MAX(0, _oxiMutedUntil - self.clock()));
        NSString *oxiSide = SLSiteSide(sites[SLSensorOxi]);
        s.oxiCuffOccluded = _oxiOn && _nibpOn && _nibpStatus == SLNibpMeasuring && cuffSide && oxiSide &&
                            [sites[SLSensorNIBP] hasPrefix:@"upper_arm"] && [sites[SLSensorOxi] hasPrefix:@"finger"] && [cuffSide isEqualToString:oxiSide];
        s.spo2DelaySec = _spo2Delay; s.spo2LowPerfusionFlag = _spo2LowPerf;
        s.operatorTouch = _touchUntil > self.clock();
        s.patientMotion = _motion; s.patientMotionRemaining = (_motion && _motionUntil > 0) ? (NSInteger)ceil(MAX(0, _motionUntil - self.clock())) : 0;
        s.spo2Searching = _spo2On && _spo2Stage == 1; s.spo2Acquiring = _spo2On && _spo2Stage < 3;
        s.temperatureTenths = _tempT; s.crtTenths = _crtT; s.crtEnabled = _crtOn; s.crtAssessSeq = _crtSeq; s.layout = _layout;
        s.devicePowered = _devicePowered;
        s.defib = [self defibInfoAt:self.clock()];
        s.nibpStatus = _nibpStatus; s.nibpError = _nibpError; s.nibpStartedAt = _nibpStartedAt;
        s.nibpTarget = _nibpTarget; s.nibpEnd = _nibpEnd; s.nibpCuffOK = _nibpCuffOK;
        s.nibpLastSystolic = _nibpLastSys; s.nibpLastDiastolic = _nibpLastDia; s.nibpMeasuredAt = _nibpMeasuredAt;
        s.alarmsMuted = _muted;
        s.alarmsMutedRemaining = _muted ? (NSInteger)ceil(MAX(0, _mutedUntil - self.clock())) : 0; s.qrsBeepEnabled = _qrsBeep; s.volume = _volume;
        s.simulationRunning = _running;
        s.scenarioTime = _scenAccum + (_running && _scenSince > 0 ? self.clock() - _scenSince : 0);
        s.alarmLimits = _limits;
        s.autoPhysiology = _autoPhysio;
        s.cprActive = _cpr;
        // ventilazione manuale: con l'RCP in corso, o in apnea, il paziente non respira da solo: il capnogramma mostra
        // solo le insufflazioni dei partecipanti (segnalate dall'istruttore) e la FR è quella delle insufflazioni.
        s.respRateSet = _rr; s.etco2Set = _etco2;
        BOOL manual = _cpr || _rr < 1;
        s.ventilationManual = manual;
        if (manual) {
            NSTimeInterval now = self.clock();
            if (!_breaths) _breaths = [NSMutableArray array];
            while (_breaths.count && now - _breaths.firstObject.doubleValue > 60) [_breaths removeObjectAtIndex:0];
            s.breathTimes = [_breaths copy];
            BOOL recent = _breaths.count && now - _breaths.lastObject.doubleValue <= 30;      // dopo 30 s senza ventilare: EtCO2 "---"
            s.respRate = recent ? (NSInteger)MAX(1, _breaths.count) : 0;
            if (_etco2 < 1 && recent) s.etco2 = _cpr ? 15 : 35;          // un'insufflazione porta sempre un po' di CO2
        } else s.breathTimes = @[];
        s.alarmEnabled = [_alarmOn copy];                // copia: il dizionario originale cambia con i comandi
        s.nibpIntervalMin = _nibpInterval; s.nibpNextAt = _nibpNext;
        NSTimeInterval now = self.clock();
        NSMutableDictionary *tr = [NSMutableDictionary dictionary];
        for (NSString *k in _ramps) {
            NSDictionary *r = _ramps[k];
            double rem = [r[@"start"] doubleValue] + [r[@"dur"] doubleValue] - now;
            tr[k] = @{ @"to": r[@"to"], @"remaining_s": @((NSInteger)ceil(MAX(0, rem))) };
        }
        s.transitions = tr;
        if (_chainActive && _chainIndex < (NSInteger)_chainSteps.count) {
            NSDictionary *st = _chainSteps[_chainIndex];
            double len = _chainWaiting ? [st[@"wait_s"] doubleValue] : [st[@"duration_s"] doubleValue];
            NSString *lbl = [st[@"label"] isKindOfClass:[NSString class]] ? st[@"label"] : @"";
            s.chain = @{ @"active": @YES, @"name": _chainName ?: @"", @"step": @(_chainIndex + 1), @"steps": @(_chainSteps.count),
                         @"label": lbl, @"phase": _chainWaiting ? @"waiting" : @"running",
                         @"remaining_s": @((NSInteger)ceil(MAX(0, _chainPhaseStart + len - now))) };
        } else {
            s.chain = @{ @"active": @NO };
        }
    }
    return s;
}

#pragma mark Validazione

static BOOL SLIsBool(id v) {
    return [v isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID();
}

static BOOL SLIntValue(id v, NSInteger min, NSInteger max, NSInteger *out, NSString *name, NSString **err) {
    if (![v isKindOfClass:[NSNumber class]] || SLIsBool(v)) {
        if (err) *err = [NSString stringWithFormat:@"%@: numeric value required", name];
        return NO;
    }
    double d = [v doubleValue];
    if (d != d || d < min || d > max) {   // d != d -> NaN
        if (err) *err = [NSString stringWithFormat:@"%@: value out of range [%ld..%ld]", name, (long)min, (long)max];
        return NO;
    }
    *out = (NSInteger)lround(d);
    return YES;
}

static BOOL SLBoolValue(id v, BOOL *out, NSString *name, NSString **err) {
    if (!SLIsBool(v)) {
        if (err) *err = [NSString stringWithFormat:@"%@: boolean value required", name];
        return NO;
    }
    *out = [v boolValue];
    return YES;
}

- (void)spo2Connect:(BOOL)on {
    if (on && !_spo2On) {                         // sonda appena messa: ricerca del polso, poi il valore
        _spo2ConnAt = self.clock();
        _spo2Stage = _spo2Delay > 0 ? 1 : 3;
    }
    _spo2On = on;
}

- (BOOL)setSensor:(NSString *)sensor connected:(BOOL)on error:(NSString **)error {
    if ([sensor isEqualToString:SLSensorECG]) _ecgOn = on;
    else if ([sensor isEqualToString:SLSensorSpO2]) [self spo2Connect:on];
    else if ([sensor isEqualToString:SLSensorNIBP]) {
        if (on && !_nibpOn && _nibpStatus == SLNibpError && [_nibpError isEqualToString:@"cuff"]) { _nibpStatus = SLNibpIdle; _nibpError = nil; }   // bracciale messo: l'errore di perdita sparisce
        _nibpOn = on;
        if (!on && _nibpStatus == SLNibpMeasuring) {         // bracciale staccato durante la misura
            _nibpStatus = SLNibpError; _nibpError = @"cuff"; _nibpLastSys = -1; _nibpLastDia = -1; _nibpMeasuredAt = nil;   // perdita: il valore precedente non è più valido
        }
    }
    else if ([sensor isEqualToString:SLSensorEtCO2]) _etco2On = on;
    else if ([sensor isEqualToString:SLSensorART]) _artOn = on;
    else if ([sensor isEqualToString:SLSensorTemp]) _tempOn = on;
    else if ([sensor isEqualToString:SLSensorPads]) { if (on != _padsOn) { _padsOn = on; [self defibPadsChanged]; } }
    else if ([sensor isEqualToString:SLSensorOxi]) { if (on && !_oxiOn) _oxiConnAt = self.clock(); _oxiOn = on; }
    else {
        if (error) *error = [NSString stringWithFormat:@"sensor: unsupported value; allowed: %@",
                             [[SimulationState supportedSensors] componentsJoinedByString:@", "]];
        return NO;
    }
    return YES;
}

- (BOOL)validateTransition:(NSDictionary *)value error:(NSString **)error {
    @synchronized (self) { return [self transition:value apply:NO error:error]; }
}

- (BOOL)applyCommand:(NSDictionary *)cmd error:(NSString **)error {
    if (![cmd isKindOfClass:[NSDictionary class]]) { if (error) *error = @"body must be a JSON object"; return NO; }
    id dev = cmd[@"device_id"];
    if (dev && (![dev isKindOfClass:[NSString class]] || ![dev isEqualToString:self.deviceId])) {
        if (error) *error = @"device_id does not match this monitor"; return NO;
    }
    NSString *name = cmd[@"command"];
    if (![name isKindOfClass:[NSString class]]) { if (error) *error = @"missing 'command'"; return NO; }
    id value = cmd[@"value"];

    @synchronized (self) {
        BOOL handled = NO;
        if (![self defibCommand:name value:value handled:&handled error:error]) return NO;
        if (handled) { _revision++; return YES; }
        if ([name isEqualToString:@"set_heart_rate"]) {
            NSInteger v; if (!SLIntValue(value, kHRMin, kHRMax, &v, @"heart_rate_bpm", error)) return NO;
            _hr = v; [_ramps removeObjectForKey:@"heart_rate_bpm"];
            [self asystoleIfZeroRate];
        } else if ([name isEqualToString:@"set_rhythm"]) {
            if (![value isKindOfClass:[NSString class]] || ![[SimulationState supportedRhythms] containsObject:value]) {
                if (error) *error = [NSString stringWithFormat:@"rhythm: unsupported value; allowed: %@",
                                     [[SimulationState supportedRhythms] componentsJoinedByString:@", "]];
                return NO;
            }
            [self applyRhythm:value];
        } else if ([name isEqualToString:@"set_spo2"]) {
            NSInteger v; if (!SLIntValue(value, kSpO2Min, kSpO2Max, &v, @"spo2_percent", error)) return NO;
            _spo2 = v; [_ramps removeObjectForKey:@"spo2_percent"];
            if (_apneaSince > 0) { _spo2PreApnea = v; _apneaSince = self.clock() - 20; }   // in apnea: riparte da qui
        } else if ([name isEqualToString:@"set_spo2_delay"]) {
            // secondi tra il collegamento della sonda e la comparsa del valore (metà: ricerca, metà: onda senza numero)
            NSInteger v; if (!SLIntValue(value, 0, 120, &v, @"spo2_delay_s", error)) return NO;
            _spo2Delay = v;
        } else if ([name isEqualToString:@"patient_touch"]) {
            // PUSH: un operatore tocca / scuote il paziente per N secondi (1-10, predefinito 3), con qualsiasi ritmo
            double dur = 3;
            if (value && ![value isKindOfClass:[NSNull class]]) {
                if (![value isKindOfClass:[NSNumber class]] || SLIsBool(value) || [value doubleValue] < 1 || [value doubleValue] > 10) { if (error) *error = @"patient_touch: seconds 1-10"; return NO; }
                dur = [value doubleValue];
            }
            _touchUntil = MAX(_touchUntil, self.clock() + dur);
            [self defibLog:@"Operatore tocca il paziente" instructor:YES];
        } else if ([name isEqualToString:@"set_patient_motion"]) {
            // "off" | "light" | "strong"  oppure  {"level": ..., "duration_s": 0-120}  (0 = finché non viene fermato)
            NSString *lv = value; double dur = 0;
            if ([value isKindOfClass:[NSDictionary class]]) {
                lv = value[@"level"];
                id d = value[@"duration_s"];
                if (d) { if (![d isKindOfClass:[NSNumber class]] || SLIsBool(d) || [d doubleValue] < 0 || [d doubleValue] > 120) { if (error) *error = @"duration_s must be 0-120"; return NO; } dur = [d doubleValue]; }
            }
            NSUInteger li = [lv isKindOfClass:[NSString class]] ? [@[@"off", @"light", @"strong"] indexOfObject:lv] : NSNotFound;
            if (li == NSNotFound) { if (error) *error = @"patient motion must be off, light or strong"; return NO; }
            if (li > 0 && ![self effectivePulse]) { if (error) *error = @"patient motion requires a rhythm with pulse (use patient_touch)"; return NO; }
            _motion = (NSInteger)li;
            _motionUntil = (_motion && dur > 0) ? self.clock() + dur : 0;
            if (_motion == 2 && _nibpStatus == SLNibpMeasuring) _nibpMotionHit = YES;
            if (_motion) [self defibLog:_motion == 2 ? @"Movimenti marcati del paziente" : @"Movimenti lievi del paziente" instructor:YES];
        } else if ([name isEqualToString:@"set_spo2_low_perfusion"]) {
            BOOL b; if (!SLBoolValue(value, &b, @"spo2_low_perfusion", error)) return NO;
            _spo2LowPerf = b;
        } else if ([name isEqualToString:@"set_temperature"]) {
            if (![value isKindOfClass:[NSNumber class]] || SLIsBool(value) || [value doubleValue] != [value doubleValue]
                || [value doubleValue] < 25.0 || [value doubleValue] > 45.0) {
                if (error) *error = @"temperature_c: value out of range [25..45]"; return NO;
            }
            _tempT = lround([value doubleValue] * 10.0);
        } else if ([name isEqualToString:@"set_crt"]) {
            if (![value isKindOfClass:[NSNumber class]] || SLIsBool(value) || [value doubleValue] != [value doubleValue]
                || [value doubleValue] < 0.5 || [value doubleValue] > 10.0) {
                if (error) *error = @"crt_s: value out of range [0.5..10]"; return NO;
            }
            _crtT = lround([value doubleValue] * 10.0);
        } else if ([name isEqualToString:@"assess_crt"]) {
            // l'istruttore fa valutare il refill (il partecipante lo chiede a voce invece di toccare il monitor):
            // sul monitor parte la stessa valutazione del tocco, ~3 s poi compare il tempo
            _crtSeq++; _crtOn = YES;
        } else if ([name isEqualToString:@"set_crt_enabled"]) {
            BOOL b; if (!SLBoolValue(value, &b, @"crt_enabled", error)) return NO;
            _crtOn = b;
        } else if ([name isEqualToString:@"set_layout"]) {
            if (![value isKindOfClass:[NSString class]] || ![[SimulationState supportedLayouts] containsObject:value]) {
                if (error) *error = [@"layout: allowed " stringByAppendingString:[[SimulationState supportedLayouts] componentsJoinedByString:@", "]]; return NO;
            }
            _layout = [value copy];
        } else if ([name isEqualToString:@"set_spo2_signal_valid"]) {
            BOOL b; if (!SLBoolValue(value, &b, @"spo2_signal_valid", error)) return NO;
            _spo2Valid = b;
        } else if ([name isEqualToString:@"set_sensor"]) {
            // {"command":"set_sensor","value":{"sensor":"ecg","connected":false}}
            if (![value isKindOfClass:[NSDictionary class]] || ![value[@"sensor"] isKindOfClass:[NSString class]]) {
                if (error) *error = @"set_sensor: value must be {\"sensor\":name,\"connected\":bool}"; return NO;
            }
            BOOL b; if (!SLBoolValue(value[@"connected"], &b, @"connected", error)) return NO;
            id site = value[@"site"];           // facoltativo: dove è messo il sensore sul paziente
            if (site && site != [NSNull null]) {
                NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"] invertedSet];
                if (![site isKindOfClass:[NSString class]] || [site length] == 0 || [site length] > 24 || [site rangeOfCharacterFromSet:bad].location != NSNotFound) {
                    if (error) *error = @"site: lowercase letters, digits and _ (max 24)"; return NO;
                }
            }
            if (![self setSensor:value[@"sensor"] connected:b error:error]) return NO;
            if (!b) [_sites removeObjectForKey:value[@"sensor"]];
            else if ([site isKindOfClass:[NSString class]]) _sites[value[@"sensor"]] = site;
            // senza lato esplicito vale quello di serie (SLDefaultSite, applicato nello snapshot): uguale in monitor e regie
        } else if ([name isEqualToString:@"set_probe_connected"]) {          // compatibilità v0.1 (SpO2)
            BOOL b; if (!SLBoolValue(value, &b, @"probe_connected", error)) return NO;
            [self spo2Connect:b];
        } else if ([name isEqualToString:@"set_resp_rate"]) {
            NSInteger v; if (!SLIntValue(value, kRRMin, kRRMax, &v, @"respiratory_rate_rpm", error)) return NO;
            NSInteger oldRR = _rr;
            _rr = v; [_ramps removeObjectForKey:@"respiratory_rate_rpm"];
            [self coupleEtCO2FromRR:oldRR to:v duration:45];
        } else if ([name isEqualToString:@"set_etco2"]) {
            NSInteger v; if (!SLIntValue(value, kEtCO2Min, kEtCO2Max, &v, @"etco2_mmhg", error)) return NO;
            _etco2 = v; [_ramps removeObjectForKey:@"etco2_mmhg"];
        } else if ([name isEqualToString:@"set_bp"] || [name isEqualToString:@"set_nibp"]) {
            // PA del paziente: la mostra l'ART in continuo e la misura la NIBP
            if (![value isKindOfClass:[NSDictionary class]]) { if (error) *error = @"set_bp: value must be {\"systolic\":n,\"diastolic\":n}"; return NO; }
            NSInteger s, d;
            if (!SLIntValue(value[@"systolic"], kSysMin, kSysMax, &s, @"systolic_mmhg", error)) return NO;
            if (!SLIntValue(value[@"diastolic"], kDiaMin, kDiaMax, &d, @"diastolic_mmhg", error)) return NO;
            if (d >= s && s > 0) { if (error) *error = @"set_bp: diastolic must be lower than systolic"; return NO; }
            _sys = s; _dia = d;
            [_ramps removeObjectForKey:@"systolic_mmhg"]; [_ramps removeObjectForKey:@"diastolic_mmhg"];
            if (_baseline) {   // durante l'arresto: la nuova PA diventa l'obiettivo del ROSC
                NSMutableDictionary *nb = [_baseline mutableCopy]; nb[@"systolic_mmhg"] = @(s); nb[@"diastolic_mmhg"] = @(d); _baseline = nb;
            }
        } else if ([name isEqualToString:@"mute_alarms"]) {
            // true/false (silenziamento standard) oppure un numero di secondi 1..900 (es. alcuni dispositivi: 120 s, sospensione 15 min)
            BOOL b = YES; NSInteger secs = 0;
            if (value && [value isKindOfClass:[NSNumber class]] && !SLIsBool(value)) {
                if (!SLIntValue(value, 1, 900, &secs, @"alarms_muted_s", error)) return NO;
            } else if (value && !SLBoolValue(value, &b, @"alarms_muted", error)) return NO;
            _muted = b;
            _mutedUntil = b ? self.clock() + (secs > 0 ? secs : self.muteDuration) : 0;
        } else if ([name isEqualToString:@"set_oximeter"]) {
            // saturimetro palmare: {power, volume, alarm_limits{spo2_low,spo2_high,pr_low,pr_high}, mute_s (0 = riattiva)}
            if (![value isKindOfClass:[NSDictionary class]]) { if (error) *error = @"value: object expected"; return NO; }
            BOOL b; NSInteger v;
            if (value[@"power"]) { if (!SLBoolValue(value[@"power"], &b, @"power", error)) return NO; _oxiPower = b; if (!b) _oxiMutedUntil = 0; }
            if (value[@"volume"]) { if (!SLIntValue(value[@"volume"], 0, 100, &v, @"volume", error)) return NO; _oxiVolume = v; }
            if (value[@"mute_s"]) { if (!SLIntValue(value[@"mute_s"], 0, 900, &v, @"mute_s", error)) return NO; _oxiMutedUntil = v ? self.clock() + v : 0; }
            NSDictionary *lim = value[@"alarm_limits"];
            if (lim) {
                if (![lim isKindOfClass:[NSDictionary class]]) { if (error) *error = @"alarm_limits: object expected"; return NO; }
                NSMutableDictionary *next = [_oxiLimits mutableCopy]; NSDictionary *rg = SLOxiLimitRanges();
                for (NSString *k in lim) {
                    if (!rg[k]) { if (error) *error = [NSString stringWithFormat:@"alarm_limits.%@: unknown limit", k]; return NO; }
                    if (!SLIntValue(lim[k], [rg[k][0] integerValue], [rg[k][1] integerValue], &v, k, error)) return NO; next[k] = @(v);
                }
                if ([next[@"spo2_low"] integerValue] >= [next[@"spo2_high"] integerValue] || [next[@"pr_low"] integerValue] >= [next[@"pr_high"] integerValue]) {
                    if (error) *error = @"alarm_limits: low limit must be below high limit"; return NO;
                }
                _oxiLimits = next;
            }
        } else if ([name isEqualToString:@"set_qrs_beep"]) {
            BOOL b; if (!SLBoolValue(value, &b, @"qrs_beep_enabled", error)) return NO;
            _qrsBeep = b;
        } else if ([name isEqualToString:@"set_volume"]) {
            NSInteger v; if (!SLIntValue(value, 0, 100, &v, @"volume_percent", error)) return NO;
            _volume = v;
        } else if ([name isEqualToString:@"set_alarm_limits"]) {
            // {"command":"set_alarm_limits","value":{"hr_low":45,"hr_high":130}}  (anche parziale)
            if (![value isKindOfClass:[NSDictionary class]] || [value count] == 0) {
                if (error) *error = @"set_alarm_limits: value must be an object like {\"hr_low\":50}"; return NO;
            }
            NSMutableDictionary *next = [_limits mutableCopy];
            NSDictionary *ranges = SLLimitRanges();
            for (NSString *k in value) {
                NSArray *r = ranges[k];
                if (!r) { if (error) *error = [NSString stringWithFormat:@"set_alarm_limits: unknown limit '%@'", k]; return NO; }
                NSInteger v; if (!SLIntValue(value[k], [r[0] integerValue], [r[1] integerValue], &v, k, error)) return NO;
                next[k] = @(v);
            }
            for (NSString *pfx in @[@"hr", @"rr", @"etco2", @"sys"]) {
                NSString *lo = [pfx stringByAppendingString:@"_low"], *hi = [pfx stringByAppendingString:@"_high"];
                if ([next[lo] integerValue] >= [next[hi] integerValue]) {
                    if (error) *error = [NSString stringWithFormat:@"set_alarm_limits: %@ must be lower than %@", lo, hi]; return NO;
                }
            }
            _limits = next;
        } else if ([name isEqualToString:@"reset_alarm_limits"]) {
            _limits = [[SimulationState defaultAlarmLimits] mutableCopy];
        } else if ([name isEqualToString:@"transition"]) {
            // {"command":"transition","value":{"params":{"heart_rate_bpm":140},"duration_s":60,"rhythm":"afib"}}
            if (![self transition:value apply:YES error:error]) return NO;
        } else if ([name isEqualToString:@"cancel_transitions"]) {
            // senza valore: tutte; con ["heart_rate_bpm", ...]: solo quei parametri (restano al valore raggiunto)
            if ([value isKindOfClass:[NSArray class]]) { for (id k in value) if ([k isKindOfClass:[NSString class]]) [_ramps removeObjectForKey:k]; }
            else if (value) { if (error) *error = @"cancel_transitions: value must be an array of parameter names"; return NO; }
            else [_ramps removeAllObjects];
        } else if ([name isEqualToString:@"run_chain"]) {
            // {"command":"run_chain","value":{"name":"...","steps":[{"wait_s":10,"duration_s":30,"rhythm":"vf","params":{...},"label":"..."}]}}
            NSArray *steps = [value isKindOfClass:[NSDictionary class]] ? value[@"steps"] : nil;
            if (![steps isKindOfClass:[NSArray class]] || steps.count == 0 || steps.count > 40) {
                if (error) *error = @"run_chain: value.steps must be an array of 1..40 steps"; return NO;
            }
            for (NSUInteger i = 0; i < steps.count; i++) {
                NSDictionary *st = steps[i]; NSInteger w;
                if (![st isKindOfClass:[NSDictionary class]]) { if (error) *error = [NSString stringWithFormat:@"run_chain: step %lu is not an object", (unsigned long)i + 1]; return NO; }
                if (st[@"wait_s"] && !SLIntValue(st[@"wait_s"], 0, 3600, &w, @"wait_s", error)) return NO;
                NSString *e2 = nil;
                if (![self transition:st apply:NO error:&e2]) { if (error) *error = [NSString stringWithFormat:@"run_chain: step %lu: %@", (unsigned long)i + 1, e2]; return NO; }
            }
            _chainSteps = [steps copy];
            NSString *nm = value[@"name"];
            _chainName = [nm isKindOfClass:[NSString class]] ? [nm substringToIndex:MIN(nm.length, (NSUInteger)60)] : @"catena";
            _chainIndex = 0; _chainWaiting = YES; _chainPhaseStart = self.clock(); _chainActive = YES;
            [self advanceChainAt:_chainPhaseStart];
        } else if ([name isEqualToString:@"stop_chain"]) {
            _chainActive = NO; [_ramps removeAllObjects];
        } else if ([name isEqualToString:@"set_auto_physiology"]) {
            BOOL b; if (!SLBoolValue(value, &b, @"auto_physiology", error)) return NO;
            _autoPhysio = b; if (!b) _baseline = nil;
        } else if ([name isEqualToString:@"set_alarm_enabled"]) {
            // {"command":"set_alarm_enabled","value":{"param":"hr","enabled":false}}
            NSString *pk = [value isKindOfClass:[NSDictionary class]] ? value[@"param"] : nil;
            if (![pk isKindOfClass:[NSString class]] || !_alarmOn[pk]) {
                if (error) *error = @"set_alarm_enabled: param must be one of hr, spo2, art, nibp, rr, etco2"; return NO;
            }
            BOOL b; if (!SLBoolValue(value[@"enabled"], &b, @"enabled", error)) return NO;
            _alarmOn[pk] = @(b);
        } else if ([name isEqualToString:@"ventilate"]) {
            // una insufflazione dei partecipanti (pallone, ventilatore, bocca a bocca): onda di CO2 e valore a monitor
            if (!(_cpr || _rr < 1)) { if (error) *error = @"ventilate: the patient is breathing on his own (only during CPR or apnoea)"; return NO; }
            if (!_breaths) _breaths = [NSMutableArray array];
            NSTimeInterval now = self.clock();
            if (!_breaths.count || now - _breaths.lastObject.doubleValue > 0.8) [_breaths addObject:@(now)];   // due tocchi ravvicinati = uno
        } else if ([name isEqualToString:@"set_cpr"]) {
            BOOL b; if (!SLBoolValue(value, &b, @"cpr_active", error)) return NO;
            if (b != _cpr) {
                _cpr = b;
                if (_autoPhysio && ![SimulationState rhythmHasPulse:_rhythm]) {
                    // RCP efficace: EtCO2 10-20 mmHg, ventilazioni 10/min; stop: crollo
                    if (b) { [self rampParam:@"etco2_mmhg" to:15 duration:10]; [self rampParam:@"respiratory_rate_rpm" to:10 duration:5]; }
                    else   { [self rampParam:@"etco2_mmhg" to:0 duration:15]; [self rampParam:@"respiratory_rate_rpm" to:0 duration:5]; }
                }
            }
        } else if ([name isEqualToString:@"set_nibp_interval"]) {
            // minuti tra due misure automatiche (0 = spenta); la prima parte dopo un intervallo
            NSInteger v; if (!SLIntValue(value, 0, 60, &v, @"nibp_interval_min", error)) return NO;
            if (![[SimulationState nibpIntervals] containsObject:@(v)]) { if (error) *error = @"nibp_interval_min: allowed 0,1,2,3,5,10,15,30,60"; return NO; }
            _nibpInterval = v; _nibpNext = v > 0 ? self.clock() + v * 60.0 : 0;
        } else if ([name isEqualToString:@"set_simulation_running"]) {
            BOOL b; if (!SLBoolValue(value, &b, @"simulation_running", error)) return NO;
            if (b != _running) {                                   // il timer di scenario non conta le pause
                if (b) { _scenSince = self.clock(); }
                else if (_scenSince > 0) { _scenAccum += self.clock() - _scenSince; _scenSince = 0; }
            }
            _running = b;
        } else if ([name isEqualToString:@"reset_clock"]) {
            // azzera SOLO l'orologio di scenario (parametri, sonde e contatori restano): lo usa l'istruttore
            // e l'avvio di uno scenario a fasi
            _scenAccum = 0; _scenSince = _running ? self.clock() : 0;
        } else if ([name isEqualToString:@"reset_scenario"]) {
            [self resetValues];
            _devicePowered = NO; // il reset spegne sempre il monitor (torna lo standby)
        } else {
            if (error) *error = [NSString stringWithFormat:@"unknown command '%@'", name];
            return NO;
        }
        _revision++;
    }
    return YES;
}

- (BOOL)startNibpMeasurementError:(NSString **)error {
    @synchronized (self) {
        if (_nibpStatus == SLNibpMeasuring) { if (error) *error = @"NIBP measurement already in progress"; return NO; }
        _nibpStatus = SLNibpMeasuring;
        _nibpError = nil; _nibpMotionHit = (_motion == 2);
        _nibpStartedAt = self.clock();
        _nibpCuffOK = _nibpOn;
        // gonfia ~30 mmHg sopra la sistolica (minimo 140); se non trova oscillazioni scende fino a 20
        _nibpTarget = MAX(140.0, (double)_sys + 30.0);
        BOOL pulse = [self effectivePulse] && _sys > 0;
        _nibpEnd = pulse ? MAX(20.0, (double)_dia - 12.0) : 20.0;
        _revision++;
    }
    return YES;
}

- (void)tickAtTime:(NSTimeInterval)now {
    @synchronized (self) {
        [self defibTickAt:now];
        if (_spo2On && _spo2Stage < 3) {          // acquisizione SpO2: ricerca -> onda -> valore
            NSInteger st = now - _spo2ConnAt >= _spo2Delay ? 3 : (now - _spo2ConnAt >= _spo2Delay / 2.0 ? 2 : 1);
            if (st != _spo2Stage) { _spo2Stage = st; _revision++; }
        }
        [self advanceChainAt:now];
        [self apneaPhysiologyAt:now];
        // NIBP automatica: quando scade l'intervallo parte una misura (se non ce n'è già una)
        if (_nibpInterval > 0 && _nibpNext > 0 && now >= _nibpNext) {
            if (_nibpStatus != SLNibpMeasuring) {
                _nibpStatus = SLNibpMeasuring; _nibpError = nil; _nibpMotionHit = (_motion == 2); _nibpStartedAt = now; _nibpCuffOK = _nibpOn;
                _nibpTarget = MAX(140.0, (double)_sys + 30.0);
                BOOL pulse = [self effectivePulse] && _sys > 0;
                _nibpEnd = pulse ? MAX(20.0, (double)_dia - 12.0) : 20.0;
            }
            _nibpNext = now + _nibpInterval * 60.0;
            _revision++;
        }
        if (_ramps.count) [self advanceRampsAt:now];
        for (NSDictionary *sc in [_scheduled copy]) {
            if (now >= [sc[@"at"] doubleValue]) {
                _rampStartOverride = [sc[@"at"] doubleValue];        // la rampa parte all'istante programmato
                [self rampParam:sc[@"key"] to:[sc[@"to"] integerValue] duration:[sc[@"dur"] doubleValue]];
                _rampStartOverride = 0;
                [_scheduled removeObject:sc];
                [self advanceRampsAt:now];                            // applica subito il tratto già trascorso
            }
        }
        if (_motion && _motionUntil > 0 && now >= _motionUntil) { _motion = 0; _motionUntil = 0; _revision++; }   // fine del movimento a tempo
        if (_motion && ![self effectivePulse]) { _motion = 0; _motionUntil = 0; _revision++; }                     // senza polso il paziente non si muove
        if (_touchUntil > 0 && now >= _touchUntil) { _touchUntil = 0; _revision++; }
        if (_nibpStatus == SLNibpMeasuring && _motion == 2) _nibpMotionHit = YES;
        if (_nibpStatus == SLNibpMeasuring) {
            SLSnapshot *s = [SLSnapshot new];
            s.nibpStatus = _nibpStatus; s.nibpStartedAt = _nibpStartedAt;
            s.nibpTarget = _nibpTarget; s.nibpEnd = _nibpEnd; s.nibpCuffOK = _nibpCuffOK;
            if (now - _nibpStartedAt >= SLNibpTotalDuration(s)) {
                if (!_nibpCuffOK) {
                    _nibpStatus = SLNibpError; _nibpError = @"cuff"; _nibpLastSys = -1; _nibpLastDia = -1; _nibpMeasuredAt = nil;   // perdita: il valore precedente non è più valido
                } else if (_nibpMotionHit) {
                    _nibpStatus = SLNibpError; _nibpError = @"motion";      // artefatto da movimento: misura non riuscita
                } else if ([self effectivePulse] && _sys > 0) {
                    // l'oscillometria non coincide mai esattamente con la PA invasiva: scarto di pochi mmHg
                    NSInteger js = (NSInteger)arc4random_uniform(9) - 4, jd = (NSInteger)arc4random_uniform(7) - 3;
                    _nibpLastSys = MAX(0, _sys + js); _nibpLastDia = MAX(0, MIN(_nibpLastSys - 5, _dia + jd));
                    _nibpStatus = SLNibpComplete;
                    _nibpMeasuredAt = [NSDate date];
                } else {
                    // Senza polso il bracciale non rileva oscillazioni
                    _nibpStatus = SLNibpError; _nibpError = @"no_pulse";
                }
                _revision++;
            }
        }
        if (_muted && _mutedUntil > 0 && now >= _mutedUntil) {
            _muted = NO; _mutedUntil = 0; _revision++;
        }
    }
}

static NSString *SLNibpStatusName(SLNibpStatus s) {
    switch (s) {
        case SLNibpMeasuring: return @"measuring";
        case SLNibpComplete:  return @"complete";
        case SLNibpError:     return @"error";
        default:              return @"idle";
    }
}

- (NSDictionary *)stateDictionary {
    SLSnapshot *s = [self snapshot];
    id null = [NSNull null];
    NSDictionary *defib; @synchronized (self) { defib = [self defibDictionary:s.defib]; }
    return @{
        @"device_id": self.deviceId,
        @"device_type": @"multiparameter",
        @"product": @"SimulaFranz_Monitor",
        @"version": ([[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?"),
        @"revision": @(s.revision),
        @"monitor_on": @(s.devicePowered),
        @"rhythm": s.rhythm,
        @"heart_rate_bpm": @(s.heartRate),
        @"displayed_heart_rate_bpm": s.displayedHeartRate >= 0 ? @(s.displayedHeartRate) : null,
        @"pulse_present": @(s.pulsePresent),
        @"spo2_percent": @(s.spo2),
        @"spo2_signal_valid": @(s.spo2SignalSetting),
        @"spo2_cuff_occluded": @(s.spo2CuffOccluded), @"art_cuff_occluded": @(s.artCuffOccluded),
        @"sensor_sites": s.sensorSites ?: @{},
        @"probe_connected": @(s.spo2Connected),
        @"spo2_displayed": s.spo2Displayable ? @(s.spo2) : null,
        @"spo2_low_perfusion": @(s.lowPerfusion),
        // valori VERI impostati dall'istruttore; in ventilazione manuale il monitor mostra quelli misurati (sotto)
        @"respiratory_rate_rpm": @((NSInteger)lround(s.respRateSet)), @"respiratory_rate_measured": @(s.respRate),
        @"etco2_mmhg": @(s.etco2Set),
        @"etco2_displayed": (s.etco2Connected && s.respRate > 0) ? @(s.etco2) : null,
        @"systolic_mmhg": @(s.systolic),
        @"diastolic_mmhg": @(s.diastolic),
        @"nibp_systolic_mmhg": @(s.systolic),
        @"nibp_diastolic_mmhg": @(s.diastolic),
        @"art_displayed_systolic_mmhg": s.artDisplayedSystolic >= 0 ? @(s.artDisplayedSystolic) : null,
        @"art_displayed_diastolic_mmhg": s.artDisplayedDiastolic >= 0 ? @(s.artDisplayedDiastolic) : null,
        @"nibp_status": SLNibpStatusName(s.nibpStatus),
        @"nibp_error": s.nibpError ?: null,
        @"nibp_last_systolic_mmhg": s.nibpLastSystolic >= 0 ? @(s.nibpLastSystolic) : null,
        @"nibp_last_diastolic_mmhg": s.nibpLastDiastolic >= 0 ? @(s.nibpLastDiastolic) : null,
        @"sensors": @{ SLSensorECG: @(s.ecgConnected), SLSensorSpO2: @(s.spo2Connected),
                       SLSensorNIBP: @(s.nibpConnected), SLSensorEtCO2: @(s.etco2Connected),
                       SLSensorART: @(s.artConnected), SLSensorTemp: @(s.tempConnected), SLSensorPads: @(s.padsConnected),
                       SLSensorOxi: @(s.oxiConnected) },
        @"alarms_muted": @(s.alarmsMuted),
        @"alarms_muted_remaining_s": @(s.alarmsMutedRemaining),
        @"qrs_beep_enabled": @(s.qrsBeepEnabled),
        @"volume_percent": @(s.volume),
        @"simulation_running": @(s.simulationRunning),
        @"scenario_time_s": @((NSInteger)floor(s.scenarioTime)),
        @"supported_rhythms": [SimulationState supportedRhythms],
        @"supported_sensors": [SimulationState supportedSensors],
        @"alarm_limits": s.alarmLimits,
        @"auto_physiology": @(s.autoPhysiology),
        @"cpr_active": @(s.cprActive), @"ventilation_manual": @(s.ventilationManual), @"breaths_last_min": @(s.breathTimes.count),
        @"pulse_rate_bpm": @(s.pulseRate),
        @"alarm_enabled": s.alarmEnabled,
        @"nibp_interval_min": @(s.nibpIntervalMin),
        @"nibp_next_in_s": s.nibpIntervalMin > 0 ? @((NSInteger)ceil(MAX(0, s.nibpNextAt - self.clock()))) : null,
        @"transitions": s.transitions,
        @"chain": s.chain,
        @"spo2_delay_s": @(s.spo2DelaySec),
        @"spo2_acquiring": @(s.spo2Acquiring),
        @"spo2_low_perfusion_flag": @(s.spo2LowPerfusionFlag),
        @"patient_motion": @[@"off", @"light", @"strong"][(NSUInteger)MAX(0, MIN(2, s.patientMotion))], @"patient_motion_remaining_s": @(s.patientMotionRemaining), @"operator_touch": @(s.operatorTouch),
        @"temperature_c": @(s.temperatureTenths / 10.0),
        @"temperature_displayed": s.tempConnected ? @(s.temperatureTenths / 10.0) : null,
        @"crt_s": @(s.crtTenths / 10.0),
        @"crt_enabled": @(s.crtEnabled), @"crt_assess_seq": @(s.crtAssessSeq),
        @"layout": s.layout ?: @"generic_icu",
        @"layouts": [SimulationState layoutCatalog],
        @"oximeter": @{ @"power": @(s.oxiPower), @"online": @(s.oxiOnline), @"sensor_connected": @(s.oxiConnected),
                        @"sensor_since_s": s.oxiConnected ? @(floor(s.oxiSensorSince)) : null, @"site": s.sensorSites[SLSensorOxi] ?: null,
                        @"cuff_occluded": @(s.oxiCuffOccluded), @"alarm_limits": s.oxiLimits ?: @{}, @"volume": @(s.oxiVolume),
                        @"muted_remaining_s": @(s.oxiMutedRemaining) },
        @"defib": defib,
    };
}

@end
