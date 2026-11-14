# Tasche in TPU — impostazioni Bambu Studio (Bambu Lab A1)

File: `stl/monitor_tasche_laterali_x2_v8.stl` — le **due tasche laterali** nello stesso file (la stessa tasca va a destra e a sinistra).
Ogni tasca è un pezzo unico: contenitore + coperchio con cerniera flessibile, già orientato come va sul piatto
(coricato su un'estremità, coperchio aperto a fianco). Ingombro del file: 164 × 120 × 83 mm.

La **tasca posteriore** (`stl/monitor_tasca_posteriore_v8.stl`, 230 × 35 × 70 mm) si stampa in piedi, col fondo sul piatto,
con lo stesso filamento e le stesse impostazioni: non ha cerniera, quindi le voci sulla cerniera non la riguardano.

Valori di partenza presi dalla scheda tecnica ufficiale Bambu del TPU 95A, adattati a questi pezzi.
Le voci segnate con ⚙︎ sono quelle da cambiare rispetto al profilo standard.

---

## 1. Prima di stampare

| Cosa | Come |
|---|---|
| **Filamento** | TPU 95A (Bambu TPU 95A o 95A HF vanno bene). Più morbidi di 95A (90A, 85A) **no**: la cerniera e lo scatto del coperchio sono dimensionati per 95A |
| **Asciugatura** | 70 °C per 8 h (essiccatore o forno ventilato, mai microonde o forno da cucina). Il TPU assorbe umidità in fretta: se fa fili e "sfrigola" è umido |
| **Conservazione** | in sacchetto chiuso con essiccante, umidità < 20 % |
| **Caricamento** | **non nell'AMS lite**. Usa il porta-bobina esterno e carica il filo direttamente nell'estrusore come "bobina esterna" (Ext). Il TPU 95A HF Bambu è dichiarato non compatibile con l'AMS |
| **Piatto** | piatto testurizzato PEI dell'A1 + **colla stick** (un velo). Serve soprattutto come *distaccante*: il TPU si attacca fortissimo e senza colla rischi di rovinare il piatto staccandolo |

---

## 2. Profili da scegliere in Bambu Studio

- **Stampante:** Bambu Lab A1, ugello 0.4
- **Filamento:** *Bambu TPU 95A* (o *Bambu TPU 95A HF*). Se usi TPU di altre marche: *Generic TPU*
- **Processo:** *0.20mm Standard @BBL A1* come base, poi le modifiche sotto

Importa lo STL **senza ruotarlo**: è già nella posizione giusta. Se Bambu Studio chiede "dividere in oggetti?", rispondi **No**.

---

## 3. Impostazioni filamento (TPU)

| Parametro | Valore | Note |
|---|---|---|
| Temperatura ugello | **230 °C** (strato iniziale 230 °C) | intervallo ufficiale 220–240 °C |
| Temperatura piatto (Textured PEI) | **35 °C** (iniziale 35 °C) | intervallo ufficiale 30–35 °C |
| Ventola raffreddamento | **100 %** (min e max) | |
| Velocità volumetrica massima | lascia quella del profilo Bambu | è il "freno" che tiene il TPU lento: non alzarla |
| ⚙︎ Retrazione | **1.0 mm @ 30 mm/s** | ufficiale 0.8–1.4 mm e 20–40 mm/s. Il TPU non ama retrazioni lunghe |
| ⚙︎ Z-hop | **0.2 mm** | riduce i fili senza tirare il materiale |

---

## 4. Impostazioni processo (solo per le tasche)

### Qualità
| Parametro | Valore | Perché |
|---|---|---|
| Altezza strato | 0.20 mm | |
| ⚙︎ Larghezza linea parete esterna | **0.42 mm** | la cerniera (0.8 mm) viene fatta da 2 linee piene |
| ⚙︎ Rileva pareti sottili | **ON** | senza, la cerniera da 0.8 mm può sparire nell'anteprima |
| ⚙︎ Posizione cucitura | **Allineata** o **Dietro** | controlla nell'anteprima che la cucitura **non** cada sulla cerniera |

### Resistenza
| Parametro | Valore | Perché |
|---|---|---|
| ⚙︎ Anelli parete (wall loops) | **6** | pareti da 2.4 mm tutte "piene" di perimetri: più robuste, più flessibili in modo uniforme, a tenuta |
| Strati superiori / inferiori | 4 / 4 | |
| ⚙︎ Riempimento | **15 % giroide** | il riempimento resta solo nel "tetto" interno e nei rinforzi delle viti |

### Velocità
| Parametro | Valore |
|---|---|
| ⚙︎ Parete esterna | **25 mm/s** |
| ⚙︎ Parete interna | **40 mm/s** |
| ⚙︎ Riempimento / superficie superiore | **40 mm/s** |
| Strato iniziale | 20 mm/s |
| Rallenta sugli sbalzi | ON (default) |

Ufficiale: stampa sotto 80 mm/s. In pratica il limite di velocità volumetrica del profilo rallenta già tutto. Queste velocità servono a fare pareti esterne belle e una cerniera senza difetti.

### Supporti e adesione
| Parametro | Valore | Perché |
|---|---|---|
| ⚙︎ Supporti | **OFF** | il pezzo è progettato senza: sbalzi max 45°, ponti max 6 mm (il TPU arriva a ~70° e 20 mm) |
| ⚙︎ Brim | **Esterno, 3 mm** | il coperchio poggia sul piatto solo con un bordo di 2 mm: il brim lo tiene fermo. Si toglie a mano |

### Altro
| Parametro | Valore |
|---|---|
| ⚙︎ Evita di attraversare le pareti | **ON** (meno fili dentro la tasca) |
| Stiratura (ironing) | OFF |

---

## 5. Controllo nell'anteprima (prima di inviare)

1. Scorri gli strati: la **cerniera** (striscia sottile tra dorso e coperchio) deve essere **continua, 2 linee, per tutta l'altezza**.
2. Le **sedi esagonali dei dadi** e i **fori dei cavi** devono vedersi aperti.
3. La cucitura (puntini bianchi) non deve cadere sulla cerniera.
4. Nessun supporto generato.

---

## 6. Dopo la stampa

1. Stacca il pezzo a piatto **tiepido** (non freddo, non caldo). Togli il brim.
2. **Piega il coperchio** 10–15 volte: la cerniera si "ammorbidisce" e lavora meglio.
3. Chiudilo premendo lungo i bordi: lo scatto entra negli ultimi 2–3 mm.
4. **Dadi M3**: spingili nelle sedi esagonali del dorso (4 per ogni tasca laterale, 6 nella tasca posteriore), dall'interno della tasca (aiutati con il retro di un cacciavite). Il TPU li tiene da solo.
5. Montaggio sulla scocca: viti **M3×8** (4 per tasca laterale, 6 per la posteriore), testa dentro la scocca, **prima** di montare la cornice. Stringi solo finché la tasca è ben appoggiata: stringere troppo deforma il TPU.

> Non ricuocere le tasche in forno: Bambu sconsiglia di ricuocere i pezzi in TPU, perché le forme non semplici si deformano.

---

## Se qualcosa va storto

| Problema | Rimedio |
|---|---|
| Fili sottili dentro la tasca | asciuga il filo; prova retrazione 1.2 mm; temperatura −5 °C |
| Superficie a bolle / ruvida | filamento umido → 70 °C per 8 h |
| Il filo si attorciglia nell'estrusore | velocità troppo alta → abbassa del 20 % la velocità volumetrica massima |
| Cerniera bucata / interrotta | attiva "rileva pareti sottili"; larghezza linea 0.42 mm |
| Coperchio troppo duro da chiudere | normale le prime volte; se resta duro carteggia leggermente il bordino |
| Coperchio che si apre da solo | stampa un po' più calda (235 °C) per pareti più compatte, oppure alza lo scatto di 0,2 mm nello script |

Fonte valori: scheda tecnica ufficiale Bambu Lab TPU 95A (V3.0).
