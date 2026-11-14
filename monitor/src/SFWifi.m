#import "SFWifi.h"
#import "SFLog.h"
#import <dlfcn.h>

typedef const void *WRef;
static WRef (*pManagerCreate)(CFAllocatorRef, int);
static CFArrayRef (*pCopyDevices)(WRef);
static CFArrayRef (*pCopyNetworks)(WRef);
static void (*pSchedule)(WRef, CFRunLoopRef, CFStringRef);
static int (*pScanAsync)(WRef, CFDictionaryRef, void (*)(WRef, CFArrayRef, int, void *), void *);
static int (*pAssociateAsync)(WRef, WRef, void (*)(WRef, WRef, CFDictionaryRef, int, void *), void *);
static WRef (*pCopyCurrent)(WRef);
static CFStringRef (*pGetSSID)(WRef);
static CFTypeRef (*pGetProperty)(WRef, CFStringRef);
static Boolean (*pSetPassword)(WRef, CFStringRef);
static CFStringRef (*pCopyPassword)(WRef);
static Boolean (*pIsWPA)(WRef), (*pIsWEP)(WRef), (*pIsEAP)(WRef);
static void (*pAddNetwork)(WRef, WRef);
static CFTypeRef (*pMgrCopyProperty)(WRef, CFStringRef);
static Boolean (*pMgrSetProperty)(WRef, CFStringRef, CFTypeRef);

@implementation SFWifiNetwork
- (NSInteger)bars { return self.rssi >= -60 ? 3 : (self.rssi >= -75 ? 2 : 1); }
@end

@interface SFWifi ()
- (void)scanDone:(CFArrayRef)results error:(int)err;
- (void)joinDone:(int)err;
@end
static void ScanCB(WRef dev, CFArrayRef results, int err, void *tok) { [[SFWifi shared] scanDone:results error:err]; }
static void AssocCB(WRef dev, WRef net, CFDictionaryRef d, int err, void *tok) { [[SFWifi shared] joinDone:err]; }

@implementation SFWifi {
    WRef _mgr, _dev;
    NSMutableDictionary<NSString *, id> *_refs;      // ssid -> WiFiNetworkRef dell'ultima scansione
    void (^_joinDone)(BOOL, NSString *);
    WRef _joinNet;
}
+ (instancetype)shared { static SFWifi *s; static dispatch_once_t once; dispatch_once(&once, ^{ s = [SFWifi new]; }); return s; }

- (instancetype)init {
    if ((self = [super init])) {
        _refs = [NSMutableDictionary dictionary]; _networks = @[];
        void *h = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_NOW);
        NSMutableArray *missing = [NSMutableArray array];
#define SYM(var, name) var = dlsym(h, name); if (!var) [missing addObject:@name];
        if (h) {
            SYM(pManagerCreate, "WiFiManagerClientCreate") SYM(pCopyDevices, "WiFiManagerClientCopyDevices")
            SYM(pCopyNetworks, "WiFiManagerClientCopyNetworks") SYM(pSchedule, "WiFiManagerClientScheduleWithRunLoop")
            SYM(pScanAsync, "WiFiDeviceClientScanAsync") SYM(pAssociateAsync, "WiFiDeviceClientAssociateAsync")
            SYM(pCopyCurrent, "WiFiDeviceClientCopyCurrentNetwork") SYM(pGetSSID, "WiFiNetworkGetSSID")
            SYM(pGetProperty, "WiFiNetworkGetProperty") SYM(pSetPassword, "WiFiNetworkSetPassword")
            SYM(pCopyPassword, "WiFiNetworkCopyPassword") SYM(pIsWPA, "WiFiNetworkIsWPA") SYM(pIsWEP, "WiFiNetworkIsWEP")
            SYM(pIsEAP, "WiFiNetworkIsEAP") SYM(pAddNetwork, "WiFiManagerClientAddNetwork")
            SYM(pMgrCopyProperty, "WiFiManagerClientCopyProperty") SYM(pMgrSetProperty, "WiFiManagerClientSetProperty")
        }
        if (h && !missing.count) {
            _mgr = pManagerCreate(kCFAllocatorDefault, 0);
            if (_mgr) {
                pSchedule(_mgr, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
                CFArrayRef devs = pCopyDevices(_mgr);
                if (devs && CFArrayGetCount(devs) > 0) _dev = CFRetain(CFArrayGetValueAtIndex(devs, 0));
                if (devs) CFRelease(devs);
            }
        }
        _available = _mgr && _dev;
        SFLog(@"wifi in app: %@%@", _available ? @"disponibile" : @"NON disponibile",
              missing.count ? [@" — simboli mancanti: " stringByAppendingString:[missing componentsJoinedByString:@","]] : (h ? @"" : @" — framework non caricato"));
    }
    return self;
}

- (void)changed { if (self.onChange) self.onChange(); }

- (NSString *)currentSSID {
    if (!_available) return nil;
    WRef n = pCopyCurrent(_dev); if (!n) return nil;
    NSString *s = [(__bridge NSString *)pGetSSID(n) copy]; CFRelease(n); return s;
}
- (BOOL)powerOn {
    if (!_available) return NO;
    CFTypeRef v = pMgrCopyProperty(_mgr, CFSTR("AllowEnable")); BOOL on = v ? [(__bridge id)v boolValue] : YES; if (v) CFRelease(v); return on;
}
- (void)setPower:(BOOL)on { if (_available) pMgrSetProperty(_mgr, CFSTR("AllowEnable"), on ? kCFBooleanTrue : kCFBooleanFalse); }

- (NSSet<NSString *> *)knownSSIDs {
    NSMutableSet *s = [NSMutableSet set];
    CFArrayRef nets = pCopyNetworks(_mgr);
    if (nets) { for (CFIndex i = 0; i < CFArrayGetCount(nets); i++) { NSString *n = (__bridge NSString *)pGetSSID(CFArrayGetValueAtIndex(nets, i)); if (n) [s addObject:n]; } CFRelease(nets); }
    return s;
}

- (void)scan {
    if (!_available || _scanning) return;
    _scanning = YES; _lastError = nil;
    int r = pScanAsync(_dev, (__bridge CFDictionaryRef)@{}, ScanCB, NULL);
    if (r != 0) { _scanning = NO; _lastError = [NSString stringWithFormat:@"ricerca non avviata (%d)", r]; SFLog(@"wifi: %@", _lastError); }
    [self changed];
}
- (void)scanDone:(CFArrayRef)results error:(int)err {
    _scanning = NO;
    if (err != 0) { _lastError = [NSString stringWithFormat:@"ricerca fallita (%d)", err]; SFLog(@"wifi: %@", _lastError); [self changed]; return; }
    NSSet *known = [self knownSSIDs]; NSString *cur = [self currentSSID];
    NSMutableDictionary<NSString *, SFWifiNetwork *> *best = [NSMutableDictionary dictionary];
    [_refs removeAllObjects];
    for (CFIndex i = 0; results && i < CFArrayGetCount(results); i++) {
        WRef n = CFArrayGetValueAtIndex(results, i);
        NSString *ssid = (__bridge NSString *)pGetSSID(n);
        if (!ssid.length) continue;                                   // reti nascoste: non elencate
        NSInteger rssi = [(__bridge id)pGetProperty(n, CFSTR("RSSI")) integerValue];
        SFWifiNetwork *o = best[ssid];
        if (o && o.rssi >= rssi) continue;
        o = [SFWifiNetwork new]; o.ssid = ssid; o.rssi = rssi;
        o.channel = [(__bridge id)pGetProperty(n, CFSTR("CHANNEL")) integerValue];
        o.secured = pIsWPA(n) || pIsWEP(n) || pIsEAP(n);
        o.known = [known containsObject:ssid]; o.current = [ssid isEqualToString:cur];
        best[ssid] = o; _refs[ssid] = (__bridge id)n;
    }
    _networks = [best.allValues sortedArrayUsingComparator:^NSComparisonResult(SFWifiNetwork *a, SFWifiNetwork *b) {
        if (a.current != b.current) return a.current ? NSOrderedAscending : NSOrderedDescending;
        if (a.known != b.known) return a.known ? NSOrderedAscending : NSOrderedDescending;
        return a.rssi > b.rssi ? NSOrderedAscending : (a.rssi < b.rssi ? NSOrderedDescending : [a.ssid compare:b.ssid]);
    }];
    SFLog(@"wifi: %lu reti trovate", (unsigned long)_networks.count);
    [self changed];
}

- (void)join:(SFWifiNetwork *)net password:(NSString *)password completion:(void (^)(BOOL, NSString *))done {
    WRef n = (__bridge WRef)_refs[net.ssid];
    if (!_available || !n) { if (done) done(NO, @"rete non più visibile: aggiornare l'elenco"); return; }
    if (_joining) { if (done) done(NO, @"collegamento già in corso"); return; }
    if (password.length) { Boolean pwOk = pSetPassword(n, (__bridge CFStringRef)password); SFLog(@"wifi: password impostata=%d", (int)pwOk); }
    else if (net.known) {                                            // rete già salvata: si riusa la password che l'iPad ricorda
        CFArrayRef nets = pCopyNetworks(_mgr);
        for (CFIndex i = 0; nets && i < CFArrayGetCount(nets); i++) {
            WRef k = CFArrayGetValueAtIndex(nets, i);
            if (![(__bridge NSString *)pGetSSID(k) isEqualToString:net.ssid]) continue;
            CFStringRef pw = pCopyPassword(k);
            if (pw) { pSetPassword(n, pw); CFRelease(pw); }
            break;
        }
        if (nets) CFRelease(nets);
    }
    _joining = YES; _joiningSSID = net.ssid; _joinDone = [done copy]; _joinNet = CFRetain(n); _lastError = nil;
    int r = pAssociateAsync(_dev, n, AssocCB, NULL);
    SFLog(@"wifi: collegamento a \"%@\" avviato (%d)", net.ssid, r);
    if (r != 0) { [self joinDone:r]; return; }
    [self changed];
    __weak SFWifi *w = self; NSString *ssid = net.ssid;                // rete che non risponde: non restare appesi
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (w.joining && [w.joiningSSID isEqualToString:ssid]) [w joinDone:-1];
    });
}
- (void)joinDone:(int)err {
    if (!_joining) return;
    BOOL ok = err == 0;
    SFLog(@"wifi: collegamento a \"%@\" %@ (%d)", _joiningSSID, ok ? @"riuscito" : @"FALLITO", err);
    if (ok && _joinNet) {                                             // la rete resta salvata sull'iPad: alla prossima accensione si ricollega da sola
        pAddNetwork(_mgr, _joinNet);
        [[NSUserDefaults standardUserDefaults] setObject:_joiningSSID forKey:@"sf_last_ssid"];
    }
    // -3924 = autenticazione rifiutata (visto sull'iPad con una password sbagliata); -1 = nostro tempo scaduto
    NSString *e = ok ? nil : (err == -1 ? @"nessuna risposta dalla rete (hotspot spento o troppo lontano?)"
                              : (err == -3924 ? @"password errata" : [NSString stringWithFormat:@"non riuscito (errore %d): controllare password e sicurezza dell'hotspot (WPA2)", err]));
    _lastError = e; _joining = NO;
    if (_joinNet) { CFRelease(_joinNet); _joinNet = NULL; }
    for (SFWifiNetwork *n in _networks) n.current = ok && [n.ssid isEqualToString:_joiningSSID];
    void (^d)(BOOL, NSString *) = _joinDone; _joinDone = nil;
    if (d) d(ok, e);
    [self changed];
}
@end
