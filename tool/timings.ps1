<#
.SYNOPSIS
  Show the UI timings the app recorded (%APPDATA%/nvimos/ui-timing.json).
.PARAMETER Which
  last (default): the newest session; totals: all kept sessions; a number: that many sessions back (1 = last).
.PARAMETER Filter
  Only actions whose name contains this text (e.g. tasks, rpc, changes.stage).
#>
param([string]$Which = 'last', [string]$Filter = '')

$file = Join-Path $env:APPDATA 'nvimos/ui-timing.json'
if (-not (Test-Path $file)) { Write-Error "no timings yet: $file (run a debug build: make run)"; exit 1 }
$data = Get-Content $file -Raw | ConvertFrom-Json -DateKind String
$sessions = @($data.sessions)

if ($Which -eq 'totals') {
  $actions = $data.totals
  "totals of the last $($sessions.Count) sessions, $($sessions[0].started) .. $($sessions[-1].started)"
} else {
  $back = if ($Which -eq 'last') { 1 } else { [int]$Which }
  if ($back -lt 1 -or $back -gt $sessions.Count) { Write-Error "only $($sessions.Count) sessions kept"; exit 1 }
  $s = $sessions[$sessions.Count - $back]
  $actions = $s.actions
  $end = if ($s.ended) { $s.ended } else { 'still running' }
  "session $($s.started) .. $end"
}

$rows = $actions.PSObject.Properties | Where-Object { $_.Name -like "*$Filter*" }
if (-not $rows) { 'no actions'; exit 0 }
$w = ($rows.Name | Measure-Object -Maximum -Property Length).Maximum
$fmt = "{0,-$w} {1,6} {2,8} {3,8} {4,8}"
$fmt -f 'action', 'n', 'p50', 'p95', 'max'
foreach ($r in $rows) {
  $v = $r.Value
  $p50 = if ($null -ne $v.p50) { $v.p50 } else { '' }
  $fmt -f $r.Name, $v.n, $p50, $v.p95, $v.max
}
