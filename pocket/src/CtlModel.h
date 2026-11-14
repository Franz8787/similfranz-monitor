// similFranz Controller — stato dell'app: collegamento, PIN, stato del paziente letto dal monitor, comandi, scenari.
#import <Foundation/Foundation.h>
#import "SFLink.h"

typedef NS_ENUM(NSInteger, CtlStage) {
    CtlStageSearching = 0,   // nessun monitor collegato: elenco dei monitor vicini
    CtlStageConnecting,      // invito in corso
    CtlStageNeedPin,         // collegato, manca il PIN (o è sbagliato)
    CtlStageReady            // collegato e autorizzato: si comanda
};

@interface CtlModel : NSObject
@property (nonatomic, readonly) SFLink *link;
@property (nonatomic, readonly) CtlStage stage;
@property (nonatomic, readonly, copy) NSString *pinError;            // "PIN non valido", "troppi tentativi…"
@property (nonatomic, readonly, copy) NSString *monitorName;
@property (nonatomic, readonly, copy) NSDictionary *state;           // ultimo stato del paziente (API /state), nil se mai letto
@property (nonatomic, readonly, copy) NSDictionary *controller;      // {active, name, mine, transport}
@property (nonatomic, readonly, copy) NSDictionary *scenario;        // conduzione in corso {active, phase, ...}
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *scenarios;
@property (nonatomic, readonly) BOOL mine;                           // questo controller sta comandando
@property (nonatomic, readonly, copy) NSString *lastMessage;         // esito dell'ultimo comando (errore leggibile) o nil
@property (nonatomic, copy) void (^onUpdate)(void);                  // main thread: qualcosa è cambiato

- (void)start;
- (void)suspend;                       // app in background
- (void)connect:(SFLinkMonitor *)m;
- (void)forgetMonitor;                 // scollega e non ricollegarti da solo
- (void)submitPin:(NSString *)pin;
- (void)takeControl;

- (void)command:(NSString *)name value:(id)value;
- (void)command:(NSString *)name value:(id)value done:(void (^)(BOOL ok, NSString *error))done;
- (void)startNibp;
- (void)refreshScenarios;
// Registro della sessione (tenuto sul monitor, condiviso con la web app): voci e riepilogo per il debriefing
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *log;      // {i, t, w, k, text, tag?, by?}
@property (nonatomic, readonly, copy) NSDictionary *logSummary;
@property (nonatomic, readonly) BOOL logAvailable;                       // NO con un monitor vecchio, senza registro
- (void)logAdd:(NSString *)kind text:(NSString *)text tag:(NSString *)tag;
- (void)logClear:(void (^)(BOOL ok, NSString *error))done;
// Sessioni del registro (una per simulazione): elenco, sessione corrente, lettura di una sessione passata, sessione nuova
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *logSessions;     // {id, title, w, entries, duration_s, current}
@property (nonatomic, readonly) NSInteger logSession;
- (void)loadSession:(NSInteger)sid done:(void (^)(NSArray<NSDictionary *> *entries, NSDictionary *summary))done;
- (void)newSession:(NSString *)title;
// Aggiornamento dell'app dal monitor (che lo ha ricevuto dal computer, regia web): versione disponibile o nil;
// installUpdate scarica il pacchetto a pezzi dal collegamento diretto e lo installa (l'app si chiude e si riapre).
@property (nonatomic, readonly, copy) NSString *updateVersion;
@property (nonatomic, readonly) double updateProgress;             // 0…1 durante lo scaricamento, -1 fermo
- (void)installUpdate:(void (^)(NSString *error))done;
// action: save | delete | start | goto | next | stop
- (void)scenarioAction:(NSDictionary *)body done:(void (^)(BOOL ok, NSString *error, NSDictionary *resp))done;
@end
