// SimulaFranz_Monitor — sintetizzatore audio in tempo reale (AudioQueue, iOS 2+).
// Tutti i suoni sono generati dal codice (nessun file audio, nessun copyright):
//  - bip QRS/polso con tono legato alla SpO2 (acuto = alta, grave = bassa)
//  - allarmi a priorità alta / media / bassa con cadenze distinte
//  - NIBP: motore della pompa durante il gonfiaggio, "tss" della valvola a ogni
//    gradino di sgonfiaggio, sfiato finale.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SFAlarmSound) {
    SFAlarmSoundNone = 0,
    SFAlarmSoundLow,
    SFAlarmSoundMedium,
    SFAlarmSoundHigh
};

@interface SoundEngine : NSObject

@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly, copy) NSString *lastError;   // diagnostica

- (BOOL)start;      // configura AVAudioSession + AudioQueue
- (void)stop;

@property (nonatomic) double volume;                  // 0..1 (master)

// Volumi per canale (0..1, relativi al volume generale), salvati e ripristinati alla riapertura dell'app
typedef NS_ENUM(NSInteger, SFVolChannel) { SFVolBeepECG = 0, SFVolBeepSpO2, SFVolAlarm, SFVolMonitor, SFVolVoice, SFVolCount };
- (double)gainFor:(SFVolChannel)c;
- (void)setGain:(double)g forChannel:(SFVolChannel)c;
+ (NSString *)nameForChannel:(SFVolChannel)c;

// Bip del battito: frequenza in Hz (fromECG: sorgente QRS -> volume "Bip ECG", altrimenti "Bip SpO2")
- (void)beepWithFrequency:(double)hz;
- (void)beepWithFrequency:(double)hz fromECG:(BOOL)ecg;
// Frequenza del bip in funzione della SpO2 (stile monitor reali)
+ (double)beepFrequencyForSpO2:(NSInteger)spo2;

- (void)setAlarm:(SFAlarmSound)alarm;

// Pompa NIBP: in funzione mentre il bracciale si gonfia; pressione per il timbro
- (void)setPumpRunning:(BOOL)running pressure:(double)mmHg;
- (void)valveStep;          // breve sfiato a ogni gradino
- (void)valveDump;          // sfiato finale lungo

// Defibrillatore: 0 = silenzio, 1 = carica (tono che sale con progress 0..1), 2 = carico/pronto (bip continui)
- (void)setDefibTone:(NSInteger)mode progress:(double)progress;
- (void)shockSound;         // scarica: tonfo + clic del relè
- (void)metronomeTick;      // metronomo RCP del DAE

@end
