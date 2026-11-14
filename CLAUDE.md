# Istruzioni per Claude Code

Questo progetto è un monitor multiparametrico **simulato** per la simulazione sanitaria. Tre app, su dispositivi
Apple® vecchi con jailbreak:

| App | Dispositivo | Comando | Porta SSH locale |
|---|---|---|---|
| similFranz Monitor | iPad mini® 1 (iOS 9.3.5/9.3.6) | `./aggiorna.sh monitor` | 2222 |
| similFranz Controller (regia) | secondo iPad mini 1 | `./aggiorna.sh controller` | 2226 |
| similFranz Pocket (regia tascabile) | iPod touch® 5 (iOS 9.3.5) | `./aggiorna.sh pocket` | 2228 |

Rispondi all'utente in italiano, con passi brevi: spesso non è uno sviluppatore. Le guide per lui sono in `docs/`
(installazione: `docs/02-installazione.md`, aggiornamenti: `docs/05-aggiornamenti.md`).

## Se l'utente chiede di installare

Segui questa sequenza, **un dispositivo alla volta**, e dopo ogni passo di' all'utente che cosa fare con le mani.

1. **Strumenti.** Servono `iproxy`, `idevice_id`, `curl`, `python3`, `ssh`. Se mancano: Mac® `brew install libimobiledevice`
   (Homebrew da https://brew.sh), Linux® `sudo apt install libimobiledevice-utils usbmuxd`.
2. **Jailbreak.** Chiedi se i dispositivi sono già sbloccati con OpenSSH e iocaste untether. Se no, guidalo con
   `docs/01-jailbreak.md`: lo fa lui, toccando lo schermo. Non scaricare né ridistribuire file di Apple.
3. **Per ogni dispositivo, in quest'ordine: monitor, controller, Pocket** (salta quelli che non ha):
   - chiedi di collegare **solo quel dispositivo**, sbloccarlo e toccare «Autorizza» se compare;
   - verifica con `idevice_id -l` che ce ne sia uno solo;
   - esegui `./aggiorna.sh <app>`. La prima volta crea la chiave SSH e installa la chiave sul dispositivo:
     **avvisa prima** che comparirà una finestra di macOS® (su Linux una richiesta nel terminale) in cui lui scrive
     la password di root, predefinita `alpine`. **Non scrivere mai tu la password** e non chiederla in chat;
   - controlla che finisca con `OK: … aggiornato a v…`, poi chiedi di scollegarlo.
4. **Collegamento.** Spiega: sul monitor tocca (i) e leggi il PIN; nel controller o nel Pocket tocca il monitor
   nell'elenco e scrivi il PIN. Wi-Fi® e Bluetooth® accesi su entrambi, nessuna rete necessaria. Per la regia web
   (solo da computer, mai da telefono o tablet): computer sulla stessa rete Wi-Fi del monitor, indirizzo in (i), poi il PIN.
5. Alla fine riassumi e indica `docs/05-aggiornamenti.md`: da qui in poi le versioni nuove arrivano dalla regia web, dal computer.

Se c'è anche il saturimetro (https://github.com/Franz8787/similfranz-saturimetro), clonalo in una cartella accanto
e segui il suo `CLAUDE.md`: è un iPod touch 4 e non chiede password.

Errori frequenti di `aggiorna.sh`: vedi la tabella «Se qualcosa non va» in `docs/02-installazione.md`.
Con due dispositivi collegati per forza: `SIMILFRANZ_UDID=<udid> ./aggiorna.sh …`.

## Regole

- Jailbreak e gesti sui dispositivi li fa l'utente. Le password le scrive solo lui.
- Non disattivare processi di sistema e non usare "Inizializza contenuto e impostazioni" su un dispositivo con jailbreak.
  Per fare spazio c'è `monitor/scripts/pulizia.sh` (cancella solo app e risorse inutili): proponilo, non eseguirlo senza un sì.
- Non presentare mai il progetto come dispositivo medico.
- I layout devono restare originali: nessun nome, logo o frontale di dispositivi in commercio.
- Per modificare il codice: `docs/sviluppo.md`. Test di logica sul Mac `monitor/scripts/test-mac.sh`: devono passare
  tutti prima di reinstallare.
