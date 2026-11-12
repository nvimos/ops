# Why `make live` left a stale app running, and the fix

## Situation

`make live` runs `tool/live.ps1`. It starts `cmd /c flutter.bat run -d windows` and sends `r` (hot reload) whenever a `.dart` file under `lib/` is saved.

At one point the app (`build/windows/x64/runner/Debug/ops.exe`) kept running, but the pwsh running `live.ps1` was gone. Nothing watched `lib/` any more, so saved changes never reached the app.

## Cause (found after the first fix, commit `2179d2f`)

A bug in `live.ps1`: `$flutter = [System.Diagnostics.Process]::Start($psi)`. PowerShell variable names ignore case, so `$flutter` is the `[string]$Flutter` parameter. The process was converted to a string, which has no `StandardInput` and no `HasExited`.

- `while (-not $flutter.HasExited)` was always true, so the loop ran.
- The first save sent the reload with `$flutter.StandardInput.Write(...)`. That threw, and the script ended.
- `finally` could not send `q` either, for the same reason. `flutter run` and the app stayed up with no watcher.

So every `make live` stopped reloading after the first save. The process is now in `$run`.

The first guess, that something killed `live.ps1` from outside, was wrong. Its fix is still useful: the job object below covers real kills.

## Fix (commit `d32b72f`)

`tool/live.ps1` now puts `flutter run` in a Windows job object with the kill-on-close flag:

- right after `Process.Start`, the script calls `[LiveJob]::Add($job, $run.Handle)`
  (with the old `$flutter` name this failed at once: "Cannot convert null to type System.IntPtr")
- everything `cmd` starts afterwards (`flutter run`, its Dart processes, `ops.exe`) joins the job automatically
- only the script's pwsh holds the job handle; however that process ends, Windows closes the handle and ends everything in the job
- the existing `finally` still sends `q` first for a clean exit; the job is the backstop
- cost: about a second at startup, while PowerShell compiles a small piece of C# (`Add-Type`)

## Check

Tested with `ping` in place of `flutter run`:

- with the job: `ping` ended as soon as the owning pwsh exited
- without the job: `ping` kept running for its full 60 s, the same orphaning seen with the app

## If it happens again

Look for an orphaned `flutter run` and app:

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'flutter.bat" run|runner\\Debug\\ops.exe' } |
  Select-Object ProcessId, Name, CreationDate
```

Close the Ops window, then start `make live` again. A change that a hot reload doesn't pick up (new fields in a state class, `initState`) needs `R` (hot restart) in the `make live` terminal.
