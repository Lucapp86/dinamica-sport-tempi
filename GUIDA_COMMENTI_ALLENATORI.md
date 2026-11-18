# Guida per gli Allenatori · Inserimento Commenti Tecnici alle Gare

Questa funzionalità permette agli allenatori della **Dinamica Sport** di inserire un breve commento tecnico (es. feedback su partenza, virata, bracciata, passaggi o gestione gara) direttamente sotto ciascun risultato di gara.

---

## 1. Come Accedere in Modalità Allenatore

Hai due modi semplici per accedere come allenatore, sia da **smartphone** che da **computer**:

### Opzione A: Dalla schermata iniziale di accesso (Login)
1. Tocca la scheda **⏱️ Allenatore** in cima al modulo di login.
2. Inserisci la **Password di squadra** e il **PIN Allenatore** (PIN impostato: `0286`).
3. Clicca su **Accedi come Allenatore**.
4. L'applicazione si aprirà direttamente con i permessi di scrittura e modifica abilitati.

### Opzione B: Direttamente dall'interno dell'app
Se sei già entrato come genitore/atleta:
1. In alto a destra nella barra superiore tocca il pulsante **⏱️ Accesso Coach**.
2. Digita il PIN `0286` e tocca **Attiva Modalità Coach**.
3. Il pulsante diventerà verde con la dicitura **⏱️ Coach Attivo ✓**.

> [!TIP]
> Il PIN `0286` può essere modificato a piacimento nel file `config.team.json` alla voce `"coachPin"`.

---

## 2. Come Inserire o Modificare un Commento

1. Dalla sezione **Atleti & Categorie**, cerca e apri la scheda dell'atleta interessato.
2. Nella tabella **Storico Risultati**, sotto ciascuna gara comparirà:
   - Se la gara non ha ancora un commento: il pulsante **💬 + Aggiungi commento tecnico Coach**.
   - Se è già presente un commento: il box con il testo, l'autore e il pulsante **✏️ Modifica**.
3. Cliccando sul pulsante si apre una finestra dedicata in cui puoi:
   - Modificare il nome dell'autore (es. *Coach Luca*). Viene ricordato automaticamente per i commenti successivi.
   - Usare i bottoni di inserimento rapido: `[Partenza]`, `[Virata]`, `[Subacquea]`, `[Passaggio]`, `[Frequenza]`, `[Arrivo]`.
   - Scrivere il feedback tecnico per l'atleta.
   - Cliccare su **Salva Commento** (oppure **Elimina** se desideri cancellarlo).

---

## 3. Come Vengono Salvati i Dati

Il sistema è progettato per funzionare in **3 livelli**, senza alcun costo di server o hosting:

1. **Salvataggio Istantaneo Locale (`localStorage`):**
   - Appena salvi un commento dallo smartphone, viene memorizzato istantaneamente sul dispositivo. Anche se sei in piscina senza segnale o connessione internet, il commento non andrà mai perso.
2. **Esportazione in 1 Click (`commenti.csv`):**
   - In modalità Coach, toccando il pulsante **⏱️ Coach Attivo ✓** puoi cliccare su **OK** per scaricare un file `commenti_dinamica_DATA.csv`.
   - Puoi copiare questo file nella cartella `data/` del tuo PC e rinominarlo in `commenti.csv`. Quando fai doppio click su `aggiorna-dati.bat`, tutti i commenti vengono cifrati in modo permanente nel dataset ufficiale `team-data.enc.json` visibile a tutti gli atleti!
3. **Sincronizzazione Cloud Automatica (100% Gratuita con Google Sheets):**
   - Se vuoi che i commenti inseriti da uno smartphone siano visibili immediatamente anche sugli smartphone degli altri allenatori e degli atleti senza dover passare dal PC, basta collegare un foglio Google gratuito in 2 minuti (vedi sotto).

---

## 4. Come Attivare la Sincronizzazione Cloud Automatica (Opzionale)

Se desideri che ogni commento salvato da cellulare si sincronizzi all'istante su un Foglio Google condiviso:

1. Apri [Google Drive](https://drive.google.com/) e crea un nuovo **Foglio Google** (es. chiamalo *Dinamica Sport - Commenti Coach*).
2. Nel menu in alto del foglio clicca su **Estensioni** -> **Apps Script**.
3. Cancella tutto il codice preesistente e incolla il contenuto del file [`scripts/google-apps-script-comments.js`](file:///c:/Users/lucaz/Desktop/Gare%20atleti/scripts/google-apps-script-comments.js).
4. Clicca su **Salva** (icona dischetto).
5. In alto a destra clicca su **Distribuisci** -> **Nuova distribuzione**.
6. Clicca sull'icona a ingranaggio -> seleziona **Applicazione web**.
7. Compila così:
   - **Descrizione:** *API Commenti Dinamica Sport*
   - **Esegui come:** *Utente corrente (tua email Google)*
   - **Chi può accedere:** *Chiunque*
8. Clicca su **Distribuisci**, autorizza l'accesso con il tuo account Google e **copia l'URL** generato (termina con `/exec`).
9. Apri il file `config.team.json` sul PC e incolla l'URL alla voce `commentsApiUrl`:
   ```json
   "commentsApiUrl": "https://script.google.com/macros/s/AKfycb.../exec"
   ```
10. Esegui `aggiorna-dati.bat` una volta per pubblicare l'aggiornamento. Da quel momento, ogni commento inserito da cellulare si salverà in tempo reale sia sul cellulare sia nel Foglio Google!
