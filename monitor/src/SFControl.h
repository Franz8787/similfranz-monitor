// similFranz Monitor — un solo controller alla volta, con regole chiare e visibili a tutti.
// Controller = web app, app per iPad (Wi-Fi o diretto), app per iPod (diretto). I "seguaci" (saturimetro) non passano di qui.
//  1. LEGGERE non prende il comando: chi apre l'app osserva e basta.
//  2. Il primo COMANDO prende il comando, se nessuno comanda.
//  3. Chi comanda ATTIVAMENTE (un comando negli ultimi actionIdle secondi, 60) è protetto: i comandi degli altri
//     sono rifiutati (423) e chi li ha inviati vede chi comanda e il pulsante «Prendi il controllo».
//  4. Chi comanda ma è FERMO da più di actionIdle secondi non blocca nessuno: il primo comando di un altro passa
//     e il comando cambia di mano da solo (un iPad dimenticato acceso non tiene in ostaggio il monitor).
//  5. «Prendi il controllo» (take) funziona sempre. Chi perde il comando lo sa: infoFor gli dice da chi e quando.
//  6. Chi comanda e non si fa più sentire per idleTimeout secondi (10, app chiusa o fuori portata) libera il posto.
//  Ogni cambio di mano produce un testo (lastEvent) che il monitor scrive nel registro della sessione.
// Foundation pura: testabile su macOS.
#import <Foundation/Foundation.h>

@interface SFControl : NSObject
@property (nonatomic) NSTimeInterval idleTimeout;              // default 10 s: senza nessuna richiesta il posto si libera
@property (nonatomic) NSTimeInterval actionIdle;               // default 60 s: senza comandi chi comanda non è più protetto
@property (nonatomic, copy) NSTimeInterval (^clock)(void);
@property (nonatomic, copy) void (^onChange)(void);            // controller attivo cambiato (thread qualsiasi)
@property (atomic, readonly, copy) NSString *lastEvent;        // es. "Comando a «similFranz Pocket 1» (prima: «Web · Mac», fermo da 2 min)"

// Lettura: tiene vivo il controller attivo (se è lui), non occupa mai il posto.
- (void)seen:(NSString *)clientId;
// Comando: ritorna YES se il client può comandare (prendendo il posto se libero o se chi comandava è fermo).
- (BOOL)act:(NSString *)clientId name:(NSString *)name kind:(NSString *)kind transport:(NSString *)transport;
// Presa di controllo esplicita: sempre accettata.
- (void)take:(NSString *)clientId name:(NSString *)name kind:(NSString *)kind transport:(NSString *)transport;
// Rilascio (solo se clientId è il controller attivo). clientId nil = rilascio forzato dal monitor.
- (void)releaseClient:(NSString *)clientId;

// Per le risposte dell'API. Con un controller attivo:
//   {active, name, kind, transport, mine, idle_s, action_idle_s, since_s, protected}
//   protected = NO: chi comanda è fermo, il prossimo comando di un altro passa da solo.
// Senza controller: {active:false, mine:false}. In più, a chi ha perso il comando negli ultimi 5 minuti:
//   lost_to (nome di chi l'ha preso), lost_ago_s.
- (NSDictionary *)infoFor:(NSString *)clientId;
// Per l'interfaccia dell'iPad: nil se libero, altrimenti {name, kind, transport}
- (NSDictionary *)owner;
@end
