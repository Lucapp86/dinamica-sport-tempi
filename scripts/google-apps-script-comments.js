/**
 * =========================================================================
 * GOOGLE APPS SCRIPT · BACKEND COMMENTI TECNICI DINAMICA SPORT
 * =========================================================================
 * Questo script gratuito si collega a un Google Sheet per salvare,
 * aggiornare e sincronizzare in tempo reale i commenti tecnici inseriti
 * dagli allenatori da smartphone o PC a bordo vasca.
 *
 * GUIDA DI INSTALLAZIONE (Richiede 2 minuti - 100% Gratuito):
 * 1. Apri Google Drive (https://drive.google.com/) e crea un nuovo "Foglio Google".
 * 2. Chiama il foglio ad esempio "Dinamica Sport - Commenti Coach".
 * 3. Rinomina la scheda in basso con "Commenti" (o lascia Foglio1).
 * 4. Nella prima riga inserisci le intestazioni di colonna:
 *    A1: Id | B1: AtletaId | C1: Atleta | D1: Data | E1: Gara | F1: Commento | G1: Allenatore | H1: DataAggiornamento
 * 5. Dal menu in alto del foglio clicca: Estensioni -> Apps Script.
 * 6. Cancella eventuale codice presente, incolla tutto questo file e clicca Salva (icona dischetto).
 * 7. In alto a destra clicca: Distribuisci -> Nuova distribuzione.
 * 8. Clicca sull'icona a ingranaggio -> seleziona "Applicazione web".
 * 9. Imposta:
 *    - Descrizione: "API Commenti Dinamica Sport"
 *    - Esegui come: "Utente corrente (tua-email)"
 *    - Chi può accedere: "Chiunque" (importante per permettere alla Web App di salvare i dati)
 * 10. Clicca "Distribuisci" e copia l'URL dell'applicazione web (termina con /exec).
 * 11. Incolla questo URL nel file "config.team.json" alla voce "commentsApiUrl":
 *     "commentsApiUrl": "https://script.google.com/macros/s/XXXXX/exec"
 * =========================================================================
 */

function setupSheet() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Commenti') || ss.getActiveSheet();
  sheet.setName('Commenti');

  if (sheet.getLastRow() === 0) {
    sheet.appendRow([
      'Id',
      'AtletaId',
      'Atleta',
      'Data',
      'Gara',
      'Commento',
      'Allenatore',
      'DataAggiornamento'
    ]);
    sheet.getRange(1, 1, 1, 8).setFontWeight('bold').setBackground('#e0f2fe');
    sheet.setFrozenRows(1);
  }
}

function doGet(e) {
  try {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName('Commenti') || ss.getActiveSheet();
    var rows = sheet.getDataRange().getValues();

    if (rows.length <= 1) {
      return ContentService.createTextOutput(JSON.stringify({ comments: [] }))
        .setMimeType(ContentService.MimeType.JSON);
    }

    var headers = rows[0].map(function (h) {
      return String(h).toLowerCase().trim();
    });

    var colId = headers.indexOf('id');
    var colAid = headers.indexOf('atletaid');
    var colName = headers.indexOf('atleta');
    var colDate = headers.indexOf('data');
    var colEvent = headers.indexOf('gara');
    var colText = headers.indexOf('commento');
    var colAuthor = headers.indexOf('allenatore');
    var colUpdated = headers.indexOf('dataaggiornamento');

    var comments = [];
    for (var i = 1; i < rows.length; i++) {
      var r = rows[i];
      var text = colText >= 0 ? String(r[colText]).trim() : '';
      if (!text) continue;

      var dt = colDate >= 0 ? r[colDate] : '';
      var isoDate = '';
      if (dt instanceof Date) {
        isoDate = Utilities.formatDate(dt, Session.getScriptTimeZone(), 'yyyy-MM-dd');
      } else {
        isoDate = String(dt).trim();
      }

      comments.push({
        id: colId >= 0 ? String(r[colId]) : 'c_' + i,
        athleteId: colAid >= 0 ? String(r[colAid]) : '',
        athleteName: colName >= 0 ? String(r[colName]) : '',
        date: isoDate,
        event: colEvent >= 0 ? String(r[colEvent]) : '',
        text: text,
        author: colAuthor >= 0 ? String(r[colAuthor]) : 'Coach',
        updatedAt: colUpdated >= 0 ? String(r[colUpdated]) : new Date().toISOString()
      });
    }

    return ContentService.createTextOutput(JSON.stringify({ comments: comments }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({ error: err.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

function doPost(e) {
  var lock = LockService.getScriptLock();
  lock.tryLock(10000);

  try {
    setupSheet();
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var sheet = ss.getSheetByName('Commenti') || ss.getActiveSheet();

    var payload = {};
    if (e && e.postData && e.postData.contents) {
      payload = JSON.parse(e.postData.contents);
    } else if (e && e.parameter) {
      payload = e.parameter;
    }

    var action = payload.action || 'save';
    var c = payload.comment || payload;
    if (!c || !c.text && action !== 'delete') {
      return ContentService.createTextOutput(JSON.stringify({ success: false, message: 'Dati mancanti' }))
        .setMimeType(ContentService.MimeType.JSON);
    }

    var id = String(c.id || '');
    var athleteId = String(c.athleteId || '');
    var athleteName = String(c.athleteName || '');
    var date = String(c.date || '');
    var event = String(c.event || '');
    var text = String(c.text || '');
    var author = String(c.author || 'Coach');
    var updatedAt = String(c.updatedAt || new Date().toISOString());

    var rows = sheet.getDataRange().getValues();
    var foundRowIdx = -1;

    for (var i = 1; i < rows.length; i++) {
      var rId = String(rows[i][0]);
      var rAid = String(rows[i][1]);
      var rDate = String(rows[i][3]);
      var rEvent = String(rows[i][4]);

      if (id && rId === id) {
        foundRowIdx = i + 1;
        break;
      }
      if (athleteId && rAid === athleteId && date && rDate === date && event && rEvent === event) {
        foundRowIdx = i + 1;
        break;
      }
    }

    if (action === 'delete') {
      if (foundRowIdx > 0) {
        sheet.deleteRow(foundRowIdx);
      }
      return ContentService.createTextOutput(JSON.stringify({ success: true, action: 'deleted' }))
        .setMimeType(ContentService.MimeType.JSON);
    }

    if (foundRowIdx > 0) {
      // Aggiorna riga esistente
      sheet.getRange(foundRowIdx, 1, 1, 8).setValues([[
        id,
        athleteId,
        athleteName,
        date,
        event,
        text,
        author,
        updatedAt
      ]]);
    } else {
      // Nuova riga
      sheet.appendRow([
        id,
        athleteId,
        athleteName,
        date,
        event,
        text,
        author,
        updatedAt
      ]);
    }

    return ContentService.createTextOutput(JSON.stringify({ success: true, action: 'saved', id: id }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({ success: false, error: err.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  } finally {
    lock.releaseLock();
  }
}
