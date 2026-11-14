# 2 · Installa da zero

Dalla scatola al monitor acceso, un dispositivo alla volta. Ti serve un computer (Mac® o Linux®) **solo questa
volta**, con il cavo: dopo, gli aggiornamenti arrivano senza cavi, dalla regia web ([Aggiorna](05-aggiornamenti.md)).
Non serve Xcode®, non serve un account sviluppatore, non devi compilare nulla.

**Tempo:** circa 20 minuti per il primo dispositivo e 5 per gli altri, jailbreak escluso.

## Che cosa ti serve

| Dispositivo | App | Obbligatorio? |
|---|---|---|
| iPad mini® 1ª gen. (iOS 9.3.5 o 9.3.6) | **similFranz Monitor**, il monitor-defibrillatore | sì |
| un secondo iPad mini 1 | **similFranz Controller**, la regia | no: in alternativa la regia è una pagina web |
| iPod touch® 5ª gen. (iOS 9.3.5) | **similFranz Pocket**, la regia tascabile | no |

Più un computer Mac o Linux con internet e il cavo Lightning di ciascun dispositivo.

**Preferisci farlo fare a qualcun altro?** Con [Claude Code](06-claude-code.md) basta il link del progetto: lui
esegue i comandi e ti dice quando collegare, sbloccare o toccare.

## Passo 1 · Sblocca ogni dispositivo (una volta sola)

Segui [Sblocca l'iPad®](01-jailbreak.md) su ogni iPad e sull'iPod®: jailbreak, **OpenSSH** e **iocaste untether**
da Cydia. Lo fai tu, dal browser del dispositivo.

**Controllo:** è andata se, dopo un riavvio, l'icona di Cydia si apre ancora.

## Passo 2 · Prepara il computer (una volta sola)

Apri il **Terminale** e scrivi:

- **Mac**: installa prima [Homebrew](https://brew.sh) (una riga da copiare dal sito), poi
  ```bash
  brew install libimobiledevice
  ```
- **Linux** (Ubuntu, Debian…):
  ```bash
  sudo apt install libimobiledevice-utils usbmuxd curl python3 openssh-client
  ```

Poi scarica il progetto: su GitHub® pulsante verde **Code › Download ZIP**, scompatta la cartella ed entraci
dal Terminale (scrivi `cd `, trascina la cartella nella finestra, premi Invio).

**Controllo:** è andata se `idevice_id -l` risponde senza errori (anche senza dispositivi collegati).

## Passo 3 · Installa le app: un comando per dispositivo

Collega **un dispositivo alla volta** con il cavo e sbloccalo. Se sul dispositivo compare «Autorizzare questo
computer?», tocca **Autorizza**. Poi, a seconda del dispositivo collegato:

```bash
./aggiorna.sh monitor       # l'iPad del monitor
./aggiorna.sh controller    # l'iPad della regia
./aggiorna.sh pocket        # l'iPod touch
```

Lo script scarica da GitHub l'ultima versione pubblicata e la installa. **La prima volta su ogni dispositivo**
ti chiede la sua password di root: è quella predefinita dopo il jailbreak, **`alpine`** (sul Mac la scrivi in una
finestra, su Linux nel Terminale). Da lì in poi non la chiede più.

**Controllo:** è andata se lo script finisce con `OK: … aggiornato a v…` e l'app si apre da sola sul dispositivo.

> Sicurezza: `alpine` la conoscono tutti. Se il dispositivo resta su reti condivise, cambiala: con il dispositivo
> collegato scrivi `monitor/scripts/ssh.sh` (o `controller/…`, `pocket/…`), poi `passwd`, scegli una password tua
> e chiudi con `exit`. Gli script continuano a funzionare: usano la chiave, non la password.

## Passo 4 · Collega la regia al monitor (una volta sola)

1. Sul monitor tocca **(i)**: si apre «Collegamento del controller», con il **PIN** a sei cifre.
2. Apri similFranz Controller o similFranz Pocket: il monitor compare nell'elenco. Toccalo e scrivi il PIN.
3. Dalla volta dopo si ritrovano da soli. Non serve nessuna rete: basta Wi-Fi® e Bluetooth® accesi su entrambi.

Per la regia web, solo dal computer: in **(i)** leggi l'indirizzo e scrivilo nel browser del computer, collegato alla
stessa rete Wi-Fi del monitor. Tutti i dettagli in [Le regie e come si collegano](03-uso.md#le-regie-e-come-si-collegano).

**Controllo:** è andata se nella regia compare in verde il nome del monitor e, cambiando un valore, il monitor risponde.

## Se qualcosa non va

| Messaggio | Che cosa fare |
|---|---|
| `manca iproxy` (o `idevice_id`) | ripeti il passo 2 |
| `nessun dispositivo collegato` | cavo inserito, schermo sbloccato, «Autorizza» toccato. Prova un altro cavo o un'altra porta |
| `sono collegati 2 dispositivi` | scollega quelli che non stai installando |
| `chiave non installata` | password sbagliata (`alpine`, minuscolo) oppure manca OpenSSH: installalo da Cydia |
| `nessuna versione pubblicata` | il computer non ha internet, oppure la copia del progetto non ha ancora una *Release* |
| l'app non compare | riavvia il dispositivo: se Cydia non si apre più, l'untether manca (passo 1) |

## Più spazio sull'iPad (facoltativo)

Un iPad mini 1 ha la partizione di sistema quasi piena. `monitor/scripts/pulizia.sh` elimina le app di serie
che non servono e alcune risorse inutilizzate (lingue, dizionari). **Cancella soltanto, non disattiva nessun
processo**: per riavere quei file serve un ripristino dal Finder®.

Pronto? Vai a [Porta lo scenario in sala](03-uso.md). Per le versioni nuove: [Aggiorna](05-aggiornamenti.md).
