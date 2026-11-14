// SimulaFranz_Monitor — modello clinico SIMULATO (nessun dato reale).
// Foundation pura: compilabile e testabile anche su macOS (tests/).
// Thread-safe: tutti gli accessi sono serializzati con @synchronized.

#import <Foundation/Foundation.h>

// Ritmi supportati (valori stringa usati dall'API)
extern NSString *const SLRhythmSinus;              // "sinus"
extern NSString *const SLRhythmSinusTachycardia;   // "sinus_tachycardia"
extern NSString *const SLRhythmSinusBradycardia;   // "sinus_bradycardia"
extern NSString *const SLRhythmAtrialFibrillation; // "afib"
extern NSString *const SLRhythmVentricularTachy;   // "vt"        TV senza polso
extern NSString *const SLRhythmVentricularTachyPulse; // "vt_pulse" TV con polso
extern NSString *const SLRhythmVentricularFib;     // "vf"
extern NSString *const SLRhythmAsystole;           // "asystole"
extern NSString *const SLRhythmPEA;                // "pea"

// Sensori collegabili al "paziente" (valori stringa usati dall'API)
extern NSString *const SLSensorECG;     // "ecg"   elettrodi ECG
extern NSString *const SLSensorSpO2;    // "spo2"  sonda saturimetrica
extern NSString *const SLSensorNIBP;    // "nibp"  bracciale
extern NSString *const SLSensorEtCO2;   // "etco2" sensore/linea capnografia
extern NSString *const SLSensorART;     // "art"   trasduttore pressione arteriosa cruenta
extern NSString *const SLSensorTemp;    // "temp"  sonda di temperatura
extern NSString *const SLSensorPads;    // "pads"  piastre adesive del defibrillatore
extern NSString *const SLSensorOxi;     // "oxi"   sensore a dito del saturimetro palmare (SimulaFranz_Saturimetro)

// Defibrillatore (cassetto sotto il monitor)
typedef NS_ENUM(NSInteger, SLDefibMode) { SLDefibOff = 0, SLDefibAED, SLDefibManual, SLDefibPacer };
typedef NS_ENUM(NSInteger, SLDefibCharge) { SLChargeNone = 0, SLChargeCharging, SLChargeReady };
// Fasi del DAE (semiautomatico)
typedef NS_ENUM(NSInteger, SLAedPhase) {
    SLAedPads = 0,      // "applicare le piastre"
    SLAedAnalyzing,     // analisi del ritmo (non toccare il paziente)
    SLAedCharging,      // shock consigliato, carica in corso
    SLAedReady,         // premere il pulsante shock
    SLAedCPR            // RCP per N secondi, poi nuova analisi
};

typedef NS_ENUM(NSInteger, SLNibpStatus) {
    SLNibpIdle = 0,
    SLNibpMeasuring,
    SLNibpComplete,
    SLNibpError
};

// Fasi del ciclo NIBP simulato (solo software: nessuna pompa reale)
typedef NS_ENUM(NSInteger, SLNibpPhase) {
    SLNibpPhaseNone = 0,
    SLNibpPhaseInflating,   // pompa in funzione
    SLNibpPhaseDeflating,   // sgonfiaggio a gradini (valvola)
    SLNibpPhaseDumping,     // scarico finale rapido
    SLNibpPhaseDone
};

// Stato del defibrillatore nell'istantanea (immutabile)
@interface SLDefibInfo : NSObject
@property (nonatomic, readonly) SLDefibMode mode;
@property (nonatomic, readonly) BOOL padsConnected;
@property (nonatomic, readonly) NSInteger energy;              // J selezionati (manuale) o del DAE
@property (nonatomic, readonly) SLDefibCharge charge;
@property (nonatomic, readonly) double chargeProgress;        // 0..1 durante la carica
@property (nonatomic, readonly) NSInteger chargedEnergy;
@property (nonatomic, readonly) BOOL sync;
@property (nonatomic, readonly) BOOL syncPending;              // shock sincronizzato in attesa dell'onda R
@property (nonatomic, readonly) NSTimeInterval syncPendingSince;
@property (nonatomic, readonly) SLAedPhase aedPhase;
@property (nonatomic, readonly) NSInteger aedRemaining;        // s rimanenti della fase (RCP, analisi)
@property (nonatomic, readonly) BOOL aedShockAdvised;
@property (nonatomic, readonly, copy) NSString *message;       // messaggio sul display (italiano)
@property (nonatomic, readonly) NSUInteger promptSeq;          // cambia a ogni nuovo messaggio vocale
@property (nonatomic, readonly, copy) NSString *voicePrompt;   // testo da pronunciare (DAE), nil = nessuno
@property (nonatomic, readonly) NSInteger shockCount;
@property (nonatomic, readonly) NSTimeInterval lastShockAt;     // 0 = nessuno (clock del modello)
@property (nonatomic, readonly) NSInteger lastShockEnergy;
@property (nonatomic, readonly) BOOL lastShockSynced;
@property (nonatomic, readonly) NSTimeInterval sessionStart;    // accensione del defibrillatore
// pacing
@property (nonatomic, readonly) NSInteger paceRate, paceOutput;  // ppm, mA
@property (nonatomic, readonly) BOOL paceDemand, paceRunning;
@property (nonatomic, readonly) BOOL pacePaused;                 // PAUSE tenuto premuto: stimola al 25% della frequenza
@property (nonatomic, readonly) NSInteger paceSetRate;           // frequenza impostata (paceRate = effettiva)
@property (nonatomic, readonly) BOOL paceLeadsOff;               // alcuni dispositivi: demand senza elettrodi ECG -> non-demand
@property (nonatomic, readonly) BOOL paceActive;                 // stimola davvero (piastre ok, non inibito)
@property (nonatomic, readonly) BOOL paceCapture;                // cattura elettrica
@property (nonatomic, readonly) BOOL paceMechanical;             // cattura meccanica (polso)
@property (nonatomic, readonly) BOOL voiceEnabled;
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *events;   // registro eventi {t, text}
@end

// Istantanea immutabile dello stato, usata da UI, suoni e waveform senza lock.
@interface SLSnapshot : NSObject
@property (nonatomic, readonly) NSUInteger revision;
@property (nonatomic, readonly, copy) NSString *rhythm;
@property (nonatomic, readonly) NSInteger heartRate;      // FC impostata (ritmo)
@property (nonatomic, readonly) NSInteger spo2;
@property (nonatomic, readonly) BOOL spo2SignalValid;
@property (nonatomic, readonly) NSInteger respRate;
@property (nonatomic, readonly) NSInteger etco2;
@property (nonatomic, readonly) NSInteger systolic;       // PA "vera" del paziente simulato
@property (nonatomic, readonly) NSInteger diastolic;
// sensori
@property (nonatomic, readonly) BOOL ecgConnected, spo2Connected, nibpConnected, etco2Connected, artConnected;
@property (nonatomic, readonly) BOOL tempConnected, padsConnected;
// Saturimetro palmare (secondo dispositivo, iPod touch): sensore a dito, tempo dal collegamento, bracciale sullo stesso braccio
@property (nonatomic, readonly) BOOL oxiConnected, oxiCuffOccluded, oxiPower, oxiOnline;
@property (nonatomic, readonly) NSTimeInterval oxiSensorSince;        // secondi dal collegamento del sensore (-1 = scollegato)
@property (nonatomic, readonly) NSInteger oxiVolume, oxiMutedRemaining;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSNumber *> *oxiLimits;   // spo2_low, spo2_high, pr_low, pr_high
// posizione dei sensori sul paziente (es. nibp -> "upper_arm_r", spo2 -> "finger_l2"); solo per i controller
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *sensorSites;
@property (nonatomic, readonly) BOOL spo2SignalSetting;     // impostazione dell'istruttore (spo2SignalValid include l'occlusione)
@property (nonatomic, readonly) BOOL spo2CuffOccluded;      // bracciale NIBP in misura sullo stesso braccio della sonda SpO2
// SpO2: acquisizione dopo il collegamento della sonda (ritardo impostabile) e bassa perfusione forzata
@property (nonatomic, readonly) NSInteger spo2DelaySec;
@property (nonatomic, readonly) BOOL spo2Searching;       // prima metà del ritardo: niente onda, "ricerca"
@property (nonatomic, readonly) BOOL spo2Acquiring;       // valore non ancora mostrato
@property (nonatomic, readonly) BOOL spo2LowPerfusionFlag;
@property (nonatomic, readonly) NSInteger patientMotion;            // movimenti del paziente: 0 no, 1 lievi, 2 marcati (artefatti)
@property (nonatomic, readonly) NSInteger patientMotionRemaining;   // secondi rimanenti (0 = finché non viene fermato)
@property (nonatomic, readonly) BOOL operatorTouch;                 // un operatore sta toccando il paziente (PUSH dal controller)
// temperatura (decimi di °C) e refill capillare (decimi di secondo)
@property (nonatomic, readonly) NSInteger temperatureTenths;
@property (nonatomic, readonly) NSInteger crtTenths;
@property (nonatomic, readonly) NSInteger crtAssessSeq;           // cresce a ogni "fai valutare il refill" dell'istruttore
@property (nonatomic, readonly) BOOL crtEnabled;                 // refill visibile sul monitor (disattivabile)
@property (nonatomic, readonly, copy) NSString *layout;          // "generic_icu" | "extrah" | "dae"
@property (nonatomic, readonly) BOOL devicePowered;               // monitor/defibrillatore acceso (stato condiviso tra i layout)
// defibrillatore
@property (nonatomic, readonly, strong) SLDefibInfo *defib;
// NIBP
@property (nonatomic, readonly) SLNibpStatus nibpStatus;
@property (nonatomic, readonly, copy) NSString *nibpError;       // nil, "cuff", "no_pulse"
@property (nonatomic, readonly) NSInteger nibpLastSystolic;      // -1 = nessuna misura
@property (nonatomic, readonly) NSInteger nibpLastDiastolic;
@property (nonatomic, readonly) NSTimeInterval nibpStartedAt;
@property (nonatomic, readonly) NSDate *nibpMeasuredAt;
// audio / allarmi
@property (nonatomic, readonly) BOOL alarmsMuted;
@property (nonatomic, readonly) NSInteger alarmsMutedRemaining;   // secondi al ritorno degli allarmi
@property (nonatomic, readonly) BOOL qrsBeepEnabled;
@property (nonatomic, readonly) NSInteger volume;                // 0..100
@property (nonatomic, readonly) BOOL simulationRunning;
@property (nonatomic, readonly) NSTimeInterval scenarioTime;     // secondi di scenario (esclude le pause; 0 dopo reset)
// limiti di allarme (chiavi: hr_low, hr_high, spo2_low, rr_low, rr_high,
// etco2_low, etco2_high, sys_low, sys_high) -> NSNumber
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSNumber *> *alarmLimits;
- (NSInteger)limit:(NSString *)key;
// allarme attivo per parametro (hr, spo2, art, nibp, rr, etco2): se NO non dà allarmi di limite
// (i ritmi letali FV/TV/asistolia suonano comunque)
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSNumber *> *alarmEnabled;
- (BOOL)alarmOn:(NSString *)param;
// NIBP automatica: intervallo in minuti (0 = spenta) e istante della prossima misura
@property (nonatomic, readonly) NSInteger nibpIntervalMin;
@property (nonatomic, readonly) NSTimeInterval nibpNextAt;
// reazioni automatiche (arresto -> SpO2/FR/EtCO2 a 0; ROSC -> recupero)
@property (nonatomic, readonly) BOOL autoPhysiology;
@property (nonatomic, readonly) BOOL cprActive;                  // RCP (compressioni toraciche) in corso
// Ventilazione manuale (RCP in corso o apnea): ogni insufflazione la segnala l'istruttore ("ventilate") quando i
// partecipanti ventilano; solo allora il capnogramma mostra un'onda e compare l'EtCO2. FR = insufflazioni nell'ultimo minuto.
@property (nonatomic, readonly) BOOL ventilationManual;
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *breathTimes;   // istanti (clock) delle insufflazioni dell'ultimo minuto
@property (nonatomic, readonly) double respRateSet;                      // FR impostata (in ventilazione manuale respRate è quella misurata)
@property (nonatomic, readonly) NSInteger etco2Set;                      // EtCO2 impostata (in ventilazione manuale etco2 può essere quella dell'ultima insufflazione)
@property (nonatomic, readonly) NSInteger pulseRate;             // PR periferica (FA rapida: deficit di polso)
// transizioni attive: param -> {to, remaining_s}; catena: {active, name, step, steps, label, phase, remaining_s}
@property (nonatomic, readonly, copy) NSDictionary *transitions, *chain;

// derivati
@property (nonatomic, readonly) BOOL pulsePresent;        // dal ritmo
@property (nonatomic, readonly) BOOL ecgOrganized;        // ritmo con complessi QRS
@property (nonatomic, readonly) BOOL spo2Displayable;     // sonda + segnale + polso
@property (nonatomic, readonly) BOOL lowPerfusion;        // ipotensione marcata (sist < 70): SpO2 con "?"
@property (nonatomic, readonly) NSInteger displayedHeartRate; // FC da ECG, -1 = "---"
@property (nonatomic, readonly) NSInteger meanArterialPressure; // ultima NIBP, -1 se assente
@property (nonatomic, readonly) NSInteger artDisplayedSystolic;  // -1 = "--"
@property (nonatomic, readonly) NSInteger artDisplayedDiastolic;

// Profilo del bracciale al tempo t: fase, pressione (mmHg), indice del gradino di sgonfiaggio.
- (SLNibpPhase)nibpPhaseAt:(NSTimeInterval)t pressure:(double *)pressure step:(NSInteger *)step;
@end

@interface SimulationState : NSObject

@property (nonatomic, readonly, copy) NSString *deviceId;   // "monitor-01"

// Accensione del dispositivo simulato: condivisa tra tutti i layout, parte spenta
// e torna spenta con reset_scenario (la imposta la UI, non l'API).
@property (nonatomic) BOOL devicePowered;

+ (NSArray<NSString *> *)supportedRhythms;
+ (NSArray<NSString *> *)supportedSensors;
+ (BOOL)rhythmHasPulse:(NSString *)rhythm;
+ (NSDictionary<NSString *, NSNumber *> *)defaultAlarmLimits;
+ (NSArray<NSNumber *> *)nibpIntervals;     // 0, 1, 2, 3, 5, 10, 15, 30, 60 minuti

- (instancetype)initWithDeviceId:(NSString *)deviceId;

- (SLSnapshot *)snapshot;

// Applica un comando API. Ritorna YES se applicato; altrimenti *error contiene
// un messaggio leggibile (in inglese tecnico, stabile per i client).
- (BOOL)applyCommand:(NSDictionary *)command error:(NSString **)error;
// Controlla il valore di un comando "transition" (parametri, ritmo, durata) SENZA applicarlo.
- (BOOL)validateTransition:(NSDictionary *)value error:(NSString **)error;

// Avvia un ciclo NIBP simulato (solo software). NO se già in corso.
- (BOOL)startNibpMeasurementError:(NSString **)error;

// Da chiamare periodicamente: completa la misura NIBP e fa scadere il silenziamento.
- (void)tickAtTime:(NSTimeInterval)now;

- (void)resetScenario;

// Il saturimetro (client HTTP) ha appena interrogato lo stato: "online" per qualche secondo
- (void)noteOximeterSeen;
+ (NSDictionary<NSString *, NSNumber *> *)defaultOximeterLimits;

// Defibrillatore: shock sincronizzato in attesa -> la UI segnala ogni onda R rilevata dall'ECG
- (void)defibRWaveAt:(NSTimeInterval)t;
+ (NSArray<NSNumber *> *)defibEnergies;
+ (NSArray<NSString *> *)supportedLayouts;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)layoutCatalog;   // [{id, name}] per i menu dei layout

// Rappresentazione JSON-serializzabile per /api/v1/state
- (NSDictionary *)stateDictionary;

@property (nonatomic) NSTimeInterval muteDuration;      // default 20 s

// Clock iniettabile per i test
@property (nonatomic, copy) NSTimeInterval (^clock)(void);

@end
