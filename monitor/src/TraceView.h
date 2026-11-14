// SimulaFranz_Monitor — vista tracciato a "sweep" (come un monitor reale):
// il cursore avanza da sinistra a destra, cancellando una piccola fascia davanti.
#import <UIKit/UIKit.h>

@interface TraceView : UIView
@property (nonatomic, strong) UIColor *traceColor;
@property (nonatomic, copy) NSString *label;          // es. "II", "Pleth", "CO2"
@property (nonatomic) double minValue, maxValue;      // scala verticale
@property (nonatomic) double sweepSpeed;              // punti al secondo
@property (nonatomic) BOOL flatWhenNoSignal;          // se YES, mostra la scritta noSignalText
@property (nonatomic, copy) NSString *noSignalText;   // es. "SONDA SCOLLEGATA"
// Sensore scollegato: linea tratteggiata ferma sulla linea di base (come i monitor reali)
@property (nonatomic) BOOL disconnected;
// Fronti realistici (tracciato ECG): allo stacco dell'elettrodo uno scatto al bordo del canale e poi il tratteggio;
// al riattacco la linea di base oscilla e si assesta (~1.5 s). Il cursore continua a scorrere in entrambi i casi.
@property (nonatomic) BOOL edgeArtifacts;
@property (nonatomic) double baselineValue;           // valore della linea di base (default 0)
// Scala automatica: 0 = fissa, 1 = continua (pleth), 2 = scale standard da 0,
// 3 = "ottimale" per pressioni (attorno a sist/diast, arrotondata a 10 mmHg, come i monitor di TI)
@property (nonatomic) BOOL showScaleLabels;
@property (nonatomic) CGFloat markerYOffset;          // sposta in basso i triangoli SYNC (se sopra c'è l'etichetta della derivazione)
@property (nonatomic) BOOL filled;                    // area sotto la curva colorata (es. capnogramma)           // scrive i valori di inizio/fine scala sul tracciato
@property (nonatomic) NSInteger autoScale;
@property (nonatomic) double minSpan;                 // ampiezza minima della scala continua
@property (nonatomic, copy) double (^sampler)(NSTimeInterval t);
// Marcatori opzionali per colonna (bit 1 = sync sull'onda R, bit 2 = spike del pacemaker)
@property (nonatomic, copy) NSInteger (^markerSampler)(NSTimeInterval t0, NSTimeInterval t1);

// Avanza fino al tempo t, campionando "sampler". Ritorna YES se ridisegnare.
- (BOOL)advanceTo:(NSTimeInterval)t;
- (void)resetAtTime:(NSTimeInterval)t;
@end
