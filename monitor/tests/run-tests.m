// Test di logica di SimulaFranz_Monitor eseguibili su macOS (nessuna dipendenza UIKit).
// Compilazione/esecuzione: scripts/test-mac.sh
#import <Foundation/Foundation.h>
#include <zlib.h>
#import "SFUpdate.h"
#import "SimulationState.h"
#import "WaveformEngine.h"
#import "AlarmManager.h"
#import "APIController.h"
#import "SFControl.h"
#import "SFScenarioStore.h"
#import "SFSessionLog.h"

static int gPass = 0, gFail = 0;
#define CHECK(cond, ...) do { if (cond) { gPass++; } else { gFail++; \
    fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } } while (0)

static NSTimeInterval gNow = 1000;
static BOOL Cmd(SimulationState *s, NSString *c, id v, NSString **err);
// monitoraggio base collegato (ECG, SpO2, NIBP): premessa di molti test
static void BaseSensors(SimulationState *s) {
    for (NSString *k in @[@"ecg", @"spo2", @"nibp"]) Cmd(s, @"set_sensor", @{@"sensor": k, @"connected": @YES}, NULL);
}
static SimulationState *NewStateRaw(void) {
    SimulationState *s = [[SimulationState alloc] initWithDeviceId:@"monitor-01"];
    s.clock = ^NSTimeInterval { return gNow; };
    return s;
}
static SimulationState *NewState(void) { SimulationState *s = NewStateRaw(); BaseSensors(s); return s; }
static void Reset(SimulationState *s) { [s resetScenario]; BaseSensors(s); }
static BOOL Cmd(SimulationState *s, NSString *c, id v, NSString **err) {
    NSMutableDictionary *d = [@{@"command": c} mutableCopy];
    if (v) d[@"value"] = v;
    return [s applyCommand:d error:err];
}
static BOOL Sensor(SimulationState *s, NSString *name, BOOL on) {
    return Cmd(s, @"set_sensor", @{@"sensor": name, @"connected": @(on)}, NULL);
}
static void RunNibp(SimulationState *s) {
    [s startNibpMeasurementError:NULL];
    gNow += 60; [s tickAtTime:gNow];
}

static void testState(void) {
    SimulationState *s = NewState();
    SLSnapshot *sn = [s snapshot];
    CHECK([sn.rhythm isEqualToString:@"sinus"] && sn.heartRate == 82 && sn.spo2 == 98, "valori iniziali");
    SLSnapshot *raw = [NewStateRaw() snapshot];
    CHECK(!raw.ecgConnected && !raw.spo2Connected && !raw.nibpConnected && !raw.etco2Connected && !raw.artConnected,
          "all'avvio tutti i sensori sono scollegati");
    NSString *err = nil;
    CHECK(Cmd(s, @"set_heart_rate", @110, &err) && [s snapshot].heartRate == 110, "set_heart_rate 110");
    CHECK(!Cmd(s, @"set_heart_rate", @400, &err) && [err containsString:@"range"], "FC fuori range rifiutata");
    CHECK(!Cmd(s, @"set_heart_rate", @"abc", &err), "FC stringa rifiutata");
    CHECK(!Cmd(s, @"set_heart_rate", @YES, &err), "FC booleana rifiutata");
    CHECK(!Cmd(s, @"set_rhythm", @"torsade", &err), "ritmo non supportato rifiutato");
    CHECK(!Cmd(s, @"boom", nil, &err) && [err containsString:@"unknown"], "comando sconosciuto");
    CHECK((![s applyCommand:@{@"command": @"set_spo2", @"value": @90, @"device_id": @"altro"} error:&err]), "device_id errato");
    CHECK(!Cmd(s, @"set_bp", @{@"systolic": @80, @"diastolic": @90}, &err), "diastolica >= sistolica rifiutata");
    CHECK(Cmd(s, @"set_bp", @{@"systolic": @95, @"diastolic": @60}, &err), "set_bp valido");
    CHECK(Cmd(s, @"set_nibp", @{@"systolic": @95, @"diastolic": @60}, &err), "set_nibp (alias compatibilità)");
    CHECK(!Cmd(s, @"set_sensor", @{@"sensor": @"eeg", @"connected": @YES}, &err), "sensore sconosciuto rifiutato");
    CHECK(!Cmd(s, @"set_sensor", @{@"sensor": @"ecg", @"connected": @1}, &err), "set_sensor richiede booleano");
    CHECK(!Cmd(s, @"set_volume", @150, &err) && Cmd(s, @"set_volume", @40, &err) && [s snapshot].volume == 40, "volume 0..100");
    CHECK(Cmd(s, @"set_qrs_beep", @NO, &err) && ![s snapshot].qrsBeepEnabled, "bip QRS disattivabile");

    NSUInteger rev = [s snapshot].revision;
    Cmd(s, @"set_spo2", @91, NULL);
    CHECK([s snapshot].revision == rev + 1, "revision incrementale");

    Cmd(s, @"set_rhythm", @"vf", NULL);
    sn = [s snapshot];
    CHECK(!sn.pulsePresent && !sn.spo2Displayable && sn.displayedHeartRate == -1, "VF senza polso");
    CHECK([[s stateDictionary][@"spo2_displayed"] isKindOfClass:[NSNull class]], "VF: spo2_displayed null");
    Cmd(s, @"set_rhythm", @"asystole", NULL);
    CHECK([s snapshot].displayedHeartRate == 0, "asistolia FC 0");
    Cmd(s, @"set_rhythm", @"pea", NULL);
    sn = [s snapshot];
    CHECK(!sn.pulsePresent && sn.displayedHeartRate > 0, "PEA: attività elettrica senza polso");
    Cmd(s, @"set_rhythm", @"sinus_tachycardia", NULL);
    CHECK([s snapshot].heartRate > 100 && [s snapshot].pulsePresent, "preset tachicardia sinusale");

    // Sensori
    Sensor(s, @"spo2", NO);
    CHECK(![s snapshot].spo2Displayable && [s snapshot].spo2 == 91, "sonda staccata: valore non mostrato");
    Sensor(s, @"spo2", YES);
    Sensor(s, @"ecg", NO);
    CHECK([s snapshot].displayedHeartRate == -1, "elettrodi staccati: FC ECG '---'");
    Sensor(s, @"ecg", YES);
    CHECK([s snapshot].artDisplayedSystolic == -1, "ART non collegata: '--'");
    Sensor(s, @"art", YES);
    Cmd(s, @"set_bp", @{@"systolic": @130, @"diastolic": @70}, NULL);
    CHECK([s snapshot].artDisplayedSystolic == 130 && [s snapshot].artDisplayedDiastolic == 70, "ART mostra la PA del paziente");
    Cmd(s, @"set_rhythm", @"vf", NULL);
    CHECK([s snapshot].artDisplayedSystolic == 20, "ART in arresto ~20 mmHg");
    Cmd(s, @"set_rhythm", @"sinus", NULL);

    // NIBP: profilo realistico (gonfiaggio -> gradini -> scarico)
    Cmd(s, @"set_bp", @{@"systolic": @120, @"diastolic": @80}, NULL);
    CHECK([s startNibpMeasurementError:NULL], "avvio NIBP");
    CHECK(![s startNibpMeasurementError:&err], "NIBP già in corso rifiutato");
    double p = 0; NSInteger step = -1;
    SLSnapshot *m = [s snapshot];
    CHECK([m nibpPhaseAt:gNow + 2 pressure:&p step:&step] == SLNibpPhaseInflating && p > 30, "fase gonfiaggio (%.0f mmHg)", p);
    double pk = 0; [m nibpPhaseAt:gNow + 5.74 pressure:&pk step:&step];
    CHECK(pk > 140, "picco di gonfiaggio sopra la sistolica (%.0f mmHg)", pk);
    CHECK([m nibpPhaseAt:gNow + 9 pressure:&p step:&step] == SLNibpPhaseDeflating && step >= 0 && p < pk, "sgonfiaggio a gradini");
    gNow += 3; [s tickAtTime:gNow];
    CHECK([s snapshot].nibpStatus == SLNibpMeasuring, "NIBP in misura dopo 3 s");
    gNow += 60; [s tickAtTime:gNow];
    sn = [s snapshot];
    CHECK(sn.nibpStatus == SLNibpComplete && labs(sn.nibpLastSystolic - 120) <= 4 && labs(sn.nibpLastDiastolic - 80) <= 3,
          "NIBP completata ~120/80 (%ld/%ld, scarto realistico)", (long)sn.nibpLastSystolic, (long)sn.nibpLastDiastolic);
    CHECK(labs(sn.meanArterialPressure - 93) <= 4, "PAM ~93 (%ld)", (long)sn.meanArterialPressure);
    Cmd(s, @"set_rhythm", @"vf", NULL); RunNibp(s);
    CHECK([s snapshot].nibpStatus == SLNibpError && [[s snapshot].nibpError isEqualToString:@"no_pulse"], "NIBP in VF: nessuna oscillazione");
    Cmd(s, @"set_rhythm", @"sinus", NULL); Sensor(s, @"nibp", NO); RunNibp(s);
    CHECK([[s snapshot].nibpError isEqualToString:@"cuff"], "NIBP con bracciale staccato: errore bracciale");
    Sensor(s, @"nibp", YES);
    [s startNibpMeasurementError:NULL]; Sensor(s, @"nibp", NO);
    CHECK([s snapshot].nibpStatus == SLNibpError, "bracciale staccato durante la misura: interrotta");
    Sensor(s, @"nibp", YES);

    // Bassa perfusione: SpO2 con "?" e allarme tecnico
    Cmd(s, @"set_bp", @{@"systolic": @62, @"diastolic": @38}, NULL);
    CHECK([s snapshot].lowPerfusion && [[s stateDictionary][@"spo2_low_perfusion"] boolValue], "ipotensione marcata: SpO2 con ?");
    CHECK([[[AlarmManager evaluate:[s snapshot]].messages componentsJoinedByString:@","] containsString:@"BASSA PERFUSIONE"], "allarme bassa perfusione");
    Cmd(s, @"set_bp", @{@"systolic": @120, @"diastolic": @80}, NULL);
    CHECK(![s snapshot].lowPerfusion, "PA normale: niente ?");

    // Allarme disattivato per parametro (i ritmi letali suonano comunque)
    Cmd(s, @"set_alarm_limits", @{@"hr_high": @80}, NULL); Cmd(s, @"set_heart_rate", @100, NULL);
    CHECK([[AlarmManager evaluate:[s snapshot]].severity[@"hr"] integerValue] > 0, "FC 100 > 80: allarme");
    CHECK(Cmd(s, @"set_alarm_enabled", @{@"param": @"hr", @"enabled": @NO}, &err), "disattiva allarme FC");
    CHECK([[AlarmManager evaluate:[s snapshot]].severity[@"hr"] integerValue] == 0, "allarme FC disattivato: niente allarme");
    Cmd(s, @"set_rhythm", @"vf", NULL);
    CHECK([AlarmManager evaluate:[s snapshot]].level == SLAlarmHigh, "FV suona anche con allarme FC disattivato");
    Cmd(s, @"set_rhythm", @"sinus", NULL); Cmd(s, @"set_alarm_enabled", @{@"param": @"hr", @"enabled": @YES}, NULL);
    Cmd(s, @"reset_alarm_limits", nil, NULL); Cmd(s, @"set_heart_rate", @82, NULL); Cmd(s, @"set_bp", @{@"systolic": @120, @"diastolic": @80}, NULL);
    CHECK(!Cmd(s, @"set_alarm_enabled", @{@"param": @"xx", @"enabled": @NO}, &err), "parametro sconosciuto rifiutato");

    // NIBP automatica ogni 5 minuti
    CHECK(!Cmd(s, @"set_nibp_interval", @7, &err), "intervallo non previsto rifiutato");
    CHECK(Cmd(s, @"set_nibp_interval", @5, &err) && [[s stateDictionary][@"nibp_next_in_s"] intValue] == 300, "NIBP auto: prossima tra 300 s");
    gNow += 299; [s tickAtTime:gNow];
    CHECK([s snapshot].nibpStatus != SLNibpMeasuring, "non ancora partita a 299 s");
    gNow += 2; [s tickAtTime:gNow];
    CHECK([s snapshot].nibpStatus == SLNibpMeasuring, "misura automatica partita allo scadere");
    gNow += 60; [s tickAtTime:gNow];
    CHECK([s snapshot].nibpStatus == SLNibpComplete && [[s stateDictionary][@"nibp_next_in_s"] intValue] > 200, "misura completata, ciclo successivo programmato");
    Cmd(s, @"set_nibp_interval", @0, NULL);
    CHECK([[s stateDictionary][@"nibp_next_in_s"] isKindOfClass:[NSNull class]], "NIBP auto spenta");

    // Silenziamento con scadenza
    Cmd(s, @"mute_alarms", @YES, NULL);
    CHECK([s snapshot].alarmsMuted && [s snapshot].alarmsMutedRemaining == 20, "allarmi silenziati per 20 s");
    gNow += 12; [s tickAtTime:gNow];
    CHECK([s snapshot].alarmsMuted && [s snapshot].alarmsMutedRemaining == 8, "countdown: 8 s rimanenti");
    gNow += 9; [s tickAtTime:gNow];
    CHECK(![s snapshot].alarmsMuted, "dopo 20 s gli allarmi si riattivano da soli");

    // Limiti di allarme
    CHECK(Cmd(s, @"set_alarm_limits", @{@"hr_high": @100, @"spo2_low": @94}, &err) &&
          [[s snapshot] limit:@"hr_high"] == 100 && [[s snapshot] limit:@"hr_low"] == 50, "limiti parziali applicati");
    CHECK(!Cmd(s, @"set_alarm_limits", @{@"hr_low": @110}, &err) && [err containsString:@"lower"], "limite min >= max rifiutato");
    CHECK(!Cmd(s, @"set_alarm_limits", @{@"foo": @1}, &err), "limite sconosciuto rifiutato");
    CHECK(!Cmd(s, @"set_alarm_limits", @{@"spo2_low": @20}, &err), "limite fuori range rifiutato");
    Reset(s);
    CHECK([[s snapshot].rhythm isEqualToString:@"sinus"] && [s snapshot].heartRate == 82, "reset_scenario");
    CHECK([[s snapshot] limit:@"hr_high"] == 100, "i limiti NON si azzerano con il reset dello scenario");
    Cmd(s, @"reset_alarm_limits", nil, NULL);
    CHECK([[s snapshot] limit:@"hr_high"] == 120, "reset_alarm_limits");
}


static void testTransitions(void) {
    SimulationState *s = NewState(); NSString *err = nil;
    // Rampa lineare FC 82 -> 142 in 60 s
    CHECK(Cmd(s, @"transition", @{@"params": @{@"heart_rate_bpm": @142}, @"duration_s": @60}, &err), "transizione accettata");
    gNow += 30; [s tickAtTime:gNow];
    NSInteger hr = [s snapshot].heartRate;
    CHECK(hr >= 110 && hr <= 114, "a metà rampa FC ~112 (%ld)", (long)hr);
    CHECK([[s stateDictionary][@"transitions"][@"heart_rate_bpm"][@"remaining_s"] intValue] == 30, "tempo residuo esposto");
    gNow += 31; [s tickAtTime:gNow];
    CHECK([s snapshot].heartRate == 142 && [[s stateDictionary][@"transitions"] count] == 0, "rampa completata");
    // Comando manuale annulla la rampa di quel parametro
    Cmd(s, @"transition", @{@"params": @{@"spo2_percent": @80}, @"duration_s": @100}, NULL);
    gNow += 10; [s tickAtTime:gNow];
    Cmd(s, @"set_spo2", @95, NULL); gNow += 50; [s tickAtTime:gNow];
    CHECK([s snapshot].spo2 == 95, "set manuale interrompe la rampa");
    // Interruzione di un solo parametro: resta al valore raggiunto, l'altro continua
    Cmd(s, @"transition", @{@"params": @{@"heart_rate_bpm": @100, @"respiratory_rate_rpm": @26}, @"duration_s": @20}, NULL);
    gNow += 10; [s tickAtTime:gNow];
    NSInteger hrMid = [s snapshot].heartRate;
    CHECK(Cmd(s, @"cancel_transitions", @[@"heart_rate_bpm"], &err), "interruzione singolo parametro");
    gNow += 15; [s tickAtTime:gNow];
    CHECK([s snapshot].heartRate == hrMid && [s snapshot].respRate == 26, "FC ferma a %ld, FR completata a 26", (long)hrMid);
    CHECK(!Cmd(s, @"cancel_transitions", @"x", &err), "cancel_transitions con valore non valido rifiutato");
    CHECK(!Cmd(s, @"transition", @{@"params": @{@"pippo": @1}, @"duration_s": @10}, &err), "parametro sconosciuto rifiutato");
    CHECK(!Cmd(s, @"transition", @{@"params": @{@"diastolic_mmhg": @150}, @"duration_s": @10}, &err), "diastolica >= sistolica rifiutata");
    CHECK(!Cmd(s, @"transition", @{@"duration_s": @10}, &err), "transizione vuota rifiutata");
    // Sinusale -> tachicardia sinusale in 10 s: ritmo subito, FC in rampa verso 130 (non a scatto)
    SimulationState *t = NewState();
    Cmd(t, @"set_heart_rate", @80, NULL);
    Cmd(t, @"transition", @{@"params": @{@"spo2_percent": @97}, @"duration_s": @10, @"rhythm": @"sinus_tachycardia"}, NULL);
    CHECK([[t snapshot].rhythm isEqualToString:@"sinus_tachycardia"] && [t snapshot].heartRate == 80, "ritmo cambiato subito, FC ancora 80 (%ld)", (long)[t snapshot].heartRate);
    gNow += 5; [t tickAtTime:gNow];
    NSInteger hrT = [t snapshot].heartRate;
    CHECK(hrT >= 100 && hrT <= 110, "a metà la FC sale gradualmente (~105: %ld)", (long)hrT);
    gNow += 6; [t tickAtTime:gNow];
    CHECK([t snapshot].heartRate == 130, "a fine rampa FC 130 (%ld)", (long)[t snapshot].heartRate);
    // FV resta istantanea
    Cmd(t, @"transition", @{@"params": @{@"spo2_percent": @90}, @"duration_s": @10, @"rhythm": @"vf"}, NULL);
    CHECK([[t snapshot].rhythm isEqualToString:@"vf"], "FV immediata anche in una transizione");

    // FC 0 = asistolia (diretta o al termine di una rampa)
    Reset(s);
    Cmd(s, @"set_heart_rate", @0, NULL);
    CHECK([[s snapshot].rhythm isEqualToString:@"asystole"], "FC 0 -> asistolia");
    Reset(s);
    Cmd(s, @"transition", @{@"params": @{@"heart_rate_bpm": @0}, @"duration_s": @10}, NULL);
    gNow += 11; [s tickAtTime:gNow];
    CHECK([[s snapshot].rhythm isEqualToString:@"asystole"], "rampa FC fino a 0 -> asistolia");

    // Fisiologia automatica: arresto -> SpO2/FR/EtCO2 a 0; ROSC -> recupero
    Reset(s); Sensor(s, @"etco2", YES);
    Cmd(s, @"set_rhythm", @"vf", NULL);
    gNow += 60; [s tickAtTime:gNow];
    SLSnapshot *sn = [s snapshot];
    CHECK(sn.spo2 == 0 && sn.respRate == 0 && sn.etco2 == 0, "arresto: SpO2 %ld FR %ld EtCO2 %ld a 0", (long)sn.spo2, (long)sn.respRate, (long)sn.etco2);
    gNow += 1; [s tickAtTime:gNow];
    CHECK([s snapshot].systolic <= 50, "arresto: la PA del paziente crolla (%ld)", (long)[s snapshot].systolic);
    Cmd(s, @"set_rhythm", @"sinus", NULL);
    gNow += 2; [s tickAtTime:gNow];
    CHECK([s snapshot].systolic <= 62 && [s snapshot].pulsePresent, "ROSC: la PA riparte bassa (%ld)", (long)[s snapshot].systolic);
    gNow += 58; [s tickAtTime:gNow];
    sn = [s snapshot];
    CHECK(sn.spo2 == 98 && sn.respRate == 16 && sn.etco2 == 35, "ROSC: ritorno ai valori pre-arresto");
    CHECK(sn.systolic > 60 && sn.systolic < 110, "ROSC: dopo 60 s la PA sta ancora risalendo (%ld)", (long)sn.systolic);
    gNow += 70; [s tickAtTime:gNow];
    CHECK([s snapshot].systolic == 120 && [s snapshot].diastolic == 80, "ROSC: PA tornata a 120/80 dopo ~2 minuti");
    Cmd(s, @"set_auto_physiology", @NO, NULL);
    Cmd(s, @"set_rhythm", @"asystole", NULL); gNow += 60; [s tickAtTime:gNow];
    CHECK([s snapshot].spo2 == 98, "fisiologia automatica disattivabile");

    // ROSC: picco di EtCO2 nei primi secondi
    Cmd(s, @"set_auto_physiology", @YES, NULL);
    Reset(s); Sensor(s, @"etco2", YES);
    Cmd(s, @"set_rhythm", @"vf", NULL); gNow += 60; [s tickAtTime:gNow];
    Cmd(s, @"set_rhythm", @"sinus", NULL); gNow += 6; [s tickAtTime:gNow];
    CHECK([s snapshot].etco2 >= 45, "ROSC: picco di EtCO2 (%ld)", (long)[s snapshot].etco2);
    gNow += 50; [s tickAtTime:gNow];
    CHECK([s snapshot].etco2 == 35, "ROSC: EtCO2 tornata a 35");

    // RCP in arresto: EtCO2 10-20, ventilazioni; stop -> crollo
    Reset(s); Sensor(s, @"etco2", YES);
    Cmd(s, @"set_rhythm", @"vf", NULL); gNow += 60; [s tickAtTime:gNow];
    CHECK(Cmd(s, @"set_cpr", @YES, &err) && [s snapshot].cprActive, "RCP avviata");
    gNow += 15; [s tickAtTime:gNow];
    CHECK([s snapshot].etco2 == 15 && [s snapshot].respRateSet == 10, "RCP: EtCO2 15, FR impostata 10");
    // ventilazione manuale: senza insufflazioni niente CO2 a monitor; ogni "ventilate" = un'onda e il valore
    CHECK([s snapshot].ventilationManual && [s snapshot].respRate == 0 && [[s stateDictionary][@"etco2_displayed"] isKindOfClass:[NSNull class]], "RCP: senza ventilazioni l'EtCO2 non compare");
    CHECK(Cmd(s, @"ventilate", nil, &err) && Cmd(s, @"ventilate", nil, &err), "RCP: ventilazione segnalata");
    CHECK([s snapshot].breathTimes.count == 1, "RCP: due tocchi ravvicinati = una insufflazione");
    gNow += 1.5; Cmd(s, @"ventilate", nil, NULL);
    CHECK([s snapshot].respRate == 2 && [[s stateDictionary][@"etco2_displayed"] integerValue] == 15, "RCP: 2 insufflazioni, EtCO2 15 a monitor");
    { WaveformEngine *we = [[WaveformEngine alloc] initWithSeed:1]; [we updateWithSnapshot:[s snapshot]];
      double b0 = [[s snapshot].breathTimes.lastObject doubleValue];
      CHECK([we capnoAt:b0 + 0.5] == 0 && [we capnoAt:b0 + 2.0] > 10 && [we capnoAt:b0 + 3.5] == 0, "RCP: capnogramma solo dopo l'insufflazione"); }
    gNow += 31; CHECK([s snapshot].respRate == 0, "RCP: 30 s senza ventilare, EtCO2 sparisce");
    Cmd(s, @"set_rhythm", @"sinus", NULL);
    CHECK(![s snapshot].cprActive, "al ROSC la RCP si ferma");

    // TV con polso: polso presente, allarme alto, sigla TV
    Reset(s); Cmd(s, @"set_rhythm", @"vt_pulse", NULL);
    CHECK([s snapshot].pulsePresent && [s snapshot].heartRate >= 120, "TV con polso: polso presente, FC >= 120");
    CHECK([AlarmManager evaluate:[s snapshot]].level == SLAlarmHigh, "TV con polso: allarme alto");

    // Apnea con polso: desaturazione progressiva, poi recupero
    Reset(s);
    Cmd(s, @"set_resp_rate", @0, NULL);
    for (int i = 0; i < 60; i++) { gNow += 1; [s tickAtTime:gNow]; }
    CHECK([s snapshot].spo2 < 90, "apnea 60 s: SpO2 in calo (%ld)", (long)[s snapshot].spo2);
    Cmd(s, @"set_resp_rate", @16, NULL);
    for (int i = 0; i < 45; i++) { gNow += 1; [s tickAtTime:gNow]; }
    CHECK([s snapshot].spo2 == 98, "ripresa del respiro: SpO2 risale a 98");

    // FR -> EtCO2: iperventilazione abbassa l'EtCO2
    Reset(s);
    Cmd(s, @"set_resp_rate", @32, NULL); gNow += 50; [s tickAtTime:gNow];
    CHECK([s snapshot].etco2 >= 16 && [s snapshot].etco2 <= 19, "FR 16->32: EtCO2 35 -> ~18 (%ld)", (long)[s snapshot].etco2);

    // FA rapida: deficit di polso
    Reset(s); Cmd(s, @"set_rhythm", @"afib", NULL); Cmd(s, @"set_heart_rate", @150, NULL);
    CHECK([s snapshot].pulseRate < 150 && [s snapshot].pulseRate > 120, "FA 150: PR %ld < FC", (long)[s snapshot].pulseRate);

    // Catena: attesa 10 s -> FC 120 in 20 s -> attesa 5 s -> FV immediata
    Reset(s); Cmd(s, @"set_auto_physiology", @YES, NULL);
    NSArray *steps = @[ @{@"wait_s": @10, @"duration_s": @20, @"params": @{@"heart_rate_bpm": @122}, @"label": @"tachicardia"},
                        @{@"wait_s": @5, @"duration_s": @0, @"rhythm": @"vf", @"label": @"arresto"} ];
    CHECK(Cmd(s, @"run_chain", @{@"name": @"Test", @"steps": steps}, &err), "catena avviata");
    gNow += 5; [s tickAtTime:gNow];
    CHECK([s snapshot].heartRate == 82 && [[s stateDictionary][@"chain"][@"phase"] isEqualToString:@"waiting"], "passo 1 in attesa");
    gNow += 15; [s tickAtTime:gNow];
    hr = [s snapshot].heartRate;
    CHECK(hr > 95 && hr < 110, "passo 1 in rampa (FC %ld)", (long)hr);
    gNow += 16; [s tickAtTime:gNow];
    CHECK([s snapshot].heartRate == 122 && [[s snapshot].rhythm isEqualToString:@"vf"], "passo 2: FV dopo l'attesa");
    CHECK(![[s stateDictionary][@"chain"][@"active"] boolValue], "catena terminata");
    CHECK(!Cmd(s, @"run_chain", @{@"steps": @[@{@"wait_s": @5, @"params": @{@"spo2_percent": @200}}]}, &err) && [err containsString:@"step 1"],
          "passo non valido rifiutato con indicazione del passo");
    Cmd(s, @"run_chain", @{@"steps": steps}, NULL); Cmd(s, @"stop_chain", nil, NULL);
    gNow += 100; [s tickAtTime:gNow];
    CHECK(![[s stateDictionary][@"chain"][@"active"] boolValue], "stop_chain");
}

static int CountBeats(WaveformEngine *e, double t0, double secs, double thr) {
    int n = 0; BOOL above = NO;
    for (double t = t0; t < t0 + secs; t += 0.002) {
        double v = [e ecgAt:t lead:SLLeadII];
        if (!above && v > thr) { n++; above = YES; } else if (above && v < thr * 0.5) above = NO;
    }
    return n;
}

static void testWaveforms(void) {
    SimulationState *s = NewState();
    Sensor(s, @"art", YES); Sensor(s, @"etco2", YES);
    WaveformEngine *e = [[WaveformEngine alloc] initWithSeed:42];
    [e updateWithSnapshot:[s snapshot]];
    int beats = CountBeats(e, 0, 30, 0.6);
    CHECK(beats >= 38 && beats <= 44, "sinusale 82 bpm: %d battiti in 30 s", beats);

    double maxP = 0; for (double t = 30; t < 33; t += 0.01) maxP = MAX(maxP, [e plethAt:t]);
    CHECK(maxP > 0.5, "pletismografia presente (max %.2f)", maxP);
    double amx = 0, amn = 999; for (double t = 33; t < 38; t += 0.005) { double a = [e artAt:t]; amx = MAX(amx, a); amn = MIN(amn, a); }
    CHECK(fabs(amx - 120) < 12 && fabs(amn - 80) < 8, "ART sinusale: max %.0f min %.0f (atteso ~120/80)", amx, amn);

    // Derivazione V diversa da II
    double diff = 0; for (double t = 40; t < 42; t += 0.004) diff += fabs([e ecgAt:t lead:SLLeadII] - [e ecgAt:t lead:SLLeadV]);
    CHECK(diff > 20, "II e V hanno morfologie diverse (diff %.1f)", diff);

    // Elettrodi staccati: ECG piatto
    Sensor(s, @"ecg", NO); [e updateWithSnapshot:[s snapshot]];
    double mxe = 0; for (double t = 43; t < 45; t += 0.004) mxe = MAX(mxe, fabs([e ecgAt:t lead:SLLeadV]));
    CHECK(mxe == 0, "elettrodi staccati: ECG piatto");
    Sensor(s, @"ecg", YES);

    Cmd(s, @"set_rhythm", @"vf", NULL); [e updateWithSnapshot:[s snapshot]];
    double mn = 9, mx = -9; for (double t = 50; t < 55; t += 0.004) { double v = [e ecgAt:t lead:SLLeadII]; mn = MIN(mn, v); mx = MAX(mx, v); }
    CHECK(mx - mn > 0.4, "VF: attività caotica ampia (%.2f mV)", mx - mn);
    double maxPv = 0; for (double t = 58; t < 62; t += 0.01) maxPv = MAX(maxPv, [e plethAt:t]);
    CHECK(maxPv < 0.01, "VF: pletismografia piatta");
    double av = 0; for (double t = 62; t < 64; t += 0.01) av = MAX(av, [e artAt:t]);
    CHECK(av < 25, "VF: ART senza onde pulsatili (max %.1f)", av);

    Cmd(s, @"set_rhythm", @"asystole", NULL); [e updateWithSnapshot:[s snapshot]];
    double amp = 0; for (double t = 70; t < 75; t += 0.004) amp = MAX(amp, fabs([e ecgAt:t lead:SLLeadII]));
    CHECK(amp > 0.1 && amp < 0.35, "asistolia: linea ondulata non piatta, senza QRS (max %.3f mV)", amp);

    Cmd(s, @"set_rhythm", @"vt", NULL); [e updateWithSnapshot:[s snapshot]];
    int vtBeats = CountBeats(e, 80, 10, 0.6);
    CHECK(vtBeats >= 25 && vtBeats <= 35, "TV 180 bpm: %d battiti in 10 s", vtBeats);
    double above = 0; for (double t = 90; t < 100; t += 0.001) if ([e ecgAt:t lead:SLLeadII] > 0.6) above += 0.001;
    Cmd(s, @"set_rhythm", @"sinus", NULL); [e updateWithSnapshot:[s snapshot]];
    double aboveS = 0; for (double t = 110; t < 120; t += 0.001) if ([e ecgAt:t lead:SLLeadII] > 0.6) aboveS += 0.001;
    CHECK(above / MAX(vtBeats, 1) > 2.5 * aboveS / 13.0, "QRS TV più largo del sinusale");

    Cmd(s, @"set_rhythm", @"afib", NULL); Cmd(s, @"set_heart_rate", @100, NULL); [e updateWithSnapshot:[s snapshot]];
    NSMutableArray *rr = [NSMutableArray array]; double last = -1; BOOL up = NO;
    for (double t = 130; t < 160; t += 0.002) {
        double v = [e ecgAt:t lead:SLLeadII];
        if (!up && v > 0.6) { if (last > 0) [rr addObject:@(t - last)]; last = t; up = YES; } else if (up && v < 0.3) up = NO;
    }
    double mean = [[rr valueForKeyPath:@"@avg.self"] doubleValue], var = 0;
    for (NSNumber *x in rr) var += pow(x.doubleValue - mean, 2);
    CHECK(sqrt(var / MAX(rr.count, 1)) / mean > 0.12, "FA: RR irregolare");

    Cmd(s, @"set_rhythm", @"pea", NULL); [e updateWithSnapshot:[s snapshot]];
    int peaBeats = CountBeats(e, 170, 10, 0.6);
    double maxPP = 0; for (double t = 175; t < 180; t += 0.01) maxPP = MAX(maxPP, [e plethAt:t]);
    CHECK(peaBeats > 5 && maxPP < 0.01, "PEA: %d QRS, pleth assente", peaBeats);

    Cmd(s, @"set_rhythm", @"sinus", NULL); Cmd(s, @"set_etco2", @40, NULL); [e updateWithSnapshot:[s snapshot]];
    double cmax = 0, cmin = 99; for (double t = 200; t < 215; t += 0.01) { double v = [e capnoAt:t]; cmax = MAX(cmax, v); cmin = MIN(cmin, v); }
    CHECK(fabs(cmax - 40) < 1.5 && cmin < 1, "capnogramma: max %.1f, min %.1f", cmax, cmin);
    Sensor(s, @"etco2", NO); [e updateWithSnapshot:[s snapshot]];
    CHECK([e capnoAt:220] == 0, "sensore CO2 staccato: capnogramma piatto");
    Sensor(s, @"etco2", YES); Cmd(s, @"set_rhythm", @"sinus", NULL);
    Cmd(s, @"set_bp", @{@"systolic": @120, @"diastolic": @80}, NULL);   // annulla le rampe post-ROSC dei passi precedenti
    // Frequenze alte: ART e pleth restano nel range impostato (niente accumulo dei battiti)
    for (NSNumber *f in @[@150, @200, @250]) {
        Cmd(s, @"set_heart_rate", f, NULL); [e updateWithSnapshot:[s snapshot]];
        double ax = 0, an = 999, px = 0, pn = 9;
        double t0 = 1000 + 10 * f.doubleValue;
        for (double t = t0; t < t0 + 6; t += 0.002) { double a = [e artAt:t], p = [e plethAt:t]; ax = MAX(ax, a); an = MIN(an, a); px = MAX(px, p); pn = MIN(pn, p); }
        CHECK(ax <= 121 && an >= 79 && ax > 110, "FC %d: ART %.0f/%.0f entro 120/80", f.intValue, ax, an);
        CHECK(px <= 0.85 && pn < 0.1, "FC %d: pleth %.2f..%.2f non sale verso l'alto", f.intValue, pn, px);
    }

}

static void testAlarms(void) {
    SimulationState *s = NewState();
    CHECK([AlarmManager evaluate:[s snapshot]].level == SLAlarmNone, "nessun allarme a riposo");
    Cmd(s, @"set_spo2", @88, NULL);
    SLAlarmResult *r = [AlarmManager evaluate:[s snapshot]];
    CHECK(r.level == SLAlarmMedium && [r.violated containsObject:@"spo2"], "SpO2 88 < 90 -> allarme medio");
    Cmd(s, @"set_alarm_limits", @{@"spo2_low": @85}, NULL);
    CHECK([AlarmManager evaluate:[s snapshot]].level == SLAlarmNone, "abbassando il limite l'allarme rientra");
    Cmd(s, @"set_rhythm", @"vf", NULL);
    r = [AlarmManager evaluate:[s snapshot]];
    CHECK(r.level == SLAlarmHigh && [r.messages.firstObject containsString:@"FIBRILLAZIONE"], "VF -> allarme alto");
    Sensor(s, @"ecg", NO);
    r = [AlarmManager evaluate:[s snapshot]];
    CHECK(![r.messages.firstObject containsString:@"FIBRILLAZIONE"] && [[r.messages componentsJoinedByString:@","] containsString:@"ELETTRODI"],
          "elettrodi staccati: il monitor non vede la VF, solo allarme tecnico");
    Reset(s); Sensor(s, @"spo2", NO);
    CHECK([AlarmManager evaluate:[s snapshot]].level == SLAlarmTechnical, "sonda staccata -> allarme tecnico");
    Reset(s); Cmd(s, @"set_alarm_limits", @{@"hr_high": @80}, NULL);
    r = [AlarmManager evaluate:[s snapshot]];
    CHECK(r.level == SLAlarmMedium && [r.violated containsObject:@"hr"], "FC 82 > limite 80 -> allarme medio");
    CHECK([r.messages.firstObject isEqualToString:@"FC > 80"], "il banner indica solo il limite superato (%s)", [r.messages.firstObject UTF8String]);
    CHECK([r.severity[@"hr"] integerValue] == SLAlarmMedium, "FC appena sopra il limite: riquadro GIALLO");
    Cmd(s, @"set_heart_rate", @140, NULL);
    CHECK([[AlarmManager evaluate:[s snapshot]].severity[@"hr"] integerValue] == SLAlarmHigh, "FC molto sopra il limite: riquadro ROSSO");
    Cmd(s, @"set_spo2", @75, NULL);   // limite SpO2 attuale 85 (impostato sopra): 75 < 85-5 -> critico
    r = [AlarmManager evaluate:[s snapshot]];
    CHECK([r.severity[@"spo2"] integerValue] == SLAlarmHigh && [r.severity[@"hr"] integerValue] == SLAlarmHigh, "più valori in allarme insieme");
    Reset(s); Cmd(s, @"reset_alarm_limits", nil, NULL); Sensor(s, @"etco2", YES); Cmd(s, @"set_resp_rate", @0, NULL);
    CHECK([AlarmManager evaluate:[s snapshot]].level == SLAlarmHigh, "apnea (con CO2) -> allarme alto");
    Sensor(s, @"etco2", NO);
    CHECK([[[AlarmManager evaluate:[s snapshot]].messages componentsJoinedByString:@","] containsString:@"APNEA"], "apnea rilevata anche dall'impedenza ECG senza CO2");
}

static SLHTTPRequest *Req(NSString *m, NSString *p, NSString *token, NSString *body) {
    SLHTTPRequest *r = [SLHTTPRequest new];
    r.method = m; r.path = p; r.remoteAddress = @"192.168.4.9";
    NSMutableDictionary *h = [NSMutableDictionary dictionary];
    if (token) h[@"x-simulafranz-token"] = token;
    if (body) { h[@"content-type"] = @"application/json"; r.body = [body dataUsingEncoding:NSUTF8StringEncoding]; }
    r.headers = h;
    return r;
}
static NSDictionary *J(SLHTTPResponse *r) { return [NSJSONSerialization JSONObjectWithData:r.body options:0 error:NULL]; }

static void testAPI(void) {
    SimulationState *s = NewState();
    APIController *api = [[APIController alloc] initWithState:s pinProvider:^NSString *{ return @"482913"; }
                                                  staticFiles:@{@"index.html": [@"<html>" dataUsingEncoding:NSUTF8StringEncoding]}];
    api.clock = ^NSTimeInterval { return gNow; };
    SLHTTPResponse *r = [api handle:Req(@"GET", @"/api/v1/health", nil, nil)];
    CHECK(r.status == 200 && [J(r)[@"ok"] boolValue] && !J(r)[@"pin"], "health senza auth e senza segreti");
    CHECK([api handle:Req(@"GET", @"/", nil, nil)].status == 200, "controller statico servito");
    CHECK([api handle:Req(@"GET", @"/../etc/passwd", nil, nil)].status == 404, "path non in whitelist -> 404");
    CHECK([api handle:Req(@"GET", @"/api/v1/state", nil, nil)].status == 401, "state senza token -> 401");
    r = [api handle:Req(@"GET", @"/api/v1/state", @"482913", nil)];
    CHECK(r.status == 200 && [J(r)[@"state"][@"heart_rate_bpm"] intValue] == 82 && J(r)[@"state"][@"sensors"] && J(r)[@"state"][@"alarm_limits"],
          "state con token, sensori e limiti");
    r = [api handle:Req(@"POST", @"/api/v1/command", @"482913", @"{\"device_id\":\"monitor-01\",\"command\":\"set_heart_rate\",\"value\":120}")];
    CHECK(r.status == 200 && [J(r)[@"state"][@"heart_rate_bpm"] intValue] == 120 && J(r)[@"revision"], "comando FC 80->120");
    r = [api handle:Req(@"POST", @"/api/v1/command", @"482913", @"{\"command\":\"set_sensor\",\"value\":{\"sensor\":\"art\",\"connected\":true}}")];
    CHECK(r.status == 200 && [J(r)[@"state"][@"sensors"][@"art"] boolValue], "set_sensor via API");
    r = [api handle:Req(@"POST", @"/api/v1/command", @"482913", @"{not json")];
    CHECK(r.status == 400 && ![J(r)[@"ok"] boolValue], "JSON malformato -> 400");
    r = [api handle:Req(@"POST", @"/api/v1/command", @"482913", @"{\"command\":\"set_spo2\",\"value\":140}")];
    CHECK(r.status == 400 && [J(r)[@"error"] containsString:@"range"], "valore fuori range -> 400 leggibile");
    CHECK([api handle:Req(@"GET", @"/api/v1/command", @"482913", nil)].status == 405, "metodo errato -> 405");
    CHECK([api handle:Req(@"POST", @"/api/v1/nibp/start", @"482913", @"{}")].status == 200, "nibp/start");
    CHECK([api handle:Req(@"POST", @"/api/v1/nibp/start", @"482913", @"{}")].status == 409, "nibp già in corso -> 409");
    for (int i = 0; i < 5; i++) [api handle:Req(@"GET", @"/api/v1/state", @"000000", nil)];
    CHECK([api handle:Req(@"GET", @"/api/v1/state", @"482913", nil)].status == 429, "blocco dopo 5 tentativi errati");
    gNow += 31;
    CHECK([api handle:Req(@"GET", @"/api/v1/state", @"482913", nil)].status == 200, "sblocco dopo 30 s");
}

// richiesta di un controller con identità (header X-SimulaFranz-Client*) da un certo indirizzo
static SLHTTPRequest *CReq(NSString *m, NSString *p, NSString *body, NSString *cid, NSString *name, NSString *remote) {
    SLHTTPRequest *r = Req(m, p, @"482913", body);
    NSMutableDictionary *h = [r.headers mutableCopy];
    if (cid) h[@"x-simulafranz-client"] = cid;
    if (name) h[@"x-simulafranz-client-name"] = name;
    r.headers = h; if (remote) r.remoteAddress = remote;
    return r;
}

static void testControl(void) {
    SimulationState *s = NewState();
    APIController *api = [[APIController alloc] initWithState:s pinProvider:^NSString *{ return @"482913"; } staticFiles:@{}];
    api.clock = ^NSTimeInterval { return gNow; };
    __block int changes = 0; api.control.onChange = ^{ changes++; };
    NSString *hr = @"{\"command\":\"set_heart_rate\",\"value\":90}";
    SLHTTPResponse *r = [api handle:Req(@"GET", @"/api/v1/health", nil, nil)];
    CHECK(![J(r)[@"controller_active"] boolValue] && [J(r)[@"transports"] containsObject:@"direct"], "controllo: all'inizio nessun controller");
    CHECK([api.control owner] == nil, "controllo: owner nil");
    // A (web) apre la pagina: legge e basta, non prende il comando
    r = [api handle:CReq(@"GET", @"/api/v1/state", nil, @"web-A", @"Web%20%C2%B7%20Mac", nil)];
    CHECK(r.status == 200 && ![J(r)[@"controller"][@"active"] boolValue] && changes == 0, "controllo: leggere non prende il comando");
    // il primo comando prende il comando
    CHECK([api handle:CReq(@"POST", @"/api/v1/command", hr, @"web-A", @"Web%20%C2%B7%20Mac", nil)].status == 200, "controllo: il primo comando passa");
    r = [api handle:CReq(@"GET", @"/api/v1/state", nil, @"web-A", nil, nil)];
    CHECK([J(r)[@"controller"][@"mine"] boolValue] && [J(r)[@"controller"][@"name"] isEqualToString:@"Web · Mac"]
          && [J(r)[@"controller"][@"transport"] isEqualToString:@"wifi"] && [J(r)[@"controller"][@"kind"] isEqualToString:@"web"]
          && [J(r)[@"controller"][@"protected"] boolValue], "controllo: chi comanda è il controller attivo (nome decodificato, canale wifi, protetto)");
    CHECK(changes == 1 && [api.control.lastEvent containsString:@"Comanda «Web · Mac»"], "controllo: notifica e testo per il registro");
    // B (iPad in collegamento diretto) legge ma non comanda finché A è attivo
    r = [api handle:CReq(@"GET", @"/api/v1/state", nil, @"ipad-B", @"iPad di Franz", @"peer:iPad di Franz")];
    CHECK(r.status == 200 && ![J(r)[@"controller"][@"mine"] boolValue] && [J(r)[@"controller"][@"active"] boolValue]
          && [J(r)[@"controller"][@"name"] isEqualToString:@"Web · Mac"], "controllo: il secondo legge lo stato e vede chi comanda");
    for (int i = 0; i < 6; i++) { gNow += 5; [api handle:CReq(@"GET", @"/api/v1/state", nil, @"web-A", nil, nil)]; }   // A legge di continuo (come le app)
    r = [api handle:CReq(@"POST", @"/api/v1/command", @"{\"command\":\"set_heart_rate\",\"value\":50}", @"ipad-B", nil, @"peer:iPad di Franz")];
    CHECK(r.status == 423 && [J(r)[@"error"] isEqualToString:@"controller_busy"] && [J(r)[@"message"] containsString:@"Web · Mac"]
          && [s snapshot].heartRate == 90, "controllo: chi ha comandato da 30 s è protetto (423), stato invariato");
    CHECK([api handle:CReq(@"POST", @"/api/v1/nibp/start", @"{}", @"ipad-B", nil, @"peer:x")].status == 423, "controllo: anche nibp/start rifiutato");
    // A resta collegato (legge) ma non comanda da più di un minuto: il primo comando di B passa da solo
    for (int i = 0; i < 7; i++) { gNow += 5; [api handle:CReq(@"GET", @"/api/v1/state", nil, @"web-A", nil, nil)]; }
    r = [api handle:CReq(@"GET", @"/api/v1/state", nil, @"ipad-B", nil, @"peer:iPad di Franz")];
    CHECK(![J(r)[@"controller"][@"protected"] boolValue] && [J(r)[@"controller"][@"action_idle_s"] integerValue] >= 60, "controllo: chi è fermo da un minuto non è più protetto");
    r = [api handle:CReq(@"POST", @"/api/v1/command", @"{\"command\":\"set_heart_rate\",\"value\":50}", @"ipad-B", @"iPad di Franz", @"peer:iPad di Franz")];
    CHECK(r.status == 200 && [s snapshot].heartRate == 50 && [api.control.lastEvent containsString:@"era fermo"], "controllo: il comando passa da solo da chi è fermo (e il registro lo dice)");
    r = [api handle:CReq(@"GET", @"/api/v1/state", nil, @"web-A", nil, nil)];
    CHECK(![J(r)[@"controller"][@"mine"] boolValue] && [J(r)[@"controller"][@"lost_to"] isEqualToString:@"iPad di Franz"], "controllo: chi perde il comando sa a chi è passato");
    // A riprende il controllo in modo esplicito
    r = [api handle:CReq(@"POST", @"/api/v1/control", @"{\"action\":\"take\"}", @"web-A", @"Web%20%C2%B7%20Mac", nil)];
    CHECK(r.status == 200 && [J(r)[@"controller"][@"mine"] boolValue] && !J(r)[@"controller"][@"lost_to"]
          && [api.control.lastEvent containsString:@"ha preso il controllo"], "controllo: «Prendi il controllo» funziona sempre");
    // B prende il controllo (canale diretto)
    r = [api handle:CReq(@"POST", @"/api/v1/control", @"{\"action\":\"take\"}", @"ipad-B", @"iPad di Franz", @"peer:iPad di Franz")];
    CHECK(r.status == 200 && [J(r)[@"controller"][@"mine"] boolValue] && [J(r)[@"controller"][@"transport"] isEqualToString:@"direct"]
          && [J(r)[@"controller"][@"kind"] isEqualToString:@"ipad"], "controllo: presa di controllo (canale diretto)");
    CHECK([api handle:CReq(@"POST", @"/api/v1/command", hr, @"web-A", nil, nil)].status == 423, "controllo: il precedente non comanda più");
    r = [api handle:CReq(@"GET", @"/api/v1/control", nil, @"web-A", nil, nil)];
    CHECK(r.status == 200 && ![J(r)[@"controller"][@"mine"] boolValue] && [J(r)[@"controller"][@"name"] isEqualToString:@"iPad di Franz"], "controllo: GET control dice chi comanda");
    CHECK([api handle:CReq(@"POST", @"/api/v1/control", @"{\"action\":\"boh\"}", @"web-A", nil, nil)].status == 400, "controllo: azione sconosciuta -> 400");
    CHECK([api handle:Req(@"GET", @"/api/v1/control", nil, nil)].status == 401, "controllo: senza PIN -> 401");
    // rilascio di chi non comanda: nessun effetto; rilascio del controller attivo: posto libero
    [api handle:CReq(@"POST", @"/api/v1/control", @"{\"action\":\"release\"}", @"web-A", nil, nil)];
    CHECK([api.control owner] != nil, "controllo: il rilascio di chi non comanda non cambia nulla");
    r = [api handle:CReq(@"POST", @"/api/v1/control", @"{\"action\":\"release\"}", @"ipad-B", nil, @"peer:iPad di Franz")];
    CHECK(r.status == 200 && ![J(r)[@"controller"][@"active"] boolValue] && [api.control owner] == nil, "controllo: rilascio");
    // chi comanda sparisce (app chiusa, fuori portata): dopo 10 s senza farsi sentire il posto torna libero
    [api handle:CReq(@"POST", @"/api/v1/command", hr, @"web-A", nil, nil)];
    gNow += 6; CHECK([api handle:CReq(@"POST", @"/api/v1/command", hr, @"ipad-B", nil, nil)].status == 423, "controllo: 6 s di silenzio non bastano");
    gNow += 6; CHECK([api handle:CReq(@"POST", @"/api/v1/command", hr, @"ipad-B", nil, nil)].status == 200, "controllo: dopo 12 s il posto è libero e lo prende chi comanda");
    [api handle:CReq(@"POST", @"/api/v1/control", @"{\"action\":\"release\"}", @"ipad-B", nil, nil)];
    // il saturimetro (seguace) non occupa il posto e non viene bloccato
    SLHTTPRequest *ox = Req(@"GET", @"/api/v1/state", @"482913", nil);
    NSMutableDictionary *h = [ox.headers mutableCopy]; h[@"x-simulafranz-device"] = @"oximeter"; ox.headers = h;
    r = [api handle:ox];
    CHECK(r.status == 200 && [api.control owner] == nil && ![J(r)[@"controller"][@"active"] boolValue], "controllo: il saturimetro non diventa controller");
    [api handle:CReq(@"GET", @"/api/v1/state", nil, @"web-A", nil, nil)];
    ox = Req(@"POST", @"/api/v1/command", @"482913", @"{\"command\":\"set_oximeter\",\"value\":{\"power\":true}}");
    h = [ox.headers mutableCopy]; h[@"x-simulafranz-device"] = @"oximeter"; ox.headers = h;
    CHECK([api handle:ox].status != 423, "controllo: i comandi del saturimetro non sono bloccati dal controller attivo");
    // vecchi client senza identità: vale l'indirizzo
    [api handle:CReq(@"POST", @"/api/v1/control", @"{\"action\":\"release\"}", @"web-A", nil, nil)];
    CHECK([api handle:Req(@"POST", @"/api/v1/command", @"482913", hr)].status == 200, "controllo: client senza identità accettato (indirizzo)");
    SLHTTPRequest *other = Req(@"POST", @"/api/v1/command", @"482913", hr); other.remoteAddress = @"192.168.4.77";
    CHECK([api handle:other].status == 423, "controllo: altro indirizzo senza identità rifiutato");
    // identità "sporca": caratteri non ammessi tolti, lunghezza limitata
    [api.control releaseClient:nil];
    [api handle:CReq(@"POST", @"/api/v1/command", hr, @"a b<c>\"", @"%0Anome%7F", nil)];
    r = [api handle:CReq(@"GET", @"/api/v1/state", nil, @"a b<c>\"", @"%0Anome%7F", nil)];
    CHECK([J(r)[@"controller"][@"mine"] boolValue] && [J(r)[@"controller"][@"name"] isEqualToString:@"nome"], "controllo: identità ripulita");
}

static NSDictionary *SCJ(NSString *json) { return [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL]; }
static void Tick(SimulationState *s, double sec) { for (double x = 0; x < sec; x += 0.5) { gNow += 0.5; [s tickAtTime:gNow]; } }

static BOOL LogHas(SFSessionLog *l, NSString *needle) { for (NSDictionary *d in [l entriesSince:0]) if ([d[@"text"] containsString:needle]) return YES; return NO; }

static void testSessionLog(void) {
    SimulationState *s = NewStateRaw();
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"sf-test-registro.json"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    SFSessionLog *lg = [[SFSessionLog alloc] initWithPath:path state:s];
    [lg observe];
    CHECK([lg entriesSince:0].count == 0, "registro: vuoto all'inizio");
    // partecipanti: accendono, applicano le sonde, misurano la pressione
    s.devicePowered = YES; Sensor(s, @"ecg", YES); Sensor(s, @"nibp", YES); [lg observe];
    CHECK(LogHas(lg, @"Monitor acceso") && LogHas(lg, @"Elettrodi ECG: applicata") && LogHas(lg, @"Bracciale NIBP: applicata"), "registro: accensione e sonde");
    [s startNibpMeasurementError:NULL]; [lg observe]; gNow += 60; [s tickAtTime:gNow]; [lg observe];
    CHECK(LogHas(lg, @"Misura NIBP avviata") && LogHas(lg, @"NIBP misurata: "), "registro: misura NIBP con il valore");
    // istruttore: comandi tradotti in voci leggibili, con il nome del controller
    [lg noteCommand:SCJ(@"{\"command\":\"transition\",\"value\":{\"params\":{\"heart_rate_bpm\":130,\"spo2_percent\":88},\"duration_s\":30}}") by:@"similFranz Controller 1"];
    NSDictionary *last = [lg entriesSince:0].lastObject;
    CHECK([last[@"text"] isEqualToString:@"Parametri: FC 130, SpO₂ 88 (in 30 s)"] && [last[@"by"] isEqualToString:@"similFranz Controller 1"] && [last[@"k"] isEqualToString:@"patient"], "registro: comando dell'istruttore (%s)", [last[@"text"] UTF8String]);
    [lg noteCommand:SCJ(@"{\"command\":\"set_sensor\",\"value\":{\"sensor\":\"ecg\",\"connected\":true}}") by:@"x"];
    CHECK([[lg entriesSince:0].lastObject[@"text"] hasPrefix:@"Parametri"], "registro: i comandi già registrati dall'osservazione non si duplicano");
    // arresto, osservazioni dell'istruttore, RCP, scarica, ROSC -> riepilogo con i tempi dall'arresto
    gNow += 100; Cmd(s, @"set_rhythm", @"vf", NULL); [lg observe];
    CHECK(LogHas(lg, @"Ritmo: fibrillazione ventricolare") && LogHas(lg, @"arresto cardiaco"), "registro: arresto");
    NSInteger t0 = (NSInteger)[s snapshot].scenarioTime;
    gNow += 12; [lg add:@"action" text:@"Riconosciuto l'arresto" tag:@"ac" by:@"istr"];
    gNow += 8; Cmd(s, @"set_cpr", @YES, NULL); [lg observe];
    gNow += 5; [lg add:@"drug" text:@"Adrenalina 1 mg" tag:nil by:@"istr"];
    Cmd(s, @"defib_mode", @"manual", NULL); Sensor(s, @"pads", YES); Cmd(s, @"defib_energy", @200, NULL); [lg observe];
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 6); [lg observe];
    Cmd(s, @"defib_shock", nil, NULL); [lg observe];
    NSDictionary *sm = [lg summary];
    CHECK([sm[@"arrest_at_s"] integerValue] == t0 && [sm[@"to_recognition_s"] integerValue] == 12 && [sm[@"to_cpr_s"] integerValue] == 20, "registro: tempi dall'arresto (riconoscimento %s, RCP %s)", [[sm[@"to_recognition_s"] description] UTF8String], [[sm[@"to_cpr_s"] description] UTF8String]);
    CHECK([sm[@"shocks"] count] == 1 && [sm[@"shocks"][0][@"energy_j"] integerValue] == 200 && [sm[@"to_first_shock_s"] integerValue] >= 30, "registro: scarica con energia e tempo (%s)", [[sm[@"shocks"] description] UTF8String]);
    CHECK([sm[@"drugs"] count] == 1 && [sm[@"drugs"][0][@"text"] isEqualToString:@"Adrenalina 1 mg"], "registro: farmaci nel riepilogo");
    CHECK(LogHas(lg, @"manuale") && LogHas(lg, @"Piastre applicate"), "registro: eventi del defibrillatore fatti dai partecipanti");
    NSInteger shockEntries = 0; for (NSDictionary *d in [lg entriesSince:0]) if ([d[@"tag"] isEqual:@"shock"]) shockEntries++;
    CHECK(shockEntries == 1, "registro: una sola voce per la scarica (%ld)", (long)shockEntries);
    Cmd(s, @"set_simulation_running", @NO, NULL); [lg observe]; Cmd(s, @"set_simulation_running", @YES, NULL); [lg observe];
    [lg noteCommand:@{@"command": @"reset_clock"} by:@"istr"];
    CHECK(LogHas(lg, @"Scenario in pausa") && LogHas(lg, @"Scenario ripreso") && LogHas(lg, @"Timer di scenario azzerato"), "registro: azioni sul timer");
    [lg add:@"plus" text:@"Ottima comunicazione a circuito chiuso" tag:nil by:@"istr"]; [lg add:@"minus" text:@"Ritardo nel cambio alle compressioni" tag:nil by:@"istr"];
    CHECK([[lg summary][@"plus"] intValue] == 1 && [[lg summary][@"minus"] intValue] == 1, "registro: punti di forza e da discutere");
    CHECK([lg add:@"boh" text:@"x" tag:nil by:nil] && [[lg entriesSince:0].lastObject[@"k"] isEqualToString:@"note"] && ![lg add:@"note" text:@"   " tag:nil by:nil], "registro: categoria sconosciuta = nota, testo vuoto rifiutato");
    CHECK([[lg plainText] containsString:@"FARMACO"] && [[lg plainText] containsString:@"Adrenalina 1 mg"], "registro: esportazione in testo");
    NSInteger n = [lg nextIndex];
    CHECK([lg entriesSince:n - 2].count == 2, "registro: lettura incrementale");
    // persistenza
    [lg observe]; [lg flush]; gNow += 10;
    SFSessionLog *lg2 = [[SFSessionLog alloc] initWithPath:path state:s];
    CHECK([lg2 entriesSince:0].count >= (NSUInteger)n - 1 || [lg2 entriesSince:0].count > 10, "registro: riletto dal file dopo il riavvio (%lu voci)", (unsigned long)[lg2 entriesSince:0].count);
    // API
    APIController *api = [[APIController alloc] initWithState:s pinProvider:^NSString *{ return @"482913"; } staticFiles:@{}];
    api.clock = ^NSTimeInterval { return gNow; }; api.sessionLog = lg;
    [api handle:CReq(@"POST", @"/api/v1/control", @"{\"action\":\"take\"}", @"web-A", @"Web%20A", nil)];     // A comanda
    SLHTTPResponse *r = [api handle:CReq(@"GET", @"/api/v1/log", nil, @"web-A", @"Web%20A", nil)];
    CHECK(r.status == 200 && [J(r)[@"log"] count] > 10 && J(r)[@"summary"][@"shocks"] && [J(r)[@"next"] integerValue] == [lg nextIndex], "registro API: lettura con riepilogo");
    SLHTTPRequest *q = CReq(@"GET", @"/api/v1/log", nil, @"web-A", nil, nil); q.query = [NSString stringWithFormat:@"since=%ld", (long)[lg nextIndex] - 1];
    CHECK([J([api handle:q])[@"log"] count] == 1, "registro API: since");
    q = CReq(@"GET", @"/api/v1/log", nil, @"web-A", nil, nil); q.query = @"format=text";
    CHECK([[[NSString alloc] initWithData:[api handle:q].body encoding:NSUTF8StringEncoding] containsString:@"registro della sessione"], "registro API: testo");
    // un secondo istruttore (che non comanda) può annotare ma non svuotare
    r = [api handle:CReq(@"POST", @"/api/v1/log", @"{\"action\":\"add\",\"kind\":\"note\",\"text\":\"Nota del secondo istruttore\"}", @"web-B", @"Secondo", nil)];
    CHECK(r.status == 200 && [[lg entriesSince:0].lastObject[@"by"] isEqualToString:@"Secondo"], "registro API: annota anche chi non comanda");
    CHECK([api handle:CReq(@"POST", @"/api/v1/log", @"{\"action\":\"clear\"}", @"web-B", nil, nil)].status == 423, "registro API: svuota solo chi comanda");
    CHECK([api handle:CReq(@"POST", @"/api/v1/log", @"{\"action\":\"add\",\"text\":\"\"}", @"web-A", nil, nil)].status == 400, "registro API: testo obbligatorio");
    [api handle:CReq(@"POST", @"/api/v1/command", @"{\"command\":\"set_spo2\",\"value\":91}", @"web-A", @"Web%20A", nil)];
    CHECK([[lg entriesSince:0].lastObject[@"text"] isEqualToString:@"Parametri: SpO₂ 91"], "registro API: i comandi finiscono nel registro");
    // sessioni: l'azzeramento dello scenario e l'avvio di uno scenario aprono una sessione nuova
    NSInteger s1 = [lg currentSession]; NSUInteger n1 = [lg entriesSince:0 session:s1].count;
    [api handle:CReq(@"POST", @"/api/v1/command", @"{\"command\":\"reset_scenario\"}", @"web-A", nil, nil)];
    CHECK([lg currentSession] == s1 + 1 && [lg entriesSince:0 session:s1].count == n1, "sessioni: l'azzeramento apre una sessione nuova, la precedente resta intatta");
    [lg observe]; [lg observe];
    CHECK([lg entriesSince:0 session:s1 + 1].count == 0, "sessioni: l'azzeramento non lascia voci false (ritmo/ROSC) nella sessione nuova (%lu)", (unsigned long)[lg entriesSince:0 session:s1 + 1].count);
    [api handle:CReq(@"POST", @"/api/v1/log", @"{\"action\":\"new_session\",\"title\":\"Prova a mano\"}", @"web-A", nil, nil)];
    CHECK([lg currentSession] == s1 + 1 && [[lg sessions].lastObject[@"title"] isEqualToString:@"Prova a mano"], "sessioni: una sessione ancora vuota viene riusata (cambia solo il titolo)");
    [lg add:@"note" text:@"prima nota della sessione nuova" tag:nil by:nil];
    r = [api handle:CReq(@"GET", @"/api/v1/log", nil, @"web-A", nil, nil)];
    CHECK([J(r)[@"log"] count] == 1 && [J(r)[@"session"] integerValue] == s1 + 1 && [J(r)[@"sessions"] count] == 2 && [J(r)[@"summary"][@"shocks"] count] == 0, "sessioni API: per default la sessione corrente, con il suo riepilogo");
    q = CReq(@"GET", @"/api/v1/log", nil, @"web-A", nil, nil); q.query = [NSString stringWithFormat:@"session=%ld", (long)s1];
    CHECK([J([api handle:q])[@"log"] count] == n1 && [J([api handle:q])[@"summary"][@"shocks"] count] == 1, "sessioni API: una sessione precedente con il suo riepilogo");
    api.scenarios = [[SFScenarioStore alloc] initWithPath:nil state:s];
    [api handle:CReq(@"POST", @"/api/v1/scenarios", @"{\"action\":\"start\",\"id\":\"es-arresto-fv\"}", @"web-A", nil, nil)];
    CHECK([lg currentSession] == s1 + 2 && [[lg sessions].lastObject[@"title"] containsString:@"Dolore toracico"] && [lg entriesSince:0 session:s1 + 2].count >= 1, "sessioni: ogni scenario avviato è una sessione con il suo nome");
    CHECK([J([api handle:CReq(@"GET", @"/api/v1/state", nil, @"web-A", nil, nil)])[@"log_session"] integerValue] == s1 + 2, "sessioni API: log_session nello stato");
    r = [api handle:CReq(@"POST", @"/api/v1/log", @"{\"action\":\"clear\"}", @"web-A", nil, nil)];
    CHECK(r.status == 200 && [J(r)[@"log"] count] == 0 && [J(r)[@"sessions"] count] == 1, "registro API: svuotato, resta una sessione nuova e vuota");
    CHECK([J([api handle:CReq(@"GET", @"/api/v1/state", nil, @"web-A", nil, nil)])[@"log_next"] integerValue] == [lg nextIndex], "registro API: log_next nello stato");
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

static void testScenarios(void) {
    SimulationState *s = NewState();
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"sf-test-scenari.json"];
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    SFScenarioStore *st = [[SFScenarioStore alloc] initWithPath:path state:s];
    CHECK(st.scenarios.count == 3 && ![[st runInfo][@"active"] boolValue], "scenari: tre esempi all'inizio, nessuno in corso");
    NSString *err = nil;
    NSDictionary *(^SC)(NSString *) = ^NSDictionary *(NSString *json) { return [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL]; };
    CHECK(![st save:SC(@"{\"name\":\"\",\"phases\":[{\"rhythm\":\"sinus\"}]}") error:&err] && err, "scenari: nome obbligatorio");
    CHECK(![st save:SC(@"{\"name\":\"x\",\"phases\":[]}") error:&err], "scenari: almeno una fase");
    CHECK(![st save:SC(@"{\"name\":\"x\",\"phases\":[{\"name\":\"vuota\"}]}") error:&err] && [err containsString:@"empty"], "scenari: fase vuota rifiutata");
    CHECK(![st save:SC(@"{\"name\":\"x\",\"phases\":[{\"params\":{\"spo2_percent\":140}}]}") error:&err] && [err containsString:@"phase 1"], "scenari: valore fuori range con numero di fase");
    CHECK(![st save:SC(@"{\"name\":\"x\",\"phases\":[{\"rhythm\":\"boh\"}]}") error:&err], "scenari: ritmo sconosciuto rifiutato");
    CHECK(![st save:SC(@"{\"name\":\"x\",\"phases\":[{\"params\":{\"systolic_mmhg\":80,\"diastolic_mmhg\":90}}]}") error:&err], "scenari: diastolica >= sistolica rifiutata");
    NSDictionary *sc = [st save:SC(@"{\"name\":\"  Prova  \",\"notes\":\"note\",\"phases\":["
        "{\"name\":\"A\",\"rhythm\":\"sinus\",\"duration_s\":0,\"params\":{\"heart_rate_bpm\":100,\"spo2_percent\":95},\"temperature_c\":38.44,\"crt_s\":3},"
        "{\"rhythm\":\"vf\"},"
        "{\"name\":\"C\",\"note\":\"dopo la scarica\",\"rhythm\":\"sinus\",\"duration_s\":20,\"params\":{\"heart_rate_bpm\":60}}]}") error:&err];
    CHECK(sc && [sc[@"name"] isEqualToString:@"Prova"] && [sc[@"id"] length] && [sc[@"phases"][1][@"name"] isEqualToString:@"Fase 2"]
          && fabs([sc[@"phases"][0][@"temperature_c"] doubleValue] - 38.4) < 1e-6, "scenari: salvataggio normalizzato (%s)", err.UTF8String);
    CHECK(st.scenarios.count == 4, "scenari: aggiunto all'elenco");
    NSString *sid = sc[@"id"];
    CHECK(![st next:&err], "scenari: fase successiva senza scenario in corso -> errore");
    CHECK(![st start:@"non-esiste" phase:0 error:&err], "scenari: avvio di uno scenario inesistente");
    CHECK([st start:sid phase:0 error:&err] && [s snapshot].heartRate == 100 && [s snapshot].spo2 == 95 && [s snapshot].temperatureTenths == 384,
          "scenari: avvio = fase 1 applicata subito");
    CHECK([[s stateDictionary][@"scenario_time_s"] intValue] == 0, "scenari: l'avvio azzera l'orologio di scenario");
    NSDictionary *r = [st runInfo];
    CHECK([r[@"active"] boolValue] && [r[@"phase"] intValue] == 0 && [r[@"phases"] intValue] == 3 && [r[@"phase_name"] isEqualToString:@"A"] && [r[@"next_name"] isEqualToString:@"Fase 2"], "scenari: stato della conduzione");
    gNow += 40; CHECK([[s stateDictionary][@"scenario_time_s"] intValue] == 40, "orologio: 40 s dopo l'avvio");
    Cmd(s, @"reset_clock", nil, NULL);
    CHECK([[s stateDictionary][@"scenario_time_s"] intValue] == 0 && [s snapshot].heartRate == 100, "orologio: azzerato a mano, i parametri restano");
    gNow += 5; CHECK([[s stateDictionary][@"scenario_time_s"] intValue] == 5, "orologio: riparte da zero");
    gNow -= 45;
    // la fase NON avanza da sola; l'istruttore può ritoccare a mano
    gNow += 300; [s tickAtTime:gNow];
    CHECK([[st runInfo][@"phase"] intValue] == 0 && [[st runInfo][@"phase_time_s"] intValue] >= 300, "scenari: dopo 5 minuti è ancora nella fase 1 (decide l'istruttore)");
    Cmd(s, @"set_heart_rate", @140, NULL);
    CHECK([s snapshot].heartRate == 140 && [[st runInfo][@"phase"] intValue] == 0, "scenari: modifica a mano durante la fase");
    CHECK([st next:&err] && [[s snapshot].rhythm isEqualToString:@"vf"] && [[st runInfo][@"phase"] intValue] == 1 && [[st runInfo][@"phase_time_s"] intValue] == 0, "scenari: fase successiva (FV)");
    CHECK([st next:&err] && [[s snapshot].rhythm isEqualToString:@"sinus"] && [st runInfo][@"next_name"] == nil, "scenari: ultima fase");
    Tick(s, 25);
    CHECK([s snapshot].heartRate == 60, "scenari: la fase con transizione arriva al valore nel tempo scelto (FC %ld)", (long)[s snapshot].heartRate);
    CHECK(![st next:&err] && [err containsString:@"last"], "scenari: oltre l'ultima fase -> errore");
    CHECK([st gotoPhase:0 error:&err] && [s snapshot].heartRate == 100, "scenari: salto a una fase qualsiasi");
    CHECK(![st gotoPhase:9 error:&err], "scenari: fase inesistente");
    // sinusale -> tachicardia con FC di arrivo e durata: la FC parte da dov'è (niente salto al valore tipico del nuovo ritmo)
    Cmd(s, @"set_rhythm", @"sinus", NULL); Cmd(s, @"set_heart_rate", @96, NULL);
    Cmd(s, @"transition", SC(@"{\"rhythm\":\"sinus_tachycardia\",\"duration_s\":60,\"params\":{\"heart_rate_bpm\":122}}"), NULL);
    CHECK([s snapshot].heartRate == 96, "scenari: cambio di ritmo con FC di arrivo, la rampa parte dalla FC attuale (FC %ld)", (long)[s snapshot].heartRate);
    Tick(s, 30); CHECK([s snapshot].heartRate > 100 && [s snapshot].heartRate < 118, "scenari: a metà rampa FC intermedia (%ld)", (long)[s snapshot].heartRate);
    Tick(s, 35); CHECK([s snapshot].heartRate == 122, "scenari: fine rampa FC 122");
    // persistenza
    SFScenarioStore *st2 = [[SFScenarioStore alloc] initWithPath:path state:s];
    CHECK(st2.scenarios.count == 4 && [st2.scenarios[3][@"name"] isEqualToString:@"Prova"], "scenari: riletti dal file");
    // modifica per id, eliminazione dello scenario in corso
    NSMutableDictionary *mod = [sc mutableCopy]; mod[@"name"] = @"Prova 2";
    CHECK([st save:mod error:&err] && st.scenarios.count == 4 && [st.scenarios[3][@"name"] isEqualToString:@"Prova 2"], "scenari: modifica per id");
    CHECK([st deleteId:sid error:&err] && st.scenarios.count == 3 && ![[st runInfo][@"active"] boolValue], "scenari: eliminare lo scenario in corso lo chiude");
    CHECK(![st deleteId:sid error:&err], "scenari: eliminazione di uno inesistente");
    // API
    APIController *api = [[APIController alloc] initWithState:s pinProvider:^NSString *{ return @"482913"; } staticFiles:@{}];
    api.clock = ^NSTimeInterval { return gNow; };
    api.scenarios = st;
    SLHTTPResponse *resp = [api handle:CReq(@"GET", @"/api/v1/scenarios", nil, @"web-A", nil, nil)];
    CHECK(resp.status == 200 && [J(resp)[@"scenarios"] count] == 3 && ![J(resp)[@"scenario"][@"active"] boolValue], "scenari API: elenco");
    CHECK([api handle:Req(@"GET", @"/api/v1/scenarios", nil, nil)].status == 401, "scenari API: serve il PIN");
    resp = [api handle:CReq(@"POST", @"/api/v1/scenarios", @"{\"action\":\"start\",\"id\":\"es-arresto-fv\"}", @"web-A", nil, nil)];
    CHECK(resp.status == 200 && [J(resp)[@"scenario"][@"phase"] intValue] == 0 && [J(resp)[@"state"][@"heart_rate_bpm"] intValue] == 96, "scenari API: avvio");
    resp = [api handle:CReq(@"GET", @"/api/v1/state", nil, @"web-A", nil, nil)];
    CHECK([J(resp)[@"scenario"][@"active"] boolValue] && [J(resp)[@"scenario"][@"phases"] intValue] == 4, "scenari API: la conduzione è nello stato");
    CHECK([api handle:CReq(@"POST", @"/api/v1/scenarios", @"{\"action\":\"next\"}", @"altro", nil, nil)].status == 423, "scenari API: chi non comanda non avanza le fasi");
    resp = [api handle:CReq(@"POST", @"/api/v1/scenarios", @"{\"action\":\"goto\",\"phase\":2}", @"web-A", nil, nil)];
    CHECK(resp.status == 200 && [J(resp)[@"state"][@"rhythm"] isEqualToString:@"vf"], "scenari API: salto alla fase 3 (FV)");
    resp = [api handle:CReq(@"POST", @"/api/v1/scenarios", @"{\"action\":\"save\",\"scenario\":{\"name\":\"Da API\",\"phases\":[{\"rhythm\":\"afib\",\"params\":{\"heart_rate_bpm\":140}}]}}", @"web-A", nil, nil)];
    CHECK(resp.status == 200 && [J(resp)[@"scenarios"] count] == 4 && [J(resp)[@"saved"][@"id"] length], "scenari API: salvataggio");
    resp = [api handle:CReq(@"POST", @"/api/v1/scenarios", @"{\"action\":\"save\",\"scenario\":{\"name\":\"\",\"phases\":[]}}", @"web-A", nil, nil)];
    CHECK(resp.status == 400 && [J(resp)[@"error"] length], "scenari API: errore leggibile");
    CHECK([api handle:CReq(@"POST", @"/api/v1/scenarios", @"{\"action\":\"boh\"}", @"web-A", nil, nil)].status == 400, "scenari API: azione sconosciuta");
    [api handle:CReq(@"POST", @"/api/v1/command", @"{\"command\":\"reset_scenario\"}", @"web-A", nil, nil)];
    CHECK(![[st runInfo][@"active"] boolValue], "scenari API: il reset chiude lo scenario a fasi");
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}


static void testDefib(void) {
    SimulationState *s = NewState();
    NSString *err = nil;
    SLDefibInfo *d = [s snapshot].defib;
    CHECK(d.mode == SLDefibOff && !d.padsConnected && d.energy == 150 && d.shockCount == 0, "defib: stato iniziale spento");
    CHECK(!Cmd(s, @"defib_mode", @"boh", &err), "defib_mode non valido rifiutato");

    CHECK([[s stateDictionary][@"defib"][@"config"][@"outcome_mode"] isEqualToString:@"instructor"], "esito predefinito: decide l'istruttore dopo ogni scarica");
    Cmd(s, @"set_defib_config", @{@"outcome_mode": @"instructor"}, NULL);
    CHECK(!Cmd(s, @"set_defib_config", @{@"outcome_mode": @"boh"}, &err), "outcome_mode non valido rifiutato");
    // decide l'istruttore: lo shock non cambia il ritmo finché non sceglie
    Cmd(s, @"defib_mode", @"manual", NULL); Sensor(s, @"pads", YES); Cmd(s, @"set_rhythm", @"vf", NULL);
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 5); Cmd(s, @"defib_shock", nil, NULL);
    NSDictionary *dd = [s stateDictionary][@"defib"];
    CHECK([[s snapshot].rhythm isEqualToString:@"vf"] && [dd[@"outcome_pending"] boolValue] && [dd[@"outcome_from"] isEqualToString:@"vf"],
          "istruttore: dopo lo shock resta FV in attesa della decisione");
    CHECK(!Cmd(s, @"defib_outcome", @"boh", &err), "defib_outcome non valido rifiutato");
    CHECK(Cmd(s, @"defib_outcome", @"stay", &err) && [[s snapshot].rhythm isEqualToString:@"vf"] &&
          ![[s stateDictionary][@"defib"][@"outcome_pending"] boolValue], "istruttore: resta nel ritmo pre-shock");
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 5); Cmd(s, @"defib_shock", nil, NULL);
    CHECK(Cmd(s, @"defib_outcome", @"sinus", &err) && [[s snapshot].rhythm isEqualToString:@"sinus"] && [s snapshot].pulsePresent,
          "istruttore: torna in sinusale (ROSC)");
    // anche la scarica SINCRONIZZATA chiede l'esito, e lo stato dice che era sincronizzata e con quanti joule
    Cmd(s, @"set_rhythm", @"afib", NULL); Cmd(s, @"defib_energy", @100, NULL); Cmd(s, @"defib_sync", @YES, NULL);
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 5); Cmd(s, @"defib_shock", nil, NULL); [s defibRWaveAt:gNow + 0.2];
    dd = [s stateDictionary][@"defib"];
    CHECK([dd[@"outcome_pending"] boolValue] && [dd[@"outcome_sync"] boolValue] && [dd[@"outcome_energy_j"] integerValue] == 100 &&
          [dd[@"outcome_from"] isEqualToString:@"afib"] && [[s snapshot].rhythm isEqualToString:@"afib"],
          "istruttore: cardioversione sincronizzata in attesa della decisione (FA, 100 J, SYNC)");
    CHECK(Cmd(s, @"defib_outcome", @"sinus", &err) && [[s snapshot].rhythm isEqualToString:@"sinus"], "istruttore: cardioversione → sinusale");
    Cmd(s, @"defib_sync", @NO, NULL);
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 5);
    Cmd(s, @"defib_charge", nil, NULL);
    CHECK([s snapshot].defib.charge == SLChargeReady, "CARICA da già carico: non ricomincia la carica");
    Cmd(s, @"defib_disarm", nil, NULL);
    Sensor(s, @"pads", NO); Sensor(s, @"ecg", YES);
    Cmd(s, @"defib_sync", @YES, NULL);
    CHECK(!Cmd(s, @"defib_charge", nil, &err), "solo elettrodi ECG: il defibrillatore non ha le piastre");
    Cmd(s, @"defib_sync", @NO, NULL);
    Cmd(s, @"defib_mode", @"off", NULL);
    Reset(s);
    Cmd(s, @"set_defib_config", @{@"outcome_mode": @"auto"}, NULL);     // i test seguenti verificano le regole automatiche

    // --- MANUALE ---
    Cmd(s, @"defib_mode", @"manual", NULL);
    CHECK(!Cmd(s, @"defib_charge", nil, &err) && [[s snapshot].defib.message containsString:@"PIASTRE"], "carica senza piastre rifiutata");
    Sensor(s, @"pads", YES);
    CHECK(!Cmd(s, @"defib_energy", @"12", &err) && !Cmd(s, @"defib_energy", @11, &err), "energia non selezionabile rifiutata");
    CHECK(Cmd(s, @"defib_energy", @200, &err) && [s snapshot].defib.energy == 200, "energia 200 J");
    CHECK(!Cmd(s, @"defib_shock", nil, &err), "shock senza carica rifiutato");
    Cmd(s, @"defib_charge", nil, NULL);
    CHECK([s snapshot].defib.charge == SLChargeCharging, "carica in corso");
    Tick(s, 6);
    CHECK([s snapshot].defib.charge == SLChargeReady && [s snapshot].defib.chargedEnergy == 200, "carica completa ~5 s");
    Cmd(s, @"defib_energy", @150, NULL);
    CHECK([s snapshot].defib.charge == SLChargeNone, "cambio energia da carico: carica annullata");
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 5); Tick(s, 61);
    CHECK([s snapshot].defib.charge == SLChargeNone, "scarica interna dopo 60 s");

    // FV: shock asincrono 150 J -> conversione al ritmo configurato (sinusale) e ROSC
    Cmd(s, @"set_rhythm", @"vf", NULL);
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 5);
    CHECK(Cmd(s, @"defib_shock", nil, &err), "shock erogato");
    SLSnapshot *sn = [s snapshot];
    CHECK(sn.defib.shockCount == 1 && sn.defib.lastShockEnergy == 150 && [sn.rhythm isEqualToString:@"sinus"] && sn.pulsePresent,
          "FV + 150 J -> sinusale");
    // energia sotto la soglia: nessuna conversione
    Cmd(s, @"set_rhythm", @"vf", NULL); Cmd(s, @"defib_energy", @50, NULL);
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 3); Cmd(s, @"defib_shock", nil, NULL);
    CHECK([[s snapshot].rhythm isEqualToString:@"vf"], "FV + 50 J (sotto soglia 120): resta FV");
    // servono 2 shock efficaci
    Cmd(s, @"set_defib_config", @{@"shocks_to_convert": @2, @"post_shock_rhythm": @"pea"}, NULL);
    Cmd(s, @"defib_energy", @200, NULL);
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 6); Cmd(s, @"defib_shock", nil, NULL);
    CHECK([[s snapshot].rhythm isEqualToString:@"vf"], "1° shock efficace su 2: resta FV");
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 6); Cmd(s, @"defib_shock", nil, NULL);
    CHECK([[s snapshot].rhythm isEqualToString:@"pea"], "2° shock: ritmo post-shock configurato (PEA)");
    CHECK(!Cmd(s, @"set_defib_config", @{@"post_shock_rhythm": @"torsade"}, &err) && !Cmd(s, @"set_defib_config", @{@"boh": @1}, &err),
          "config non valida rifiutata");
    Cmd(s, @"set_defib_config", @{@"shocks_to_convert": @1, @"post_shock_rhythm": @"sinus"}, NULL);

    // R su T: shock NON sincronizzato su FA -> FV
    Cmd(s, @"set_rhythm", @"afib", NULL);
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 6); Cmd(s, @"defib_shock", nil, NULL);
    CHECK([[s snapshot].rhythm isEqualToString:@"vf"], "FA + shock asincrono -> FV (R su T)");

    // Cardioversione sincronizzata: lo shock attende l'onda R
    Cmd(s, @"set_rhythm", @"afib", NULL);
    CHECK(Cmd(s, @"defib_sync", @YES, &err) && [s snapshot].defib.sync, "SYNC attivo");
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 6);
    Cmd(s, @"defib_shock", nil, NULL);
    sn = [s snapshot];
    CHECK(sn.defib.syncPending && sn.defib.shockCount == 5 && [sn.rhythm isEqualToString:@"afib"], "SYNC: shock in attesa dell'onda R");
    [s defibRWaveAt:gNow - 1];
    CHECK([s snapshot].defib.syncPending, "onda R precedente alla pressione ignorata");
    [s defibRWaveAt:gNow + 0.2];
    sn = [s snapshot];
    CHECK(!sn.defib.syncPending && sn.defib.shockCount == 6 && sn.defib.lastShockSynced && [sn.rhythm isEqualToString:@"sinus"],
          "SYNC: erogato sull'onda R, FA -> sinusale");
    CHECK(!sn.defib.sync, "dopo lo shock il SYNC si disattiva (predefinito)");
    Cmd(s, @"set_defib_config", @{@"sync_stays_on": @YES}, NULL);
    Cmd(s, @"set_rhythm", @"vt_pulse", NULL); Cmd(s, @"defib_sync", @YES, NULL);
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 6); Cmd(s, @"defib_shock", nil, NULL); [s defibRWaveAt:gNow + 0.1];
    sn = [s snapshot];
    CHECK([sn.rhythm isEqualToString:@"sinus"] && sn.defib.sync, "TV con polso: cardioversione e SYNC che resta attivo");
    Cmd(s, @"defib_sync", @NO, NULL);
    // piastre staccate da carico: disarmo
    Cmd(s, @"defib_charge", nil, NULL); Tick(s, 6);
    Sensor(s, @"pads", NO);
    CHECK([s snapshot].defib.charge == SLChargeNone, "piastre staccate: carica annullata");

    // --- DAE ---
    Reset(s);
    Cmd(s, @"set_rhythm", @"vf", NULL);
    Cmd(s, @"defib_mode", @"aed", NULL);
    d = [s snapshot].defib;
    CHECK(d.aedPhase == SLAedPads && [d.voicePrompt containsString:@"piastre"], "DAE: chiede le piastre");
    NSUInteger seq = d.promptSeq;
    CHECK(!Cmd(s, @"defib_energy", @200, &err), "DAE: energia non modificabile");
    Sensor(s, @"pads", YES);
    d = [s snapshot].defib;
    CHECK(d.aedPhase == SLAedAnalyzing && d.promptSeq > seq, "DAE: piastre -> analisi con voce");
    Cmd(s, @"set_cpr", @YES, NULL); Tick(s, 10);
    CHECK([s snapshot].defib.aedPhase == SLAedAnalyzing && [[s snapshot].defib.message containsString:@"MOVIMENTO"], "DAE: RCP durante l'analisi = movimento");
    Cmd(s, @"set_cpr", @NO, NULL); Tick(s, 8.5);
    d = [s snapshot].defib;
    CHECK(d.aedShockAdvised && (d.aedPhase == SLAedCharging || d.aedPhase == SLAedReady), "DAE: FV -> shock consigliato");
    Tick(s, 5);
    CHECK([s snapshot].defib.aedPhase == SLAedReady && [s snapshot].defib.charge == SLChargeReady, "DAE: carico, premere shock");
    Cmd(s, @"defib_shock", nil, NULL);
    sn = [s snapshot];
    CHECK(sn.defib.aedPhase == SLAedCPR && sn.defib.shockCount == 1 && sn.defib.lastShockEnergy == 150 && [sn.rhythm isEqualToString:@"sinus"],
          "DAE: shock 150 J, conversione, RCP");
    Cmd(s, @"set_rhythm", @"asystole", NULL);
    Tick(s, 121);
    CHECK([s snapshot].defib.aedPhase == SLAedAnalyzing, "DAE: dopo 2 min di RCP nuova analisi");
    Tick(s, 9);
    d = [s snapshot].defib;
    CHECK(!d.aedShockAdvised && d.aedPhase == SLAedCPR, "DAE: asistolia -> shock non consigliato");
    Cmd(s, @"defib_analyze", nil, NULL);
    CHECK([s snapshot].defib.aedPhase == SLAedAnalyzing, "DAE: ANALIZZA manuale");
    Cmd(s, @"set_rhythm", @"vf", NULL); Tick(s, 9); Tick(s, 5); Tick(s, 61);
    CHECK([s snapshot].defib.aedPhase == SLAedCPR && [s snapshot].defib.shockCount == 1, "DAE: shock non premuto -> scarica interna e RCP");
    Cmd(s, @"set_rhythm", @"vt_pulse", NULL); Cmd(s, @"set_heart_rate", @180, NULL); Cmd(s, @"defib_analyze", nil, NULL); Tick(s, 9);
    CHECK([s snapshot].defib.aedShockAdvised, "DAE: TV rapida (>=150) consigliata anche con polso");

    // --- PACER ---
    Reset(s);
    Cmd(s, @"set_rhythm", @"sinus_bradycardia", NULL);       // FC 45
    Cmd(s, @"defib_mode", @"pacer", NULL);
    CHECK(!Cmd(s, @"defib_pacer", @{@"running": @YES}, &err), "pacing senza piastre rifiutato");
    Sensor(s, @"pads", YES);
    CHECK(!Cmd(s, @"defib_pacer", @{@"rate": @250}, &err), "frequenza fuori range rifiutata");
    Cmd(s, @"defib_pacer", @{@"rate": @70, @"output_ma": @40, @"running": @YES}, NULL);
    d = [s snapshot].defib;
    CHECK(d.paceRunning && d.paceActive && !d.paceCapture && [s snapshot].displayedHeartRate == 45, "40 mA sotto soglia (70): spike senza cattura");
    Cmd(s, @"defib_pacer", @{@"output_ma": @80}, NULL);
    sn = [s snapshot];
    CHECK(sn.defib.paceCapture && sn.defib.paceMechanical && sn.displayedHeartRate == 70 && sn.pulseRate == 70, "80 mA: cattura elettrica e meccanica a 70");
    Cmd(s, @"defib_pacer", @{@"rate": @40}, NULL);
    CHECK(![s snapshot].defib.paceActive, "demand: inibito con ritmo proprio (45) >= frequenza (40)");
    Cmd(s, @"defib_pacer", @{@"demand": @NO}, NULL);
    d = [s snapshot].defib;
    CHECK(d.paceActive && !d.paceCapture, "fisso: spike anche con ritmo proprio, ma senza cattura");
    Cmd(s, @"defib_pacer", @{@"rate": @70, @"demand": @YES}, NULL);
    Cmd(s, @"set_rhythm", @"asystole", NULL);
    sn = [s snapshot];
    CHECK(sn.defib.paceCapture && sn.defib.paceMechanical && sn.pulsePresent, "asistolia: cattura meccanica (predefinita) genera polso");
    Cmd(s, @"set_defib_config", @{@"mechanical_capture": @NO}, NULL);
    sn = [s snapshot];
    CHECK(sn.defib.paceCapture && !sn.defib.paceMechanical && !sn.pulsePresent, "istruttore: solo cattura elettrica, nessun polso");
    Cmd(s, @"set_rhythm", @"sinus_bradycardia", NULL);
    CHECK(![s snapshot].pulsePresent, "bradicardia stimolata senza cattura meccanica: niente polso");
    Cmd(s, @"set_defib_config", @{@"mechanical_capture": @YES}, NULL); Cmd(s, @"set_rhythm", @"asystole", NULL);
    CHECK(![[AlarmManager evaluate:sn].messages containsObject:@"ASISTOLIA"], "asistolia stimolata: niente allarme asistolia");
    Cmd(s, @"set_defib_config", @{@"capture_possible": @NO}, NULL);
    CHECK(![s snapshot].defib.paceCapture, "istruttore: cattura impossibile");
    Cmd(s, @"set_defib_config", @{@"capture_possible": @YES}, NULL);
    // PAUSE: 25% della frequenza impostata (ritmo proprio visibile)
    Cmd(s, @"set_rhythm", @"sinus_bradycardia", NULL); Cmd(s, @"set_heart_rate", @40, NULL);
    Cmd(s, @"defib_pacer", @{@"rate": @80, @"paused": @YES}, NULL);
    d = [s snapshot].defib;
    CHECK(d.pacePaused && d.paceRate == 20 && d.paceSetRate == 80 && !d.paceActive, "PAUSE: 25%% (20 ppm), demand inibito dal ritmo proprio");
    Cmd(s, @"defib_pacer", @{@"paused": @NO}, NULL);
    CHECK([s snapshot].defib.paceRate == 80 && [s snapshot].defib.paceActive, "PAUSE rilasciato: 80 ppm");
    Cmd(s, @"defib_pacer", @{@"running": @YES, @"rate": @200}, NULL);      // stesso stato di arrivo del blocco qui sopra
    CHECK(Cmd(s, @"defib_energy", @4, &err), "energia 4 J accettata");
    Cmd(s, @"defib_mode", @"pacer", NULL);
    Cmd(s, @"set_layout", @"generic_icu", NULL); Cmd(s, @"set_heart_rate", @45, NULL); Cmd(s, @"defib_pacer", @{@"rate": @70}, NULL);
    Sensor(s, @"pads", NO);
    CHECK(![s snapshot].defib.paceRunning, "piastre staccate: pacing interrotto");

    // forme d'onda: spike e battiti stimolati
    Cmd(s, @"set_rhythm", @"sinus_bradycardia", NULL); Sensor(s, @"pads", YES);
    Cmd(s, @"defib_pacer", @{@"rate": @80, @"output_ma": @90, @"running": @YES}, NULL);
    WaveformEngine *e = [[WaveformEngine alloc] initWithSeed:7];
    [e updateWithSnapshot:[s snapshot]];
    int spikes = 0, beats = 0; NSTimeInterval lastB = -1;
    for (double t = 0; t < 6.0; t += 0.004) {
        [e ecgAt:t lead:SLLeadII];
        if ([e markersFrom:t to:t + 0.004 sync:NO] & SLMarkerPace) spikes++;
        NSTimeInterval b = [e lastBeatAtOrBefore:t]; if (b > lastB) { lastB = b; beats++; }
    }
    CHECK(spikes >= 7 && spikes <= 9 && beats >= 7 && beats <= 9, "pacing 80/min: ~8 spike e ~8 battiti in 6 s (spike %d, battiti %d)", spikes, beats);
    CHECK([e ecgAt:6.1 lead:SLLeadPads] != 0 || [e ecgAt:6.2 lead:SLLeadPads] != 0, "derivazione piastre attiva");

    // reset: config dell'istruttore conservata, stato del defibrillatore azzerato
    Cmd(s, @"set_defib_config", @{@"capture_threshold_ma": @55}, NULL);
    Reset(s);
    NSDictionary *st = [s stateDictionary];
    CHECK([st[@"defib"][@"mode"] isEqualToString:@"off"] && [st[@"defib"][@"config"][@"capture_threshold_ma"] intValue] == 55 &&
          ![st[@"sensors"][@"pads"] boolValue], "reset: defib spento, config conservata");
}

static void testSpO2TempCrt(void) {
    SimulationState *s = NewStateRaw();
    NSString *err = nil;
    CHECK(Cmd(s, @"set_spo2_delay", @10, &err) && !Cmd(s, @"set_spo2_delay", @500, &err), "ritardo SpO2 0..120 s");
    Sensor(s, @"ecg", YES); Sensor(s, @"spo2", YES);
    SLSnapshot *sn = [s snapshot];
    CHECK(sn.spo2Searching && sn.spo2Acquiring && !sn.spo2Displayable, "sonda appena messa: ricerca, valore nascosto");
    Tick(s, 5.5);
    sn = [s snapshot];
    CHECK(!sn.spo2Searching && sn.spo2Acquiring && !sn.spo2Displayable, "metà ritardo: onda presente, valore ancora nascosto");
    Tick(s, 5);
    CHECK([s snapshot].spo2Displayable, "dopo 10 s il valore compare");
    Sensor(s, @"spo2", NO); Sensor(s, @"spo2", YES);
    CHECK([s snapshot].spo2Acquiring, "ricollegando la sonda il ritardo riparte");
    Cmd(s, @"set_spo2_delay", @0, NULL); Sensor(s, @"spo2", NO); Sensor(s, @"spo2", YES);
    CHECK([s snapshot].spo2Displayable, "ritardo 0: valore subito");
    CHECK(Cmd(s, @"set_spo2_low_perfusion", @YES, &err) && [s snapshot].lowPerfusion && [[s stateDictionary][@"spo2_low_perfusion"] boolValue],
          "flag bassa perfusione con PA normale");
    Cmd(s, @"set_spo2_low_perfusion", @NO, NULL);
    CHECK(![s snapshot].lowPerfusion, "flag bassa perfusione disattivato");

    CHECK(Cmd(s, @"set_temperature", @38.6, &err) && [s snapshot].temperatureTenths == 386, "temperatura 38.6");
    CHECK(!Cmd(s, @"set_temperature", @50, &err) && !Cmd(s, @"set_temperature", @YES, &err), "temperatura fuori range rifiutata");
    CHECK([[s stateDictionary][@"temperature_displayed"] isKindOfClass:[NSNull class]], "temperatura nascosta senza sonda");
    Sensor(s, @"temp", YES);
    CHECK(fabs([[s stateDictionary][@"temperature_displayed"] doubleValue] - 38.6) < 0.01, "temperatura mostrata con la sonda");
    Sensor(s, @"pads", YES);
    CHECK([[s stateDictionary][@"sensors"][@"temp"] boolValue] && [[s stateDictionary][@"sensors"][@"pads"] boolValue], "stato API: sensori temp e pads");
    CHECK(Cmd(s, @"set_crt", @3.5, &err) && [s snapshot].crtTenths == 35 && !Cmd(s, @"set_crt", @0, &err), "refill capillare 0.5..10 s");
    CHECK(Cmd(s, @"set_crt_enabled", @NO, &err) && ![s snapshot].crtEnabled, "refill disattivabile");
    // NIBP: seconda misura senza bracciale -> errore "cuff" e il valore precedente sparisce
    Sensor(s, @"nibp", YES); Cmd(s, @"set_rhythm", @"sinus", NULL); RunNibp(s);
    CHECK([s snapshot].nibpLastSystolic > 0, "prima misura NIBP valida");
    Sensor(s, @"nibp", NO); RunNibp(s);
    CHECK([[s snapshot].nibpError isEqualToString:@"cuff"] && [s snapshot].nibpLastSystolic < 0, "bracciale tolto: errore perdite e valore precedente cancellato");
    CHECK(Cmd(s, @"mute_alarms", @120, &err) && [s snapshot].alarmsMuted && [s snapshot].alarmsMutedRemaining == 120, "silenzio di 120 s");
    CHECK(!Cmd(s, @"mute_alarms", @2000, &err), "silenzio oltre 15 min rifiutato");
    Cmd(s, @"mute_alarms", @NO, NULL);
    // layout originali (versione pubblica) per primi nel catalogo, con i loro nomi
    NSArray *cat = [SimulationState layoutCatalog];
    CHECK(cat.count >= 3 && [cat[0][@"id"] isEqualToString:@"generic_icu"] && [cat[0][@"name"] isEqualToString:@"ICU"]
          && [cat[1][@"id"] isEqualToString:@"extrah"] && [cat[1][@"name"] isEqualToString:@"extraH"]
          && [cat[2][@"id"] isEqualToString:@"dae"] && [cat[2][@"name"] isEqualToString:@"DAE"], "catalogo dei layout: ICU, extraH, DAE per primi");
    CHECK([[s stateDictionary][@"layouts"] isEqual:cat] && [[SimulationState supportedLayouts] count] == cat.count, "catalogo nello stato, elenco degli id coerente");
    CHECK(Cmd(s, @"set_layout", @"extrah", &err) && [[s snapshot].layout isEqualToString:@"extrah"], "layout extrah");
    CHECK(Cmd(s, @"set_layout", @"dae", &err) && [[s snapshot].layout isEqualToString:@"dae"], "layout dae");
    CHECK(!Cmd(s, @"set_layout", @"boh", &err) && [err containsString:@"extrah"] && [err containsString:@"dae"], "layout sconosciuto: l'errore elenca quelli disponibili");
    // extraH: il defibrillatore usa anche gli elettrodi ECG del dispositivo, e nessuna regola di marca
    Cmd(s, @"set_layout", @"extrah", NULL);
    CHECK(!Cmd(s, @"set_layout", @"boh", &err) && Cmd(s, @"set_layout", @"extrah", &err) && [[s snapshot].layout isEqualToString:@"extrah"], "layout valido / non valido");
    CHECK(Cmd(s, @"defib_event", nil, &err) && [[[s snapshot].defib.events.lastObject objectForKey:@"text"] isEqualToString:@"Evento marcato"], "tasto EVENT nel registro");
    Reset(s);
    CHECK([s snapshot].temperatureTenths == 368 && [s snapshot].crtTenths == 20 && ![s snapshot].tempConnected, "reset: 36.8 °C, refill 2 s, sonda staccata");
    CHECK(![s snapshot].crtEnabled && [[s snapshot].layout isEqualToString:@"extrah"], "reset: refill e layout sono impostazioni del monitor, restano");
}

static void testMotion(void) {
    NSString *err = nil;
    SimulationState *s = NewState();
    CHECK(!Cmd(s, @"set_patient_motion", @"jump", &err), "movimento: livello non valido rifiutato");
    CHECK(!Cmd(s, @"set_patient_motion", @{@"level": @"light", @"duration_s": @500}, &err), "movimento: durata fuori range rifiutata");
    CHECK(Cmd(s, @"set_patient_motion", @"strong", &err) && [s snapshot].patientMotion == 2, "movimento marcato continuo");
    CHECK([[s stateDictionary][@"patient_motion"] isEqualToString:@"strong"], "stato JSON: patient_motion");
    CHECK([s snapshot].lowPerfusion, "movimento marcato: SpO2 incerta ('?')");
    // ECG con artefatto: la differenza fra con e senza movimento deve essere ampia
    WaveformEngine *e1 = [[WaveformEngine alloc] initWithSeed:7], *e2 = [[WaveformEngine alloc] initWithSeed:7];
    [e1 updateWithSnapshot:[s snapshot]];
    Cmd(s, @"set_patient_motion", @"off", NULL);
    [e2 updateWithSnapshot:[s snapshot]];
    double maxd = 0; for (int i = 0; i < 500; i++) { double t = 10 + i * 0.01; maxd = MAX(maxd, fabs([e1 ecgAt:t lead:SLLeadII] - [e2 ecgAt:t lead:SLLeadII])); }
    CHECK(maxd > 0.5, "movimento: artefatto visibile sull'ECG");
    // a tempo: si ferma da solo
    Cmd(s, @"set_patient_motion", @{@"level": @"light", @"duration_s": @5}, NULL);
    CHECK([s snapshot].patientMotion == 1 && [s snapshot].patientMotionRemaining == 5, "movimento lieve per 5 s");
    gNow += 6; [s tickAtTime:gNow];
    CHECK([s snapshot].patientMotion == 0, "movimento a tempo: finisce da solo");
    // NIBP: movimenti marcati durante la misura -> misura non riuscita
    [s startNibpMeasurementError:NULL];
    Cmd(s, @"set_patient_motion", @{@"level": @"strong", @"duration_s": @3}, NULL);
    gNow += 60; [s tickAtTime:gNow];
    CHECK([s snapshot].nibpStatus == SLNibpError && [[s snapshot].nibpError isEqualToString:@"motion"], "NIBP: movimento marcato = misura non riuscita");
    RunNibp(s);
    CHECK([s snapshot].nibpStatus == SLNibpComplete, "NIBP: paziente fermo = misura riuscita");
    // senza polso il paziente non si muove: movimenti rifiutati e quelli in corso si fermano
    Cmd(s, @"set_patient_motion", @"strong", NULL);
    Cmd(s, @"set_rhythm", @"vf", NULL); gNow += 0.5; [s tickAtTime:gNow];
    CHECK([s snapshot].patientMotion == 0, "movimento: si ferma quando il polso scompare");
    CHECK(!Cmd(s, @"set_patient_motion", @"light", &err) && [err containsString:@"pulse"], "movimento: rifiutato in FV (senza polso)");
    CHECK(Cmd(s, @"set_patient_motion", @"off", &err), "movimento: 'off' sempre accettato");
    CHECK(!Cmd(s, @"patient_touch", @30, &err) && Cmd(s, @"patient_touch", nil, &err) && [s snapshot].operatorTouch, "tocco operatore: con qualsiasi ritmo (3 s)");
    WaveformEngine *e3 = [[WaveformEngine alloc] initWithSeed:7]; Sensor(s, @"pads", YES); [e3 updateWithSnapshot:[s snapshot]];
    gNow += 3.5; [s tickAtTime:gNow];
    CHECK(![s snapshot].operatorTouch, "tocco operatore: finisce da solo");
    WaveformEngine *e4 = [[WaveformEngine alloc] initWithSeed:7]; [e4 updateWithSnapshot:[s snapshot]];
    maxd = 0; for (int i = 0; i < 300; i++) { double t = 20 + i * 0.01; maxd = MAX(maxd, fabs([e3 ecgAt:t lead:SLLeadPads] - [e4 ecgAt:t lead:SLLeadPads])); }
    CHECK(maxd > 0.8, "tocco operatore: artefatto sulle piastre");
    Sensor(s, @"pads", NO);
    // DAE: il tocco interrompe l'analisi, che riparte da capo quando nessuno tocca il paziente
    Cmd(s, @"defib_mode", @"aed", NULL); Sensor(s, @"pads", YES);
    Tick(s, 3);
    Cmd(s, @"patient_touch", @10, NULL); Tick(s, 1);
    SLDefibInfo *d = [s snapshot].defib;
    CHECK(d.aedPhase == SLAedAnalyzing && [d.message containsString:@"FERMARE IL MOVIMENTO"] && [d.voicePrompt containsString:@"Fermare il movimento"], "DAE: movimento = analisi interrotta, non toccare il paziente");
    NSUInteger seq = d.promptSeq;
    Tick(s, 7);
    CHECK([s snapshot].defib.promptSeq > seq && [s snapshot].defib.aedPhase == SLAedAnalyzing, "DAE: il messaggio si ripete finché il movimento continua");
    Tick(s, 2.5);
    d = [s snapshot].defib;
    CHECK(d.aedPhase == SLAedAnalyzing && [d.voicePrompt containsString:@"Analisi del ritmo"], "DAE: paziente fermo = analisi riprende");
    Tick(s, 5);
    CHECK([s snapshot].defib.aedPhase == SLAedAnalyzing, "DAE: l'analisi riparte da capo (non ancora finita)");
    Tick(s, 6);
    CHECK([s snapshot].defib.aedPhase == SLAedCharging || [s snapshot].defib.aedPhase == SLAedReady, "DAE: analisi completata dopo il movimento");
    [s resetScenario];
    CHECK([s snapshot].patientMotion == 0, "reset: paziente fermo");
}

static void testSites(void) {
    SimulationState *s = NewStateRaw(); NSString *err = nil;
    CHECK(Cmd(s, @"set_sensor", @{@"sensor": @"nibp", @"connected": @YES, @"site": @"upper_arm_r"}, &err), "set_sensor con posizione");
    CHECK([[s snapshot].sensorSites[@"nibp"] isEqualToString:@"upper_arm_r"], "posizione del bracciale salvata");
    CHECK(!Cmd(s, @"set_sensor", @{@"sensor": @"spo2", @"connected": @YES, @"site": @"Dito Destro!"}, &err), "posizione non valida rifiutata");
    CHECK(Cmd(s, @"set_sensor", @{@"sensor": @"spo2", @"connected": @YES, @"site": @"finger_r2"}, &err), "SpO2 al dito destro");
    CHECK([s snapshot].spo2SignalValid && ![s snapshot].spo2CuffOccluded, "bracciale fermo: SpO2 regolare");
    [s startNibpMeasurementError:NULL];
    SLSnapshot *sn = [s snapshot];
    CHECK(sn.spo2CuffOccluded && !sn.spo2SignalValid && sn.spo2SignalSetting, "NIBP sullo stesso braccio: SpO2 occlusa durante la misura");
    NSDictionary *j = [s stateDictionary];
    CHECK([j[@"spo2_cuff_occluded"] boolValue] && [j[@"spo2_signal_valid"] boolValue] && [j[@"sensor_sites"][@"spo2"] isEqualToString:@"finger_r2"], "JSON: posizioni e occlusione");
    Cmd(s, @"set_sensor", @{@"sensor": @"spo2", @"connected": @NO}, NULL);
    Cmd(s, @"set_sensor", @{@"sensor": @"spo2", @"connected": @YES, @"site": @"finger_l4"}, NULL);
    CHECK(![s snapshot].spo2CuffOccluded, "SpO2 sul braccio opposto: nessuna occlusione");
    Cmd(s, @"set_sensor", @{@"sensor": @"nibp", @"connected": @NO}, NULL);
    CHECK([s snapshot].sensorSites[@"nibp"] == nil, "scollegato: posizione rimossa");
    [s resetScenario];
    CHECK([s snapshot].sensorSites.count == 0, "reset: nessuna posizione");
    // senza lato indicato (Pocket, stati, scenari) vale quello di serie che mostrano le regie: bracciale a destra
    Cmd(s, @"set_sensor", @{@"sensor": @"nibp", @"connected": @YES}, NULL);
    Cmd(s, @"set_sensor", @{@"sensor": @"spo2", @"connected": @YES, @"site": @"finger_r2"}, NULL);
    CHECK([[s snapshot].sensorSites[@"nibp"] isEqualToString:@"upper_arm_r"] && [[s stateDictionary][@"sensor_sites"][@"nibp"] isEqualToString:@"upper_arm_r"],
          "bracciale senza lato: braccio destro di serie, anche nel JSON");
    [s startNibpMeasurementError:NULL];
    CHECK([s snapshot].spo2CuffOccluded, "bracciale di serie (dx) e SpO2 al dito destro: occlusa durante la misura");
    // linea arteriosa radiale sullo stesso braccio: curva piatta durante la misura, poi torna
    Cmd(s, @"set_sensor", @{@"sensor": @"art", @"connected": @YES, @"site": @"radial_r"}, NULL);
    SLSnapshot *a1 = [s snapshot];
    CHECK(a1.artCuffOccluded && a1.artDisplayedSystolic == 26 && a1.artDisplayedDiastolic == 24 && [[s stateDictionary][@"art_cuff_occluded"] boolValue],
          "ART radiale destra con bracciale destro in misura: smorzata (26/24)");
    Tick(s, 60);
    SLSnapshot *a2 = [s snapshot];
    CHECK(!a2.artCuffOccluded && a2.artDisplayedSystolic == a2.systolic, "misura finita: la curva arteriosa torna pulsatile");
    Cmd(s, @"set_sensor", @{@"sensor": @"art", @"connected": @NO}, NULL);
    Cmd(s, @"set_sensor", @{@"sensor": @"art", @"connected": @YES}, NULL);
    [s startNibpMeasurementError:NULL];
    CHECK([[s snapshot].sensorSites[@"art"] isEqualToString:@"radial_l"] && ![s snapshot].artCuffOccluded, "ART di serie a sinistra, bracciale a destra: nessun effetto");
    Cmd(s, @"set_sensor", @{@"sensor": @"art", @"connected": @NO}, NULL);
    Cmd(s, @"set_sensor", @{@"sensor": @"art", @"connected": @YES, @"site": @"femoral_r"}, NULL);
    CHECK(![s snapshot].artCuffOccluded, "ART femorale: il bracciale non la influenza");
}

static void testCrtAssess(void) {
    SimulationState *s = NewStateRaw();
    NSInteger q0 = [s snapshot].crtAssessSeq;
    Cmd(s, @"set_crt_enabled", @NO, NULL);
    CHECK(Cmd(s, @"assess_crt", nil, NULL) && [s snapshot].crtAssessSeq == q0 + 1 && [s snapshot].crtEnabled, "refill: l'istruttore fa valutare (e il riquadro torna visibile)");
    CHECK([[s stateDictionary][@"crt_assess_seq"] integerValue] == q0 + 1, "refill: contatore nello stato");
}

static void testCuffError(void) {
    SimulationState *s = NewStateRaw();
    [s startNibpMeasurementError:NULL]; Tick(s, 40);
    CHECK([s snapshot].nibpStatus == SLNibpError && [[s snapshot].nibpError isEqualToString:@"cuff"], "NIBP senza bracciale: errore perdita");
    Cmd(s, @"set_sensor", @{@"sensor": @"nibp", @"connected": @YES}, NULL);
    CHECK([s snapshot].nibpStatus == SLNibpIdle && [s snapshot].nibpError == nil, "bracciale collegato: errore cancellato");
}

// --- aggiornamenti senza computer: pacchetto del monitor installato, quelli dei controller conservati e serviti a pezzi ---
static NSData *TGzip(NSData *d) {
    z_stream z; memset(&z, 0, sizeof z); deflateInit2(&z, 9, Z_DEFLATED, 16 + MAX_WBITS, 8, Z_DEFAULT_STRATEGY);
    NSMutableData *o = [NSMutableData dataWithLength:d.length + 1024];
    z.next_in = (Bytef *)d.bytes; z.avail_in = (uInt)d.length; z.next_out = o.mutableBytes; z.avail_out = (uInt)o.length;
    deflate(&z, Z_FINISH); o.length = z.total_out; deflateEnd(&z); return o;
}
static NSData *TDebEd(NSString *pkg, NSString *ver, NSUInteger padding, NSString *edition);
static NSData *TDeb(NSString *pkg, NSString *ver, NSUInteger padding) { return TDebEd(pkg, ver, padding, nil); }
static NSData *TDebEd(NSString *pkg, NSString *ver, NSUInteger padding, NSString *edition) {
    NSData *c = [[NSString stringWithFormat:@"Package: %@\nVersion: %@\nArchitecture: iphoneos-arm\n%@", pkg, ver,
                  edition ? [NSString stringWithFormat:@"X-SimilFranz-Edizione: %@\n", edition] : @""] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *tar = [NSMutableData dataWithLength:512];
    char *h = tar.mutableBytes; strcpy(h, "./control"); strcpy(h + 100, "0000644"); snprintf(h + 124, 12, "%011lo", (unsigned long)c.length); h[156] = '0';
    [tar appendData:c]; tar.length = 512 + (c.length + 511) / 512 * 512 + 1024;
    NSData *gz = TGzip(tar); NSMutableData *pad = [NSMutableData dataWithLength:padding];
    for (NSUInteger i = 0; i < padding; i++) ((uint8_t *)pad.mutableBytes)[i] = (uint8_t)(i * 7);
    NSMutableData *deb = [[@"!<arch>\n" dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];
    for (NSArray *m in @[@[@"debian-binary", [@"2.0\n" dataUsingEncoding:NSASCIIStringEncoding]], @[@"control.tar.gz", gz], @[@"data.tar.gz", pad]]) {
        NSData *d = m[1];
        [deb appendData:[[NSString stringWithFormat:@"%-16s%-12d%-6d%-6d%-8s%-10lu`\n", [m[0] UTF8String], 0, 0, 0, "100644", (unsigned long)d.length] dataUsingEncoding:NSASCIIStringEncoding]];
        [deb appendData:d]; if (d.length % 2) [deb appendBytes:"\n" length:1];
    }
    return deb;
}
static void testUpdates(void) {
    SimulationState *s = NewState();
    APIController *api = [[APIController alloc] initWithState:s pinProvider:^NSString *{ return @"482913"; } staticFiles:@{}];
    api.clock = ^NSTimeInterval { return gNow; };
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"sf-test-pacchetti"];
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    CHECK([api handle:Req(@"GET", @"/api/v1/update", @"482913", nil)].status == 404, "aggiornamenti: senza cartella non disponibili");
    api.packagesDir = dir; api.appVersion = @"0.13.0"; api.updateRepo = @"utente/repo";
    __block NSData *installed = nil;
    api.installHandler = ^NSString *(NSData *deb, NSString **err) { installed = deb; return [SFUpdate inspectDeb:deb allowed:@[@"it.simulafranz.monitor"] error:err][@"Version"]; };
    CHECK([api handle:Req(@"GET", @"/api/v1/update", nil, nil)].status == 401, "aggiornamenti: senza PIN -> 401");
    SLHTTPResponse *r = [api handle:Req(@"GET", @"/api/v1/update", @"482913", nil)];
    CHECK(r.status == 200 && [J(r)[@"version"] isEqualToString:@"0.13.0"] && [J(r)[@"repo"] isEqualToString:@"utente/repo"] && [J(r)[@"packages"] count] == 0, "aggiornamenti: GET versione, repository, nessun pacchetto conservato");
    SLHTTPRequest *up = Req(@"POST", @"/api/v1/update", @"482913", nil); up.body = TDeb(@"it.simulafranz.monitor", @"0.13.1", 10);
    r = [api handle:up];
    CHECK(r.status == 202 && installed && [J(r)[@"to"] isEqualToString:@"0.13.1"], "aggiornamenti: il pacchetto del monitor si installa (202)");
    installed = nil; up.body = TDeb(@"it.simulafranz.pocket", @"0.2.0", 70000);
    r = [api handle:up];
    CHECK(r.status == 200 && !installed && [J(r)[@"stored"] isEqualToString:@"0.2.0"], "aggiornamenti: il pacchetto del Pocket resta sul monitor");
    r = [api handle:Req(@"GET", @"/api/v1/update", @"482913", nil)];
    CHECK([J(r)[@"packages"][@"it.simulafranz.pocket"] isEqualToString:@"0.2.0"], "aggiornamenti: il monitor dichiara il pacchetto conservato");
    up.body = TDeb(@"it.simulafranz.saturimetro", @"9.9", 10);
    CHECK([api handle:up].status == 400, "aggiornamenti: pacchetto estraneo rifiutato");
    up.body = [@"boh" dataUsingEncoding:NSUTF8StringEncoding];
    CHECK([api handle:up].status == 400, "aggiornamenti: file qualsiasi rifiutato");
    // un controller ricompone il pacchetto a pezzi (come farà via collegamento diretto)
    NSMutableData *joined = [NSMutableData data]; long long off = 0, size = -1; int pieces = 0;
    while (size < 0 || off < size) {
        SLHTTPRequest *cq = Req(@"GET", @"/api/v1/update/chunk", @"482913", nil); cq.query = [NSString stringWithFormat:@"pkg=it.simulafranz.pocket&offset=%lld", off];
        NSDictionary *j = J([api handle:cq]);
        if (![j[@"ok"] boolValue]) break;
        NSData *d = [[NSData alloc] initWithBase64EncodedString:j[@"data"] options:0];
        [joined appendData:d]; off += d.length; size = [j[@"size"] longLongValue]; pieces++;
        if (!d.length || pieces > 100) break;
    }
    CHECK([joined isEqualToData:TDeb(@"it.simulafranz.pocket", @"0.2.0", 70000)] && pieces >= 3, "aggiornamenti: pacchetto ricomposto identico da %d pezzi", pieces);
    SLHTTPRequest *cq = Req(@"GET", @"/api/v1/update/chunk", @"482913", nil); cq.query = @"pkg=it.simulafranz.monitor&offset=0";
    CHECK([api handle:cq].status == 400, "aggiornamenti: il pacchetto del monitor non si distribuisce a pezzi");
    cq.query = @"pkg=it.simulafranz.controller&offset=0";
    CHECK([api handle:cq].status == 404, "aggiornamenti: pacchetto non conservato -> 404");
    // edizione privata (layout aggiuntivi): il pacchetto pubblico del monitor è rifiutato, quello privato e i controller passano
    api.edition = @"privata"; installed = nil;
    r = [api handle:Req(@"GET", @"/api/v1/update", @"482913", nil)];
    CHECK([J(r)[@"edition"] isEqualToString:@"privata"], "aggiornamenti: il monitor dichiara l'edizione privata");
    up.body = TDebEd(@"it.simulafranz.monitor", @"0.15.0", 10, @"pubblica");
    CHECK([api handle:up].status == 409 && !installed, "edizione privata: pacchetto PUBBLICO del monitor rifiutato (i layout restano)");
    up.body = TDeb(@"it.simulafranz.monitor", @"0.15.0", 10);
    CHECK([api handle:up].status == 409 && !installed, "edizione privata: pacchetto del monitor senza edizione rifiutato");
    up.body = TDebEd(@"it.simulafranz.monitor", @"0.15.0", 10, @"privata");
    CHECK([api handle:up].status == 202 && installed, "edizione privata: pacchetto privato del monitor installato");
    up.body = TDebEd(@"it.simulafranz.controller", @"0.4.0", 10, @"pubblica");
    CHECK([api handle:up].status == 200, "edizione privata: il controller pubblico si conserva come sempre");
    api.edition = @"pubblica"; installed = nil;
    up.body = TDebEd(@"it.simulafranz.monitor", @"0.15.1", 10, @"pubblica");
    CHECK([api handle:up].status == 202 && installed, "edizione pubblica: pacchetto pubblico installato");
}

int main(void) {
    @autoreleasepool {
        testState(); testTransitions(); testWaveforms(); testAlarms(); testAPI(); testControl(); testDefib(); testScenarios(); testSessionLog(); testSpO2TempCrt(); testMotion(); testSites(); testCuffError(); testCrtAssess(); testUpdates();
        printf("\nTest superati: %d   falliti: %d\n", gPass, gFail);
        return gFail ? 1 : 0;
    }
}
