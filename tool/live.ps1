# live.ps1: run the app with `flutter run` and hot-reload it whenever a file under lib/ is saved.
#   -Restart   hot restart (R) instead of hot reload (r): state is reset, but more changes apply
# Keys typed here go to flutter as usual (r, R, q). Ctrl+C or q stops.
param(
    [string]$Flutter = 'C:/tools/flutter/bin/flutter.bat',
    [switch]$Restart
)

$root = Split-Path -Parent $PSScriptRoot
$key = if ($Restart) { 'R' } else { 'r' }

$psi = [System.Diagnostics.ProcessStartInfo]::new('cmd.exe', "/c `"$Flutter`" run -d windows")
$psi.WorkingDirectory = $root
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true  # output goes to this console as it is
$flutter = [System.Diagnostics.Process]::Start($psi)

$watcher = [System.IO.FileSystemWatcher]::new((Join-Path $root 'lib'), '*.dart')
$watcher.IncludeSubdirectories = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]'LastWrite, FileName'

# Editors write a file in several steps: wait for a quiet 300 ms before reloading.
$last = [datetime]::MinValue
$pending = $false
try {
    while (-not $flutter.HasExited) {
        $change = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 100)
        if (-not $change.TimedOut) {
            $last = Get-Date
            $pending = $true
        }
        if ($pending -and ((Get-Date) - $last).TotalMilliseconds -ge 300) {
            $pending = $false
            $flutter.StandardInput.Write($key)
            $flutter.StandardInput.Flush()
        }
        while (-not [Console]::IsInputRedirected -and [Console]::KeyAvailable) {
            $c = [Console]::ReadKey($true).KeyChar
            $flutter.StandardInput.Write($c)
            $flutter.StandardInput.Flush()
        }
    }
} finally {
    $watcher.Dispose()
    if (-not $flutter.HasExited) {
        $flutter.StandardInput.Write('q')
        $flutter.StandardInput.Flush()
        if (-not $flutter.WaitForExit(5000)) { $flutter.Kill($true) }
    }
}
