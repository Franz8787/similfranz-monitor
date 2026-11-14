#import "SFLink.h"
#import "SFLog.h"
#import <MultipeerConnectivity/MultipeerConnectivity.h>
#import <QuartzCore/QuartzCore.h>

static NSString *const kService = @"similfranz";
static const NSTimeInterval kRequestTimeout = 3.0;


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

@implementation SFLinkMonitor
@end

@interface SFLink () <MCNearbyServiceBrowserDelegate, MCSessionDelegate>
@end

@implementation SFLink {
    MCPeerID *_me;
    MCNearbyServiceBrowser *_browser;
    MCSession *_session; MCPeerID *_target;
    NSMutableArray<SFLinkMonitor *> *_found; NSMutableDictionary<NSString *, MCPeerID *> *_peers;   // nome -> peer
    NSMutableDictionary<NSNumber *, void (^)(NSInteger, NSDictionary *)> *_pending;
    NSInteger _seq;
    BOOL _running;
    NSInteger _fails; NSTimer *_watch; CFTimeInterval _browseSince;
}

- (instancetype)initWithDisplayName:(NSString *)name {
    if ((self = [super init])) {
        NSString *n = name.length ? name : @"Controller";
        while ([n lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 63) n = [n substringToIndex:n.length - 1];
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSData *saved = [d dataForKey:@"sf_peer_id"]; MCPeerID *p = nil;
        @try { if (saved) p = [NSKeyedUnarchiver unarchiveObjectWithData:saved]; } @catch (NSException *e) { p = nil; }
        if (![p isKindOfClass:[MCPeerID class]] || ![p.displayName isEqualToString:n]) {
            p = [[MCPeerID alloc] initWithDisplayName:n];
            [d setObject:[NSKeyedArchiver archivedDataWithRootObject:p] forKey:@"sf_peer_id"];
        }
        _me = p;
        _found = [NSMutableArray array]; _peers = [NSMutableDictionary dictionary]; _pending = [NSMutableDictionary dictionary];
    }
    return self;
}

// tutto lo stato vive sul main thread: i delegate di Multipeer arrivano su code private e vengono riportati qui
static void OnMain(void (^b)(void)) { if ([NSThread isMainThread]) b(); else dispatch_async(dispatch_get_main_queue(), b); }
- (void)changed { if (self.onChange) self.onChange(); }
- (NSArray<SFLinkMonitor *> *)monitors { return [_found copy]; }

- (void)start {
    if (_running) return;
    _running = YES;
    _browser = [[MCNearbyServiceBrowser alloc] initWithPeer:_me serviceType:kService];
    _browser.delegate = self;
    [_browser startBrowsingForPeers]; _browseSince = CACurrentMediaTime();
    SFLog(@"ricerca dei monitor avviata (io sono \"%@\")", _me.displayName);
    // guardia: Multipeer su iOS 9 a volte resta "cieco" dopo una sessione fallita (il monitor c'è ma non compare).
    // Se per 20 s non si vede nessun monitor, la ricerca riparte da capo con un'identità nuova.
    if (!_watch) _watch = [NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(watchdog) userInfo:nil repeats:YES];
}

- (void)watchdog {
    if (!_running || _state != SFLinkIdle || _found.count || CACurrentMediaTime() - _browseSince < 20) return;
    SFLog(@"nessun monitor visibile da 20 s: ricerca riavviata con un'identità nuova");
    [self freshIdentity]; [self restartBrowsing];
}
- (void)freshIdentity { _me = [[MCPeerID alloc] initWithDisplayName:_me.displayName]; }
- (void)restartBrowsing {
    [_browser stopBrowsingForPeers]; _browser.delegate = nil;
    [_found removeAllObjects]; [_peers removeAllObjects];
    _browser = [[MCNearbyServiceBrowser alloc] initWithPeer:_me serviceType:kService];
    _browser.delegate = self; [_browser startBrowsingForPeers]; _browseSince = CACurrentMediaTime();
    [self changed];
}

- (void)stop {
    if (!_running) return;
    _running = NO;
    [_watch invalidate]; _watch = nil;
    [_browser stopBrowsingForPeers]; _browser.delegate = nil; _browser = nil;
    [self dropSession:nil];
    [_found removeAllObjects]; [_peers removeAllObjects];
    [self changed];
}

#pragma mark - Ricerca

- (void)browser:(MCNearbyServiceBrowser *)browser foundPeer:(MCPeerID *)peerID withDiscoveryInfo:(NSDictionary<NSString *, NSString *> *)info {
    OnMain(^{
        if (![info[@"type"] isEqualToString:@"monitor"]) return;
        NSString *n = peerID.displayName;
        SFLinkMonitor *m = nil;
        for (SFLinkMonitor *x in self->_found) if ([x.name isEqualToString:n]) m = x;
        if (!m) { m = [SFLinkMonitor new]; m.name = n; [self->_found addObject:m]; }
        m.deviceId = info[@"id"] ?: @""; m.version = info[@"ver"] ?: @"";
        self->_peers[n] = peerID;
        SFLog(@"monitor trovato: \"%@\" (%@, v%@)", n, m.deviceId, m.version);
        [self changed];
    });
}

- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID {
    OnMain(^{
        NSString *n = peerID.displayName;
        if (self->_peers[n] != peerID && ![self->_peers[n] isEqual:peerID]) return;
        if (self->_state != SFLinkIdle && [self->_connectedName isEqualToString:n]) return;   // collegato: decide la sessione
        [self->_peers removeObjectForKey:n];
        for (SFLinkMonitor *x in [self->_found copy]) if ([x.name isEqualToString:n]) [self->_found removeObject:x];
        SFLog(@"monitor non più visibile: \"%@\"", n);
        [self changed];
    });
}

- (void)browser:(MCNearbyServiceBrowser *)browser didNotStartBrowsingForPeers:(NSError *)error {
    OnMain(^{ self->_lastError = error.localizedDescription; SFLog(@"ricerca NON avviata: %@", error); [self changed]; });
}

#pragma mark - Collegamento

- (void)connectTo:(SFLinkMonitor *)monitor {
    MCPeerID *p = _peers[monitor.name];
    if (!p || !_browser) return;
    [self teardown];            // senza notifica: altrimenti chi si ricollega da solo rientrerebbe qui all'infinito
    // senza cifratura Multipeer: la negoziazione DTLS fa fallire molte sessioni su questi iPad/iPod lenti, e il PIN
    // viaggia comunque in chiaro anche sul Wi-Fi (HTTP). Il monitor accetta sia sessioni cifrate sia in chiaro.
    _session = [[MCSession alloc] initWithPeer:_me securityIdentity:nil encryptionPreference:MCEncryptionNone];
    _session.delegate = self;
    _target = p; _connectedName = [monitor.name copy]; _state = SFLinkConnecting; _lastError = nil;
    [_browser invitePeer:p toSession:_session withContext:nil timeout:15];
    SFLog(@"invito a \"%@\"", monitor.name);
    [self changed];
    MCSession *s = _session;            // se dopo 20 s è ancora "in collegamento", si rinuncia
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_session == s && self->_state == SFLinkConnecting) [self dropSession:@"il monitor non ha risposto"];
    });
}

- (void)disconnect { [self dropSession:nil]; }
- (void)resetAfterSilence { if (_state != SFLinkIdle) { SFLog(@"il monitor non risponde: collegamento chiuso e ricerca riavviata"); [self dropSession:@"il monitor non rispondeva più"]; } }

// chiude la sessione senza avvisare nessuno (chi chiama decide quando notificare il cambiamento)
- (void)teardown {
    if (_session) { SFRetire(_session); _session = nil; }
    _target = nil; _state = SFLinkIdle; _connectedName = nil;
    NSDictionary *p = [_pending copy]; [_pending removeAllObjects];
    for (NSNumber *k in p) ((void (^)(NSInteger, NSDictionary *))p[k])(0, nil);
}
- (void)dropSession:(NSString *)error {
    [self teardown];
    if (error) {
        // collegamento caduto o non riuscito: si riparte da una ricerca pulita dopo una breve pausa. Il monitor
        // ricompare nell'elenco quando è davvero raggiungibile, e solo allora ci si ricollega (niente inviti a raffica,
        // che lasciano sessioni a metà sui due iPad).
        _lastError = [error copy];
        if (++_fails >= 2) [self freshIdentity];       // dopo due tentativi falliti ci si ripresenta come peer nuovo
        [_found removeAllObjects]; [_peers removeAllObjects];
        [_browser stopBrowsingForPeers]; _browser.delegate = nil; _browser = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self->_running || self->_browser) return;
            self->_browser = [[MCNearbyServiceBrowser alloc] initWithPeer:self->_me serviceType:kService];
            self->_browser.delegate = self; [self->_browser startBrowsingForPeers]; self->_browseSince = CACurrentMediaTime();
            SFLog(@"ricerca dei monitor riavviata");
        });
    }
    [self changed];
}

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state {
    OnMain(^{
        if (session != self->_session) return;
        if (state == MCSessionStateConnected) {
            self->_state = SFLinkConnected; self->_lastError = nil; self->_fails = 0;
            SFLog(@"COLLEGATO a \"%@\"", peerID.displayName);
            [self changed];
        } else if (state == MCSessionStateNotConnected) {
            SFLog(@"collegamento con \"%@\" chiuso", peerID.displayName);
            [self dropSession:self->_state == SFLinkConnecting ? @"collegamento non riuscito" : @"collegamento interrotto"];
        }
    });
}

- (void)request:(NSString *)method path:(NSString *)path headers:(NSDictionary *)headers body:(NSDictionary *)body
     completion:(void (^)(NSInteger, NSDictionary *))done {
    if (_state != SFLinkConnected || !_target) { if (done) done(0, nil); return; }
    NSNumber *rid = @(++_seq);
    NSMutableDictionary *m = [@{@"id": rid, @"method": method, @"path": path} mutableCopy];
    if (headers) m[@"headers"] = headers;
    if (body) m[@"body"] = body;
    NSData *d = [NSJSONSerialization dataWithJSONObject:m options:0 error:NULL];
    NSError *err = nil;
    if (!d || ![_session sendData:d toPeers:@[_target] withMode:MCSessionSendDataReliable error:&err]) {
        SFLog(@"invio fallito: %@", err.localizedDescription);
        if (done) done(0, nil);
        return;
    }
    if (done) _pending[rid] = [done copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRequestTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        void (^cb)(NSInteger, NSDictionary *) = self->_pending[rid];
        if (cb) { [self->_pending removeObjectForKey:rid]; cb(0, nil); }
    });
}

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID {
    id j = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![j isKindOfClass:[NSDictionary class]]) return;
    OnMain(^{
        if (session != self->_session || j[@"event"]) return;
        NSNumber *rid = [j[@"id"] isKindOfClass:[NSNumber class]] ? j[@"id"] : nil;
        void (^cb)(NSInteger, NSDictionary *) = rid ? self->_pending[rid] : nil;
        if (!cb) return;
        [self->_pending removeObjectForKey:rid];
        cb([j[@"status"] integerValue], [j[@"body"] isKindOfClass:[NSDictionary class]] ? j[@"body"] : @{});
    });
}

- (void)session:(MCSession *)session didReceiveCertificate:(NSArray *)certificate fromPeer:(MCPeerID *)peerID certificateHandler:(void (^)(BOOL))certificateHandler { certificateHandler(YES); }
- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)streamName fromPeer:(MCPeerID *)peerID {}
- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID withProgress:(NSProgress *)progress {}
- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID atURL:(NSURL *)localURL withError:(NSError *)error {}
@end
