# Dinamica Sport — Portale Tempi, Personal Best & Grafici

Web app gratuita e responsive (PC e smartphone) dedicata alla società **Dinamica Sport s.s.d. a r.l.** per raccogliere automaticamente i tempi dalle gare pubblicate su [`nuotopiemonte-uisp.it`](https://nuotopiemonte-uisp.it/), dividere gli atleti per categoria, evidenziare i **Personal Best (PB)** e mostrare i grafici dell'andamento nel tempo.

Tutti i dati sono **cifrati (AES-256 + HMAC-SHA256)** con la **password di squadra**, quindi i nominativi e i tempi restano privati anche su hosting gratuito.

---

## 1. Provala subito sul tuo PC Windows

1. Fai doppio clic su **`avvia-app.bat`**.
2. Si aprirà il browser su `http://127.0.0.1:8765`.
3. Inserisci la password iniziale di esempio: **`dinamica2026`** *(consigliato cambiarla subito, vedi punto 2)*.
4. Potrai subito esplorare atleti divisi per categoria, **Personal Best**, grafici temporali, classifiche di squadra e **staffette**.

---

## 2. Aggiornare i dati e cambiare la password di squadra

* Fai doppio clic su **`aggiorna-dati.bat`**.
* Scrivi la **nuova password di squadra** (che darai agli atleti e alle famiglie) e premi Invio.
* Lo script si collega a `nuotopiemonte-uisp.it`, scarica startlist e risultati ufficiali per `Dinamica Sport s.s.d. a r.l.`, aggiorna le categorie (`Esordienti B`, `Esordienti A`, `Ragazzi`, `Juniores`, `Assoluti`, `Master`) e rigenera il file cifrato `data/team-data.enc.json`.

---

## 3. Pubblicarla gratis online (PC + Smartphone + Aggiornamento automatico)

Con un account **GitHub gratuito**:

1. Crea un nuovo repository **pubblico** su GitHub (es. `dinamica-sport-tempi`) e carica tutti i file di questa cartella (il file `data/team-data.enc.json` è cifrato, e `.gitignore` protegge eventuali file locali in chiaro).
2. Attiva **GitHub Pages** (gratuita):
   * Vai su **Settings → Pages**.
   * In *Source* scegli **Deploy from a branch**, branch **`main`** e cartella **`/ (root)`**, poi salva.
   * Dopo 1–2 minuti avrai il link pubblico da condividere con te e con i tuoi atleti (es. `https://tuoutente.github.io/dinamica-sport-tempi/`). Su iPhone e Android possono fare *"Aggiungi a schermata Home"* per usarla come un'app!
3. Configura l'**aggiornamento automatico gratuito** (GitHub Actions):
   * Vai su **Settings → Secrets and variables → Actions → New repository secret**.
   * Crea il secret **`TEAM_PASSWORD`** inserendo la tua password di squadra.
   * Vai nella scheda **Actions** del repository e abilita i workflow.
   * Da quel momento il sistema controlla `nuotopiemonte-uisp.it` in automatico **ogni domenica sera e lunedì mattina**, oppure puoi avviarlo manualmente con un clic su **Run workflow** (anche dal telefono!).

---

## 4. Aggiungere gare extra o tempi storici (opzionale)

Se vuoi aggiungere tempi di gare fuori dal portale UISP o di stagioni passate:

* **In locale su PC:** copia `data/manual_results.sample.csv` in `data/manual_results.csv`, aggiungi le righe (anche usando il generatore nella scheda **Strumenti Coach** della web app) e lancia **`aggiorna-dati.bat`**.
* **Da smartphone (senza PC) con Google Fogli:** crea un Google Sheet con le stesse colonne di `data/manual_results.sample.csv`, fai **File → Condividi → Pubblica sul web → CSV** e salva quell'URL segreto su GitHub in **Settings → Secrets → Actions** come secret **`MANUAL_CSV_URL`**. Ogni volta che aggiorni il foglio dal telefono e lanci il workflow su GitHub, i tempi entrano nell'app cifrata.

