#import "SFPeerLink.h"
#import "SFLog.h"
#import <MultipeerConnectivity/MultipeerConnectivity.h>

NSString *const SFPeerServiceType = @"similfranz";
static NSString *const kPeerIDKey = @"sf_peer_id";       // MCPeerID salvato: evita doppioni "fantasma" nel controller
static const NSUInteger kMaxMessage = 64 * 1024;

@interface SFPeerLink () <MCNearbyServiceAdvertiserDelegate, MCSessionDelegate>
@end


// Una sessione chiusa NON va liberata subito: Multipeer (iOS 9) la usa ancora per qualche istante sulle sue code e,
// se nel frattempo viene deallocata, l'app va in crash (EXC_BAD_ACCESS dentro MultipeerConnectivity, visto il 14/11/2026).
// Si tiene in vita per 30 s, poi la si lascia andare.
static void SFRetire(MCSession *s) {
    if (!s) return;
    static NSMutableArray *grave; static dispatch_once_t once; dispatch_once(&once, ^{ grave = [NSMutableArray array]; });
    s.delegate = nil; [s disconnect];
    @synchronized (grave) { [grave addObject:s]; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ @synchronized (grave) { [grave removeObject:s]; } });
}

@implementation SFPeerLink {
    MCPeerID *_me;
    MCNearbyServiceAdvertiser *_adv;
    NSDictionary<NSString *, NSString *> *_info;
    SLHTTPHandler _handler;
    NSMutableArray<MCSession *> *_sessions;      // una sessione per controller (più robusto di una sessione condivisa)
    NSMutableArray<NSString *> *_connected;
    NSMapTable<MCSession *, NSString *> *_owner;   // sessione -> nome del controller che l'ha aperta
    dispatch_queue_t _q;
}

- (instancetype)initWithDisplayName:(NSString *)name discoveryInfo:(NSDictionary<NSString *, NSString *> *)info handler:(SLHTTPHandler)handler {
    if ((self = [super init])) {
        // displayName di MCPeerID: al massimo 63 byte UTF-8
        NSString *n = name.length ? name : @"similFranz Monitor";
        while ([n lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 63) n = [n substringToIndex:n.length - 1];
        _displayName = [n copy];
        _info = [info copy] ?: @{};
        _handler = [handler copy];
        _sessions = [NSMutableArray array]; _connected = [NSMutableArray array];
        _owner = [NSMapTable weakToStrongObjectsMapTable];
        _q = dispatch_queue_create("it.simulafranz.monitor.peer", DISPATCH_QUEUE_SERIAL);
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSData *saved = [d dataForKey:kPeerIDKey];
        MCPeerID *p = nil;
        @try { if (saved) p = [NSKeyedUnarchiver unarchiveObjectWithData:saved]; } @catch (NSException *e) { p = nil; }
        if (![p isKindOfClass:[MCPeerID class]] || ![p.displayName isEqualToString:_displayName]) {
            p = [[MCPeerID alloc] initWithDisplayName:_displayName];
            [d setObject:[NSKeyedArchiver archivedDataWithRootObject:p] forKey:kPeerIDKey];
        }
        _me = p;
    }
    return self;
}

- (NSArray<NSString *> *)peerNames { @synchronized (self) { return [_connected copy]; } }

- (void)changed {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.onChange) self.onChange(); });
}

- (void)start {
    if (_running) return;
    _lastError = nil;
    _adv = [[MCNearbyServiceAdvertiser alloc] initWithPeer:_me discoveryInfo:_info serviceType:SFPeerServiceType];
    _adv.delegate = self;
    [_adv startAdvertisingPeer];
    _running = YES;
    SFLog(@"collegamento diretto: annuncio \"%@\" (servizio %@)", _displayName, SFPeerServiceType);
    [self changed];
}

- (void)stop {
    if (!_running) return;
    [_adv stopAdvertisingPeer]; _adv.delegate = nil; _adv = nil;
    NSArray *all;
    @synchronized (self) { all = [_sessions copy]; [_sessions removeAllObjects]; [_connected removeAllObjects]; }
    for (MCSession *s in all) SFRetire(s);
    _running = NO;
    SFLog(@"collegamento diretto: fermato");
    [self changed];
}

#pragma mark - Annuncio

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didReceiveInvitationFromPeer:(MCPeerID *)peerID
       withContext:(NSData *)context invitationHandler:(void (^)(BOOL, MCSession *))invitationHandler {
    // un controller che si ripresenta (app riavviata, collegamento caduto) non deve trovare le sue vecchie sessioni
    // ancora aperte a metà: si chiudono prima di accettare il nuovo invito
    NSMutableArray<MCSession *> *stale = [NSMutableArray array];
    @synchronized (self) {
        // solo le sessioni di QUESTO controller: un secondo controller che si sta collegando non va toccato
        for (MCSession *old in _sessions) if ([[_owner objectForKey:old] isEqualToString:peerID.displayName]) [stale addObject:old];
        [_sessions removeObjectsInArray:stale];
        [_connected removeObject:peerID.displayName];
    }
    for (MCSession *old in stale) SFRetire(old);
    // Optional: accetta i controller che cifrano (versioni precedenti) e quelli che non cifrano (più affidabili su iOS 9)
    MCSession *s = [[MCSession alloc] initWithPeer:_me securityIdentity:nil encryptionPreference:MCEncryptionOptional];
    s.delegate = self;
    @synchronized (self) { [_sessions addObject:s]; [_owner setObject:peerID.displayName forKey:s]; }
    SFLog(@"collegamento diretto: invito da \"%@\" accettato", peerID.displayName);
    invitationHandler(YES, s);
    // sessione rimasta a metà (il controller è sparito durante l'accordo): dopo 15 s si chiude e l'annuncio si rinnova,
    // altrimenti il controller non ritrova più il monitor
    NSString *who = [peerID.displayName copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL stuck;
        @synchronized (self) { stuck = [self->_sessions containsObject:s] && s.connectedPeers.count == 0; if (stuck) [self->_sessions removeObject:s]; }
        if (!stuck) return;
        SFLog(@"collegamento diretto: sessione con \"%@\" mai completata, chiusa", who);
        SFRetire(s);
        [self readvertiseIfIdle];
    });
}

// annuncio rinnovato (solo se nessun controller è collegato): il controller ritrova subito un monitor "fresco"
- (void)readvertiseIfIdle {
    BOOL none; @synchronized (self) { none = _connected.count == 0; }
    if (!_running || !none) return;
    [_adv stopAdvertisingPeer]; _adv.delegate = nil;
    _adv = [[MCNearbyServiceAdvertiser alloc] initWithPeer:_me discoveryInfo:_info serviceType:SFPeerServiceType];
    _adv.delegate = self; [_adv startAdvertisingPeer];
}

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didNotStartAdvertisingPeer:(NSError *)error {
    _lastError = error.localizedDescription ?: @"annuncio non riuscito";
    _running = NO;
    SFLog(@"collegamento diretto: annuncio NON riuscito: %@", error);
    [self changed];
}

#pragma mark - Sessione

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state {
    if (state == MCSessionStateConnecting) return;
    BOOL on = state == MCSessionStateConnected;
    @synchronized (self) {
        [_connected removeObject:peerID.displayName];
        if (on) [_connected addObject:peerID.displayName];
        else [_sessions removeObject:session];
    }
    SFLog(@"collegamento diretto: \"%@\" %@", peerID.displayName, on ? @"COLLEGATO" : @"scollegato");
    if (on) {
        NSMutableDictionary *hello = [_info mutableCopy];
        hello[@"event"] = @"hello"; hello[@"name"] = _displayName;
        [self send:hello to:peerID session:session];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ SFRetire(session); });     // fuori dalla richiamata di Multipeer
        // dopo una caduta l'annuncio viene rinnovato: così il controller ritrova subito un monitor "fresco"
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self readvertiseIfIdle]; });
    }
    [self changed];
}

- (void)send:(NSDictionary *)obj to:(MCPeerID *)peer session:(MCSession *)session {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL];
    NSError *err = nil;
    if (!d || ![session sendData:d toPeers:@[peer] withMode:MCSessionSendDataReliable error:&err])
        SFLog(@"collegamento diretto: invio a \"%@\" fallito: %@", peer.displayName, err.localizedDescription);
}

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID {
    dispatch_async(_q, ^{
        id msg = data.length <= kMaxMessage ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (![msg isKindOfClass:[NSDictionary class]]) {
            [self send:@{@"id": [NSNull null], @"status": @400, @"body": @{@"ok": @NO, @"error": @"message must be a JSON object (max 64 KB)"}} to:peerID session:session];
            return;
        }
        id mid = msg[@"id"] ?: [NSNull null];
        NSString *method = [msg[@"method"] isKindOfClass:[NSString class]] ? [msg[@"method"] uppercaseString] : @"GET";
        NSString *path = [msg[@"path"] isKindOfClass:[NSString class]] ? msg[@"path"] : @"";
        if (![path hasPrefix:@"/api/"]) {            // la web app non passa di qui: solo l'API
            [self send:@{@"id": mid, @"status": @404, @"body": @{@"ok": @NO, @"error": @"only /api/ paths are available on the direct link"}} to:peerID session:session];
            return;
        }
        SLHTTPRequest *req = [SLHTTPRequest new];
        NSRange qm = [path rangeOfString:@"?"];
        req.method = method; req.path = qm.location == NSNotFound ? path : [path substringToIndex:qm.location];
        req.query = qm.location == NSNotFound ? @"" : [path substringFromIndex:qm.location + 1];
        req.remoteAddress = [@"peer:" stringByAppendingString:peerID.displayName];
        NSMutableDictionary *h = [NSMutableDictionary dictionary];
        NSDictionary *hin = [msg[@"headers"] isKindOfClass:[NSDictionary class]] ? msg[@"headers"] : @{};
        for (id k in hin) if ([k isKindOfClass:[NSString class]] && [hin[k] isKindOfClass:[NSString class]]) h[[k lowercaseString]] = hin[k];
        id body = msg[@"body"];
        if ([body isKindOfClass:[NSDictionary class]]) {
            req.body = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
            h[@"content-type"] = @"application/json";
        } else if ([method isEqualToString:@"POST"]) {
            req.body = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
            h[@"content-type"] = @"application/json";
        }
        req.headers = h;
        SLHTTPResponse *resp = self->_handler ? self->_handler(req) : nil;
        id rbody = resp.body.length ? [NSJSONSerialization JSONObjectWithData:resp.body options:0 error:NULL] : nil;
        [self send:@{@"id": mid, @"status": @(resp ? resp.status : 500), @"body": rbody ?: @{@"ok": @NO, @"error": @"no response"}} to:peerID session:session];
    });
}

- (void)session:(MCSession *)session didReceiveCertificate:(NSArray *)certificate fromPeer:(MCPeerID *)peerID certificateHandler:(void (^)(BOOL))certificateHandler {
    certificateHandler(YES);
}
- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)streamName fromPeer:(MCPeerID *)peerID {}
- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID withProgress:(NSProgress *)progress {}
- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID atURL:(NSURL *)localURL withError:(NSError *)error {}

@end
