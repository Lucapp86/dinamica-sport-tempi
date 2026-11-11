<#
.SYNOPSIS
    Aggiorna i dati della squadra Dinamica Sport da nuotopiemonte-uisp.it e da eventuali CSV manuali,
    calcola categorie/tempi/PB e genera il file cifrato data/team-data.enc.json per la Web App.
#>
[CmdletBinding()]
param(
    [string]$Password = $env:TEAM_PASSWORD,
    [string]$ConfigPath = "",
    [string]$ManualCsvPath = "",
    [string]$ManualCsvUrl = $env:MANUAL_CSV_URL,
    [string]$OutputPath = "",
    [string]$PlaintextTestOutput = "",
    [switch]$SkipRemote,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
if (-not $ConfigPath) { $ConfigPath = Join-Path $rootDir "config.team.json" }
if (-not $ManualCsvPath) { $ManualCsvPath = Join-Path (Join-Path $rootDir "data") "manual_results.csv" }
if (-not $OutputPath) { $OutputPath = Join-Path (Join-Path $rootDir "data") "team-data.enc.json" }

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
} catch {}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Read-Utf8File([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-Utf8File([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Fetch-UrlUtf8([string]$Url) {
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $wc.Headers.Add("User-Agent", "DinamicaSport-Tracker/1.0 (+https://nuotopiemonte-uisp.it)")
    try {
        return $wc.DownloadString($Url)
    } finally {
        $wc.Dispose()
    }
}

function Clean-HtmlText([string]$HtmlFragment) {
    if ([string]::IsNullOrWhiteSpace($HtmlFragment)) { return "" }
    $noTags = [regex]::Replace($HtmlFragment, '<[^>]+>', ' ')
    $decoded = [System.Net.WebUtility]::HtmlDecode($noTags)
    return ([regex]::Replace($decoded, '\s+', ' ')).Trim()
}

function Normalize-Key([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $decomposed = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $noDiacritics = [regex]::Replace($decomposed, '\p{Mn}+', '')
    $t = $noDiacritics.ToLowerInvariant().Trim()
    $t = [regex]::Replace($t, "['\u2019`".,\-]+", " ")
    $t = [regex]::Replace($t, '\s+', ' ')
    return $t.Trim()
}

function Format-TitleCase([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $words = ($Text.Trim() -split '\s+')
    $out = foreach ($w in $words) {
        if ($w.Length -le 1) { $w.ToUpperInvariant() }
        else { $w.Substring(0, 1).ToUpperInvariant() + $w.Substring(1).ToLowerInvariant() }
    }
    return ($out -join ' ')
}

function Parse-ItalianDateToIso([string]$RawDate) {
    if ([string]::IsNullOrWhiteSpace($RawDate)) { return "" }
    $s = $RawDate.Trim()
    if ($s -match '^(\d{4})-(\d{2})-(\d{2})') {
        return "$($Matches[1])-$($Matches[2])-$($Matches[3])"
    }
    if ($s -match '(\d{1,2})/(\d{1,2})/(\d{4})') {
        $d = $Matches[1].PadLeft(2, '0')
        $m = $Matches[2].PadLeft(2, '0')
        $y = $Matches[3]
        return "$y-$m-$d"
    }
    return $s
}

function Parse-SwimTime([string]$RawTime) {
    if ([string]::IsNullOrWhiteSpace($RawTime)) {
        return [pscustomobject]@{ timeCs = $null; formatted = ""; status = "" }
    }
    $s = $RawTime.Trim().ToUpperInvariant()
    $s = $s -replace '[\u2019\u2032]', "'" -replace '\u2033', '"' -replace ',', '.'
    $emDash = [string][char]0x2014
    if ($s -in @("S.T.", "ST", $emDash, "-", "N.D.", "ND")) {
        return [pscustomobject]@{ timeCs = $null; formatted = "S.T."; status = "ST" }
    }
    if ($s -match '^(SQ|DSQ|NP|DNS|RIT|DNF|SQUAL|ASS)') {
        return [pscustomobject]@{ timeCs = $null; formatted = $s; status = $s }
    }
    # Formato mm'ss.cc, mm:ss.cc, mm'ss"cc oppure mm.ss.cc
    if ($s -match "^(\d{1,2})[:'\u2019](\d{1,2})[.`"'](\d{1,2})$" -or $s -match '^(\d{1,2})\.(\d{2})\.(\d{1,2})$') {
        $min = [int]$Matches[1]
        $sec = [int]$Matches[2]
        $cs = [int]($Matches[3].PadRight(2, '0'))
        if ($sec -lt 60) {
            $totalCs = ($min * 6000) + ($sec * 100) + $cs
            $fmt = "{0:D2}'{1:D2}.{2:D2}" -f $min, $sec, $cs
            return [pscustomobject]@{ timeCs = $totalCs; formatted = $fmt; status = "OK" }
        }
    }
    # Formato solo secondi ss.cc (es. 34.50)
    if ($s -match '^(\d{1,3})\.(\d{1,2})$') {
        $totalSec = [int]$Matches[1]
        $cs = [int]($Matches[2].PadRight(2, '0'))
        $min = [math]::Floor($totalSec / 60)
        $sec = $totalSec % 60
        $totalCs = ($totalSec * 100) + $cs
        $fmt = "{0:D2}'{1:D2}.{2:D2}" -f [int]$min, [int]$sec, $cs
        return [pscustomobject]@{ timeCs = $totalCs; formatted = $fmt; status = "OK" }
    }
    return [pscustomobject]@{ timeCs = $null; formatted = $RawTime.Trim(); status = "UNKNOWN" }
}

function Normalize-CategoryAndGender([string]$MetaText, [string]$RawCategory = "", [string]$RawGender = "") {
    $combined = "$MetaText $RawCategory".Trim()
    $gender = $RawGender.Trim().ToUpperInvariant()
    if (-not $gender) {
        if ($combined -match '(?i)\bFemmin[ei]\b') { $gender = "F" }
        elseif ($combined -match '(?i)\bMasch[il]+\b') { $gender = "M" }
        elseif ($combined -match '(?i)\bMist[ao]\b|\bOpen\b') { $gender = "Mista" }
        elseif ($combined -match '/[Ff]\b|_F\b') { $gender = "F" }
        elseif ($combined -match '/[Mm]\b|_M\b') { $gender = "M" }
    }

    $cat = "Altro"
    if ($combined -match '(?i)Esordienti\s*C') { $cat = "Esordienti C" }
    elseif ($combined -match '(?i)Esordienti\s*B') { $cat = "Esordienti B" }
    elseif ($combined -match '(?i)Esordienti\s*A') { $cat = "Esordienti A" }
    elseif ($combined -match '(?i)\bRagazzi\b|Ragazzi/[FM]') { $cat = "Ragazzi" }
    elseif ($combined -match '(?i)\bJuniores\b|Juniores/[FM]') { $cat = "Juniores" }
    elseif ($combined -match '(?i)\bCadetti\b|Cadetti/[FM]') { $cat = "Cadetti" }
    elseif ($combined -match '(?i)\bSeniores\b|Seniores/[FM]') { $cat = "Seniores" }
    elseif ($combined -match '(?i)\bAssoluti\b|Assoluti/[FM]') { $cat = "Assoluti" }
    elseif ($combined -match '(?i)\bMaster') { $cat = "Master" }
    elseif ($combined -match '(?i)\bPropaganda') { $cat = "Propaganda" }
    elseif (-not [string]::IsNullOrWhiteSpace($RawCategory)) {
        $cat = ($RawCategory -replace '(/[FM]|_[FM])$', '').Trim()
    }

    return [pscustomobject]@{
        category = $cat
        gender = $gender
    }
}

function Normalize-EventName([string]$RawEventTitle) {
    $clean = $RawEventTitle.Trim()
    # Es: "Gara 1 - 50 m Dorso" -> "50 m Dorso"
    $clean = [regex]::Replace($clean, '(?i)^Gara\s*\d+\s*[\u2014\u2013\-:]\s*', '').Trim()
    $clean = [regex]::Replace($clean, '\s+', ' ')
    # Normalizza "50m" o "50 Stile" -> "50 m Stile" (preservando eventuali staffette "4x50")
    $clean = [regex]::Replace($clean, '(?<![xX\d])(\d+)\s*(?:m\b\s*)?', '$1 m ')
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
    # Capitalizzazione pulita dello stile
    $clean = [regex]::Replace($clean, '(?i)\bstile\s+libero\b', 'Stile libero')
    $clean = [regex]::Replace($clean, '(?i)\bdorso\b', 'Dorso')
    $clean = [regex]::Replace($clean, '(?i)\brana\b', 'Rana')
    $clean = [regex]::Replace($clean, '(?i)\bfarfalla\b|\bdelfino\b', 'Farfalla')
    $clean = [regex]::Replace($clean, '(?i)\bmisti\b', 'Misti')
    $clean = [regex]::Replace($clean, '(?i)\bmista\b', 'Mista')
    return $clean
}

function Detect-PoolLength([string]$Text, [string]$DefaultPool = "25m") {
    if ($Text -match '(?i)\b50\s*m\b|vasca\s*(?:lunga|50)') { return "50m" }
    if ($Text -match '(?i)\b25\s*m\b|vasca\s*(?:corta|25)') { return "25m" }
    return $DefaultPool
}

function Discover-MeetPages([string]$BaseUrl, [string]$AreaHtml, [string]$TargetHtml, [string]$TargetPath) {
    $meetMeta = @{}
    # Estrae info manifestazioni da /area-pubblica/
    $articleMatches = [regex]::Matches($AreaHtml, '<article[^>]*class="[^"]*slm-public-meet-row[^"]*"[^>]*>(.*?)</article>', 'Singleline')
    foreach ($am in $articleMatches) {
        $block = $am.Groups[1].Value
        $titleM = [regex]::Match($block, '<h3[^>]*>(.*?)</h3>', 'Singleline')
        $mutedM = [regex]::Match($block, '<div[^>]*class="[^"]*slm-muted[^"]*"[^>]*>(.*?)</div>', 'Singleline')
        $title = if ($titleM.Success) { Clean-HtmlText $titleM.Groups[1].Value } else { "" }
        $muted = if ($mutedM.Success) { Clean-HtmlText $mutedM.Groups[1].Value } else { "" }
        $dateIso = Parse-ItalianDateToIso $muted
        $city = ""
        if ($muted -match '\u00B7\s*(.+)$') { $city = $Matches[1].Trim() }

        $linkMatches = [regex]::Matches($block, 'href=["'']([^"'']*meet_id=(\d+)[^"'']*)["'']', 'IgnoreCase')
        foreach ($lm in $linkMatches) {
            $mid = $lm.Groups[2].Value
            if (-not $meetMeta.ContainsKey($mid)) {
                $meetMeta[$mid] = [pscustomobject]@{
                    meetId = $mid
                    title = $title
                    date = $dateIso
                    city = $city
                }
            }
        }
    }

    # Raccoglie tutti gli URL / select options della pagina target (startlist o risultati)
    $urls = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]

    $optionMatches = [regex]::Matches($TargetHtml, '<option[^>]*value=["''](\d+)["''][^>]*>(.*?)</option>', 'IgnoreCase,Singleline')
    foreach ($om in $optionMatches) {
        $mid = $om.Groups[1].Value
        $optText = Clean-HtmlText $om.Groups[2].Value
        if (-not $meetMeta.ContainsKey($mid)) {
            $meetMeta[$mid] = [pscustomobject]@{
                meetId = $mid
                title = ($optText -replace '\s*[\u2014\u2013\-]\s*\d{2}/\d{2}/\d{4}.*$', '').Trim()
                date = Parse-ItalianDateToIso $optText
                city = ""
            }
        }
        $u = "$BaseUrl$TargetPath`?meet_id=$mid"
        if ($seen.Add($u)) { [void]$urls.Add($u) }
    }

    $escapedPath = [regex]::Escape($TargetPath.Trim('/'))
    $hrefMatches = [regex]::Matches($AreaHtml + "`n" + $TargetHtml, "href=[`"']([^`"']*$escapedPath/\?meet_id=[^`"']+)[`"']", 'IgnoreCase')
    foreach ($hm in $hrefMatches) {
        $u = [System.Net.WebUtility]::HtmlDecode($hm.Groups[1].Value)
        if ($u -notmatch 'print=1|admin-post\.php') {
            if ($seen.Add($u)) { [void]$urls.Add($u) }
        }
    }

    # Se risultati-uisp non ha ancora un <select>, prova comunque eventuali meet_id scoperti in area-pubblica
    if ($urls.Count -eq 0 -and $meetMeta.Count -gt 0) {
        foreach ($mid in $meetMeta.Keys) {
            $u = "$BaseUrl$TargetPath`?meet_id=$mid"
            if ($seen.Add($u)) { [void]$urls.Add($u) }
        }
    }

    return [pscustomobject]@{
        Urls = [object[]]$urls.ToArray()
        MeetMeta = $meetMeta
    }
}

function Parse-SlmPage([string]$Html, [string]$SourceType, [string]$ClubRegex, [string]$DefaultPool, [hashtable]$MeetMetaById, [string]$PageUrl) {
    $records = New-Object System.Collections.Generic.List[object]
    $relays = New-Object System.Collections.Generic.List[object]

    $sections = @([regex]::Matches($Html, '<section[^>]*class="[^"]*slm-public-event[^"]*"[^>]*>(.*?)</section>', 'Singleline') | ForEach-Object { $_.Groups[1].Value })
    if ($sections.Count -eq 0 -and $Html -match '<table[^>]*class="[^"]*slm-table') {
        $chunks = [regex]::Split($Html, '(?=<div[^>]*class="[^"]*slm-event-title[^"]*")')
        $sections = @($chunks | Where-Object { $_ -match '<table[^>]*class="[^"]*slm-table' -and $_ -notmatch '<p class="slm-eyebrow">Manifestazione</p>' })
    }
    if ($sections.Count -eq 0) {
        return [pscustomobject]@{ Records = @(); Relays = @() }
    }

    $meetId = ""
    if ($PageUrl -match 'meet_id=(\d+)') { $meetId = $Matches[1] }
    elseif ($Html -match '<option[^>]*value=["''](\d+)["''][^>]*selected') { $meetId = $Matches[1] }

    $meetTitle = ""
    $titleM = [regex]::Match($Html, '<p class="slm-eyebrow">Manifestazione</p>\s*<h2[^>]*>(.*?)</h2>', 'Singleline')
    if ($titleM.Success) { $meetTitle = Clean-HtmlText $titleM.Groups[1].Value }

    $pills = [regex]::Matches($Html, '<span class="slm-public-pill">(.*?)</span>', 'Singleline') | ForEach-Object { Clean-HtmlText $_.Groups[1].Value }
    $meetDate = ""
    $meetCity = ""
    $meetPool = $DefaultPool
    foreach ($p in $pills) {
        if (-not $meetDate -and $p -match '^\d{1,2}/\d{1,2}/\d{4}$') {
            $meetDate = Parse-ItalianDateToIso $p
        } elseif ($p -match '(?i)vasca|25\s*m|50\s*m') {
            $meetPool = Detect-PoolLength $p $DefaultPool
        } elseif (-not $meetCity -and $p -notmatch '^Pubblicat|^Aggiornat|\d{2}:\d{2}' -and $p.Length -lt 40) {
            $meetCity = $p
        }
    }

    if ($meetId -and $MeetMetaById.ContainsKey($meetId)) {
        $mm = $MeetMetaById[$meetId]
        if (-not $meetTitle) { $meetTitle = $mm.title }
        if (-not $meetDate) { $meetDate = $mm.date }
        if (-not $meetCity) { $meetCity = $mm.city }
    }

    $isLive = ($Html -match '(?i)provvisori|risultati\s+live') -and ($Html -notmatch '(?i)risultati\s+ufficiali\s+pubblicati')

    foreach ($sec in $sections) {
        $evM = [regex]::Match($sec, '<div[^>]*class="[^"]*slm-event-title[^"]*"[^>]*>.*?<h2[^>]*>(.*?)</h2>(?:.*?<span[^>]*class="[^"]*slm-muted[^"]*"[^>]*>(.*?)</span>)?', 'Singleline')
        $rawEvent = if ($evM.Success) { Clean-HtmlText $evM.Groups[1].Value } else { "" }
        $rawMeta = if ($evM.Success) { Clean-HtmlText $evM.Groups[2].Value } else { "" }
        $eventName = Normalize-EventName $rawEvent
        $catInfo = Normalize-CategoryAndGender $rawMeta

        $tableMatches = [regex]::Matches($sec, '<table[^>]*class="[^"]*slm-table[^"]*"[^>]*>(.*?)</table>', 'Singleline')
        foreach ($tm in $tableMatches) {
            $tableHtml = $tm.Groups[1].Value
            $headers = @()
            $theadM = [regex]::Match($tableHtml, '<thead[^>]*>(.*?)</thead>', 'Singleline')
            if ($theadM.Success) {
                $headers = [regex]::Matches($theadM.Groups[1].Value, '<th[^>]*>(.*?)</th>', 'Singleline') | ForEach-Object {
                    Normalize-Key (Clean-HtmlText $_.Groups[1].Value)
                }
            }

            $tbodyHtml = $tableHtml
            $tbodyM = [regex]::Match($tableHtml, '<tbody[^>]*>(.*?)</tbody>', 'Singleline')
            if ($tbodyM.Success) { $tbodyHtml = $tbodyM.Groups[1].Value }

            $rowMatches = [regex]::Matches($tbodyHtml, '<tr[^>]*>(.*?)</tr>', 'Singleline')
            foreach ($rm in $rowMatches) {
                $cells = [regex]::Matches($rm.Groups[1].Value, '<td[^>]*>(.*?)</td>', 'Singleline') | ForEach-Object {
                    Clean-HtmlText $_.Groups[1].Value
                }
                if ($cells.Count -lt 4) { continue }

                $rowMap = @{}
                for ($i = 0; $i -lt $cells.Count; $i++) {
                    $h = if ($i -lt $headers.Count) { $headers[$i] } else { "col$i" }
                    $rowMap[$h] = $cells[$i]
                }

                $club = ""
                foreach ($k in @("societa", "societa sportiva", "club", "squadra")) {
                    if ($rowMap.ContainsKey($k)) { $club = $rowMap[$k]; break }
                }
                if (-not $club -and $cells.Count -ge 4) { $club = $cells[3] }

                $athleteRaw = ""
                foreach ($k in @("atleta", "nominativo", "nuotatore", "staffetta")) {
                    if ($rowMap.ContainsKey($k)) { $athleteRaw = $rowMap[$k]; break }
                }
                if (-not $athleteRaw -and $cells.Count -ge 2) { $athleteRaw = $cells[1] }

                $matchesClub = ($club -match $ClubRegex) -or ($athleteRaw -match $ClubRegex)
                if (-not $matchesClub) { continue }

                $year = ""
                foreach ($k in @("anno", "anno di nascita", "nascita")) {
                    if ($rowMap.ContainsKey($k)) { $year = $rowMap[$k]; break }
                }

                $tessera = ""
                foreach ($k in @("tessera", "codice tessera", "id")) {
                    if ($rowMap.ContainsKey($k)) { $tessera = $rowMap[$k]; break }
                }
                if ($tessera -in @([string][char]0x2014, "-", "N.D.")) { $tessera = "" }

                $rawTime = ""
                foreach ($k in @("tempo", "crono", "risultato", "tempo finale")) {
                    if ($rowMap.ContainsKey($k)) { $rawTime = $rowMap[$k]; break }
                }
                if (-not $rawTime) { $rawTime = $cells[$cells.Count - 1] }

                $pos = ""
                foreach ($k in @("pos", "pos ", "posizione", "class", "cl")) {
                    if ($rowMap.ContainsKey($k)) { $pos = $rowMap[$k]; break }
                }

                $notes = ""
                $sepDot = " " + [string][char]0x00B7 + " "
                foreach ($k in @("note", "stato", "punti")) {
                    if ($rowMap.ContainsKey($k) -and $rowMap[$k]) {
                        $notes = if ($notes) { "$notes$sepDot$($rowMap[$k])" } else { $rowMap[$k] }
                    }
                }

                $parsedTime = Parse-SwimTime $rawTime

                # Verifica se e una staffetta (es. "Dinamica Sport s.s.d. a r.l. - A 1. ...")
                $isRelay = ($athleteRaw -match $ClubRegex) -or ($athleteRaw -match '\b1\.\s+.*\b2\.\s+') -or ($eventName -match '(?i)4x\d+|staffetta')
                if ($isRelay) {
                    [void]$relays.Add([pscustomobject]@{
                        meetId = $meetId
                        meet = $meetTitle
                        date = $meetDate
                        city = $meetCity
                        pool = $meetPool
                        event = $eventName
                        category = $catInfo.category
                        gender = $catInfo.gender
                        teamLabel = $athleteRaw
                        time = $parsedTime.formatted
                        timeCs = $parsedTime.timeCs
                        status = $parsedTime.status
                        position = $pos
                        sourceType = $SourceType
                    })
                    continue
                }

                [void]$records.Add([pscustomobject]@{
                    meetId = $meetId
                    meet = $meetTitle
                    date = $meetDate
                    city = $meetCity
                    pool = $meetPool
                    event = $eventName
                    category = $catInfo.category
                    gender = $catInfo.gender
                    athleteRaw = $athleteRaw
                    athleteName = Format-TitleCase $athleteRaw
                    birthYear = if ($year -match '^\d{4}$') { [int]$year } else { $null }
                    tessera = $tessera
                    club = $club
                    time = $parsedTime.formatted
                    timeCs = $parsedTime.timeCs
                    status = $parsedTime.status
                    position = $pos
                    notes = $notes
                    sourceType = $SourceType
                    isLive = $isLive
                    sourceUrl = $PageUrl
                })
            }
        }
    }

    return [pscustomobject]@{
        Records = [object[]]$records.ToArray()
        Relays = [object[]]$relays.ToArray()
    }
}

function Parse-ManualCsv([string]$CsvText, [string]$DefaultPool, [string]$DefaultClub, [string]$SourceType = "manual") {
    $records = New-Object System.Collections.Generic.List[object]
    $lines = @($CsvText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith('#') })
    if ($lines.Count -lt 2) { return @() }

    $delim = if (($lines[0] -split ';').Count -ge ($lines[0] -split ',').Count) { ';' } else { ',' }
    $rows = ($lines -join "`n") | ConvertFrom-Csv -Delimiter $delim
    foreach ($r in $rows) {
        $props = @{}
        foreach ($p in $r.PSObject.Properties) {
            $props[(Normalize-Key $p.Name)] = if ($null -ne $p.Value) { ([string]$p.Value).Trim() } else { "" }
        }
        $name = $props["atleta"]
        if (-not $name) { continue }

        $catInfo = Normalize-CategoryAndGender "" ($props["categoria"]) ($props["sesso"])
        $parsedTime = Parse-SwimTime ($props["tempo"])
        $pool = if ($props["vasca"]) { Detect-PoolLength $props["vasca"] $DefaultPool } else { $DefaultPool }
        $birthYear = if ($props["anno"] -match '^\d{4}$') { [int]$props["anno"] } else { $null }

        [void]$records.Add([pscustomobject]@{
            meetId = "manual"
            meet = if ($props["manifestazione"]) { $props["manifestazione"] } else { "Inserimento manuale" }
            date = Parse-ItalianDateToIso ($props["data"])
            city = $props["luogo"]
            pool = $pool
            event = Normalize-EventName ($props["gara"])
            category = $catInfo.category
            gender = $catInfo.gender
            athleteRaw = $name
            athleteName = Format-TitleCase $name
            birthYear = $birthYear
            tessera = if ($props["tessera"] -in @([string][char]0x2014, "-")) { "" } else { [string]$props["tessera"] }
            club = $DefaultClub
            time = $parsedTime.formatted
            timeCs = $parsedTime.timeCs
            status = $parsedTime.status
            position = $props["posizione"]
            notes = $props["note"]
            sourceType = $SourceType
            isLive = $false
            sourceUrl = ""
        })
    }
    return $records.ToArray()
}

function Build-Dataset([object[]]$OfficialResults, [object[]]$ManualResults, [object[]]$StartlistEntries, [object[]]$Relays, [object]$Config) {
    $allResults = New-Object System.Collections.Generic.List[object]
    $seenResultKeys = New-Object System.Collections.Generic.HashSet[string]

    foreach ($item in (@($OfficialResults) + @($ManualResults))) {
        if ($null -eq $item) { continue }
        $idKey = "{0}|{1}|{2}|{3}|{4}|{5}" -f (Normalize-Key $item.athleteRaw), $item.date, (Normalize-Key $item.meet), (Normalize-Key $item.event), $item.pool, $item.time
        if ($seenResultKeys.Add($idKey)) {
            [void]$allResults.Add($item)
        }
    }

    # Costruisce anagrafica atleti unificata (da risultati ufficiali + manuali + startlist)
    $athletesByKey = @{}
    $tesseraToKey = @{}
    $nameYearToKey = @{}

    $resolveAthleteKey = {
        param($rec)
        $t = if ($rec.tessera) { $rec.tessera.Trim() } else { "" }
        $ny = "{0}|{1}" -f (Normalize-Key $rec.athleteRaw), $(if ($rec.birthYear) { $rec.birthYear } else { "" })
        if ($t -and $tesseraToKey.ContainsKey($t)) { return $tesseraToKey[$t] }
        if ($nameYearToKey.ContainsKey($ny)) { return $nameYearToKey[$ny] }
        $key = if ($t) { "t_$t" } else { "n_" + ($ny -replace '[^a-z0-9]+', '_') }
        if ($t) { $tesseraToKey[$t] = $key }
        $nameYearToKey[$ny] = $key
        return $key
    }

    $registerAthlete = {
        param($rec)
        $key = & $resolveAthleteKey $rec
        if (-not $athletesByKey.ContainsKey($key)) {
            $athletesByKey[$key] = [ordered]@{
                id = $key
                name = $rec.athleteName
                birthYear = $rec.birthYear
                tessera = $rec.tessera
                gender = $rec.gender
                category = $rec.category
                _categoryDate = $rec.date
            }
        } else {
            $a = $athletesByKey[$key]
            if (-not $a.birthYear -and $rec.birthYear) { $a.birthYear = $rec.birthYear }
            if (-not $a.tessera -and $rec.tessera) { $a.tessera = $rec.tessera }
            if (-not $a.gender -and $rec.gender -and $rec.gender -ne "Mista") { $a.gender = $rec.gender }
            # Aggiorna categoria se la data e piu recente; a parita di data (stessa gara) preferisci la categoria di fascia d'eta rispetto ad Assoluti
            if ($rec.category -and $rec.category -ne "Altro") {
                if ($a.category -eq "Altro") {
                    $a.category = $rec.category
                    $a._categoryDate = $rec.date
                } elseif ($rec.date -gt $a._categoryDate) {
                    $a.category = $rec.category
                    $a._categoryDate = $rec.date
                } elseif ($rec.date -eq $a._categoryDate -and $a.category -eq "Assoluti" -and $rec.category -ne "Assoluti") {
                    $a.category = $rec.category
                }
            }
        }
        return $key
    }

    $normalizedResults = New-Object System.Collections.Generic.List[object]
    foreach ($r in $allResults) {
        $aid = & $registerAthlete $r
        [void]$normalizedResults.Add([ordered]@{
            athleteId = $aid
            date = $r.date
            meet = $r.meet
            city = $r.city
            pool = $r.pool
            event = $r.event
            category = $r.category
            gender = $r.gender
            time = $r.time
            timeCs = $r.timeCs
            status = $r.status
            position = $r.position
            notes = $r.notes
            sourceType = $r.sourceType
            isLive = [bool]$r.isLive
        })
    }

    $normalizedEntries = New-Object System.Collections.Generic.List[object]
    $seenEntryKeys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($e in @($StartlistEntries)) {
        if ($null -eq $e) { continue }
        $ek = "{0}|{1}|{2}|{3}" -f (Normalize-Key $e.athleteRaw), $e.date, (Normalize-Key $e.meet), (Normalize-Key $e.event)
        if (-not $seenEntryKeys.Add($ek)) { continue }
        $aid = & $registerAthlete $e
        [void]$normalizedEntries.Add([ordered]@{
            athleteId = $aid
            date = $e.date
            meet = $e.meet
            city = $e.city
            pool = $e.pool
            event = $e.event
            category = $e.category
            gender = $e.gender
            entryTime = $e.time
            entryTimeCs = $e.timeCs
        })
    }

    $catOrder = @($Config.categoryOrder)
    $athletesOut = New-Object System.Collections.Generic.List[object]
    foreach ($a in ($athletesByKey.Values | Sort-Object {
        $idx = $catOrder.IndexOf($_.category)
        if ($idx -lt 0) { 999 } else { $idx }
    }, { $_.name })) {
        $a.Remove("_categoryDate")
        [void]$athletesOut.Add([pscustomobject]$a)
    }

    $sortedResults = [object[]]@($normalizedResults | Sort-Object date, event, athleteId)
    $sortedEntries = [object[]]@($normalizedEntries | Sort-Object date, event, athleteId)
    $sortedRelays = [object[]]@($Relays | Sort-Object date, event)

    return [ordered]@{
        clubName = $Config.clubName
        sourceBaseUrl = $Config.sourceBaseUrl
        generatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
        categoryOrder = $catOrder
        athletes = [object[]]$athletesOut.ToArray()
        results = $sortedResults
        entries = $sortedEntries
        relays = $sortedRelays
    }
}

function Encrypt-DatasetJson([string]$PlaintextJson, [string]$Passphrase, [int]$Iterations = 150000) {
    if ([string]::IsNullOrEmpty($Passphrase)) {
        throw "Password squadra mancante. Passa -Password oppure imposta la variabile d'ambiente TEAM_PASSWORD."
    }

    $salt = New-Object byte[] 16
    $iv = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($salt)
        $rng.GetBytes($iv)
    } finally {
        $rng.Dispose()
    }

    $passBytes = $Utf8NoBom.GetBytes($Passphrase)
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passBytes, $salt, $Iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        $derived = $kdf.GetBytes(64)
    } finally {
        $kdf.Dispose()
    }

    $encKey = New-Object byte[] 32
    $macKey = New-Object byte[] 32
    [Array]::Copy($derived, 0, $encKey, 0, 32)
    [Array]::Copy($derived, 32, $macKey, 0, 32)

    $plainBytes = $Utf8NoBom.GetBytes($PlaintextJson)
    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.KeySize = 256
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $encKey
        $aes.IV = $iv
        $encryptor = $aes.CreateEncryptor()
        try {
            $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
        } finally {
            $encryptor.Dispose()
        }
    } finally {
        $aes.Dispose()
    }

    $macInput = New-Object byte[] ($iv.Length + $cipherBytes.Length)
    [Array]::Copy($iv, 0, $macInput, 0, $iv.Length)
    [Array]::Copy($cipherBytes, 0, $macInput, $iv.Length, $cipherBytes.Length)

    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    try {
        $hmac.Key = $macKey
        $macBytes = $hmac.ComputeHash($macInput)
    } finally {
        $hmac.Dispose()
    }

    return [ordered]@{
        version = 1
        alg = "PBKDF2-SHA256/AES-256-CBC/HMAC-SHA256"
        iterations = $Iterations
        salt = [Convert]::ToBase64String($salt)
        iv = [Convert]::ToBase64String($iv)
        mac = [Convert]::ToBase64String($macBytes)
        ciphertext = [Convert]::ToBase64String($cipherBytes)
        updatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    }
}

function Decrypt-DatasetJson([object]$Envelope, [string]$Passphrase) {
    $salt = [Convert]::FromBase64String([string]$Envelope.salt)
    $iv = [Convert]::FromBase64String([string]$Envelope.iv)
    $mac = [Convert]::FromBase64String([string]$Envelope.mac)
    $cipherBytes = [Convert]::FromBase64String([string]$Envelope.ciphertext)
    $iterations = if ($Envelope.iterations) { [int]$Envelope.iterations } else { 150000 }

    $passBytes = $Utf8NoBom.GetBytes($Passphrase)
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passBytes, $salt, $iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        $derived = $kdf.GetBytes(64)
    } finally {
        $kdf.Dispose()
    }

    $encKey = New-Object byte[] 32
    $macKey = New-Object byte[] 32
    [Array]::Copy($derived, 0, $encKey, 0, 32)
    [Array]::Copy($derived, 32, $macKey, 0, 32)

    $macInput = New-Object byte[] ($iv.Length + $cipherBytes.Length)
    [Array]::Copy($iv, 0, $macInput, 0, $iv.Length)
    [Array]::Copy($cipherBytes, 0, $macInput, $iv.Length, $cipherBytes.Length)

    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    try {
        $hmac.Key = $macKey
        $expectedMac = $hmac.ComputeHash($macInput)
    } finally {
        $hmac.Dispose()
    }

    if ($expectedMac.Length -ne $mac.Length) { throw "HMAC mismatch" }
    $diff = 0
    for ($i = 0; $i -lt $mac.Length; $i++) { $diff = $diff -bor ($expectedMac[$i] -bxor $mac[$i]) }
    if ($diff -ne 0) { throw "Password errata o dati corrotti (HMAC mismatch)" }

    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.KeySize = 256
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $encKey
        $aes.IV = $iv
        $decryptor = $aes.CreateDecryptor()
        try {
            $plainBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
        } finally {
            $decryptor.Dispose()
        }
    } finally {
        $aes.Dispose()
    }

    return $Utf8NoBom.GetString($plainBytes)
}

function Get-DatasetFingerprint([object]$Dataset) {
    $core = [ordered]@{
        clubName = $Dataset.clubName
        athletes = $Dataset.athletes
        results = $Dataset.results
        entries = $Dataset.entries
        relays = $Dataset.relays
    }
    return ($core | ConvertTo-Json -Depth 10 -Compress)
}

# === ESECUZIONE PRINCIPALE ===
if ($MyInvocation.InvocationName -ne '.') {
    $config = Read-Utf8File $ConfigPath | ConvertFrom-Json
    $baseUrl = $config.sourceBaseUrl.TrimEnd('/')
    $clubRegex = $config.clubMatchRegex

    $officialResults = New-Object System.Collections.Generic.List[object]
    $startlistEntries = New-Object System.Collections.Generic.List[object]
    $relays = New-Object System.Collections.Generic.List[object]
    $manualResults = New-Object System.Collections.Generic.List[object]

    if (-not $SkipRemote) {
        Write-Host "Scarico indice manifestazioni da $baseUrl..."
        $areaHtml = Fetch-UrlUtf8 "$baseUrl$($config.publicAreaPath)"
        $resultsIndexHtml = Fetch-UrlUtf8 "$baseUrl$($config.resultsPath)"
        $startlistIndexHtml = Fetch-UrlUtf8 "$baseUrl$($config.startlistPath)"

        # 1) Risultati ufficiali / live
        $resDiscovery = Discover-MeetPages $baseUrl $areaHtml $resultsIndexHtml $config.resultsPath
        $resParsedHome = Parse-SlmPage $resultsIndexHtml "official" $clubRegex $config.defaultPoolLength $resDiscovery.MeetMeta "$baseUrl$($config.resultsPath)"
        foreach ($r in $resParsedHome.Records) { [void]$officialResults.Add($r) }
        foreach ($rel in $resParsedHome.Relays) { [void]$relays.Add($rel) }

        foreach ($u in $resDiscovery.Urls) {
            try {
                $html = Fetch-UrlUtf8 $u
                $parsed = Parse-SlmPage $html "official" $clubRegex $config.defaultPoolLength $resDiscovery.MeetMeta $u
                foreach ($r in $parsed.Records) { [void]$officialResults.Add($r) }
                foreach ($rel in $parsed.Relays) { [void]$relays.Add($rel) }
            } catch {
                Write-Warning "Impossibile leggere pagina risultati $u : $($_.Exception.Message)"
            }
        }

        # 2) Startlist pubbliche (anagrafica + iscrizioni)
        $slDiscovery = Discover-MeetPages $baseUrl $areaHtml $startlistIndexHtml $config.startlistPath
        $slUrls = if ($slDiscovery.Urls.Count -gt 0) { @($slDiscovery.Urls) } else { @("$baseUrl$($config.startlistPath)") }
        foreach ($u in ($slUrls | Select-Object -Unique)) {
            try {
                $html = Fetch-UrlUtf8 $u
                $parsed = Parse-SlmPage $html "startlist" $clubRegex $config.defaultPoolLength $slDiscovery.MeetMeta $u
                foreach ($r in $parsed.Records) { [void]$startlistEntries.Add($r) }
            } catch {
                Write-Warning "Impossibile leggere pagina startlist $u : $($_.Exception.Message)"
            }
        }
    }

    # 3) Eventuali dati storici/manuali locali o da Google Sheet CSV
    $dataDir = Join-Path $rootDir "data"
    if (Test-Path $dataDir) {
        $histFiles = @(Get-ChildItem -Path $dataDir -Filter "historical_*.csv" -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($hf in $histFiles) {
            Write-Host "Carico storico locale da $($hf.Name)..."
            $hText = Read-Utf8File $hf.FullName
            foreach ($m in @(Parse-ManualCsv $hText $config.defaultPoolLength $config.clubName "historical")) {
                [void]$manualResults.Add($m)
            }
        }
    }
    if ($ManualCsvPath -and (Test-Path $ManualCsvPath)) {
        Write-Host "Carico dati manuali locali da $ManualCsvPath..."
        $csvText = Read-Utf8File $ManualCsvPath
        foreach ($m in @(Parse-ManualCsv $csvText $config.defaultPoolLength $config.clubName "manual")) {
            [void]$manualResults.Add($m)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ManualCsvUrl)) {
        Write-Host "Carico dati manuali remoti da Google Sheets CSV..."
        try {
            $remoteCsv = Fetch-UrlUtf8 $ManualCsvUrl
            foreach ($m in @(Parse-ManualCsv $remoteCsv $config.defaultPoolLength $config.clubName "manual")) {
                [void]$manualResults.Add($m)
            }
        } catch {
            Write-Warning "Impossibile leggere MANUAL_CSV_URL: $($_.Exception.Message)"
        }
    }

    # 3b) Preserva eventuali record storici gia cifrati in team-data.enc.json (utile su GitHub Actions)
    $existingPlainDataset = $null
    if (Test-Path $OutputPath) {
        try {
            $existingEnv = Read-Utf8File $OutputPath | ConvertFrom-Json
            $existingPlainDataset = Decrypt-DatasetJson $existingEnv $Password | ConvertFrom-Json
            $existingAthletesById = @{}
            foreach ($ea in @($existingPlainDataset.athletes)) {
                $existingAthletesById[$ea.id] = $ea
            }
            foreach ($er in @($existingPlainDataset.results)) {
                if ($er.sourceType -eq "historical") {
                    $ea = if ($existingAthletesById.ContainsKey($er.athleteId)) { $existingAthletesById[$er.athleteId] } else { $null }
                    $aName = if ($ea) { $ea.name } else { $er.athleteId }
                    [void]$manualResults.Add([pscustomobject]@{
                        meetId = "historical"
                        meet = $er.meet
                        date = $er.date
                        city = $er.city
                        pool = $er.pool
                        event = $er.event
                        category = $er.category
                        gender = $er.gender
                        athleteRaw = $aName
                        athleteName = $aName
                        birthYear = if ($ea) { $ea.birthYear } else { $null }
                        tessera = if ($ea) { $ea.tessera } else { "" }
                        club = $config.clubName
                        time = $er.time
                        timeCs = $er.timeCs
                        status = $er.status
                        position = $er.position
                        notes = $er.notes
                        sourceType = "historical"
                        isLive = $false
                        sourceUrl = ""
                    })
                }
            }
        } catch {
            $existingPlainDataset = $null
        }
    }

    $dataset = Build-Dataset $officialResults.ToArray() $manualResults.ToArray() $startlistEntries.ToArray() $relays.ToArray() $config
    $datasetJson = $dataset | ConvertTo-Json -Depth 10 -Compress

    if ($PlaintextTestOutput) {
        Write-Utf8File $PlaintextTestOutput ($dataset | ConvertTo-Json -Depth 10)
    }

    $skipWrite = $false
    if (-not $Force -and $null -ne $existingPlainDataset) {
        if ((Get-DatasetFingerprint $existingPlainDataset) -eq (Get-DatasetFingerprint $dataset)) {
            $skipWrite = $true
        }
    }

    if ($skipWrite) {
        Write-Host ("Nessuna modifica rispetto ai dati gia salvati (Atleti: {0} | Risultati: {1} | Iscrizioni: {2})." -f $dataset.athletes.Count, $dataset.results.Count, $dataset.entries.Count)
    } else {
        $encryptedEnvelope = Encrypt-DatasetJson $datasetJson $Password
        $envelopeJson = $encryptedEnvelope | ConvertTo-Json -Depth 5
        Write-Utf8File $OutputPath $envelopeJson
        Write-Host ("Completato! Atleti: {0} | Risultati: {1} | Iscrizioni startlist: {2} -> {3}" -f $dataset.athletes.Count, $dataset.results.Count, $dataset.entries.Count, $OutputPath)
    }
}
