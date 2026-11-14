#import "SoundEngine.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include <pthread.h>
#include <math.h>
#import "SFLog.h"

#define SR        22050.0
#define FRAMES    384          // ~17 ms per buffer: bip del battito in sincrono con il QRS (latenza ~50 ms)
#define NBUF      3
#define MAXVOICE  12

typedef enum { VTone = 1, VNoise = 2 } VKind;

typedef struct {
    VKind kind;
    double freq, phase, amp;
    long pos, len;             // campioni
    double attack, release;    // campioni
    double decayTau;           // per rumore: costante di decadimento (campioni)
    double harm3;              // ampiezza armonica (timbro allarme)
    double lp;                 // stato filtro
    BOOL click;
} Voice;

@implementation SoundEngine {
    AudioQueueRef _queue;
    AudioQueueBufferRef _bufs[NBUF];
    pthread_mutex_t _lock;
    Voice _voices[MAXVOICE];
    // allarme (sequenziato nel thread audio, preciso al campione)
    SFAlarmSound _alarm;
    long _alarmPos;
    // pompa
    BOOL _pump;
    double _pumpPressure, _pumpPhase, _pumpEnv, _pumpLP;
    unsigned int _rng;
    double _master;
    // defibrillatore
    NSInteger _dTone; double _dProg, _dPhase, _dEnv; long _dPos;
    double _gain[SFVolCount];          // volumi per canale
}

#pragma mark - Avvio

- (instancetype)init {
    if ((self = [super init])) {
        pthread_mutex_init(&_lock, NULL);
        _rng = 22222; _master = 0.7;
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        for (int c = 0; c < SFVolCount; c++) {
            id v = [ud objectForKey:[NSString stringWithFormat:@"sf_vol_%d", c]];
            _gain[c] = v ? MAX(0, MIN(1, [v doubleValue])) : 1.0;
        }
    }
    return self;
}

static void SFCallback(void *user, AudioQueueRef q, AudioQueueBufferRef buf);

- (BOOL)start {
    if (_running) return YES;
    NSError *err = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    // Playback: suona anche con l'interruttore laterale in "silenzioso" (come un monitor reale)
    if (![session setCategory:AVAudioSessionCategoryPlayback error:&err])
        SFLog(@"audio: setCategory errore %@", err);
    if (![session setActive:YES error:&err])
        SFLog(@"audio: setActive errore %@", err);
    SFLog(@"audio: route=%@ volume di sistema=%.2f", session.currentRoute.outputs.firstObject.portType, session.outputVolume);

    AudioStreamBasicDescription f = {0};
    f.mSampleRate = SR;
    f.mFormatID = kAudioFormatLinearPCM;
    f.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    f.mBytesPerPacket = 2; f.mFramesPerPacket = 1; f.mBytesPerFrame = 2;
    f.mChannelsPerFrame = 1; f.mBitsPerChannel = 16;
    OSStatus st = AudioQueueNewOutput(&f, SFCallback, (__bridge void *)self, NULL, NULL, 0, &_queue);
    if (st != noErr) { _lastError = [NSString stringWithFormat:@"AudioQueueNewOutput %d", (int)st]; SFLog(@"audio: %@", _lastError); return NO; }
    for (int i = 0; i < NBUF; i++) {
        AudioQueueAllocateBuffer(_queue, FRAMES * 2, &_bufs[i]);
        SFCallback((__bridge void *)self, _queue, _bufs[i]);       // pre-riempimento
    }
    AudioQueueSetParameter(_queue, kAudioQueueParam_Volume, 1.0);
    st = AudioQueueStart(_queue, NULL);
    if (st != noErr) { _lastError = [NSString stringWithFormat:@"AudioQueueStart %d", (int)st]; SFLog(@"audio: %@", _lastError); return NO; }
    _running = YES; _lastError = nil;
    SFLog(@"audio: AudioQueue avviata (%.0f Hz)", SR);
    return YES;
}

- (void)stop {
    if (!_running) return;
    AudioQueueStop(_queue, true);
    AudioQueueDispose(_queue, true);
    _queue = NULL; _running = NO;
}

- (void)dealloc { [self stop]; pthread_mutex_destroy(&_lock); }

- (void)setVolume:(double)v { _master = MAX(0, MIN(1, v)); }
- (double)volume { return _master; }

#pragma mark - Comandi (main thread)

- (void)addVoice:(Voice)v {
    pthread_mutex_lock(&_lock);
    for (int i = 0; i < MAXVOICE; i++) if (_voices[i].kind == 0) { _voices[i] = v; break; }
    pthread_mutex_unlock(&_lock);
}

+ (double)beepFrequencyForSpO2:(NSInteger)spo2 {
    // ~1/3 di semitono per punto di SpO2: 100% = 880 Hz, 90% ≈ 698 Hz, 80% ≈ 554 Hz, 70% ≈ 440 Hz
    double s = MAX(50, MIN(100, spo2));
    return 880.0 * pow(2.0, (s - 100.0) / 30.0);
}

- (double)gainFor:(SFVolChannel)c { return (c >= 0 && c < SFVolCount) ? _gain[c] : 1.0; }
- (void)setGain:(double)g forChannel:(SFVolChannel)c {
    if (c < 0 || c >= SFVolCount) return;
    pthread_mutex_lock(&_lock); _gain[c] = MAX(0, MIN(1, g)); pthread_mutex_unlock(&_lock);
    [[NSUserDefaults standardUserDefaults] setObject:@(_gain[c]) forKey:[NSString stringWithFormat:@"sf_vol_%d", (int)c]];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
+ (NSString *)nameForChannel:(SFVolChannel)c {
    return @[@"Bip ECG (QRS)", @"Bip SpO2 (polso)", @"Allarmi", @"Suoni del monitor (NIBP, carica, scarica)", @"Istruzioni vocali"][(NSUInteger)c];
}
- (void)beepWithFrequency:(double)hz { [self beepWithFrequency:hz fromECG:YES]; }
- (void)beepWithFrequency:(double)hz fromECG:(BOOL)ecg {
    Voice v = {0};
    v.kind = VTone; v.freq = hz; v.amp = 0.45 * _gain[ecg ? SFVolBeepECG : SFVolBeepSpO2];
    v.len = (long)(0.075 * SR); v.attack = 0.004 * SR; v.release = 0.025 * SR;
    [self addVoice:v];
}

- (void)setAlarm:(SFAlarmSound)alarm {
    pthread_mutex_lock(&_lock);
    if (alarm != _alarm) { _alarm = alarm; _alarmPos = 0; }
    pthread_mutex_unlock(&_lock);
}

- (void)setPumpRunning:(BOOL)running pressure:(double)mmHg {
    pthread_mutex_lock(&_lock);
    _pump = running; _pumpPressure = mmHg;
    pthread_mutex_unlock(&_lock);
}

- (void)valveStep {
    Voice v = {0};
    v.kind = VNoise; v.amp = 0.30 * _gain[SFVolMonitor]; v.len = (long)(0.20 * SR);
    v.attack = 0.003 * SR; v.release = 0.04 * SR; v.decayTau = 0.07 * SR; v.click = YES;
    [self addVoice:v];
}

- (void)valveDump {
    Voice v = {0};
    v.kind = VNoise; v.amp = 0.40 * _gain[SFVolMonitor]; v.len = (long)(1.5 * SR);
    v.attack = 0.01 * SR; v.release = 0.2 * SR; v.decayTau = 0.55 * SR; v.click = YES;
    [self addVoice:v];
}

- (void)setDefibTone:(NSInteger)mode progress:(double)progress {
    pthread_mutex_lock(&_lock);
    if (mode != _dTone) _dPos = 0;
    _dTone = mode; _dProg = MAX(0, MIN(1, progress));
    pthread_mutex_unlock(&_lock);
}

- (void)shockSound {
    Voice v = {0};
    v.kind = VNoise; v.amp = 0.55 * _gain[SFVolMonitor]; v.len = (long)(0.35 * SR);
    v.attack = 0.001 * SR; v.release = 0.1 * SR; v.decayTau = 0.09 * SR; v.click = YES;
    [self addVoice:v];
    Voice t = {0};
    t.kind = VTone; t.freq = 70; t.amp = 0.5 * _gain[SFVolMonitor]; t.len = (long)(0.25 * SR); t.attack = 0.002 * SR; t.release = 0.15 * SR;
    [self addVoice:t];
}

- (void)metronomeTick {
    Voice v = {0};
    v.kind = VTone; v.freq = 1250; v.amp = 0.38 * _gain[SFVolMonitor]; v.len = (long)(0.06 * SR); v.attack = 0.001 * SR; v.release = 0.025 * SR;   // "tic" ben udibile sopra la voce
    [self addVoice:v];
}

#pragma mark - Sintesi (thread audio)

static inline double noise(unsigned int *s) {
    *s = *s * 1664525u + 1013904223u;
    return ((*s >> 9) / (double)(1u << 23)) * 2.0 - 1.0;
}

// Cadenze allarme: elenco di (inizio s, durata s, freq Hz); periodo totale
typedef struct { double t, d, f; } Pulse;
static const Pulse kHigh[] = { {0,.12,960},{.20,.12,960},{.40,.12,960},{.85,.12,960},{1.05,.12,960} };   // 3+2 (alta priorità)
static const Pulse kMed[]  = { {0,.20,660},{.32,.20,660},{.64,.20,660} };                               // 3 impulsi (media)
static const Pulse kLow[]  = { {0,.22,520},{.40,.22,520} };                                             // 2 impulsi (bassa)

static double alarmSample(SFAlarmSound a, long pos) {
    const Pulse *p; int n; double period;
    switch (a) {
        case SFAlarmSoundHigh:   p = kHigh; n = 5; period = 6.0; break;
        case SFAlarmSoundMedium: p = kMed;  n = 3; period = 8.0; break;
        case SFAlarmSoundLow:    p = kLow;  n = 2; period = 16.0; break;
        default: return 0;
    }
    double t = fmod(pos / SR, period);
    for (int i = 0; i < n; i++) {
        double x = t - p[i].t;
        if (x >= 0 && x < p[i].d) {
            double env = MIN(1.0, MIN(x, p[i].d - x) / 0.012);
            double w = 2 * M_PI * p[i].f * x;
            return env * 0.42 * (sin(w) + 0.35 * sin(3 * w) + 0.15 * sin(5 * w)) / 1.5;
        }
    }
    return 0;
}

- (void)render:(int16_t *)out frames:(UInt32)n {
    pthread_mutex_lock(&_lock);
    double master = _master;
    for (UInt32 i = 0; i < n; i++) {
        double s = 0;
        // voci (bip e valvola)
        for (int k = 0; k < MAXVOICE; k++) {
            Voice *v = &_voices[k];
            if (v->kind == 0) continue;
            double env = 1.0;
            if (v->pos < v->attack) env = v->pos / v->attack;
            long left = v->len - v->pos;
            if (left < v->release) env *= MAX(0.0, left / v->release);
            if (v->kind == VTone) {
                s += v->amp * env * sin(v->phase);
                v->phase += 2 * M_PI * v->freq / SR;
            } else {
                // sibilo dell'aria: rumore filtrato passa-alto (lp sottratto) con decadimento
                double w = noise(&_rng);
                v->lp += 0.25 * (w - v->lp);
                double hiss = (w - v->lp) * exp(-v->pos / v->decayTau);
                if (v->click && v->pos < 0.004 * SR) hiss += 0.8 * (1.0 - v->pos / (0.004 * SR)) * (v->pos % 2 ? 1 : -1);
                s += v->amp * env * hiss;
            }
            if (++v->pos >= v->len) v->kind = 0;
        }
        // pompa: ronzio del motorino (dente di sega ~100-130 Hz) + rumore meccanico
        double target = _pump ? 1.0 : 0.0;
        _pumpEnv += (target - _pumpEnv) * 0.0015;
        if (_pumpEnv > 0.0005) {
            double f0 = 95.0 + _pumpPressure * 0.18;            // il timbro sale con la pressione
            _pumpPhase += f0 / SR; if (_pumpPhase >= 1) _pumpPhase -= 1;
            double saw = 2 * _pumpPhase - 1;
            double rattle = noise(&_rng) * (0.5 + 0.5 * sin(2 * M_PI * _pumpPhase));
            _pumpLP += 0.18 * ((0.55 * saw + 0.45 * rattle) - _pumpLP);
            s += 0.33 * _gain[SFVolMonitor] * _pumpEnv * _pumpLP * (0.9 + 0.1 * sin(2 * M_PI * 7 * i / SR));
        }
        // defibrillatore: carica = sibilo che sale; pronto = bip ripetuti a 1 kHz
        double dTarget = _dTone ? 1.0 : 0.0;
        _dEnv += (dTarget - _dEnv) * 0.004;
        if (_dEnv > 0.0005) {
            double f = _dTone == 1 ? 420.0 + 900.0 * _dProg : 1000.0;
            _dPhase += 2 * M_PI * f / SR; if (_dPhase > 2 * M_PI) _dPhase -= 2 * M_PI;
            double gate = 1.0;
            if (_dTone == 2) { double ph = fmod(_dPos / SR, 0.5); gate = ph < 0.25 ? MIN(1.0, MIN(ph, 0.25 - ph) / 0.01) : 0; }
            s += 0.20 * _gain[SFVolMonitor] * _dEnv * gate * (sin(_dPhase) + 0.2 * sin(2 * _dPhase));
            _dPos++;
        }
        // allarme
        if (_alarm != SFAlarmSoundNone) { s += _gain[SFVolAlarm] * alarmSample(_alarm, _alarmPos); _alarmPos++; }

        s *= master;
        if (s > 1) s = 1; if (s < -1) s = -1;
        out[i] = (int16_t)(s * 30000);
    }
    pthread_mutex_unlock(&_lock);
}

static void SFCallback(void *user, AudioQueueRef q, AudioQueueBufferRef buf) {
    SoundEngine *e = (__bridge SoundEngine *)user;
    [e render:(int16_t *)buf->mAudioData frames:FRAMES];
    buf->mAudioDataByteSize = FRAMES * 2;
    AudioQueueEnqueueBuffer(q, buf, 0, NULL);
}

@end
