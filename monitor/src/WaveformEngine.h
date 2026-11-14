// SimulaFranz_Monitor — generatore di forme d'onda SIMULATE.
// Foundation + libm: nessuna dipendenza UIKit, testabile su macOS.
//
// Modello temporale continuo: battiti e atti respiratori vengono programmati
// man mano che il tempo avanza; le curve sono funzioni del tempo calcolate
// sommando i contributi dei battiti vicini (niente immagini/GIF).

#import <Foundation/Foundation.h>
@class SLSnapshot;

typedef NS_ENUM(NSInteger, SLLead) { SLLeadII = 0, SLLeadV = 1, SLLeadPads = 2 };   // Pads = ECG dalle piastre

// Marcatori disegnati sopra i tracciati ECG
typedef NS_OPTIONS(NSInteger, SLMarker) { SLMarkerNone = 0, SLMarkerSync = 1, SLMarkerPace = 2 };

@interface WaveformEngine : NSObject

- (instancetype)initWithSeed:(unsigned int)seed;

// Aggiorna i parametri (ritmo, FC, PA, FR, EtCO2, stato dei sensori...).
- (void)updateWithSnapshot:(SLSnapshot *)snapshot;

// Le query devono avvenire con tempi non decrescenti (per canale).
- (double)ecgAt:(NSTimeInterval)t lead:(SLLead)lead;  // mV circa, 0 = linea di base
// respiro da impedenza toracica (dagli elettrodi ECG): sinusoide alla FR; movimenti, tocco e RCP la disturbano come l'ECG
- (double)respImpedanceAt:(NSTimeInterval)t rate:(NSInteger)rr;
- (double)plethAt:(NSTimeInterval)t;                  // ~0..1 (può superare 1: nessun taglio)
- (double)artAt:(NSTimeInterval)t;                    // mmHg
- (double)capnoAt:(NSTimeInterval)t;                  // mmHg

// Marcatori nell'intervallo [t0, t1): spike del pacemaker e (se sync) onde R riconosciute.
- (SLMarker)markersFrom:(NSTimeInterval)t0 to:(NSTimeInterval)t1 sync:(BOOL)sync;

// Tempo dell'ultimo complesso QRS <= t, -1 se nessuno.
- (NSTimeInterval)lastBeatAtOrBefore:(NSTimeInterval)t;
// Tempo dell'ultimo battito PERFUSO <= t (per il bip da SpO2), -1 se nessuno.
- (NSTimeInterval)lastPerfusedBeatAtOrBefore:(NSTimeInterval)t;

@end
