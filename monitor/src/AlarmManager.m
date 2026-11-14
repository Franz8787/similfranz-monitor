#import "AlarmManager.h"
#import "SimulationState.h"

@interface SLAlarmResult ()
@property (nonatomic, readwrite) SLAlarmLevel level;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *messages;
@property (nonatomic, readwrite, copy) NSSet<NSString *> *violated;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSNumber *> *severity;
@end
@implementation SLAlarmResult
@end

@implementation AlarmManager

+ (SLAlarmResult *)evaluate:(SLSnapshot *)s {
    NSMutableArray *high = [NSMutableArray array], *med = [NSMutableArray array], *tech = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSNumber *> *sev = [NSMutableDictionary dictionary];   // parametro -> gravità massima
    #define MARK(k, lvl) do { if ([sev[k] integerValue] < (lvl)) sev[k] = @(lvl); } while (0)
    if (s.simulationRunning) {
        // --- ECG: il monitor "vede" il ritmo solo con gli elettrodi collegati ---
        if (!s.ecgConnected) {
            [tech addObject:@"ECG ELETTRODI SCOLLEGATI"];
        } else {
            NSString *r = s.rhythm;
            if ([r isEqualToString:SLRhythmVentricularFib]) { [high addObject:@"FIBRILLAZIONE VENTRICOLARE"]; MARK(@"hr", SLAlarmHigh); }
            else if ([r isEqualToString:SLRhythmVentricularTachy] || [r isEqualToString:SLRhythmVentricularTachyPulse]) { [high addObject:@"TACHICARDIA VENTRICOLARE"]; MARK(@"hr", SLAlarmHigh); }
            else if ([r isEqualToString:SLRhythmAsystole] && !s.defib.paceCapture) { [high addObject:@"ASISTOLIA"]; MARK(@"hr", SLAlarmHigh); }
            NSInteger hr = s.displayedHeartRate;
            BOOL pacedLP = NO;
            if ([s alarmOn:@"hr"] && hr > 0 && !pacedLP && ![r isEqualToString:SLRhythmVentricularTachy] && ![r isEqualToString:SLRhythmVentricularTachyPulse]) {
                NSInteger lo = [s limit:@"hr_low"], hi = [s limit:@"hr_high"];
                if (hr < lo) { { BOOL crit = hr < lo - 10; [(crit ? high : med) addObject:[NSString stringWithFormat:@"FC < %ld", (long)lo]]; MARK(@"hr", crit ? SLAlarmHigh : SLAlarmMedium); } }
                if (hr > hi) { { BOOL crit = hr > hi + 30; [(crit ? high : med) addObject:[NSString stringWithFormat:@"FC > %ld", (long)hi]]; MARK(@"hr", crit ? SLAlarmHigh : SLAlarmMedium); } }
            }
        }
        // --- SpO2 ---
        if (!s.spo2Connected) [tech addObject:@"SpO2 SONDA SCOLLEGATA"];
        else if (!s.spo2SignalValid) [tech addObject:@"SpO2 SEGNALE SCARSO"];
        else if (s.lowPerfusion) [tech addObject:@"SpO2 BASSA PERFUSIONE"];
        if (!s.spo2Connected || !s.spo2SignalValid) {}
        else if (![s alarmOn:@"spo2"]) {}
        else if (!s.pulsePresent) { [med addObject:@"SpO2 NESSUN POLSO"]; MARK(@"spo2", SLAlarmMedium); }
        else {
            NSInteger lo = [s limit:@"spo2_low"];
            if (s.spo2 < lo) { { BOOL crit = s.spo2 < lo - 5; [(crit ? high : med) addObject:[NSString stringWithFormat:@"SpO2 < %ld", (long)lo]]; MARK(@"spo2", crit ? SLAlarmHigh : SLAlarmMedium); } }
        }
        // --- Respiro: FR dalla capnografia oppure dall'impedenza toracica degli elettrodi ECG ---
        if (s.etco2Connected || s.ecgConnected) {
            NSInteger rlo = [s limit:@"rr_low"], rhi = [s limit:@"rr_high"];
            if (![s alarmOn:@"rr"]) {}
            else if (s.respRate == 0) { [high addObject:@"APNEA"]; MARK(@"rr", SLAlarmHigh); }
            else if (s.respRate < rlo) { [med addObject:[NSString stringWithFormat:@"FR < %ld", (long)rlo]]; MARK(@"rr", SLAlarmMedium); }
            else if (s.respRate > rhi) { [med addObject:[NSString stringWithFormat:@"FR > %ld", (long)rhi]]; MARK(@"rr", SLAlarmMedium); }
            if (s.etco2Connected && s.respRate > 0 && [s alarmOn:@"etco2"]) {          // EtCO2 solo con il sensore CO2
                NSInteger elo = [s limit:@"etco2_low"], ehi = [s limit:@"etco2_high"];
                if (s.etco2 < elo) { [med addObject:[NSString stringWithFormat:@"EtCO2 < %ld", (long)elo]]; MARK(@"etco2", SLAlarmMedium); }
                else if (s.etco2 > ehi) { [med addObject:[NSString stringWithFormat:@"EtCO2 > %ld", (long)ehi]]; MARK(@"etco2", SLAlarmMedium); }
            }
        }
        // --- Pressione: ART in continuo, NIBP all'ultima misura ---
        NSInteger plo = [s limit:@"sys_low"], phi = [s limit:@"sys_high"];
        if (s.artConnected && [s alarmOn:@"art"]) {
            NSInteger sys = s.artDisplayedSystolic;
            if (sys < plo) { { BOOL crit = sys < plo - 20; [(crit ? high : med) addObject:[NSString stringWithFormat:@"ART SIST < %ld", (long)plo]]; MARK(@"art", crit ? SLAlarmHigh : SLAlarmMedium); } }
            else if (sys > phi) { [med addObject:[NSString stringWithFormat:@"ART SIST > %ld", (long)phi]]; MARK(@"art", SLAlarmMedium); }
        }
        if (s.nibpLastSystolic >= 0 && [s alarmOn:@"nibp"]) {
            if (s.nibpLastSystolic < plo) { [med addObject:[NSString stringWithFormat:@"NIBP SIST < %ld", (long)plo]]; MARK(@"nibp", SLAlarmMedium); }
            else if (s.nibpLastSystolic > phi) { [med addObject:[NSString stringWithFormat:@"NIBP SIST > %ld", (long)phi]]; MARK(@"nibp", SLAlarmMedium); }
        }
        if (s.nibpStatus == SLNibpError) {
            [tech addObject:[s.nibpError isEqualToString:@"cuff"] ? @"NIBP BRACCIALE NON COLLEGATO"
                          : ([s.nibpError isEqualToString:@"motion"] ? @"NIBP ARTEFATTO DA MOVIMENTO" : @"NIBP NESSUN POLSO RILEVATO")];
        }
    }
    SLAlarmResult *res = [SLAlarmResult new];
    NSMutableArray *all = [NSMutableArray arrayWithArray:high];
    [all addObjectsFromArray:med]; [all addObjectsFromArray:tech];
    res.messages = all;
    res.violated = [NSSet setWithArray:sev.allKeys];
    res.severity = sev;
    res.level = high.count ? SLAlarmHigh : med.count ? SLAlarmMedium : tech.count ? SLAlarmTechnical : SLAlarmNone;
    return res;
}

@end
