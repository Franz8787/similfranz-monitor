# 5 · Aggiorna

Quando esce una versione nuova non servono cavi. Il **computer** la scarica da GitHub® e, attraverso la regia web,
la passa al monitor. Il **monitor** la tiene anche per controller e Pocket e gliela consegna al loro prossimo collegamento.

```
GitHub ──internet──▶ computer ──Wi-Fi──▶ monitor ──collegamento diretto──▶ controller e Pocket
```

Perché passa dal computer? iPad® e iPod così vecchi non riescono più ad aprire le connessioni sicure di GitHub.
Il computer sì, e fa da ponte.

## Aggiorna il monitor, dal computer (1 minuto)

1. Computer e monitor sulla **stessa rete Wi-Fi®**, e quella rete deve avere **internet**.
2. Apri la regia web nel browser del computer: l'indirizzo è sul monitor, nel tasto **(i)**. Poi il PIN.
3. Tocca la scheda **Monitor** e scorri fino al riquadro **Aggiornamento delle app**.
4. Se è uscita una versione nuova la vedi in elenco: clicca **Aggiorna tutto**.
5. Il monitor si chiude e si riapre da solo dopo circa 30 secondi. Alla fine leggi
   **«Fatto: il monitor ora ha la versione …»**.

Lo scenario e il registro non si perdono: restano sul monitor.

## Aggiorna controller e Pocket: tocca «Installa ora»

Non devi fare niente di speciale. Dopo il passo 4, la prima volta che il controller o il Pocket si collegano al
monitor compare:

> **Aggiornamento 0.x.y** · Il monitor ha la versione 0.x.y … **Più tardi** · **Installa ora**

Tocca **Installa ora**. Il pacchetto arriva dal monitor (anche senza nessuna rete), l'app si chiude e si riapre
da sola in meno di un minuto. Se tocchi «Più tardi», te lo ripropone la prossima volta che apri l'app.

**Meglio non farlo durante uno scenario.** L'aggiornamento non tocca il monitor, ma per un minuto la regia è ferma.

## Senza internet in sala

Hai un file `.deb` (lo scarichi dalla pagina **Releases** su GitHub, anche da casa)? Nella stessa scheda
**Aggiornamento delle app** usa **«Oppure carica un pacchetto .deb già scaricato»** e scegli il file. Vale per
monitor, controller e Pocket: quelli di controller e Pocket restano sul monitor, come sopra.

## Dal computer, come la prima volta

Funziona sempre, anche se qualcosa è andato storto: collega il dispositivo con il cavo e
`./aggiorna.sh monitor` (oppure `controller`, `pocket`). Vedi [Installa da zero](02-installazione.md#passo-3--installa-le-app-un-comando-per-dispositivo).

## Se qualcosa non va

| Che cosa vedi | Che cosa fare |
|---|---|
| «Per cercare aggiornamenti questo computer deve avere internet» | la rete del monitor non ha internet: usa il file `.deb` (sopra) |
| «Questo monitor non sa ancora aggiornarsi da solo» | è una versione precedente al sistema di aggiornamento: aggiornalo una volta dal computer |
| «Tutto aggiornato alla versione …» | niente da fare |
| il controller o il Pocket non propongono nulla | chiudi e riapri l'app: il controllo parte quando si collega al monitor |
| l'app non si riapre dopo «Installa ora» | aprila tu: l'aggiornamento è già installato |

## Chi pubblica le versioni nuove

Le pubblica chi cura il progetto, creando una *Release* su GitHub: GitHub compila le tre app e le rende disponibili
a tutti i monitor. Se hai fatto una tua copia del progetto (*fork*), i monitor installati dalla tua copia si aggiornano con
le **tue** versioni: [Per sviluppatori › Fai la tua versione](sviluppo.md#fai-la-tua-versione-senza-mac).
