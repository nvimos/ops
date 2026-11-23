# The build options of ops, in the spirit of ./configure: make configure pdf=on markdown=off.
# An option is a package in two variants, packages/<pkg>_on and packages/<pkg>_off; pubspec.yaml
# depends on the default one. This script writes pubspec_overrides.yaml (not in git) with an override
# for each option that differs from its default, and runs pub get when anything changed. That file is
# the configuration: the state is read back from it. No options given: prints the configuration.
[CmdletBinding(SupportsShouldProcess)]
param(
  [ValidateSet('', 'on', 'off')][string]$Pdf = '',
  [ValidateSet('', 'on', 'off')][string]$Markdown = '',
  [ValidateSet('', 'on', 'off')][string]$Html = '',
  [string]$Flutter = 'flutter'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$file = Join-Path $root 'pubspec_overrides.yaml'

# name, package, default; a new option is a line here, a parameter above and its two packages
$options = @(
  [pscustomobject]@{ Name = 'pdf'; Package = 'ops_pdf'; Default = 'off'; Want = $Pdf }
  [pscustomobject]@{ Name = 'markdown'; Package = 'ops_markdown'; Default = 'on'; Want = $Markdown }
  [pscustomobject]@{ Name = 'html'; Package = 'ops_html'; Default = 'on'; Want = $Html }
)

$text = if (Test-Path $file) { Get-Content -Raw $file } else { '' }
foreach ($o in $options) {
  $o | Add-Member Now $(if ($text -match "packages/$($o.Package)_(on|off)\b") { $Matches[1] } else { $o.Default })
}

$asked = @($options | Where-Object Want)
if (-not $asked) {
  foreach ($o in $options) { '{0,3} {1}' -f $o.Now, $o.Name }
  return
}

$changed = @($asked | Where-Object { $_.Want -ne $_.Now })
if (-not $changed) { return }
foreach ($o in $changed) { $o.Now = $o.Want }

$overrides = @($options | Where-Object { $_.Now -ne $_.Default })
$body = "# Written by tool/configure.ps1 (make configure); not in git.`ndependency_overrides:`n" +
  (($overrides | ForEach-Object { "  $($_.Package):`n    path: packages/$($_.Package)_$($_.Now)`n" }) -join '')

if (-not $PSCmdlet.ShouldProcess($file, 'configure ' + (($changed | ForEach-Object { "$($_.Name)=$($_.Now)" }) -join ' '))) { return }
if ($overrides) { Set-Content -Path $file -Value $body -NoNewline -Encoding utf8 } elseif (Test-Path $file) { Remove-Item $file }
Push-Location $root
try {
  & $Flutter pub get *> $null
  if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
} finally { Pop-Location }
foreach ($o in $changed) { '{0,3} {1}' -f $o.Now, $o.Name }
