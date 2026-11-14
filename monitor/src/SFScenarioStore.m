#import "SFScenarioStore.h"
#import "SimulationState.h"

static const NSUInteger kMaxScenarios = 40, kMaxPhases = 24;

@implementation SFScenarioStore {
    NSString *_path;
    SimulationState *_state;
    NSMutableArray<NSDictionary *> *_list;
    NSString *_runId; NSInteger _phase; NSTimeInterval _phaseAt;
}

- (instancetype)initWithPath:(NSString *)path state:(SimulationState *)state {
    if ((self = [super init])) {
        _path = [path copy]; _state = state; _phase = -1;
        NSData *d = path ? [NSData dataWithContentsOfFile:path] : nil;
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
        _list = [NSMutableArray array];
        if ([j isKindOfClass:[NSArray class]]) {
            for (id s in j) { NSDictionary *n = [self normalize:s error:NULL]; if (n) [_list addObject:n]; }
        } else {
            for (NSDictionary *s in [SFScenarioStore exampleScenarios]) { NSDictionary *n = [self normalize:s error:NULL]; if (n) [_list addObject:n]; }
        }
    }
    return self;
}

- (void)persist {
    if (!_path) return;
    NSData *d = [NSJSONSerialization dataWithJSONObject:_list options:0 error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:[_path stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
    [d writeToFile:_path atomically:YES];
}

static NSString *Text(id v, NSUInteger max) {
    if (![v isKindOfClass:[NSString class]]) return @"";
    NSString *s = [v stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return s.length > max ? [s substringToIndex:max] : s;
}

// Controlla e ripulisce uno scenario. I parametri delle fasi sono validati dal modello (stessi limiti di "transition").
- (NSDictionary *)normalize:(id)in error:(NSString **)error {
#define FAIL(...) do { if (error) *error = [NSString stringWithFormat:__VA_ARGS__]; return nil; } while (0)
    if (![in isKindOfClass:[NSDictionary class]]) FAIL(@"scenario must be an object");
    NSString *name = Text(in[@"name"], 60);
    if (!name.length) FAIL(@"scenario: name is required");
    NSArray *phases = in[@"phases"];
    if (![phases isKindOfClass:[NSArray class]] || phases.count < 1 || phases.count > kMaxPhases) FAIL(@"scenario: phases must be 1..%lu", (unsigned long)kMaxPhases);
    NSMutableArray *out = [NSMutableArray array];
    NSUInteger i = 0;
    for (id p in phases) {
        i++;
        if (![p isKindOfClass:[NSDictionary class]]) FAIL(@"phase %lu is not an object", (unsigned long)i);
        NSMutableDictionary *q = [NSMutableDictionary dictionary];
        NSString *pn = Text(p[@"name"], 40);
        q[@"name"] = pn.length ? pn : [NSString stringWithFormat:@"Fase %lu", (unsigned long)i];
        q[@"note"] = Text(p[@"note"], 200);
        NSDictionary *params = [p[@"params"] isKindOfClass:[NSDictionary class]] ? p[@"params"] : @{};
        NSString *rhythm = [p[@"rhythm"] isKindOfClass:[NSString class]] && [p[@"rhythm"] length] ? p[@"rhythm"] : nil;
        NSInteger dur = [p[@"duration_s"] respondsToSelector:@selector(integerValue)] ? [p[@"duration_s"] integerValue] : 0;
        if (dur < 0 || dur > 3600) FAIL(@"phase %lu: duration_s out of range [0..3600]", (unsigned long)i);
        q[@"duration_s"] = @(dur);
        BOOL hasExtra = NO;
        if ([p[@"temperature_c"] isKindOfClass:[NSNumber class]]) {
            double t = [p[@"temperature_c"] doubleValue];
            if (t < 25 || t > 45) FAIL(@"phase %lu: temperature_c out of range [25..45]", (unsigned long)i);
            q[@"temperature_c"] = @(round(t * 10) / 10); hasExtra = YES;
        }
        if ([p[@"crt_s"] isKindOfClass:[NSNumber class]]) {
            double c = [p[@"crt_s"] doubleValue];
            if (c < 0.5 || c > 10) FAIL(@"phase %lu: crt_s out of range [0.5..10]", (unsigned long)i);
            q[@"crt_s"] = @(round(c * 2) / 2); hasExtra = YES;
        }
        if (params.count || rhythm) {
            NSMutableDictionary *t = [@{@"params": params, @"duration_s": @(dur)} mutableCopy];
            if (rhythm) t[@"rhythm"] = rhythm;
            NSString *e = nil;
            if (![_state validateTransition:t error:&e]) FAIL(@"phase %lu: %@", (unsigned long)i, e ?: @"invalid parameters");
            NSNumber *s = params[@"systolic_mmhg"], *d = params[@"diastolic_mmhg"];
            if (s && d && d.integerValue >= s.integerValue) FAIL(@"phase %lu: diastolic must be lower than systolic", (unsigned long)i);
            NSMutableDictionary *pp = [NSMutableDictionary dictionary];
            for (NSString *k in params) pp[k] = @([params[k] integerValue]);
            q[@"params"] = pp;
            if (rhythm) q[@"rhythm"] = rhythm;
        } else {
            if (!hasExtra) FAIL(@"phase %lu is empty: set a rhythm or at least one parameter", (unsigned long)i);
            q[@"params"] = @{};
        }
        [out addObject:q];
    }
    NSString *sid = Text(in[@"id"], 40);
    if (!sid.length) sid = [NSString stringWithFormat:@"sc-%08x%04x", (unsigned)[NSDate date].timeIntervalSince1970, arc4random_uniform(0xffff)];
    return @{@"id": sid, @"name": name, @"notes": Text(in[@"notes"], 600), @"phases": out};
#undef FAIL
}

- (NSArray<NSDictionary *> *)scenarios { @synchronized (self) { return [_list copy]; } }

- (NSInteger)indexOf:(NSString *)sid {
    for (NSUInteger i = 0; i < _list.count; i++) if ([_list[i][@"id"] isEqual:sid]) return (NSInteger)i;
    return -1;
}

- (NSDictionary *)save:(NSDictionary *)scenario error:(NSString **)error {
    @synchronized (self) {
        NSDictionary *n = [self normalize:scenario error:error];
        if (!n) return nil;
        NSInteger i = [self indexOf:n[@"id"]];
        if (i >= 0) {
            _list[i] = n;
            // scenario in corso modificato: si resta sulla stessa fase se esiste ancora
            if ([_runId isEqual:n[@"id"]] && _phase >= (NSInteger)[n[@"phases"] count]) _phase = (NSInteger)[n[@"phases"] count] - 1;
        } else {
            if (_list.count >= kMaxScenarios) { if (error) *error = [NSString stringWithFormat:@"too many scenarios (max %lu): delete one first", (unsigned long)kMaxScenarios]; return nil; }
            [_list addObject:n];
        }
        [self persist];
        return n;
    }
}

- (BOOL)deleteId:(NSString *)sid error:(NSString **)error {
    @synchronized (self) {
        NSInteger i = [self indexOf:sid];
        if (i < 0) { if (error) *error = @"scenario not found"; return NO; }
        [_list removeObjectAtIndex:i];
        if ([_runId isEqual:sid]) { _runId = nil; _phase = -1; }
        [self persist];
        return YES;
    }
}

// chiamare con @synchronized già acquisito
- (BOOL)applyPhase:(NSInteger)idx of:(NSDictionary *)sc error:(NSString **)error {
    NSArray *phases = sc[@"phases"];
    if (idx < 0 || idx >= (NSInteger)phases.count) { if (error) *error = @"phase out of range"; return NO; }
    NSDictionary *p = phases[idx];
    NSDictionary *params = p[@"params"] ?: @{};
    if (params.count || p[@"rhythm"]) {
        NSMutableDictionary *t = [@{@"params": params, @"duration_s": p[@"duration_s"] ?: @0} mutableCopy];
        if (p[@"rhythm"]) t[@"rhythm"] = p[@"rhythm"];
        if (![_state applyCommand:@{@"command": @"transition", @"value": t} error:error]) return NO;
    }
    if (p[@"temperature_c"]) [_state applyCommand:@{@"command": @"set_temperature", @"value": p[@"temperature_c"]} error:NULL];
    if (p[@"crt_s"]) [_state applyCommand:@{@"command": @"set_crt", @"value": p[@"crt_s"]} error:NULL];
    _runId = [sc[@"id"] copy]; _phase = idx; _phaseAt = _state.clock();
    return YES;
}

- (BOOL)start:(NSString *)sid phase:(NSInteger)phase error:(NSString **)error {
    @synchronized (self) {
        NSInteger i = [self indexOf:sid];
        if (i < 0) { if (error) *error = @"scenario not found"; return NO; }
        if (![self applyPhase:phase of:_list[i] error:error]) return NO;
        [_state applyCommand:@{@"command": @"reset_clock"} error:NULL];      // l'orologio di scenario riparte con lo scenario
        return YES;
    }
}

- (BOOL)gotoPhase:(NSInteger)phase error:(NSString **)error {
    @synchronized (self) {
        NSInteger i = _runId ? [self indexOf:_runId] : -1;
        if (i < 0) { if (error) *error = @"no scenario is running"; return NO; }
        return [self applyPhase:phase of:_list[i] error:error];
    }
}

- (BOOL)next:(NSString **)error {
    @synchronized (self) {
        NSInteger i = _runId ? [self indexOf:_runId] : -1;
        if (i < 0) { if (error) *error = @"no scenario is running"; return NO; }
        if (_phase + 1 >= (NSInteger)[_list[i][@"phases"] count]) { if (error) *error = @"already at the last phase"; return NO; }
        return [self applyPhase:_phase + 1 of:_list[i] error:error];
    }
}

- (void)stop { @synchronized (self) { _runId = nil; _phase = -1; } }

- (NSDictionary *)runInfo {
    @synchronized (self) {
        NSInteger i = _runId ? [self indexOf:_runId] : -1;
        if (i < 0) return @{@"active": @NO};
        NSDictionary *sc = _list[i]; NSArray *ph = sc[@"phases"];
        NSDictionary *p = ph[MIN(_phase, (NSInteger)ph.count - 1)];
        NSMutableDictionary *d = [@{@"active": @YES, @"id": sc[@"id"], @"name": sc[@"name"], @"phase": @(_phase), @"phases": @(ph.count),
                                    @"phase_name": p[@"name"], @"phase_note": p[@"note"] ?: @"",
                                    @"phase_time_s": @((NSInteger)MAX(0, _state.clock() - _phaseAt))} mutableCopy];
        if (_phase + 1 < (NSInteger)ph.count) d[@"next_name"] = ph[_phase + 1][@"name"];
        return d;
    }
}

+ (NSArray<NSDictionary *> *)exampleScenarios {
#define P(hr, s, d, sp, rr, et) @{@"heart_rate_bpm": @(hr), @"systolic_mmhg": @(s), @"diastolic_mmhg": @(d), @"spo2_percent": @(sp), @"respiratory_rate_rpm": @(rr), @"etco2_mmhg": @(et)}
    return @[
      @{@"id": @"es-arresto-fv", @"name": @"Esempio · Dolore toracico, arresto in FV, ROSC",
        @"notes": @"Uomo, 58 anni, dolore toracico da 40 minuti. Obiettivi: riconoscere il peggioramento, defibrillazione precoce, gestione post-ROSC.",
        @"phases": @[
          @{@"name": @"Arrivo: dolore toracico", @"note": @"Monitoraggio, ECG, accesso venoso. Avanzare quando la squadra ha completato la valutazione.", @"duration_s": @0, @"rhythm": @"sinus", @"params": P(96, 150, 92, 96, 20, 36), @"crt_s": @2},
          @{@"name": @"Peggiora: ipoteso e tachicardico", @"note": @"Avanzare se non riconoscono il peggioramento o dopo la rivalutazione.", @"duration_s": @60, @"rhythm": @"sinus_tachycardia", @"params": P(122, 92, 58, 93, 24, 30), @"crt_s": @3},
          @{@"name": @"Arresto: fibrillazione ventricolare", @"note": @"RCP e defibrillazione. L'esito delle scariche si decide dal pannello Defibrillatore.", @"duration_s": @0, @"rhythm": @"vf", @"params": @{}},
          @{@"name": @"ROSC", @"note": @"Dopo la scarica efficace: valutazione ABCDE, ECG a 12 derivazioni.", @"duration_s": @30, @"rhythm": @"sinus_tachycardia", @"params": P(108, 98, 62, 94, 12, 42), @"crt_s": @3},
        ]},
      @{@"id": @"es-shock-settico", @"name": @"Esempio · Shock settico che risponde ai liquidi",
        @"notes": @"Donna, 72 anni, febbre e confusione. Obiettivi: riconoscere la sepsi, liquidi, rivalutazione.",
        @"phases": @[
          @{@"name": @"Arrivo: febbre e tachicardia", @"note": @"", @"duration_s": @0, @"rhythm": @"sinus_tachycardia", @"params": P(112, 105, 60, 94, 24, 32), @"temperature_c": @38.9, @"crt_s": @3},
          @{@"name": @"Shock", @"note": @"Avanzare qui se i liquidi tardano.", @"duration_s": @120, @"rhythm": @"sinus_tachycardia", @"params": P(134, 78, 42, 90, 30, 26), @"temperature_c": @39.2, @"crt_s": @5},
          @{@"name": @"Dopo il carico di liquidi", @"note": @"Avanzare quando il bolo è stato somministrato.", @"duration_s": @90, @"rhythm": @"sinus_tachycardia", @"params": P(110, 98, 58, 95, 22, 32), @"crt_s": @3},
        ]},
      @{@"id": @"es-insuff-resp", @"name": @"Esempio · Insufficienza respiratoria acuta",
        @"notes": @"Uomo, 66 anni, BPCO riacutizzata. Obiettivi: ossigeno controllato, ventilazione, rivalutazione.",
        @"phases": @[
          @{@"name": @"Arrivo: dispnea", @"note": @"", @"duration_s": @0, @"rhythm": @"sinus_tachycardia", @"params": P(108, 145, 88, 88, 28, 50)},
          @{@"name": @"Si esaurisce", @"note": @"Avanzare se non viene supportata la ventilazione.", @"duration_s": @120, @"rhythm": @"sinus_tachycardia", @"params": P(124, 150, 90, 80, 34, 62)},
          @{@"name": @"Bradipnea e sopore", @"note": @"", @"duration_s": @60, @"rhythm": @"sinus", @"params": P(88, 110, 70, 74, 8, 78)},
          @{@"name": @"Migliora con il supporto", @"note": @"Avanzare quando ventilano in modo efficace.", @"duration_s": @90, @"rhythm": @"sinus", @"params": P(96, 128, 78, 94, 18, 46)},
        ]},
    ];
#undef P
}
@end
