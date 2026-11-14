// similFranz Controller — collegamento DIRETTO con similFranz Monitor (Multipeer Connectivity).
// Funziona sulla stessa rete Wi-Fi e anche senza alcuna rete (Wi-Fi e/o Bluetooth accesi sui due iPad).
// Protocollo: la stessa API JSON del monitor incapsulata in messaggi (vedi SFPeerLink.h nel progetto del Monitor):
//   richiesta {"id", "method", "path", "headers", "body"}  ->  risposta {"id", "status", "body"}
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SFLinkState) { SFLinkIdle = 0, SFLinkConnecting, SFLinkConnected };

@interface SFLinkMonitor : NSObject
@property (nonatomic, copy) NSString *name;        // es. "Monitor iPadFranzmini"
@property (nonatomic, copy) NSString *deviceId;    // es. "monitor-01"
@property (nonatomic, copy) NSString *version;
@end

@interface SFLink : NSObject
- (instancetype)initWithDisplayName:(NSString *)name;
- (void)start;                                                    // comincia a cercare i monitor vicini
- (void)stop;
@property (nonatomic, readonly, copy) NSArray<SFLinkMonitor *> *monitors;   // monitor visibili ora
@property (nonatomic, readonly) SFLinkState state;
@property (nonatomic, readonly, copy) NSString *connectedName;    // monitor collegato (o in collegamento)
@property (nonatomic, readonly, copy) NSString *lastError;
@property (nonatomic, copy) void (^onChange)(void);               // main thread: elenco o stato cambiati
- (void)connectTo:(SFLinkMonitor *)monitor;
- (void)disconnect;
// Il collegamento sembra vivo ma il monitor non risponde più: lo si chiude e si riparte da una ricerca pulita.
- (void)resetAfterSilence;
// status 0 = nessuna risposta (collegamento caduto o tempo scaduto). Completion sul main thread.
- (void)request:(NSString *)method path:(NSString *)path headers:(NSDictionary *)headers body:(NSDictionary *)body
     completion:(void (^)(NSInteger status, NSDictionary *body))done;
@end
