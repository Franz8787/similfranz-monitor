// similFranz Monitor — registro della sessione per il debriefing, tenuto sul monitor (web app e app controller
// leggono e scrivono lo stesso registro). Ogni voce ha il tempo di scenario, l'ora reale, una categoria e un testo.
//   - VOCI AUTOMATICHE: ciò che fanno i partecipanti sul monitor/defibrillatore (accensione, sonde applicate,
//     misure NIBP, allarmi silenziati, tutti gli eventi del defibrillatore: carica, scariche con l'energia, pacing, DAE…)
//     e ciò che fa l'istruttore dal controller (ritmi, parametri, fasi dello scenario, pausa, timer…).
//   - VOCI DELL'ISTRUTTORE: osservazioni da menu rapido (riconoscimento dell'arresto, farmaci, vie aeree…),
//     punti di forza, punti da discutere, note libere.
// Dal registro si ricava il riepilogo per il debriefing (tempi delle azioni critiche, scariche, farmaci).
// Il registro è diviso in SESSIONI, una per simulazione: una sessione nuova si apre da sola quando si avvia uno
// scenario o si azzera lo scenario (oppure a mano). Si conservano le ultime 20, salvate su file: restano anche se
// l'app viene chiusa, finché non si svuota il registro.
// Foundation pura: testabile su macOS.
#import <Foundation/Foundation.h>
@class SimulationState, SFScenarioStore;

@interface SFSessionLog : NSObject
- (instancetype)initWithPath:(NSString *)path state:(SimulationState *)state;
// Da chiamare un paio di volte al secondo: confronta lo stato con quello di prima e registra i cambiamenti.
- (void)observe;
// Voce esplicita. kind: phase, patient, monitor, electric, timer, action, drug, plus, minus, note. tag facoltativo
// (ac, help, cpr_start, shock, arrest, rosc…) per il riepilogo. by = chi l'ha scritta (nome del controller).
- (NSDictionary *)add:(NSString *)kind text:(NSString *)text tag:(NSString *)tag by:(NSString *)by;
// Un comando dell'istruttore è stato eseguito: lo traduce in una voce leggibile (se merita di stare nel registro).
- (void)noteCommand:(NSDictionary *)command by:(NSString *)by;
// Apre una sessione nuova (titolo facoltativo). Se quella corrente è ancora vuota la riusa, cambiandole solo il titolo.
- (NSInteger)newSession:(NSString *)title;
- (NSInteger)currentSession;
// [{id, title, w (ora di inizio), entries, duration_s, current}] dalla più vecchia alla più recente
- (NSArray<NSDictionary *> *)sessions;
- (NSArray<NSDictionary *> *)entriesSince:(NSInteger)index session:(NSInteger)sid;
- (NSDictionary *)summaryForSession:(NSInteger)sid;
- (NSString *)plainTextForSession:(NSInteger)sid;
- (void)clear;
- (void)flush;                                                 // salva subito su file (di norma salva da solo ogni pochi secondi)
- (NSArray<NSDictionary *> *)entriesSince:(NSInteger)index;     // voci con i >= index
- (NSInteger)nextIndex;
- (NSDictionary *)summary;
- (NSString *)plainText;                                        // registro completo in testo (per salvarlo o stamparlo)
+ (NSArray<NSString *> *)kinds;
@end
