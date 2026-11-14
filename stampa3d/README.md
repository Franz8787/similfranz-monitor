# Il guscio stampato in 3D

Un guscio da monitor trasportabile attorno all'iPad mini®: maniglia, sportello sul retro per arrivare ai cavi,
tasche per sonde ed elettrodi. Lo schermo è inclinato di 5° all'indietro, il fondo è piatto.

Guida passo passo, con le immagini: [`docs/04-guscio.md`](../docs/04-guscio.md).

## Misure

| | mm |
|---|---|
| Guscio (cornice + scocca) | 250 × 107 × 165 (larghezza × profondità × altezza) |
| Con la maniglia | altezza 202 |
| Con le due tasche laterali | larghezza 372 |
| Con la tasca posteriore | profondità 142 |

La cornice è larga 250 mm: serve un piatto di stampa da almeno 256 × 256 mm.

## I pezzi

| File (`stl/`) | Pezzo | Materiale | Come va sul piatto | Supporti |
|---|---|---|---|---|
| `monitor_cornice_v7.stl` | cornice frontale, con la scritta incisa | PLA bianco | faccia in giù | solo sotto i due fermi a L del fianco sinistro |
| `monitor_scocca_v8.stl` | scocca posteriore | PLA o PETG | retro sul piatto | ad albero, sotto il bordo alto dell'apertura dello sportello |
| `monitor_sportello_v4.stl` | sportello posteriore | PLA o PETG, come la scocca | faccia esterna sul piatto | nessuno |
| `monitor_maniglia_v4.stl` | maniglia | PETG grigio scuro | distesa | nessuno |
| `monitor_pulsante_accensione_v6.stl` | pistoncino del tasto di accensione | PLA o PETG | com'è nel file | nessuno |
| `monitor_tasche_laterali_x2_v8.stl` | le due tasche laterali, con coperchio a cerniera | TPU 95A | coricate, coperchio aperto: sono già orientate | nessuno |
| `monitor_tasca_posteriore_v8.stl` | tasca posteriore, aperta in alto | TPU 95A | in piedi, fondo sul piatto | nessuno |

Gli STL sono già orientati per la stampa. Le impostazioni per il TPU sono in [`STAMPA_TASCHE_TPU.md`](STAMPA_TASCHE_TPU.md).

Il volume non ha un pistoncino: la cornice è chiusa sui due tasti, e si regola da iOS
(Centro di Controllo, oppure AssistiveTouch › Dispositivo › Volume).

## La minuteria

| Quantità | Che cosa | Dove |
|---|---|---|
| 8 | inserti filettati a caldo M3 × 5 × 5 mm | 4 in cima alle colonne d'angolo della scocca, 4 sotto i piedini della maniglia |
| 4 | viti M3 × 16 a testa svasata | cornice sulla scocca, da davanti |
| 4 | viti M3 × 12 | maniglia, dall'interno della scocca |
| 14 | viti M3 × 8 | 8 per le tasche laterali, 6 per la tasca posteriore: testa dentro la scocca |
| 14 | dadi M3 | nelle sedi esagonali delle tasche: il TPU li trattiene |
| 2 | pezzi di graffetta raddrizzata, Ø 1 mm circa, lunghi 25 mm | perni delle cerniere dello sportello |
| 4 | magneti 5 × 2 mm | 2 sullo sportello, 2 sulle battute della scocca |
| qualche | feltrino o gommino adesivo da 1 mm | sulle "dita" della scocca e sotto i fermi che reggono l'iPad® |
| 1 | cavo Lightning con spina a 90° | per tenere l'iPad in carica dentro il guscio |

## Lo script

`sorgenti/monitor_guscio.py` è il modello parametrico: tutte le misure sono in cima al file.
Con [Blender](https://www.blender.org), anche senza aprirlo:

```bash
cd stampa3d/sorgenti
/Applications/Blender.app/Contents/MacOS/Blender --background --python monitor_guscio.py
```

Rigenera tutti i pezzi in `stl/` con il suffisso della versione dello script (`VERSION`).
La scritta incisa (`LABEL_TEXT`) usa un font di sistema macOS® (`LABEL_FONT`): su un altro sistema indica un
font bastone in grassetto che hai installato.

## Licenza

Modelli 3D: [CC BY-NC 4.0](LICENSE).
