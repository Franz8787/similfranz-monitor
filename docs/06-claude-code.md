# 6 · Fallo fare a Claude Code

Non ti va di usare il Terminale? [Claude Code](https://claude.com/claude-code) è un assistente che lavora sul tuo
computer: gli dai il link del progetto e lui scarica, controlla, installa, e ti dice in italiano quando collegare
un dispositivo, sbloccarlo o toccare qualcosa. Tu fai solo i gesti con le mani.

Il jailbreak resta a te ([Sblocca l'iPad®](01-jailbreak.md)): si fa toccando lo schermo dei dispositivi.

## Una volta sola: installa Claude Code

Segui le istruzioni su [claude.com/claude-code](https://claude.com/claude-code). Serve un account Claude.
Poi apri il **Terminale**, crea una cartella di lavoro ed entra:

```bash
mkdir similfranz && cd similfranz
claude
```

## Il monitor, con controller e Pocket

Scrivi (o incolla) a Claude Code, togliendo i dispositivi che non hai:

> Installa similFranz da https://github.com/Franz8787/similfranz-monitor
> Ho l'iPad del monitor, l'iPad del controller e l'iPod touch® del Pocket, già sbloccati con OpenSSH.
> Guidami un dispositivo alla volta.

Ecco che cosa succede, nell'ordine:

| | Tu | Claude Code |
|---|---|---|
| 1 | — | scarica il progetto, legge le istruzioni in [`CLAUDE.md`](../CLAUDE.md) e controlla gli strumenti; se mancano te li fa installare |
| 2 | colleghi **l'iPad del monitor**, lo sblocchi, tocchi «Autorizza» | controlla che si veda solo quel dispositivo |
| 3 | nella finestra che compare scrivi la password di root (`alpine` se non l'hai cambiata) | installa la chiave, poi `./aggiorna.sh monitor`: il monitor si apre |
| 4 | scolleghi il monitor e colleghi **l'iPad del controller** | stessi passi: `./aggiorna.sh controller` |
| 5 | scolleghi il controller e colleghi **l'iPod touch** | stessi passi: `./aggiorna.sh pocket` |
| 6 | sul monitor tocchi **(i)** e leggi il PIN; nel controller e nel Pocket tocchi il monitor e scrivi il PIN | ti dice che cosa toccare e controlla che il collegamento risponda |

Un dispositivo alla volta: così non si confondono. La password la scrivi sempre tu, Claude Code non la vede.

## Il saturimetro

Il [saturimetro su iPod touch 4](https://github.com/Franz8787/similfranz-saturimetro) è ancora più semplice:
un dispositivo solo, nessuna password da scrivere.

> Installa il saturimetro similFranz da https://github.com/Franz8787/similfranz-saturimetro
> L'iPod touch 4 è collegato e già sbloccato con OpenSSH.

Claude Code lo installa con il cavo e ti dice come aprire la console sul telefono.

## Tutto insieme

Puoi anche chiedere tutto in una volta: monitor, controller, Pocket e saturimetro. Claude Code scarica i due
progetti e ti chiede di collegare i dispositivi uno dopo l'altro. Alla fine il saturimetro si collega al monitor
dal menu dell'iPod® (**Collegamento › Ecosistema monitor**).

## Anche dopo

Claude Code serve anche per il resto: *«il controller non trova il monitor»*, *«aggiorna il Pocket dal computer»*,
*«togli le app inutili dall'iPad del monitor»*. Conosce le regole del progetto: non tocca i processi di sistema
e non cancella mai il dispositivo.
