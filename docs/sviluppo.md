# Per sviluppatori

## Fai la tua versione (senza Mac®)

GitHub® può compilare le app al posto tuo, su un suo Mac in cloud: è gratis per i progetti pubblici.

1. **Copia il progetto**: in alto su GitHub, **Fork**.
2. **Attiva i due servizi** nella tua copia: scheda **Actions** (*enable workflows*) e **Settings › Pages**
   (*Deploy from a branch*, `main`, cartella `/docs`).
3. **Fai le tue modifiche**, anche dal browser con il tasto ✎ su ogni file.
4. **Alza i numeri di versione** delle app che hai cambiato (riga `Version:` in `monitor/control`,
   `controller/control`, `pocket/control`). Il tag della Release segue la versione del monitor.
5. **Pubblica una Release**: **Releases › Draft a new release**, tag `vX.Y.Z` (= versione del monitor), *Publish*.

Il resto è automatico (`.github/workflows/pubblica.yml`, circa 10 minuti): GitHub prepara l'SDK, esegue i test,
compila le tre app (versione pubblica), allega i `.deb` alla Release e ne mette una copia sulle Pages. I monitor
installati dalla tua copia vedono le nuove versioni nella console: l'app sa da quale repository viene (lo scrive
`build.sh` nel pacchetto), quindi segue le **tue** versioni. Per provare senza pubblicare: **Actions › Pubblica una
versione › Run workflow**, e i `.deb` restano tra gli *artifacts*.

Come funziona l'aggiornamento: la console invia il pacchetto a `POST /api/v1/update`; quello del monitor viene
controllato e passato a `/usr/libexec/similfranz-monitor-aggiorna` (`monitor/helper/aggiorna.c`, setuid root,
installato dal pacchetto: accetta solo il pacchetto della sua app, da un percorso fisso); quelli di controller e
Pocket restano sul monitor, che li serve a pezzi da 32 KB (`GET /api/v1/update/chunk`) sul collegamento diretto.

## Compilare sul tuo computer

App native Objective-C/UIKit per iOS 9 (armv7), compilate dal Mac **senza Xcode®**: bastano i Command Line Tools,
`ldid` e l'SDK di iOS 9.3.

```bash
xcode-select --install
brew install ldid libimobiledevice
monitor/scripts/setup-sdk.sh           # prepara l'SDK in sdk/ (una volta)
```

## Compilare e provare

```bash
cd monitor
./scripts/test-mac.sh                  # test di logica sul Mac (modello, API, scenari, registro)
./scripts/test-api.sh                  # test HTTP su un server di prova sul Mac
./scripts/build.sh && ./scripts/package.sh && ./scripts/install.sh

cd ../controller          # e allo stesso modo ../pocket
./scripts/build.sh && ./scripts/package.sh && ./scripts/install.sh
```

`test-mac.sh` compila anche un **monitor di prova per il Mac** (`build/mac/mac-reference-server`): serve la pagina
web e l'API senza iPad®, utile per lavorare sulla regia dal browser.

## Com'è fatto

```text
monitor/src/      SimulationState (modello del paziente, defibrillatore, transizioni), WaveformEngine, AlarmManager,
                  APIController + LocalHTTPServer (API JSON e pagina web), SFPeerLink (collegamento diretto),
                  SFControl (un controller alla volta), SFScenarioStore (scenari a fasi), SFSessionLog (registro),
                  MonitorViewController (layout ICU) e i layout dei dispositivi
monitor/web-console/   la regia nel browser (HTML/CSS/JS senza dipendenze)
controller/src/   SFLink (collegamento diretto), CtlModel, CtlViewController (regia), costruttore di scenari, debriefing
pocket/src/       regia tascabile per iPod touch: PkDial (la rotella), PkViewController; SFLink e CtlModel come il controller
```

L'API è descritta in [`monitor/docs/NETWORK_AND_API.md`](../monitor/docs/NETWORK_AND_API.md): via HTTP sulla rete,
oppure incapsulata in messaggi sul collegamento diretto. È la stessa per la pagina web e per l'app controller.

## Scrivere un layout

Un layout è una `UIView` che rispetta il protocollo `SFAltLayout` (`monitor/src/AltLayout.h`): riceve lo stato a
ogni aggiornamento, disegna il frontale e traduce i tocchi in comandi del modello (`set_sensor`, `defib_charge`…).
Il motore (tracce, allarmi, defibrillatore, voce) è comune.

1. Copia `ExtraHView.[hm]` e rinomina la classe.
2. Aggiungi l'identificativo e il nome in `SimulationState` (`supportedLayouts`, `layoutCatalog`) e la classe in
   `MonitorViewController` (`applyLayout:`).
3. Dai un nome a ogni tasto (dizionario `_keys`): così lo puoi premere dal Mac con
   `uiopen 'simulafranz-monitor://tap?key=NOME'` e fotografare lo schermo con `shot?name=…`.

Regole che tengono fluido un iPad mini® 1: niente `cornerRadius` con ritaglio sulle viste con contenuto, ogni ombra
con `shadowPath`, niente strati trasparenti sopra le tracce, decorazione fissa appiattita in un'immagine.

**I layout devono restare originali**: nessun nome, logo o frontale di dispositivi in commercio.
