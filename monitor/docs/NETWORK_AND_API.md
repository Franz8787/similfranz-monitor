# Rete e API — SimulaFranz_Monitor v0.3

## Rete

- Wi-Fi® fornito da **SimulaFranz_Hub** (ESP32; SSID attuale `SIMLAB`, da rinominare `SimulaFranz_Hub`): **solo access point e DHCP**, gateway `192.168.4.1`.
- L'IP dell'iPad® è assegnato dal DHCP e **cambia**: nei test del 02/11 si è passati da `.2` a `.4` dopo un riavvio dell'ESP32.
  L'app mostra l'URL reale in basso a destra (`http://192.168.4.x:8080`) e nel pannello ⓘ.
- `192.168.4.1` è l'ESP32, **non** l'iPad. Non usarlo per la console.
- L'app pubblica anche il servizio Bonjour `_http._tcp` con nome "SimulaFranz_Monitor monitor-01". È opzionale: il riferimento resta l'IP mostrato a schermo.
- Il server è attivo solo con l'app **in primo piano**. In background iOS sospende l'app, e il server riparte quando l'app torna attiva.

## Sicurezza

- Header `X-SimulaFranz-Token: <PIN>` obbligatorio su tutte le API tranne `/api/v1/health`.
- PIN: in Impostazioni › SimulaFranz_Monitor, oppure generato a caso (6 cifre) al primo avvio. Si legge sull'iPad dal pannello ⓘ. Non è salvato nel repository.
- Anti forza bruta: dopo 5 PIN errati in 60 s, lo stesso IP viene bloccato per 30 s (HTTP 429).
- Limiti del server: header 8 KB, body 16 KB, timeout 5 s, massimo 8 connessioni, niente chunked encoding.
- Nessun CORS: la console è *same-origin*, servita dall'app stessa.
- **Limite noto:** è HTTP in chiaro su Wi-Fi locale. WPA2 e PIN riducono i rischi ma non equivalgono a TLS. Usare la rete solo tra istruttori.
- ATS: l'app non fa connessioni in uscita, quindi non serve alcuna eccezione `NSAllowsArbitraryLoads`.

## Canali e controllo (0.11.0)

- **Wi-Fi**: server HTTP (porta 8080). Bonjour `_http._tcp` e `_similfranz-http._tcp` (nome «Monitor <nome iPad>», TXT `type=monitor`, `id`, `ver`, `api=v1`) per l'app controller.
- **Diretto, senza rete**: Multipeer Connectivity, serviceType `similfranz`, discoveryInfo come il TXT. L'invito è sempre accettato; ogni messaggio è JSON:
  richiesta `{"id":n,"method":"POST","path":"/api/v1/command","headers":{"X-SimulaFranz-Token":"<PIN>",...},"body":{...}}`,
  risposta `{"id":n,"status":200,"body":{...}}`. Alla connessione arriva `{"event":"hello",...}`. Solo percorsi `/api/`.
- **Identità del controller** (header, su entrambi i canali): `X-SimulaFranz-Client` (id stabile, max 64, `A-Za-z0-9_.:-`), `X-SimulaFranz-Client-Name` (nome leggibile, percent-encoded, max 40), `X-SimulaFranz-Client-Kind` (`web`, `ipad`, `ipod`…). Senza id vale l'indirizzo di provenienza.
- **Un solo controller alla volta** (web app, app iPad, app iPod®; regole in `SFControl`, dalla 0.12.0 rev. 14/11/2026):
  1. leggere (`GET` di stato, registro, scenari, controllo) **non** prende il comando;
  2. il primo comando lo prende, se nessuno comanda;
  3. chi comanda ed ha dato un comando negli ultimi **60 s** è protetto: gli altri ricevono **423** `{"error":"controller_busy","message":…,"controller":…}` su `command`, `nibp/start`, scenari e svuotamento del registro (annotare è sempre permesso);
  4. chi comanda ma è fermo da più di 60 s non blocca: il primo comando di un altro passa e il comando cambia di mano;
  5. `POST /api/v1/control {"action":"take"}` funziona sempre; `release` lo lascia (le app lo fanno andando in background);
  6. senza richieste per 10 s (app chiusa, fuori portata) il posto si libera.
  Ogni risposta contiene `controller` = `{active, name, kind (web|ipad|ipod), transport (wifi|direct), mine, idle_s, action_idle_s, since_s, protected}`; a chi ha perso il comando negli ultimi 5 minuti anche `lost_to` e `lost_ago_s`. Ogni cambio di mano finisce nel registro della sessione (voce di tipo `note`, autore `regia`).
- I dispositivi seguaci (`X-SimulaFranz-Device: oximeter`) non sono controller: mai bloccati, non occupano il posto.

| Metodo | Percorso | Auth | Risposta |
|---|---|---|---|
| GET | `/api/v1/control` | sì | `{ok, controller}` |
| POST | `/api/v1/control` | sì | body `{"action":"take"}` o `{"action":"release"}` → `{ok, controller}` |

## Scenari, registro, sessioni (0.12.0)

| Metodo | Percorso | Note |
|---|---|---|
| GET | `/api/v1/scenarios` | `{scenarios:[{id,name,notes,phases:[{name,note,duration_s,rhythm?,params,temperature_c?,crt_s?}]}], scenario:{active,…}}` |
| POST | `/api/v1/scenarios` | `{"action":"save","scenario":{…}}`, `delete` (`id`), `start` (`id`,`phase`), `goto` (`phase`), `next`, `stop`. Solo il controller attivo. Max 24 fasi, 40 scenari |
| GET | `/api/v1/log[?session=N\|all][&since=I][&format=text]` | voci `{i,s,t,w,k,text,tag?,by?,energy_j?}` (max 400 per chiamata, `more`), `summary`, `session`, `current_session`, `sessions` |
| POST | `/api/v1/log` | `{"action":"add","kind":K,"text":T,"tag"?}` (anche chi non comanda), `new_session` (`title`?), `clear` (tutte le sessioni) |

Ogni risposta di stato contiene anche `scenario` (conduzione in corso), `log_next`, `log_session` e, nello stato, `layouts` (id + nome).
Categorie del registro: `phase`, `patient`, `monitor`, `electric`, `timer`, `action`, `drug`, `plus`, `minus`, `note`. Tag usati dal riepilogo: `arrest`, `ac`, `help`, `cpr_start`, `shock`, `rosc`.

## Endpoint

| Metodo | Percorso | Auth | Risposta |
|---|---|---|---|
| GET | `/` (`/style.css`, `/app.js`) | no | console Web |
| GET | `/api/v1/health` | no | `{ok, service, device_id, version, api, uptime_s}` |
| GET | `/api/v1/state` | sì | `{ok, state, revision, error}` |
| POST | `/api/v1/command` | sì | `{ok, state, revision, error}`; 400 con `error` leggibile |
| POST | `/api/v1/nibp/start` | sì | avvia un ciclo NIBP **solo software** (circa 8 s); 409 se una misura è già in corso |

### Comandi (`POST /api/v1/command`, `Content-Type: application/json`)

```json
{"device_id":"monitor-01","command":"set_heart_rate","value":110}
```

| command | value |
|---|---|
| `set_heart_rate` | 0–300 |
| `set_rhythm` | `sinus`, `sinus_tachycardia`, `sinus_bradycardia`, `afib`, `vt_pulse` (TV con polso), `vt` (TV senza polso), `vf`, `asystole`, `pea`. FC 0 in un ritmo organizzato = asistolia |
| `set_spo2` | 0–100 |
| `set_spo2_signal_valid` | `true`/`false` (artefatto) |
| `set_sensor` | `{"sensor":"ecg"/"spo2"/"nibp"/"etco2"/"art","connected":bool}` |
| `set_resp_rate` | 0–60 |
| `set_etco2` | 0–150 |
| `set_bp` (alias `set_nibp`) | `{"systolic":0–300,"diastolic":0–200}`: PA del paziente, mostrata dall'ART e misurata dalla NIBP |
| `set_alarm_limits` | anche parziale: `hr_low`, `hr_high`, `spo2_low`, `rr_low`, `rr_high`, `etco2_low`, `etco2_high`, `sys_low`, `sys_high` |
| `reset_alarm_limits` | nessun valore |
| `mute_alarms` | `true`/`false`; il silenziamento scade da solo dopo **20 s** |
| `set_qrs_beep` | `true`/`false` |
| `set_volume` | 0–100 |
| `set_cpr` | `true`/`false`: RCP in corso (artefatto delle compressioni, ART da compressione, EtCO₂ ~15) |
| `set_alarm_enabled` | `{"param":"hr"/"spo2"/"art"/"nibp"/"rr"/"etco2","enabled":bool}`; i ritmi letali suonano comunque |
| `set_nibp_interval` | minuti tra misure automatiche: 0 (spenta), 1, 2, 3, 5, 10, 15, 30, 60 |
| `set_auto_physiology` | `true`/`false`: arresto → SpO₂/FR/EtCO₂ a 0; ROSC → recupero |
| `transition` | `{"params":{...},"duration_s":0–3600,"rhythm":opzionale}`; params: `heart_rate_bpm`, `spo2_percent`, `systolic_mmhg`, `diastolic_mmhg`, `respiratory_rate_rpm`, `etco2_mmhg` |
| `cancel_transitions` | nessun valore |
| `run_chain` | `{"name":"...","steps":[{"wait_s":n,"duration_s":n,"rhythm":opz,"params":{...},"label":opz}]}`, da 1 a 40 passi |
| `stop_chain` | nessun valore: ferma la catena e le rampe |
| `set_simulation_running` | `true`/`false` |
| `reset_scenario` | nessun valore (i limiti di allarme NON vengono azzerati) |
| `reset_clock` (0.12) | nessun valore: azzera solo l'orologio di scenario (`scenario_time_s`); parametri, sonde e contatori restano. Lo fa da solo anche l'avvio di uno scenario a fasi |
| `set_sensor` (nuovi) | anche `"temp"` (sonda di temperatura) e `"pads"` (piastre del defibrillatore) |
| `set_sensor` + `site` (0.7.3) | facoltativo `"site"` (minuscole, cifre, `_`, max 24): dove è messo il sensore. Valori usati dal controller: `chest`, `airway`, `forehead`, `upper_arm_r/l`, `radial_r/l`, `femoral_r/l`, `finger_r1..r5` / `finger_l1..l5` (1 = pollice). Stato: `sensor_sites` (sensore → posizione; tolto quando il sensore viene scollegato). Se il bracciale NIBP (`upper_arm_X`) misura sullo stesso braccio della SpO₂ (`finger_X*`) la SpO₂ perde il segnale per tutta la misura: `spo2_cuff_occluded` = true (`spo2_signal_valid` resta l'impostazione dell'istruttore) |
| `set_spo2_delay` | 0–120 s tra il collegamento della sonda e la comparsa del valore (prima metà: "ricerca polso", seconda: onda senza numero) |
| `set_spo2_low_perfusion` | `true`/`false`: bassa perfusione / artefatti anche con PA normale ("?" alternato e onda disturbata) |
| `set_temperature` | 25.0–45.0 °C (decimali ammessi); mostrata solo con la sonda `temp` collegata |
| `set_crt` | refill capillare 0.5–10 s |
| `set_layout` | uno degli `id` elencati nel campo `layouts` dello stato: `generic_icu` (ICU), `extrah`, `dae` (layout del monitor sull’iPad, salvato) |
| `set_patient_motion` | `"off"`, `"light"`, `"strong"` oppure `{"level":"strong","duration_s":0–120}` (0 = finché non viene fermato). **Solo con un ritmo con polso**: senza polso `light`/`strong` sono rifiutati e un movimento in corso si ferma da solo. Artefatti su ECG/piastre e pletismo; con `strong` la SpO₂ mostra "?" e una misura NIBP in corso non riesce (`nibp_error` = `motion`). Nel DAE il movimento interrompe l'analisi ("Movimento rilevato. Fermare il movimento.", ripetuto ogni 6 s) e l'analisi riparte da capo quando il paziente è fermo. Stato: `patient_motion`, `patient_motion_remaining_s` |
| `patient_touch` | PUSH, con qualsiasi ritmo: un operatore tocca o scuote il paziente per N secondi (1–10, predefinito 3; ogni pressione prolunga). Artefatto da contatto su ECG e piastre; nel DAE interrompe l'analisi come il movimento. Stato: `operator_touch` |
| `ventilate` | nessun valore: una insufflazione dei partecipanti. Con l'RCP in corso o in apnea il paziente non respira da solo: il capnogramma mostra un'onda solo dopo ogni `ventilate`, la FR a monitor è il numero di insufflazioni dell'ultimo minuto, l'EtCO₂ sparisce dopo 30 s senza ventilazioni. Stato: `ventilation_manual`, `breaths_last_min` |
| `assess_crt` | nessun valore: fa partire sul monitor la valutazione del refill (come il tocco del partecipante): ~3 s, poi compare il tempo. Stato: `crt_assess_seq` |
| `set_crt_enabled` | `true`/`false`: refill visibile sul monitor |
| `mute_alarms` (numero) | secondi 1–900 di silenziamento |
| `defib_event` | testo opzionale: segna un evento nel registro (tasto EVENT) |
| `defib_aed_cpr` | DAE: "Pausa per RCP" (toglie la carica e passa alla RCP) |
| `defib_mode` | `off`, `aed` (DAE), `manual`, `pacer` |
| `defib_energy` | J tra 1, 2, 3, 5, 7, 10, 15, 20, 30, 50, 70, 85, 100, 120, 150, 170, 200, 300, 360 (solo manuale; da carico annulla la carica) |
| `defib_charge` / `defib_disarm` / `defib_shock` | nessun valore. Manuale: carica ~1 s + 0,02 s/J, scarica interna dopo 60 s. Con SYNC lo shock parte alla prossima onda R |
| `defib_sync` | `true`/`false` (solo manuale) |
| `defib_analyze` | nessun valore: nuova analisi del DAE |
| `defib_pacer` | anche parziale: `{"rate":30–210,"output_ma":0–200,"demand":bool,"running":bool,"paused":bool}` (paused = 25% della frequenza) |
| `defib_outcome` | esito dell'ultima scarica quando `outcome_mode` = `instructor`: `"stay"` (resta nel ritmo pre-scarica) oppure un ritmo (es. `"sinus"`) |
| `set_defib_config` | istruttore, anche parziale: `outcome_mode` (`auto` predefinito, `instructor`), `shocks_to_convert` (0 = mai), `min_energy_j`, `post_shock_rhythm`, `cv_shocks_to_convert`, `cv_min_energy_j`, `cv_post_rhythm`, `unsync_shock_vf`, `sync_stays_on`, `capture_threshold_ma`, `capture_possible`, `mechanical_capture` (la cattura genera polso), `aed_energy_j` (50–360), `aed_cpr_s`, `voice_prompts`. Non si azzera con il reset |

Un comando manuale su un parametro annulla l'eventuale rampa in corso su quel parametro.

### Stato

Contiene i campi di specifica più `sensors`, `alarm_limits`, `auto_physiology`, `transitions` (parametro → `{to, remaining_s}`), `chain` (`{active, name, step, steps, label, phase, remaining_s}`), `volume_percent`, `qrs_beep_enabled`, `alarm_enabled`, `nibp_interval_min`, `nibp_next_in_s`, `cpr_active`, `pulse_rate_bpm`, `spo2_low_perfusion`, `alarms_muted_remaining_s` e alcuni campi derivati: `revision`, `monitor_on` (il monitor sull'iPad è acceso: parte spento, torna spento con `reset_scenario`; lo accende il discente sul dispositivo), `scenario_time_s` (secondi di scenario: esclude le pause, azzerato da `reset_scenario`), `pulse_present`, `displayed_heart_rate_bpm` (null in FV), `spo2_displayed` (null senza sonda, segnale o polso), `nibp_status` (`idle`/`measuring`/`complete`/`error`), `nibp_last_*` e `supported_rhythms`.

Dalla v0.3 lo stato contiene anche `temperature_c`, `temperature_displayed`, `crt_s`, `spo2_delay_s`, `spo2_acquiring`, `spo2_low_perfusion_flag` e l'oggetto `defib` (`mode`, `pads_connected`, `energy_j`, `charge`, `sync`, `sync_pending`, `aed_phase`, `aed_remaining_s`, `message`, `shock_count`, `pacer{...}` con `capture`/`mechanical_capture`, `config`, `events`).

### Defibrillatore simulato

- **DAE:** piastre → analisi 8 s ("non toccare il paziente"; con RCP in corso: "movimento rilevato") → FV, TV senza polso o TV ≥ 150/min = shock consigliato → carica → "premere shock" (30 s, poi scarica interna) → RCP per `aed_cpr_s` (metronomo 110/min) → nuova analisi. Istruzioni vocali in italiano.
- **Esito degli shock (istruttore):** FV/TV senza polso convertono dopo `shocks_to_convert` shock ≥ `min_energy_j`. FA/TV con polso convertono con la cardioversione (`cv_*`). Uno shock **non sincronizzato** su FA o ritmo sinusale → FV (R su T) se `unsync_shock_vf`. Asistolia e PEA non cambiano.
- **Piastre ed elettrodi sono indipendenti:** il defibrillatore vede solo l'ECG delle piastre (sensore `pads`).
- **SYNC:** marcatori ▼ sulle onde R. Senza QRS riconoscibili (FV) lo shock sincronizzato resta in attesa. Dopo lo shock il SYNC si spegne, salvo `sync_stays_on`.
- **Pacing:** spike su II, V5 e piastre. Sotto soglia: artefatto largo senza onda T. Sopra `capture_threshold_ma`: QRS largo + T discordante a ogni spike. Il polso c'è solo se il ritmo di base aveva polso (bradicardia), mentre in asistolia la cattura è solo elettrica. In demand il pacing è inibito se la FC propria è ≥ della frequenza impostata.

### Regole fisiologiche simulate

- **FV, TV senza polso, asistolia, PEA:** pletismografia piatta, SpO₂ `--`, NIBP `?/?` ("nessun polso rilevato").
- **Ipotensione marcata (sist < 70):** SpO₂ con "?" alternato al valore e onda pleth disturbata.
- **PEA:** l'ECG mostra attività elettrica, ma il polso è assente.
- **Sonda scollegata:** SpO₂ `--`, distinta da SpO₂ = 0.

### App futura SimulaFranz_Controller su iPod touch®

API HTTP/1.1 semplice, JSON, una richiesta per connessione: è utilizzabile da iOS 6 con `NSURLConnection`.
