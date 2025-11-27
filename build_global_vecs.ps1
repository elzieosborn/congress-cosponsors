# build_global_vecs.ps1
# Lizzie Tucker
# Last Updated: November 27, 2025
# Builds the chamber, cosponsors, sponsors, and years vectors for all bills from the 108th to the 118th
# congress. Uses the existing sponsors_by_icpsr_id_CONGRESSNUMBER.csv if one exists, if not, builds one.
# Example process to run:
# Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# cd "C:\Users\lizzi\congress\data"
# .\build_global_vecs.ps1 -Base "." -LegislatorsRoot ".\legislators"

param(
  [string]$Base = ".",
  [string[]]$CongressDirs = @(),
  [string]$LegislatorsRoot = "",
  [switch]$RebuildCsv = $false
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

function MapThomas([string]$id, $map) {
  # Generic "map an ID (thomas or bioguide) -> ICPSR"
  if ([string]::IsNullOrWhiteSpace($id)) { return $null }
  $id = $id.Trim()
  if ($map.ContainsKey($id)) {
    return [string]$map[$id]
  }
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

# Global outputs at $Base
$sponsorsPath   = Join-Path $Base "sponsors.vec"
$cosponsorsPath = Join-Path $Base "cosponsors.vec"
$yearsPath      = Join-Path $Base "years.vec"
$chamberPath    = Join-Path $Base "chamber.vec"

"" | Set-Content -Encoding ASCII $sponsorsPath
"" | Set-Content -Encoding ASCII $cosponsorsPath
"" | Set-Content -Encoding ASCII $yearsPath
"" | Set-Content -Encoding ASCII $chamberPath

function Ensure-CongressCsv {
  param([string]$CongFolder, $map)

  $folderName = Split-Path -Leaf $CongFolder
  $billsDir = Join-Path $CongFolder "bills"
  if (!(Test-Path -LiteralPath $billsDir)) { throw "No bills dir: $billsDir" }

  $csvPath = Join-Path $CongFolder ("sponsors_by_icpsr_id_{0}.csv" -f $folderName)
  if ((-not (Test-Path -LiteralPath $csvPath)) -or $RebuildCsv) {
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

      $ch = BillChamber $j.bill_type

      # --- Sponsor: prefer thomas_id, else bioguide_id ---
      $s_icpsr = "NA"
      if ($j.sponsor) {
        $sid = $null
        if ($j.sponsor.thomas_id) {
          $sid = [string]$j.sponsor.thomas_id
        }
        elseif ($j.sponsor.bioguide_id) {
          $sid = [string]$j.sponsor.bioguide_id
        }

        if ($sid) {
          $m = MapThomas $sid $map
          if ($m) { $s_icpsr = $m }
        }
      }

      # --- Cosponsors: each can have thomas_id OR bioguide_id ---
      $cs_icpsr = @()
      if ($j.cosponsors) {
        foreach ($c in $j.cosponsors) {
          $cid = $null
          if ($c.thomas_id) {
            $cid = [string]$c.thomas_id
          }
          elseif ($c.bioguide_id) {
            $cid = [string]$c.bioguide_id
          }

          if ($cid) {
            $m = MapThomas $cid $map
            if ($m) { $cs_icpsr += $m }
          }
        }
      }

      $cosLine = "NA"
      if ($cs_icpsr.Count -gt 0) {
        $cosLine = ($cs_icpsr -join " ")
      }

      $row = [pscustomobject]@{
        bill_id           = $billId
        sponsor_icpsr     = $s_icpsr
        cosponsors_icpsr  = $cosLine
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
    Add-Content -Path $sponsorsPath -Value ($s.ToString()) -Encoding ASCII

    $cs = $r.cosponsors_icpsr
    if ([string]::IsNullOrWhiteSpace($cs)) { $cs = "NA" }
    $cs = ($cs -replace ",", " ")
    $cs = ($cs -replace "\s+", " ").Trim()
    if ($cs -eq "") { $cs = "NA" }
    Add-Content -Path $cosponsorsPath -Value ($cs.ToString()) -Encoding ASCII

    $yr = $r.year
    if ([string]::IsNullOrWhiteSpace($yr)) { $yr = "NA" }
    Add-Content -Path $yearsPath -Value ($yr.ToString()) -Encoding ASCII

    $ch = $r.chamber
    if ([string]::IsNullOrWhiteSpace($ch)) { $ch = "2" }
    Add-Content -Path $chamberPath -Value ($ch.ToString()) -Encoding ASCII
  }

  Write-Progress -Activity ("Appending {0}..." -f $folderName) -Completed
}

# Final sanity check
$cntS  = (Get-Content -LiteralPath $sponsorsPath   -ReadCount 0).Count
$cntCS = (Get-Content -LiteralPath $cosponsorsPath -ReadCount 0).Count
$cntY  = (Get-Content -LiteralPath $yearsPath      -ReadCount 0).Count
$cntC  = (Get-Content -LiteralPath $chamberPath    -ReadCount 0).Count

Write-Host ("OK: Global vectors written to:`n  {0}`n  {1}`n  {2}`n  {3}" -f $sponsorsPath,$cosponsorsPath,$yearsPath,$chamberPath)
Write-Host ("Line counts - sponsors:{0} cosponsors:{1} years:{2} chamber:{3}" -f $cntS,$cntCS,$cntY,$cntC)
Write-Host ("Total bills appended: {0}" -f $totalBillsAll)

if (($cntS -ne $cntCS) -or ($cntS -ne $cntY) -or ($cntS -ne $cntC)) {
  Write-Warning "Line counts differ - the Rmd expects all four files to have identical line counts."
}