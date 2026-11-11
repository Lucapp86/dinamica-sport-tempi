Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
. (Join-Path $scriptDir "update_results.ps1")

$script:passed = 0
$script:failed = 0

function Assert-Equal([string]$Name, $Actual, $Expected) {
    if ($Actual -eq $Expected) {
        $script:passed++
    } else {
        $script:failed++
        Write-Host "[FAIL] $Name : atteso '$Expected', ottenuto '$Actual'" -ForegroundColor Red
    }
}

function Assert-True([string]$Name, [bool]$Condition) {
    if ($Condition) {
        $script:passed++
    } else {
        $script:failed++
        Write-Host "[FAIL] $Name : condizione falsa" -ForegroundColor Red
    }
}

# 1. Test parsing tempi
$t1 = Parse-SwimTime "00'54.50"
Assert-Equal "Tempo 00'54.50 cs" $t1.timeCs 5450
Assert-Equal "Tempo 00'54.50 fmt" $t1.formatted "00'54.50"

$t2 = Parse-SwimTime "01'20.50"
Assert-Equal "Tempo 01'20.50 cs" $t2.timeCs 8050
Assert-Equal "Tempo 01'20.50 fmt" $t2.formatted "01'20.50"

$t3 = Parse-SwimTime "1:05.3"
Assert-Equal "Tempo 1:05.3 cs" $t3.timeCs 6530
Assert-Equal "Tempo 1:05.3 fmt" $t3.formatted "01'05.30"

$t4 = Parse-SwimTime "34.50"
Assert-Equal "Tempo 34.50 cs" $t4.timeCs 3450
Assert-Equal "Tempo 34.50 fmt" $t4.formatted "00'34.50"

$t5 = Parse-SwimTime "1.05.32"
Assert-Equal "Tempo 1.05.32 cs" $t5.timeCs 6532
Assert-Equal "Tempo 1.05.32 fmt" $t5.formatted "01'05.32"

$t6 = Parse-SwimTime "S.T."
Assert-Equal "Tempo S.T. status" $t6.status "ST"
Assert-True "Tempo S.T. null cs" ($null -eq $t6.timeCs)

$t7 = Parse-SwimTime "SQ"
Assert-Equal "Tempo SQ status" $t7.status "SQ"
Assert-True "Tempo SQ null cs" ($null -eq $t7.timeCs)

# 2. Test categorie e sesso
$dot = [string][char]0x00B7
$c1 = Normalize-CategoryAndGender "Sessione 1 $dot Femmine $dot Esordienti B/F"
Assert-Equal "Cat Esordienti B" $c1.category "Esordienti B"
Assert-Equal "Gen F" $c1.gender "F"

$c2 = Normalize-CategoryAndGender "Sessione 2 $dot Maschi $dot Ragazzi/M"
Assert-Equal "Cat Ragazzi" $c2.category "Ragazzi"
Assert-Equal "Gen M" $c2.gender "M"

$c3 = Normalize-CategoryAndGender "Sessione 3 $dot Mista/Open $dot MASTER_M"
Assert-Equal "Cat Master" $c3.category "Master"
Assert-Equal "Gen Mista" $c3.gender "Mista"

# 3. Test normalizzazione nome gara e staffette
Assert-Equal "Evento 50 dorso" (Normalize-EventName "Gara 1 $([char]0x2014) 50 m Dorso") "50 m Dorso"
Assert-Equal "Evento 100 misti" (Normalize-EventName "Gara 12 - 100m Misti") "100 m Misti"
Assert-Equal "Evento 50 stile senza m" (Normalize-EventName "50 Stile Libero") "50 m Stile libero"
Assert-Equal "Staffetta 200 misti -> 4x50" (Normalize-RelayEventName "Gara 24 $([char]0x2014) 200 m Misti" "M") "Staffetta 4x50 m Misti"
Assert-Equal "Mistaffetta 200 misti -> 4x50" (Normalize-RelayEventName "Gara 61 $([char]0x2014) 200 m Misti" "Mista") "Mistaffetta 4x50 m Misti"
$form1 = Parse-RelayFormation "Dinamica Sport s.s.d. a r.l. $([char]0x2014) A 1. CAPUZZI LORENZO / 2. ZINI ANTONIO / 3. CARRARA LEONARDO / 4. MICHIELIN RICCARDO Esordienti A/M"
Assert-Equal "Formazione staffetta 4 frazionisti" $form1.swimmers.Count 4
Assert-Equal "Frazionista 1" $form1.swimmers[0] "Capuzzi Lorenzo"

# 4. Test parsing HTML risultati simulati (incluso Pos., societa accentata, SQ e staffetta)
$sampleHtml = @"
<div class="slm-card">
  <div class="slm-event-title"><div><p class="slm-eyebrow">Manifestazione</p><h2>I TAPPA - TROFEO FILIPPA</h2></div></div>
  <div class="slm-public-meta"><span class="slm-public-pill">15/11/2026</span><span class="slm-public-pill">Pinerolo</span><span class="slm-public-pill">Vasca 25m</span></div>
  <section class="slm-public-event">
    <div class="slm-event-title"><h2>Gara 17 $([char]0x2014) 50 m Stile libero</h2><span class="slm-muted">Sessione 1 $([char]0x00B7) Femmine $([char]0x00B7) Esordienti B/F</span></div>
    <table class="slm-table">
      <thead><tr><th>Pos.</th><th>Atleta</th><th>Anno</th><th>Societ$([char]0x00E0)</th><th>Tessera</th><th>Tempo</th><th>Punti</th></tr></thead>
      <tbody>
        <tr><td>1</td><td><strong>PIANA GINEVRA</strong></td><td>2017</td><td>Dinamica Sport s.s.d. a r.l.</td><td>270512691</td><td>00'41.20</td><td>10</td></tr>
        <tr><td>2</td><td><strong>ALTRA ATLETA</strong></td><td>2017</td><td>Altra Societa ASD</td><td>999999999</td><td>00'42.00</td><td>8</td></tr>
        <tr><td>-</td><td><strong>MAZZARA' LUDOVICA</strong></td><td>2017</td><td>Dinamica Sport s.s.d. a r.l.</td><td>270512685</td><td>SQ</td><td>0</td></tr>
      </tbody>
    </table>
  </section>
  <section class="slm-public-event">
    <div class="slm-event-title"><h2>Gara 24 $([char]0x2014) 4x50 m Mista</h2><span class="slm-muted">Sessione 1 $([char]0x00B7) Maschi $([char]0x00B7) Esordienti A/M</span></div>
    <table class="slm-table">
      <thead><tr><th>Pos.</th><th>Atleta</th><th>Anno</th><th>Societ$([char]0x00E0)</th><th>Tessera</th><th>Tempo</th></tr></thead>
      <tbody>
        <tr><td>1</td><td>Dinamica Sport s.s.d. a r.l. - A 1. CAPUZZI / 2. ZINI / 3. CARRARA / 4. MICHIELIN</td><td>-</td><td>Dinamica Sport s.s.d. a r.l.</td><td>-</td><td>02'15.40</td></tr>
      </tbody>
    </table>
  </section>
</div>
"@

$parsed = Parse-SlmPage $sampleHtml "official" "dinamica\s+sport" "25m" @{} "https://nuotopiemonte-uisp.it/risultati-uisp/?meet_id=24"
Assert-Equal "Record individuali estratti" $parsed.Records.Count 2
Assert-Equal "Staffette estratte" $parsed.Relays.Count 1
Assert-Equal "Tempo Piana Ginevra" $parsed.Records[0].time "00'41.20"
Assert-Equal "Posizione Piana Ginevra" $parsed.Records[0].position "1"
Assert-Equal "Status Mazzara SQ" $parsed.Records[1].status "SQ"
Assert-Equal "Categoria staffetta" $parsed.Relays[0].category "Esordienti A"
Assert-Equal "Nome gara staffetta normalizzato" $parsed.Relays[0].event "Staffetta 4x50 m Mista"
Assert-Equal "Frazionisti staffetta da HTML" $parsed.Relays[0].swimmers.Count 4

# 5. Test merge + deduplicazione + preferenza categoria + array JSON singolo elemento
$cfg = Read-Utf8File (Join-Path $rootDir "config.team.json") | ConvertFrom-Json
$singleCsv = @"
Atleta;Anno;Sesso;Categoria;Tessera;Data;Manifestazione;Luogo;Vasca;Gara;Tempo;Posizione;Note
PIANA GINEVRA;2017;F;Esordienti B;270512691;2026-11-15;I TAPPA - TROFEO FILIPPA;Pinerolo;25m;50 m Stile libero;00'41.20;1;Duplicato
"@
$manualParsed = @(Parse-ManualCsv $singleCsv "25m" $cfg.clubName)
Assert-Equal "CSV manuale parsato" $manualParsed.Count 1

$multiCsv = @"
Atleta;Anno;Sesso;Categoria;Tessera;Data;Manifestazione;Luogo;Vasca;Gara;Tempo;Posizione;Note
PIANA GINEVRA;2017;F;Esordienti B;270512691;2026-06-12;Riccione;Riccione;25m;50 m Dorso;00'52.21;39;
BORZILLO GREGORIO;2016;M;Esordienti B;270512667;2026-06-13;Riccione;Riccione;25m;100 m Misti;01'51.73;57;
"@
$multiParsed = @(Parse-ManualCsv $multiCsv "25m" $cfg.clubName "historical")
Assert-Equal "CSV multi-riga parsato" $multiParsed.Count 2
Assert-Equal "CSV multi-riga sourceType" $multiParsed[0].sourceType "historical"

$ds = Build-Dataset @($parsed.Records[0]) $manualParsed @() @($parsed.Relays[0]) $cfg
Assert-Equal "Deduplicazione risultati identici" $ds.results.Count 1
Assert-Equal "Atleti unificati" $ds.athletes.Count 1

$jsonString = $ds | ConvertTo-Json -Depth 10 -Compress
Assert-True "JSON array singolo atleta rimane array" ($jsonString -match '"athletes":\[\{')
Assert-True "JSON array singolo risultato rimane array" ($jsonString -match '"results":\[\{')

# 6. Test cifratura e decifratura AES-256-CBC + HMAC-SHA256
$testPw = "Dinamica#2026!"
$env = Encrypt-DatasetJson $jsonString $testPw 10000
$decrypted = Decrypt-DatasetJson $env $testPw
Assert-Equal "Round-trip cifratura/decifratura" $decrypted $jsonString

$wrongFailed = $false
try {
    [void](Decrypt-DatasetJson $env "password-sbagliata")
} catch {
    $wrongFailed = $true
}
Assert-True "Password errata rifiutata con HMAC" $wrongFailed

Write-Host ""
Write-Host ("Risultato test: {0} passati, {1} falliti." -f $script:passed, $script:failed)
if ($script:failed -gt 0) { exit 1 }
