#import "SFControl.h"

static NSString *Ago(NSTimeInterval s) {
    return s < 90 ? [NSString stringWithFormat:@"%ld s", (long)s] : [NSString stringWithFormat:@"%ld min", (long)lround(s / 60)];
}

@implementation SFControl {
    NSString *_ownerId, *_name, *_kind, *_transport;
    NSTimeInterval _seenAt, _actedAt, _since;
    NSString *_lostId, *_lostTo; NSTimeInterval _lostAt;     // l'ultimo che ha perso il comando, a favore di chi, quando
}
@synthesize lastEvent = _lastEvent;

- (instancetype)init {
    if ((self = [super init])) {
        _idleTimeout = 10; _actionIdle = 60;
        _clock = ^NSTimeInterval { return [NSProcessInfo processInfo].systemUptime; };
    }
    return self;
}

// --- da chiamare con @synchronized già acquisito ---
// il controller attivo non si fa sentire da troppo: posto libero. Ritorna YES se è appena successo.
- (BOOL)expire {
    if (_ownerId && self.clock() - _seenAt > _idleTimeout) {
        _lastEvent = [NSString stringWithFormat:@"Controllo libero: «%@» non risponde più", _name];
        _ownerId = nil; return YES;
    }
    return NO;
}
- (void)setOwner:(NSString *)cid name:(NSString *)name kind:(NSString *)kind transport:(NSString *)transport {
    NSString *newName = name.length ? [name copy] : @"controller";
    if (_ownerId && ![_ownerId isEqualToString:cid]) { _lostId = _ownerId; _lostTo = newName; _lostAt = self.clock(); }
    if ([_lostId isEqualToString:cid]) _lostId = nil;          // chi riprende il comando non ha più nulla da sapere
    _ownerId = [cid copy]; _name = newName;
    _kind = kind.length ? [kind copy] : @"altro";
    _transport = transport.length ? [transport copy] : @"wifi";
    _seenAt = _actedAt = _since = self.clock();
}
- (NSString *)via { return [_transport isEqualToString:@"direct"] ? @"collegamento diretto" : @"Wi-Fi"; }

- (void)notify { void (^cb)(void) = self.onChange; if (cb) cb(); }

- (void)seen:(NSString *)cid {
    if (!cid.length) return;
    BOOL changed;
    @synchronized (self) {
        changed = [self expire];
        if (_ownerId && [_ownerId isEqualToString:cid]) _seenAt = self.clock();
    }
    if (changed) [self notify];
}

- (BOOL)act:(NSString *)cid name:(NSString *)name kind:(NSString *)kind transport:(NSString *)transport {
    if (!cid.length) return NO;
    BOOL changed = NO, mine = NO;
    @synchronized (self) {
        changed = [self expire];
        NSTimeInterval now = self.clock();
        if (!_ownerId) {
            [self setOwner:cid name:name kind:kind transport:transport];
            _lastEvent = [NSString stringWithFormat:@"Comanda «%@» (%@)", _name, [self via]]; changed = YES;
        } else if (![_ownerId isEqualToString:cid] && now - _actedAt > _actionIdle) {
            NSString *prev = _name; NSTimeInterval idle = now - _actedAt;
            [self setOwner:cid name:name kind:kind transport:transport];
            _lastEvent = [NSString stringWithFormat:@"Comando passato a «%@» (%@): «%@» era fermo da %@", _name, [self via], prev, Ago(idle)];
            changed = YES;
        }
        mine = [_ownerId isEqualToString:cid];
        if (mine) _seenAt = _actedAt = now;
    }
    if (changed) [self notify];
    return mine;
}

- (void)take:(NSString *)cid name:(NSString *)name kind:(NSString *)kind transport:(NSString *)transport {
    if (!cid.length) return;
    BOOL changed;
    @synchronized (self) {
        [self expire];
        changed = ![_ownerId isEqualToString:cid];
        NSString *prev = _ownerId ? _name : nil;
        [self setOwner:cid name:name kind:kind transport:transport];
        if (changed) _lastEvent = prev ? [NSString stringWithFormat:@"«%@» ha preso il controllo (%@) da «%@»", _name, [self via], prev]
                                       : [NSString stringWithFormat:@"Comanda «%@» (%@)", _name, [self via]];
    }
    if (changed) [self notify];
}

- (void)releaseClient:(NSString *)cid {
    BOOL changed = NO;
    @synchronized (self) {
        if (_ownerId && (!cid || [_ownerId isEqualToString:cid])) {
            _lastEvent = [NSString stringWithFormat:@"«%@» ha lasciato il controllo", _name];
            _ownerId = nil; changed = YES;
        }
    }
    if (changed) [self notify];
}

- (NSDictionary *)infoFor:(NSString *)cid {
    BOOL expired; NSMutableDictionary *d;
    @synchronized (self) {
        expired = [self expire];
        NSTimeInterval now = self.clock();
        if (!_ownerId) d = [@{@"active": @NO, @"mine": @NO} mutableCopy];
        else d = [@{@"active": @YES, @"name": _name, @"kind": _kind, @"transport": _transport,
                    @"mine": @((BOOL)(cid && [_ownerId isEqualToString:cid])),
                    @"idle_s": @((NSInteger)(now - _seenAt)), @"action_idle_s": @((NSInteger)(now - _actedAt)),
                    @"since_s": @((NSInteger)(now - _since)), @"protected": @((BOOL)(now - _actedAt <= _actionIdle))} mutableCopy];
        if (cid && [_lostId isEqualToString:cid] && now - _lostAt < 300) { d[@"lost_to"] = _lostTo; d[@"lost_ago_s"] = @((NSInteger)(now - _lostAt)); }
    }
    if (expired) [self notify];
    return d;
}

- (NSDictionary *)owner {
    BOOL expired; NSDictionary *d = nil;
    @synchronized (self) {
        expired = [self expire];
        if (_ownerId) d = @{@"name": _name, @"kind": _kind, @"transport": _transport};
    }
    if (expired) [self notify];
    return d;
}
@end
