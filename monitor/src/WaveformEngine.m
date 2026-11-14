#import "WaveformEngine.h"
#import "SimulationState.h"
#include <math.h>

#define SL_MAX_BEATS 16
#define SL_LOOKAHEAD 0.35   // s: serve per disegnare l'onda P prima del QRS

typedef NS_ENUM(NSInteger, SLMorph) { SLMorphNarrow = 0, SLMorphWide, SLMorphPEA, SLMorphPaced };

typedef struct {
    NSTimeInterval t;     // istante del picco R
    double rr;            // intervallo rispetto al battito precedente (s)
    SLMorph morph;
    BOOL hasP;
    BOOL perfused;        // genera polso periferico (pleth/ART)
} SLBeat;

static inline double gauss(double x, double mu, double sigma) {
    double z = (x - mu) / sigma;
    return exp(-0.5 * z * z);
}

@implementation WaveformEngine {
    NSString *_rhythm;
    double _hr, _rr, _etco2, _sys, _dia;
    BOOL _pulse, _signalValid;
    double _perfusion;
    BOOL _cpr;                         // compressioni toraciche in corso
    NSInteger _motion;                 // movimenti del paziente: 0 no, 1 lievi, 2 marcati
    BOOL _touch;                       // operatore che tocca il paziente
    NSTimeInterval _cprStart;                 // 0.1..1: ampiezza pletismografica in funzione della PA
    BOOL _ecgOn, _spo2On, _etco2On, _artOn, _padsOn, _artOccl, _spo2Occl;
    // pacing transcutaneo e shock
    BOOL _paceActive, _paceCapture, _paceMech;
    double _paceRate, _paceOut;
    NSTimeInterval _nextPace, _lastBeatT;
    NSTimeInterval _paces[16]; int _paceCount, _paceHead;
    NSTimeInterval _shockAt;
    BOOL _searching;                   // SpO2 in ricerca (sonda appena messa)

    SLBeat _beats[SL_MAX_BEATS];
    int _beatCount, _beatHead;
    NSTimeInterval _nextBeat;
    BOOL _started;

    NSTimeInterval _breathStart, _breathPeriod;
    BOOL _breathStarted;
    BOOL _ventManual; NSArray<NSNumber *> *_breathTimes;

    unsigned int _seed;
}

- (instancetype)initWithSeed:(unsigned int)seed {
    if ((self = [super init])) {
        _seed = seed ?: 1;
        _rhythm = SLRhythmSinus;
        _hr = 80; _rr = 16; _etco2 = 35; _sys = 120; _dia = 80;
        _pulse = YES; _signalValid = YES;
        _ecgOn = _spo2On = _etco2On = _artOn = YES;
    }
    return self;
}

- (instancetype)init { return [self initWithSeed:12345]; }

- (double)rand01 {
    _seed = _seed * 1103515245u + 12345u;
    return ((_seed >> 8) & 0xFFFFFF) / (double)0x1000000;
}

- (void)updateWithSnapshot:(SLSnapshot *)s {
    _rhythm = s.rhythm;
    _hr = (double)s.heartRate;
    _rr = (double)s.respRate;
    _etco2 = (double)s.etco2;
    _sys = (double)s.systolic; _dia = (double)s.diastolic;
    if (s.cprActive && !_cpr) _cprStart = -1;   // il primo campione fissa l'inizio delle compressioni
    _cpr = s.cprActive;
    _ventManual = s.ventilationManual; _breathTimes = s.breathTimes;
    _motion = s.patientMotion;
    _touch = s.operatorTouch;
    _perfusion = MAX(0.12, MIN(1.0, (_sys - 40.0) / 60.0));   // 100+ mmHg = piena, 70 = metà, <50 = minima
    _pulse = s.pulsePresent;
    _signalValid = s.spo2SignalValid;
    _ecgOn = s.ecgConnected; _spo2On = s.spo2Connected;
    _etco2On = s.etco2Connected; _artOn = s.artConnected; _artOccl = s.artCuffOccluded; _spo2Occl = s.spo2CuffOccluded;
    _padsOn = s.padsConnected;
    SLDefibInfo *d = s.defib;
    _paceActive = d.paceActive; _paceCapture = d.paceCapture; _paceMech = d.paceMechanical;
    _paceRate = MAX(30, d.paceRate); _paceOut = d.paceOutput;
    _shockAt = d.lastShockAt;
    _searching = s.spo2Searching;
    if (s.spo2LowPerfusionFlag) _perfusion = MIN(_perfusion, 0.35);   // bassa perfusione impostata dall'istruttore
}

#pragma mark - Programmazione battiti

- (BOOL)rhythmIsOrganized {
    return !([_rhythm isEqualToString:SLRhythmVentricularFib] || [_rhythm isEqualToString:SLRhythmAsystole]);
}

- (double)nextIntervalForRhythm {
    double base = 60.0 / MAX(_hr, 1.0);
    if ([_rhythm isEqualToString:SLRhythmAtrialFibrillation]) return base * (0.6 + 0.8 * [self rand01]);
    if ([_rhythm isEqualToString:SLRhythmVentricularTachy])   return base * (0.98 + 0.04 * [self rand01]);
    return base * (0.97 + 0.06 * [self rand01]);
}

- (void)addBeat:(SLBeat)b {
    int idx = (_beatHead + _beatCount) % SL_MAX_BEATS;
    if (_beatCount == SL_MAX_BEATS) { _beatHead = (_beatHead + 1) % SL_MAX_BEATS; _beatCount--; idx = (_beatHead + _beatCount) % SL_MAX_BEATS; }
    _beats[idx] = b;
    _beatCount++;
    _lastBeatT = b.t;
}

- (void)schedulePacerUntil:(NSTimeInterval)t {
    if (!_paceActive) { _nextPace = 0; return; }
    if (_nextPace <= 0 || _nextPace < t - 1.0) _nextPace = t + 0.05;
    while (_nextPace <= t + SL_LOOKAHEAD) {
        _paces[(_paceHead + _paceCount) % 16] = _nextPace;
        if (_paceCount == 16) _paceHead = (_paceHead + 1) % 16; else _paceCount++;
        double rr = 60.0 / _paceRate;
        // cattura: complesso largo subito dopo lo spike (non dentro il refrattario del battito precedente)
        if (_paceCapture && _nextPace + 0.03 > _lastBeatT + 0.25) {
            SLBeat b; b.t = _nextPace + 0.03; b.rr = rr; b.morph = SLMorphPaced; b.hasP = NO; b.perfused = _paceMech;
            [self addBeat:b];
        }
        _nextPace += rr;
    }
}

- (void)scheduleUntil:(NSTimeInterval)t {
    if (!_started) { _nextBeat = t; _started = YES; }
    [self schedulePacerUntil:t];
    if (_paceCapture) {                       // stimolazione efficace: il ritmo proprio è soppresso (overdrive)
        if (_nextBeat < t + SL_LOOKAHEAD + 0.3) _nextBeat = t + SL_LOOKAHEAD + 0.3;
        return;
    }
    if (_nextBeat < _lastBeatT + 0.25) _nextBeat = _lastBeatT + 0.25;
    while (_nextBeat <= t + SL_LOOKAHEAD) {
        if ([self rhythmIsOrganized] && _hr >= 1.0) {
            double rr = [self nextIntervalForRhythm];
            SLBeat b;
            b.t = _nextBeat; b.rr = rr;
            BOOL vt = [_rhythm isEqualToString:SLRhythmVentricularTachy] || [_rhythm isEqualToString:SLRhythmVentricularTachyPulse];
            b.morph = vt ? SLMorphWide : ([_rhythm isEqualToString:SLRhythmPEA] ? SLMorphPEA : SLMorphNarrow);
            b.hasP = !([_rhythm isEqualToString:SLRhythmAtrialFibrillation] || vt);
            b.perfused = _pulse;
            [self addBeat:b];
            _nextBeat += rr;
        } else {
            _nextBeat += 0.25;   // ritmi disorganizzati: nessun QRS
        }
    }
}

#pragma mark - ECG

// Complesso PQRST attorno al picco R (tau = t - tR), ampiezze in mV.
static double ecgNarrow(double tau, double rr, BOOL hasP, SLLead lead) {
    double qt = 0.40 * sqrt(MIN(MAX(rr, 0.25), 2.0));
    double pT = -0.16 * MIN(1.0, sqrt(rr));
    double v = 0;
    if (lead == SLLeadII) {
        if (hasP) v += 0.12 * gauss(tau, pT, 0.025);
        v += -0.10 * gauss(tau, -0.028, 0.008);
        v +=  1.00 * gauss(tau,  0.000, 0.010);
        v += -0.25 * gauss(tau,  0.026, 0.009);
        v +=  0.28 * gauss(tau,  qt * 0.62, qt * 0.11);
    } else {
        // V = V5 (precordiale laterale, monitoraggio a 5 elettrodi): P positiva piccola,
        // complesso qR (piccola q, R alta più ampia che in II, piccola s), ST isoelettrico, T positiva ampia.
        if (hasP) v += 0.09 * gauss(tau, pT, 0.024);
        v += -0.08 * gauss(tau, -0.024, 0.007);            // q settale
        v +=  1.45 * gauss(tau,  0.002, 0.0105);           // R alta
        v += -0.18 * gauss(tau,  0.028, 0.008);            // piccola s
        v +=  0.40 * gauss(tau,  qt * 0.63, qt * 0.12);    // T positiva
    }
    return v;
}

// PEA: complessi più larghi (~120 ms) e di ampiezza ridotta, T ampia e smussata
static double ecgPEA(double tau, double rr, SLLead lead) {
    double k = lead == SLLeadII ? 1.0 : 1.15;
    double v = 0.04 * gauss(tau, -0.17, 0.03);
    v += 0.72 * gauss(tau, 0.000, 0.026);
    v += -0.28 * gauss(tau, 0.065, 0.030);
    v += 0.20 * gauss(tau, MIN(0.36, rr * 0.45), 0.075);
    return k * v;
}

// Compressione toracica: artefatto ampio e lento sull'ECG (forma asimmetrica)
static double cprArtifact(double ph) {
    return 0.85 * gauss(ph, 0.18, 0.07) - 0.30 * gauss(ph, 0.45, 0.10);
}
// Onda di pressione generata dalla compressione (0..1)
static double cprPulse(double ph) {
    if (ph < 0.12) return 0.5 * (1 - cos(M_PI * ph / 0.12));
    return exp(-(ph - 0.12) / 0.16);
}

- (double)cprPhaseAt:(NSTimeInterval)t {
    if (_cprStart < 0) _cprStart = t;
    double period = 60.0 / 110.0;                       // 110 compressioni/min
    return fmod(MAX(0, t - _cprStart), period) / period;
}

// Complesso stimolato (cattura elettrica): QRS largo ~160 ms e T ampia discordante
static double ecgPaced(double tau, double rr, SLLead lead) {
    double s = lead == SLLeadV ? -0.85 : 1.0;
    double v = 1.30 * gauss(tau, 0.000, 0.040) - 0.50 * gauss(tau, 0.090, 0.045);
    v += -0.45 * gauss(tau, MIN(0.32, rr * 0.5), 0.085);
    return s * v;
}

static double ecgWide(double tau, double rr, SLLead lead) {
    // QRS largo (~160 ms) e T discordante, tipico TV monomorfa; polarità opposta in V
    double s = lead == SLLeadII ? 1.0 : -0.9;
    double v = 0;
    v +=  1.25 * gauss(tau, 0.000, 0.040);
    v += -0.55 * gauss(tau, 0.090, 0.040);
    v += -0.35 * gauss(tau, MIN(0.22, rr * 0.55), 0.06);
    return s * v;
}

// artefatto da movimento: oscillazioni lente della linea di base + raffiche irregolari più rapide (deterministico nel tempo)
static double motionArtifact(NSTimeInterval t, NSInteger level) {
    if (level <= 0) return 0;
    double env = 0.5 + 0.5 * sin(2 * M_PI * 0.23 * t + 0.7); env *= env;            // raffiche che vanno e vengono
    double slow = 0.55 * sin(2 * M_PI * 0.61 * t) + 0.35 * sin(2 * M_PI * 1.37 * t + 1.1);
    double fast = 0.40 * sin(2 * M_PI * 3.9 * t + 0.4) + 0.30 * sin(2 * M_PI * 7.7 * t + 2.0) + 0.20 * sin(2 * M_PI * 11.3 * t + 0.9);
    return (level == 2 ? 1.1 : 0.35) * (slow + (0.4 + env) * fast);
}

// artefatto da contatto (operatore che tocca/scuote): sbalzi rapidi e ampi della linea di base con spike irregolari
static double touchArtifact(NSTimeInterval t) {
    double jolt = 0.9 * sin(2 * M_PI * 2.3 * t) + 0.6 * sin(2 * M_PI * 5.1 * t + 0.8);
    double spikes = pow(MAX(0, sin(2 * M_PI * 3.3 * t + 1.7)), 12) * 2.2 - pow(MAX(0, sin(2 * M_PI * 2.7 * t + 0.3)), 14) * 1.8;
    return jolt + spikes + 0.35 * sin(2 * M_PI * 13.0 * t);
}

- (double)respImpedanceAt:(NSTimeInterval)t rate:(NSInteger)rr {
    if (!_ecgOn) return 0;
    double v = rr > 0 ? sin(2 * M_PI * rr / 60.0 * t) : 0;
    if (_cpr) v += 0.9 * cprArtifact([self cprPhaseAt:t]);                 // compressioni: grandi oscillazioni dell'impedenza
    if (_motion) v += 1.1 * motionArtifact(t * 0.7 + 1.9, _motion);        // il paziente che si muove altera l'impedenza toracica
    if (_touch) v += 0.8 * touchArtifact(t * 0.6 + 0.5);
    return v;
}

- (double)ecgAt:(NSTimeInterval)t lead:(SLLead)lead {
    [self scheduleUntil:t];
    BOOL pads = lead == SLLeadPads;
    if (pads ? !_padsOn : !_ecgOn) return 0;   // elettrodi / piastre staccati: linea piatta
    SLLead ml = pads ? SLLeadII : lead;        // le piastre (apice-sottoclaveare) vedono un'onda simile a II
    double v = [self rhythmEcgAt:t lead:ml] * (pads ? 0.9 : 1.0);
    if (_cpr) v += cprArtifact([self cprPhaseAt:t]) * (lead == SLLeadV ? 0.8 : (pads ? 1.3 : 1.0));
    if (_motion) v += motionArtifact(t + (lead == SLLeadV ? 0.37 : 0), _motion) * (pads ? 1.2 : 1.0);
    if (_touch) v += touchArtifact(t + (lead == SLLeadV ? 0.21 : 0)) * (pads ? 1.3 : 0.9);
    // pacing senza cattura: grande artefatto dopo lo spike, senza onda T ("falsa cattura")
    if (_paceActive && !_paceCapture && _paceOut >= 20) {
        double k = MIN(1.3, (_paceOut - 10) / 90.0) * (lead == SLLeadV ? -0.8 : 1.0);
        for (int i = 0; i < _paceCount; i++) {
            double tau = t - _paces[(_paceHead + i) % 16];
            if (tau < 0 || tau > 0.35) continue;
            v += k * (0.9 * gauss(tau, 0.035, 0.022) + 0.35 * gauss(tau, 0.10, 0.04));
        }
    }
    // shock: deflessione fuori scala e ritorno lento alla linea di base (~2-3 s)
    if (_shockAt > 0 && t >= _shockAt && t - _shockAt < 3.0) {
        double x = t - _shockAt;
        v += (lead == SLLeadV ? -1.0 : 1.0) * (x < 0.05 ? 4.0 : 3.2 * exp(-(x - 0.05) / 0.45));
    }
    return v;
}

- (SLMarker)markersFrom:(NSTimeInterval)t0 to:(NSTimeInterval)t1 sync:(BOOL)sync {
    SLMarker m = SLMarkerNone;
    for (int i = 0; i < _paceCount; i++) {
        double p = _paces[(_paceHead + i) % 16];
        if (p >= t0 && p < t1) { m |= SLMarkerPace; break; }
    }
    if (sync) for (int i = 0; i < _beatCount; i++) {
        double b = _beats[(_beatHead + i) % SL_MAX_BEATS].t;
        if (b >= t0 && b < t1) { m |= SLMarkerSync; break; }
    }
    return m;
}

- (double)beatSumAt:(NSTimeInterval)t lead:(SLLead)lead {
    double v = 0;
    for (int i = 0; i < _beatCount; i++) {
        SLBeat *b = &_beats[(_beatHead + i) % SL_MAX_BEATS];
        double tau = t - b->t;
        if (tau < -0.4 || tau > 0.9) continue;
        v += b->morph == SLMorphWide ? ecgWide(tau, b->rr, lead)
           : b->morph == SLMorphPaced ? ecgPaced(tau, b->rr, lead)
           : b->morph == SLMorphPEA ? ecgPEA(tau, b->rr, lead) : ecgNarrow(tau, b->rr, b->hasP, lead);
    }
    return v;
}

- (double)rhythmEcgAt:(NSTimeInterval)t lead:(SLLead)lead {

    BOOL v5 = lead == SLLeadV;
    if ([_rhythm isEqualToString:SLRhythmVentricularFib]) {
        double env = 0.55 + 0.45 * sin(2 * M_PI * 0.23 * t + 0.7 * sin(2 * M_PI * 0.07 * t));
        if (!v5) return env * (0.45 * sin(2 * M_PI * 4.7 * t + 1.3 * sin(2 * M_PI * 0.5 * t))
                             + 0.25 * sin(2 * M_PI * 6.3 * t + 0.4) + 0.15 * sin(2 * M_PI * 3.1 * t + 2.1));
        return env * (0.50 * sin(2 * M_PI * 5.2 * t + 0.8 + 1.1 * sin(2 * M_PI * 0.4 * t))
                    + 0.22 * sin(2 * M_PI * 3.7 * t + 1.7) + 0.12 * sin(2 * M_PI * 7.1 * t));
    }
    if ([_rhythm isEqualToString:SLRhythmAsystole]) {
        // Asistolia reale: nessun QRS, ma linea di base che ondeggia lentamente e irregolarmente
        // (respiro agonico/movimenti, deriva degli elettrodi) con piccole irregolarità.
        double ph = v5 ? 1.7 : 0.0;
        double wander = 0.11 * sin(2 * M_PI * 0.33 * t + ph + 0.8 * sin(2 * M_PI * 0.07 * t))
                      + 0.07 * sin(2 * M_PI * 0.71 * t + 0.4 + ph * 0.5)
                      + 0.04 * sin(2 * M_PI * 1.27 * t + 1.3 + ph) * (0.6 + 0.4 * sin(2 * M_PI * 0.19 * t));
        double ripple = 0.012 * sin(2 * M_PI * 3.1 * t + ph) * (0.5 + 0.5 * sin(2 * M_PI * 0.23 * t));
        return (v5 ? 0.8 : 1.0) * (wander + ripple) + [self beatSumAt:t lead:lead];   // + eventuali battiti stimolati
    }

    double v = [self beatSumAt:t lead:lead];
    if ([_rhythm isEqualToString:SLRhythmAtrialFibrillation]) {
        double k = v5 ? 0.5 : 1.0;          // in V5 le onde f sono poco evidenti
        v += k * (0.045 * sin(2 * M_PI * 5.7 * t + (v5 ? 0.9 : 0)) + 0.03 * sin(2 * M_PI * 7.3 * t + 1.1)
                + 0.02 * sin(2 * M_PI * 4.3 * t + 2.0));
    }
    v += 0.02 * sin(2 * M_PI * MAX(_rr, 6) / 60.0 * t + (v5 ? 1.3 : 0));   // deriva respiratoria
    return v;
}

- (NSTimeInterval)lastBeatAtOrBefore:(NSTimeInterval)t {
    NSTimeInterval last = -1;
    for (int i = 0; i < _beatCount; i++) {
        SLBeat *b = &_beats[(_beatHead + i) % SL_MAX_BEATS];
        if (b->t <= t) last = b->t;
    }
    return last;
}

- (NSTimeInterval)lastPerfusedBeatAtOrBefore:(NSTimeInterval)t {
    NSTimeInterval last = -1;
    for (int i = 0; i < _beatCount; i++) {
        SLBeat *b = &_beats[(_beatHead + i) % SL_MAX_BEATS];
        if (b->perfused && b->t <= t) last = b->t;
    }
    return last;
}

#pragma mark - Onde di polso (pletismografia / ART)

// Battito perfuso "corrente" al tempo t (ritardo di transito incluso).
// tau = tempo dall'arrivo del polso; rrNext = intervallo fino al battito successivo;
// amp = riempimento relativo (FA: battiti con RR precedente breve sono più piccoli). NO se nessuno.
- (BOOL)pulseAt:(NSTimeInterval)t delay:(double)delay tau:(double *)tau rrNext:(double *)rrNext amp:(double *)amp {
    int found = -1;
    for (int i = 0; i < _beatCount; i++) {
        SLBeat *b = &_beats[(_beatHead + i) % SL_MAX_BEATS];
        if (b->t + delay <= t) found = i; else break;
    }
    if (found < 0) return NO;
    SLBeat *b = &_beats[(_beatHead + found) % SL_MAX_BEATS];
    if (!b->perfused) return NO;
    double next = (found + 1 < _beatCount) ? _beats[(_beatHead + found + 1) % SL_MAX_BEATS].t : MAX(_nextBeat, b->t + b->rr);
    *tau = t - (b->t + delay);
    *rrNext = MAX(0.2, next - b->t);
    double meanRR = 60.0 / MAX(_paceCapture ? _paceRate : _hr, 1.0);
    *amp = MIN(1.0, MAX(0.40, b->rr / meanRR));   // mai oltre il valore impostato
    return YES;
}

// Onda compressa nell'intervallo RR: a frequenze alte l'onda si "stringe" e torna
// sempre alla linea di base prima del battito successivo (niente accumulo).
static double SLFitToRR(double (*shape)(double), double tau, double rr) {
    double k = MIN(1.0, rr / 0.9);                 // compressione solo sotto ~67 bpm di intervallo
    double t1 = tau / k, end = rr / k;
    if (tau >= rr) return 0;
    return MAX(0.0, shape(t1) - shape(end) * (tau / rr));   // correzione lineare: 0 esatto a fine RR
}

#pragma mark - Pletismografia

static double plethPulse(double tau) {
    if (tau < 0) return 0;
    double up = 0.13;
    if (tau < up) return 0.5 * (1 - cos(M_PI * tau / up));
    double d = tau - up;
    return exp(-d / 0.30) * 0.85 + 0.15 * exp(-d / 0.9) + 0.12 * gauss(tau, 0.36, 0.035) * exp(-d / 0.5);
}

- (double)plethAt:(NSTimeInterval)t {
    [self scheduleUntil:t];
    if (!_spo2On || _searching) return 0;      // sonda appena messa: ricerca del polso, nessuna onda
    if (_motion) {                               // dito/mano che si muove: curva disturbata
        double base = [self plethCleanAt:t];
        return MAX(0, MIN(1.1, base * (_motion == 2 ? 0.5 : 0.8) + 0.45 * motionArtifact(t * 0.8 + 3.1, _motion) + (_motion == 2 ? 0.35 : 0.1)));
    }
    return [self plethCleanAt:t];
}
- (double)plethCleanAt:(NSTimeInterval)t {
    if (_spo2Occl) return 0.02 + 0.01 * sin(2 * M_PI * 0.2 * t);   // bracciale chiuso a monte: il dito non è perfuso, linea piatta
    if (!_signalValid) {
        return 0.35 + 0.25 * sin(2 * M_PI * 1.3 * t) * sin(2 * M_PI * 0.37 * t) + 0.15 * ([self rand01] - 0.5);
    }
    double tau, rr, amp, v = 0;
    if (!_pulse && _cpr) return 0.18 * cprPulse(fmod([self cprPhaseAt:t] + 0.85, 1.0));   // RCP: onde piccole dalle compressioni
    if (!_pulse) return 0;                       // arresto senza RCP: linea piatta (niente rumore da bassa perfusione)
    if (![self pulseAt:t delay:0.22 tau:&tau rrNext:&rr amp:&amp]) return 0;     // nessun polso: linea piatta
    v = amp * SLFitToRR(plethPulse, tau, rr) * _perfusion;
    if (_perfusion < 0.55) {
        // bassa perfusione: onda piccola, ampiezza instabile, rumore e deriva della linea di base
        double bad = (0.55 - _perfusion) / 0.43;                                   // 0..1
        v *= 0.65 + 0.35 * sin(2 * M_PI * 0.37 * t + 1.1 * sin(2 * M_PI * 0.11 * t));
        v += bad * (0.05 * sin(2 * M_PI * 0.45 * t) + 0.03 * sin(2 * M_PI * 3.3 * t) * sin(2 * M_PI * 0.7 * t)
                    + 0.035 * ([self rand01] - 0.5));
    }
    return v * 0.8;      // nessun taglio: l'ampiezza la gestisce la scala automatica del tracciato
}

#pragma mark - Pressione arteriosa cruenta

static double artPulse(double tau) {
    // 0..~1: salita rapida, spalla sistolica, incisura dicrota, decadimento diastolico
    if (tau < 0) return 0;
    double up = 0.09;
    if (tau < up) return 0.5 * (1 - cos(M_PI * tau / up));
    double d = tau - up;
    double v = 0.78 * exp(-d / 0.17) + 0.22 * exp(-d / 0.55);
    v -= 0.11 * gauss(tau, 0.30, 0.014);        // incisura
    v += 0.07 * gauss(tau, 0.345, 0.035);       // onda dicrota
    return v;
}

- (double)artAt:(NSTimeInterval)t {
    [self scheduleUntil:t];
    if (!_artOn) return 0;                     // trasduttore staccato: 0 mmHg
    if (_artOccl) return 25 + 0.4 * sin(2 * M_PI * 0.2 * t);   // bracciale chiuso a monte: pressione intrappolata, niente polso
    if (!_pulse) {
        if (_cpr) return 18 + 52 * cprPulse([self cprPhaseAt:t]);     // RCP: ~70/18 mmHg generati dalle compressioni
        // arresto: pressione di riempimento ~20 mmHg; in FV piccole oscillazioni da artefatto
        double v = 20 + 0.6 * sin(2 * M_PI * 0.25 * t);
        if ([_rhythm isEqualToString:SLRhythmVentricularFib]) v += 1.5 * sin(2 * M_PI * 4.9 * t);
        return v;
    }
    double tau, rr, amp, pulse = 0;
    if ([self pulseAt:t delay:0.12 tau:&tau rrNext:&rr amp:&amp]) pulse = amp * SLFitToRR(artPulse, tau, rr);
    // variazione respiratoria della pressione (PPV ~6%): l'onda "respira" con la ventilazione
    if (_rr > 0) pulse *= 0.97 + 0.03 * sin(2 * M_PI * _rr / 60.0 * t);
    return _dia + (_sys - _dia) * pulse;
}

#pragma mark - Capnografia

- (double)capnoAt:(NSTimeInterval)t {
    if (_ventManual) {
        // un'onda per ogni insufflazione: ~1 s di insufflazione (niente CO2), poi l'espirazione con il plateau, poi zero
        if (!_etco2On || _etco2 <= 0) return 0;
        double tb = -1; for (NSNumber *b in _breathTimes) if (b.doubleValue <= t) tb = b.doubleValue;
        if (tb < 0) return 0;
        double dt = t - tb;
        if (dt < 1.0 || dt > 3.0) return 0;
        if (dt < 1.3) { double x = (dt - 1.0) / 0.3; return _etco2 * 0.85 * (0.5 - 0.5 * cos(M_PI * x)); }
        if (dt < 2.7) { double x = (dt - 1.3) / 1.4; return _etco2 * (0.85 + 0.15 * x); }
        double x = (dt - 2.7) / 0.3; return _etco2 * (0.5 + 0.5 * cos(M_PI * x));
    }
    if (!_etco2On || _rr < 1 || _etco2 <= 0) return 0;
    if (!_breathStarted) { _breathStart = t; _breathPeriod = 60.0 / _rr; _breathStarted = YES; }
    while (t - _breathStart >= _breathPeriod) {
        _breathStart += _breathPeriod;
        _breathPeriod = 60.0 / MAX(_rr, 1);
    }
    double ph = (t - _breathStart) / _breathPeriod;
    if (ph < 0.08) return 0;
    if (ph < 0.18) { double x = (ph - 0.08) / 0.10; return _etco2 * 0.85 * (0.5 - 0.5 * cos(M_PI * x)); }
    if (ph < 0.62) { double x = (ph - 0.18) / 0.44; return _etco2 * (0.85 + 0.15 * x); }
    if (ph < 0.68) { double x = (ph - 0.62) / 0.06; return _etco2 * (0.5 + 0.5 * cos(M_PI * x)); }
    return 0;
}

@end
