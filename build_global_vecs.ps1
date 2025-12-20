# build_global_vecs.ps1
# Lizzie Tucker
# Last Updated: December 19, 2025
# Builds the chamber, cosponsors, sponsors, and years vectors for all bills from the 108th to the 118th congress
# Uses the existing sponsors_by_icpsr_id_CONGRESSNUMBER.csv if one exists, if not, builds one.
#
# Example:
# Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# cd "C:\Users\lizzi\congress\data"
# .\build_global_vecs.ps1 -Base "." -LegislatorsRoot ".\legislators"
#
# Party vecs:
# - By default, this script DOES NOT build sponsor_party.vec or cosponsors_party.vec
# - To rebuild ONLY party vecs from existing per-congress CSVs:
#     .\build_global_vecs.ps1 -Base "." -LegislatorsRoot ".\legislators" -OnlyRebuildPartyVecs

param(
  [string]$Base = ".",
  [string[]]$CongressDirs = @(),
  [string]$LegislatorsRoot = "",
  [switch]$RebuildCsv = $false,
  [switch]$OnlyRebuildPartyVecs = $false
)

$ErrorActionPreference = "Stop"

function Get-CongressFolders {
  param([string]$Base, [string[]]$Explicit)

  if ($Explicit -and $Explicit.Count -gt 0) {
    $paths = @()
    foreach ($p in $Explicit) {
      $full = Resolve-Path $p
      if (-not (Test-Path -LiteralPath $full)) { throw "Congress folder not found: $p" }
      $paths += $full
    }
    return $paths
  }

  $result = @()
  Get-ChildItem -LiteralPath $Base -Directory | ForEach-Object {
    $bills = Join-Path $_.FullName "bills"
    if (Test-Path -LiteralPath $bills) { $result += $_.FullName }
  }
  if ($result.Count -eq 0) {
    throw "No congress folders found under $Base (need subfolders that contain a 'bills' directory)."
  }
  return ($result | Sort-Object)
}

function Build-ThomasMapFromYaml {
  param([string]$YamlPath)

  # Map from BOTH thomas IDs and bioguide IDs -> ICPSR
  $map = @{}

  $thomas   = $null
  $bioguide = $null
  $icpsr    = $null

  function Commit {
    if ($icpsr) {
      if ($thomas)   { $map[$thomas]   = $icpsr }
      if ($bioguide) { $map[$bioguide] = $icpsr }
    }
    $thomas   = $null
    $bioguide = $null
    $icpsr    = $null
  }

  foreach ($line in Get-Content -LiteralPath $YamlPath) {
    if ($line -match '^\-\s') {
      Commit
    }
    elseif ($line -match '^\s+thomas:\s*["'']?([0-9]+)["'']?\s*$') {
      $thomas = $Matches[1]
    }
    elseif ($line -match '^\s+bioguide:\s*["'']?([A-Za-z0-9]+)["'']?\s*$') {
      $bioguide = $Matches[1]
    }
    elseif ($line -match '^\s+icpsr:\s*["'']?([0-9]+)["'']?\s*$') {
      $icpsr = $Matches[1]
    }
  }

  Commit
  return $map
}

# ---------------------------
# Extra lookups for ICPSR -> (name/birthyear/gender) + party-at-date
# ---------------------------

function Format-Name {
  param(
    [string]$Last,
    [string]$First,
    [string]$Middle
  )

  if ($null -eq $Last)  { $Last = "" }  else { $Last = $Last.Trim() }
  if ($null -eq $First) { $First = "" } else { $First = $First.Trim() }
  if ($null -eq $Middle) { $Middle = "" } else { $Middle = $Middle.Trim() }

  if ($Last -eq "") { return "NA" }

  $fi = ""
  if ($First -ne "") { $fi = ("{0}." -f $First.Substring(0,1).ToUpper()) }

  $mi = ""
  if ($Middle -ne "") { $mi = ("{0}." -f $Middle.Substring(0,1).ToUpper()) }

  $parts = @()
  if ($fi -ne "") { $parts += $fi }
  if ($mi -ne "") { $parts += $mi }

  if ($parts.Count -gt 0) {
    return ("{0}, {1}" -f $Last.ToUpper(), ($parts -join " ")).Trim()
  }

  return ($Last.ToUpper()).Trim()
}

function Try-ParseDate([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return $null }
  $s = $s.Trim()
  try {
    return [datetime]::ParseExact($s, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
  } catch {
    return $null
  }
}

function Abbrev-Party {
  param([string]$Party)

  if ([string]::IsNullOrWhiteSpace($Party)) { return "NA" }
  $p = $Party.Trim()

  switch -Regex ($p.ToLower()) {
    '^democrat'    { return 'D' }
    '^republican'  { return 'R' }
    '^independent' { return 'I' }
    '^libertarian' { return 'L' }
    '^green'       { return 'G' }
    default {
      if ($p.Length -le 3) { return $p.ToUpper() }
      return $p.Substring(0,1).ToUpper()
    }
  }
}

function Build-IcpsrPartyIndexFromYaml {
  param([string[]]$YamlPaths)

  # icpsr(string) -> array of terms {start,end,party}
  $idx = @{}

  $curIcpsr = $null
  $inTerms = $false
  $curTerm = $null

  function CommitTerm {
    if ($curIcpsr -and $curTerm -and $curTerm.start) {
      if (-not $idx.ContainsKey($curIcpsr)) { $idx[$curIcpsr] = @() }
      $idx[$curIcpsr] += $curTerm
    }
    $curTerm = $null
  }

  function CommitPerson {
    CommitTerm
    $curIcpsr = $null
    $inTerms = $false
    $curTerm = $null
  }

  foreach ($path in $YamlPaths) {
    foreach ($line in Get-Content -LiteralPath $path) {

      # New person entry
      if ($line -match '^\-\s+id:\s*$') {
        CommitPerson
        continue
      }

      # icpsr for current person
      if ($line -match '^\s+icpsr:\s*["'']?([0-9]+)["'']?\s*$') {
        $curIcpsr = [string]$Matches[1]
        continue
      }

      # enter terms block
      if ($line -match '^\s+terms:\s*$') {
        $inTerms = $true
        continue
      }

      if ($inTerms) {
        # New term item
        if ($line -match '^\s*-\s+type:\s*([A-Za-z]+)\s*$') {
          CommitTerm
          $curTerm = [pscustomobject]@{ start=$null; end=$null; party=$null }
          continue
        }

        # Term fields
        if ($curTerm) {
          if ($line -match '^\s+start:\s*["'']?([0-9]{4}\-[0-9]{2}\-[0-9]{2})["'']?\s*$') { $curTerm.start = $Matches[1]; continue }
          if ($line -match '^\s+end:\s*["'']?([0-9]{4}\-[0-9]{2}\-[0-9]{2})["'']?\s*$')   { $curTerm.end   = $Matches[1]; continue }
          if ($line -match '^\s+party:\s*["'']?(.+?)["'']?\s*$')                              { $curTerm.party = $Matches[1]; continue }
        }
      }
    }

    # flush file end
    CommitPerson
  }

  return $idx
}


# Party at date regardless of chamber
function Get-PartyAtDate {
  param(
    [string]$Icpsr,
    [string]$BillDate,
    $partyIndex
  )

  if ([string]::IsNullOrWhiteSpace($Icpsr) -or $Icpsr -eq "NA") { return "NA" }

  # normalize
  $k = [string]$Icpsr
  $k = $k -replace '[\uFEFF\u200B\u00A0]', ''
  $k = $k.Trim().Trim('"').Trim()

  if (-not $partyIndex.ContainsKey($k)) { return "NA" }

  $dt = Try-ParseDate $BillDate
  if (-not $dt) {
    if ($BillDate -match '^[0-9]{4}$') { $dt = [datetime]::Parse("$BillDate-07-01") }
    else { return "NA" }
  }

  $terms = $partyIndex[$k]
  if ($null -eq $terms -or $terms.Count -eq 0) { return "NA" }

  # pick in-range term with latest start date
  $bestParty = $null
  $bestStart = $null

  foreach ($t in $terms) {
    $s = Try-ParseDate $t.start
    if (-not $s) { continue }
    $e = Try-ParseDate $t.end

    $in = $false
    if ($e) { $in = ($dt -ge $s -and $dt -le $e) } else { $in = ($dt -ge $s) }

    if ($in) {
      if ($null -eq $bestStart -or $s -gt $bestStart) {
        $bestStart = $s
        $bestParty = $t.party
      }
    }
  }

  if ($bestParty) { return (Abbrev-Party ([string]$bestParty)) }

  # year fallback
  $y = $dt.Year
  foreach ($t in $terms) {
    $s = Try-ParseDate $t.start
    if (-not $s) { continue }
    $e = Try-ParseDate $t.end

    $sy = $s.Year
    $ey = 9999
    if ($e) { $ey = $e.Year }

    if ($y -ge $sy -and $y -le $ey -and $t.party) {
      return (Abbrev-Party ([string]$t.party))
    }
  }

  return "NA"
}


# Rebuild ONLY party vecs from the existing per-congress CSVs (same order as the CSV rows)
function Rebuild-PartyVecsFromCongressCsvs {
  param(
    [string[]]$congressFolders,
    [string]$Base,
    $partyIndex
  )

  Write-Host "Starting party vec rebuild..."

  $sponsorPartyPath   = Join-Path $Base "sponsor_party.vec"
  $cosponsorPartyPath = Join-Path $Base "cosponsors_party.vec"

  # Use sponsors.vec only to size the progress bar (optional but you wanted it)
  $sponsorsVecPath = Join-Path $Base "sponsors.vec"
  if (-not (Test-Path -LiteralPath $sponsorsVecPath)) {
    throw ("sponsors.vec not found at {0} - run the normal vector build first." -f $sponsorsVecPath)
  }
  $total = (Get-Content -LiteralPath $sponsorsVecPath -ReadCount 0).Count
  Write-Host ("Party vec rebuild will process {0} bills (from sponsors.vec)" -f $total)

  # Truncate outputs (NO extra blank line)
  [System.IO.File]::WriteAllText($sponsorPartyPath,   "", [System.Text.Encoding]::ASCII)
  [System.IO.File]::WriteAllText($cosponsorPartyPath, "", [System.Text.Encoding]::ASCII)

  $written = 0

  # Audits
  $naSponsor = 0
  $allSameCosPartyBills = 0
  $totalCosPartyBills = 0

  foreach ($folder in $congressFolders) {
    $folderName = Split-Path -Leaf $folder
    if ($folderName -eq "119") { continue }

    $csvPath = Join-Path $folder ("sponsors_by_icpsr_id_{0}.csv" -f $folderName)
    if (-not (Test-Path -LiteralPath $csvPath)) {
      throw ("Missing per-congress CSV needed for party rebuild: {0}" -f $csvPath)
    }

    Write-Host ("Reading {0}..." -f $csvPath)

    $rows = Import-Csv -LiteralPath $csvPath

    $bufSP = New-Object System.Collections.Generic.List[string]
    $bufCP = New-Object System.Collections.Generic.List[string]

    $i = 0
    $count = $rows.Count

    foreach ($r in $rows) {
      $i++
      $written++

      if ($written % 1000 -eq 0) {
        $pct = [math]::Round(100 * $written / [math]::Max($total,1))
        Write-Progress -Activity "Rebuilding party vectors" -Status ("{0} / {1} (congress {2}: {3} / {4})" -f $written, $total, $folderName, $i, $count) -PercentComplete $pct
      }

      # bill date
      $bd = $r.bill_date
      if ([string]::IsNullOrWhiteSpace($bd)) { $bd = $r.year }
      if ([string]::IsNullOrWhiteSpace($bd)) { $bd = "NA" }

      # sponsor
      $s = $r.sponsor_icpsr
      if ([string]::IsNullOrWhiteSpace($s)) { $s = "NA" }

      $sp = Get-PartyAtDate -Icpsr $s -BillDate $bd -partyIndex $partyIndex
      if ($sp -eq "NA") { $naSponsor++ }
      $bufSP.Add([string]$sp)

      # cosponsors line
      $cs = $r.cosponsors_icpsr
      if ([string]::IsNullOrWhiteSpace($cs)) { $cs = "NA" }
      $cs = ($cs -replace ",", " ")
      $cs = ($cs -replace "\s+", " ").Trim()
      if ($cs -eq "") { $cs = "NA" }

      $cpLine = "NA"
      if ($cs -ne "NA") {
        $cp = New-Object System.Collections.Generic.List[string]
        foreach ($cid in ($cs.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries))) {
          # IMPORTANT: use $cid, not $s
          $cp.Add((Get-PartyAtDate -Icpsr $cid -BillDate $bd -partyIndex $partyIndex))
        }

        if ($cp.Count -gt 0) {
          $cpLine = ($cp.ToArray() -join " ")

          # audit
          $totalCosPartyBills++
          $uniq = @{}
          foreach ($p in $cp.ToArray()) { $uniq[$p] = 1 }
          if ($uniq.Keys.Count -eq 1) { $allSameCosPartyBills++ }
        }
      }

      $bufCP.Add([string]$cpLine)
    }

    Add-Content -LiteralPath $sponsorPartyPath   -Value $bufSP.ToArray() -Encoding ASCII
    Add-Content -LiteralPath $cosponsorPartyPath -Value $bufCP.ToArray() -Encoding ASCII
  }

  Write-Progress -Activity "Rebuilding party vectors" -Completed

  if ($written -ne $total) {
    Write-Warning ("Party rebuild processed {0} rows but sponsors.vec has {1}. If sponsors.vec was built from a different set/order of CSVs, counts may differ." -f $written, $total)
  }

  $cntSP = (Get-Content -LiteralPath $sponsorPartyPath   -ReadCount 0).Count
  $cntCP = (Get-Content -LiteralPath $cosponsorPartyPath -ReadCount 0).Count

  Write-Host ("Rebuilt party vecs:`n  {0}`n  {1}" -f $sponsorPartyPath, $cosponsorPartyPath)
  Write-Host ("Line counts - sponsor_party:{0} cosponsors_party:{1}" -f $cntSP, $cntCP)

  $pctNaSponsor = [math]::Round(100 * $naSponsor / [math]::Max($cntSP,1), 2)
  Write-Host ("Audit: sponsor_party NA rate = {0}%" -f $pctNaSponsor)

  if ($totalCosPartyBills -gt 0) {
    $pctAllSame = [math]::Round(100 * $allSameCosPartyBills / $totalCosPartyBills, 2)
    Write-Host ("Audit: cosponsor party lines where ALL parties identical = {0}% ({1}/{2})" -f $pctAllSame, $allSameCosPartyBills, $totalCosPartyBills)
  }
}



function MapThomas([string]$id, $map) {
  if ([string]::IsNullOrWhiteSpace($id)) { return $null }
  $id = $id.Trim()
  if ($map.ContainsKey($id)) { return [string]$map[$id] }
  return $null
}

function BillChamber([string]$bt) {
  if ($null -eq $bt) { return 2 }
  $x = $bt.ToString().ToLower()
  if (@('hr','hres','hconres','hjres') -contains $x) { return 2 }
  if (@('s','sres','sconres','sjres')  -contains $x) { return 1 }
  return 2
}

# Resolve inputs
$Base = (Resolve-Path $Base).Path
if (-not $LegislatorsRoot -or $LegislatorsRoot -eq "") {
  $LegislatorsRoot = Join-Path $Base "legislators"
}

$curYaml  = Join-Path $LegislatorsRoot "legislators-current.yaml"
$histYaml = Join-Path $LegislatorsRoot "legislators-historical.yaml"

if (!(Test-Path -LiteralPath $curYaml) -or !(Test-Path -LiteralPath $histYaml)) {
  throw "Missing YAMLs in $LegislatorsRoot"
}

$congressFolders = Get-CongressFolders -Base $Base -Explicit $CongressDirs
Write-Host ("Found {0} congress folders" -f $congressFolders.Count)

# Build mapping once (both thomas + bioguide -> icpsr)
$map = Build-ThomasMapFromYaml -YamlPath $histYaml
$cur = Build-ThomasMapFromYaml -YamlPath $curYaml
foreach ($k in $cur.Keys) { $map[$k] = $cur[$k] }
Write-Host ("Loaded {0} legislator IDs -> ICPSR mappings (thomas + bioguide)" -f $map.Count)

# Build ICPSR profiles once
$partyIndex = Build-IcpsrPartyIndexFromYaml -YamlPaths @($curYaml, $histYaml)
Write-Host ("Loaded {0} ICPSR party indexes" -f $partyIndex.Count)
Write-Host ("DEBUG partyIndex.Count = {0}" -f $partyIndex.Count)

Write-Host ("DEBUG has ICPSR 39310? {0}" -f $partyIndex.ContainsKey("39310"))
if ($partyIndex.ContainsKey("39310")) {
  Write-Host ("DEBUG 39310 term count = {0}" -f $partyIndex["39310"].Count)
}
Write-Host ("DEBUG party 39310 on 2003-01-07 = {0}" -f (Get-PartyAtDate -Icpsr "39310" -BillDate "2003-01-07" -partyIndex $partyIndex))

Write-Host ("DEBUG has ICPSR 14813? {0}" -f $partyIndex.ContainsKey("14813"))
Write-Host ("DEBUG party 14813 on 2003-01-07 = {0}" -f (Get-PartyAtDate -Icpsr "14813" -BillDate "2003-01-07" -partyIndex $partyIndex))



# If flag is on, ONLY rebuild party vecs and exit
if ($OnlyRebuildPartyVecs) {
  Rebuild-PartyVecsFromCongressCsvs -congressFolders $congressFolders -Base $Base -partyIndex $partyIndex
  Write-Host "Done (OnlyRebuildPartyVecs). Skipped rebuilding other vectors/CSVs."
  return
}

# ---------------------------
# Normal mode: build NON-party vecs only
# ---------------------------

# Global outputs at $Base
$sponsorsPath   = Join-Path $Base "sponsors.vec"
$cosponsorsPath = Join-Path $Base "cosponsors.vec"
$yearsPath      = Join-Path $Base "years.vec"
$chamberPath    = Join-Path $Base "chamber.vec"

"" | Set-Content -Encoding ASCII $sponsorsPath
"" | Set-Content -Encoding ASCII $cosponsorsPath
"" | Set-Content -Encoding ASCII $yearsPath
"" | Set-Content -Encoding ASCII $chamberPath

# Track which ICPSR IDs actually appear in the sponsor/cosponsor vectors (split by chamber)
$HouseIds  = New-Object System.Collections.Generic.HashSet[string]
$SenateIds = New-Object System.Collections.Generic.HashSet[string]

function Ensure-CongressCsv {
  param([string]$CongFolder, $map)

  $folderName = Split-Path -Leaf $CongFolder
  $billsDir = Join-Path $CongFolder "bills"
  if (!(Test-Path -LiteralPath $billsDir)) { throw "No bills dir: $billsDir" }

  $csvPath = Join-Path $CongFolder ("sponsors_by_icpsr_id_{0}.csv" -f $folderName)
  $forceRebuild = $false
  if ((Test-Path -LiteralPath $csvPath) -and (-not $RebuildCsv)) {
    try {
      $first = (Get-Content -LiteralPath $csvPath -TotalCount 1)
      if ($first -and ($first -notmatch '(^|,)bill_date(,|$)')) {
        $forceRebuild = $true
      }
    } catch { }
  }

  if ((-not (Test-Path -LiteralPath $csvPath)) -or $RebuildCsv -or $forceRebuild) {
    $rows  = New-Object System.Collections.Generic.List[object]
    $files = Get-ChildItem -LiteralPath $billsDir -Recurse -Filter *.json | Sort-Object FullName
    $total = $files.Count
    $i = 0

    foreach ($f in $files) {
      $i++
      if ($i % 500 -eq 0) {
        $pct = [math]::Round(100 * $i / [math]::Max($total,1))
        Write-Progress -Activity ("Building CSV for {0}..." -f $folderName) -Status "$i / $total" -PercentComplete $pct
      }

      $j = (Get-Content -LiteralPath $f.FullName -Raw) | ConvertFrom-Json
      $billId = $j.bill_id

      $year = $null
      if     ($j.introduced_at) { $year = ([string]$j.introduced_at).Substring(0,4) }
      elseif ($j.status_at)     { $year = ([string]$j.status_at).Substring(0,4) }
      elseif ($j.congress)      { $year = [string](1787 + 2*([int]$j.congress - 1)) }
      if (-not $year) { $year = "NA" }

      $billDate = $null
      if     ($j.introduced_at) { $billDate = [string]$j.introduced_at }
      elseif ($j.status_at)     { $billDate = [string]$j.status_at }
      elseif ($year -ne "NA")   { $billDate = ("{0}-07-01" -f $year) }
      if (-not $billDate) { $billDate = "NA" }

      $ch = BillChamber $j.bill_type

      # Sponsor: prefer thomas_id, else bioguide_id
      $s_icpsr = "NA"
      if ($j.sponsor) {
        $sid = $null
        if ($j.sponsor.thomas_id) { $sid = [string]$j.sponsor.thomas_id }
        elseif ($j.sponsor.bioguide_id) { $sid = [string]$j.sponsor.bioguide_id }

        if ($sid) {
          $m = MapThomas $sid $map
          if ($m) { $s_icpsr = $m }
        }
      }

      # Cosponsors: each can have thomas_id OR bioguide_id
      $cs_icpsr = @()
      if ($j.cosponsors) {
        foreach ($c in $j.cosponsors) {
          $cid = $null
          if ($c.thomas_id) { $cid = [string]$c.thomas_id }
          elseif ($c.bioguide_id) { $cid = [string]$c.bioguide_id }

          if ($cid) {
            $m = MapThomas $cid $map
            if ($m) { $cs_icpsr += $m }
          }
        }
      }

      $cosLine = "NA"
      if ($cs_icpsr.Count -gt 0) { $cosLine = ($cs_icpsr -join " ") }

      $row = [pscustomobject]@{
        bill_id           = $billId
        sponsor_icpsr     = $s_icpsr
        cosponsors_icpsr  = $cosLine
        bill_date         = $billDate
        year              = $year
        chamber           = $ch
      }
      $rows.Add($row)
    }

    Write-Progress -Activity ("Building CSV for {0}..." -f $folderName) -Completed
    $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host ("Built {0}" -f $csvPath)
  }

  return $csvPath
}

# Aggregate
$totalBillsAll = 0

foreach ($folder in $congressFolders) {
  $folderName = Split-Path -Leaf $folder

  # Skip 119th congress explicitly
  if ($folderName -eq "119") {
    Write-Host ("Skipping congress folder {0} (not ready yet)." -f $folderName)
    continue
  }

  $csv = Ensure-CongressCsv -CongFolder $folder -map $map
  $rows = Import-Csv -LiteralPath $csv
  $count = $rows.Count
  $totalBillsAll += $count

  # Buffers for this congress
  $bufSponsors   = New-Object System.Collections.Generic.List[string]
  $bufCosponsors = New-Object System.Collections.Generic.List[string]
  $bufYears      = New-Object System.Collections.Generic.List[string]
  $bufChamber    = New-Object System.Collections.Generic.List[string]

  $i = 0
  foreach ($r in $rows) {
    $i++
    if ($i % 1500 -eq 0) {
      $pct = [math]::Round(100 * $i / [math]::Max($count,1))
      $label = ("Appending {0}..." -f $folderName)
      Write-Progress -Activity $label -Status "$i / $count" -PercentComplete $pct
    }

    $s = $r.sponsor_icpsr
    if ([string]::IsNullOrWhiteSpace($s)) { $s = "NA" }
    $bufSponsors.Add([string]$s)

    $cs = $r.cosponsors_icpsr
    if ([string]::IsNullOrWhiteSpace($cs)) { $cs = "NA" }
    $cs = ($cs -replace ",", " ")
    $cs = ($cs -replace "\s+", " ").Trim()
    if ($cs -eq "") { $cs = "NA" }
    $bufCosponsors.Add([string]$cs)

    $yr = $r.year
    if ([string]::IsNullOrWhiteSpace($yr)) { $yr = "NA" }
    $bufYears.Add([string]$yr)

    $ch = $r.chamber
    if ([string]::IsNullOrWhiteSpace($ch)) { $ch = "2" }
    $bufChamber.Add([string]$ch)

    # Collect ICPSR IDs that actually appear (split by bill chamber)
    if ($s -ne "NA") {
      if ($ch.ToString() -eq "1") { $SenateIds.Add($s.ToString()) | Out-Null } else { $HouseIds.Add($s.ToString()) | Out-Null }
    }
    if ($cs -ne "NA") {
      foreach ($cid in ($cs.ToString().Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries))) {
        if ($cid -ne "NA") {
          if ($ch.ToString() -eq "1") { $SenateIds.Add($cid) | Out-Null } else { $HouseIds.Add($cid) | Out-Null }
        }
      }
    }
  }

  # Flush buffers once per congress
  Add-Content -LiteralPath $sponsorsPath   -Value $bufSponsors.ToArray()   -Encoding ASCII
  Add-Content -LiteralPath $cosponsorsPath -Value $bufCosponsors.ToArray() -Encoding ASCII
  Add-Content -LiteralPath $yearsPath      -Value $bufYears.ToArray()      -Encoding ASCII
  Add-Content -LiteralPath $chamberPath    -Value $bufChamber.ToArray()    -Encoding ASCII
  Write-Progress -Activity ("Appending {0}..." -f $folderName) -Completed
}

# Build quick-reference cheat sheets for ICPSR IDs that appear in the vectors
$houseCheatPath  = Join-Path $Base "icpsr_house_cheatsheet.csv"
$senateCheatPath = Join-Path $Base "icpsr_senate_cheatsheet.csv"

function Write-CheatSheet {
  param($ids, [string]$outPath)

  $rows = New-Object System.Collections.Generic.List[object]
  foreach ($id in ($ids | Sort-Object)) {
    if ($profiles.ContainsKey([string]$id)) {
      $p = $profiles[[string]$id]
      $rows.Add([pscustomobject]@{
        icpsr      = [string]$id
        name       = $p.name_display
        birthyear  = $p.birthyear
        gender     = $p.gender
      })
    }
    else {
      $rows.Add([pscustomobject]@{
        icpsr      = [string]$id
        name       = "NA"
        birthyear  = "NA"
        gender     = "NA"
      })
    }
  }
  $rows | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8
}

Write-CheatSheet -ids $HouseIds  -outPath $houseCheatPath
Write-CheatSheet -ids $SenateIds -outPath $senateCheatPath

Write-Host ("Wrote cheat sheets:`n  {0}`n  {1}" -f $houseCheatPath, $senateCheatPath)

# Final sanity check (non-party vecs only)
$cntS  = (Get-Content -LiteralPath $sponsorsPath   -ReadCount 0).Count
$cntCS = (Get-Content -LiteralPath $cosponsorsPath -ReadCount 0).Count
$cntY  = (Get-Content -LiteralPath $yearsPath      -ReadCount 0).Count
$cntC  = (Get-Content -LiteralPath $chamberPath    -ReadCount 0).Count

Write-Host ("OK: Global vectors written to:`n  {0}`n  {1}`n  {2}`n  {3}" -f $sponsorsPath,$cosponsorsPath,$yearsPath,$chamberPath)
Write-Host ("Line counts - sponsors:{0} cosponsors:{1} years:{2} chamber:{3}" -f $cntS,$cntCS,$cntY,$cntC)
Write-Host ("Total bills appended: {0}" -f $totalBillsAll)

if (($cntS -ne $cntCS) -or ($cntS -ne $cntY) -or ($cntS -ne $cntC)) {
  Write-Warning "Line counts differ - the Rmd expects all vector files to have identical line counts."
}