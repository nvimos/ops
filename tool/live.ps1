# live.ps1: run the app with `flutter run` and hot-reload it whenever a file under lib/ is saved.
#   -Restart   hot restart (R) instead of hot reload (r): state is reset, but more changes apply
# Keys typed here go to flutter as usual (r, R, q). Ctrl+C or q stops.
param(
    [string]$Flutter = 'C:/tools/flutter/bin/flutter.bat',
    [switch]$Restart
)

$root = Split-Path -Parent $PSScriptRoot
$key = if ($Restart) { 'R' } else { 'r' }

# A job object that ends flutter run and the app when this script's process ends, however it ends
# (a kill skips `finally`). Only this process holds the handle; Windows closes it on exit.
if (-not ('LiveJob' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LiveJob {
    [StructLayout(LayoutKind.Sequential)] struct Basic {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit;
        public UIntPtr Affinity; public uint PriorityClass, SchedulingClass; }
    [StructLayout(LayoutKind.Sequential)] struct Io {
        public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
    [StructLayout(LayoutKind.Sequential)] struct Extended {
        public Basic BasicLimits; public Io IoInfo;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed; }
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateJobObject(IntPtr a, string name);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr job, int cls, ref Extended info, int size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    const uint KillOnJobClose = 0x2000;
    const int ExtendedLimitInformation = 9;
    public static IntPtr Create() {
        var job = CreateJobObject(IntPtr.Zero, null);
        var info = new Extended();
        info.BasicLimits.LimitFlags = KillOnJobClose;
        if (job == IntPtr.Zero || !SetInformationJobObject(job, ExtendedLimitInformation, ref info, Marshal.SizeOf(info)))
            throw new System.ComponentModel.Win32Exception();
        return job;
    }
    public static void Add(IntPtr job, IntPtr process) {
        if (!AssignProcessToJobObject(job, process)) throw new System.ComponentModel.Win32Exception();
    }
}
'@
}
$job = [LiveJob]::Create()

$psi = [System.Diagnostics.ProcessStartInfo]::new('cmd.exe', "/c `"$Flutter`" run -d windows")
$psi.WorkingDirectory = $root
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true  # output goes to this console as it is
$flutter = [System.Diagnostics.Process]::Start($psi)
[LiveJob]::Add($job, $flutter.Handle)  # cmd's children (flutter, the app) join the job too

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
