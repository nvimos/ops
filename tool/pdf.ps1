# Switches the PDF pages of the preview pane on or off (see packages/ops_pdf_on and ops_pdf_off).
# On: pubspec_overrides.yaml (not in git) points ops_pdf at the pdfrx package, which builds PDFium.
# Off: the file is removed and the stub is used. Status prints which one is active.
param(
  [ValidateSet('on', 'off', 'status')][string]$Mode = 'status',
  [string]$Flutter = 'flutter',
  [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$file = Join-Path $root 'pubspec_overrides.yaml'
$text = "# Written by tool/pdf.ps1 (make pdf-on); not in git.`ndependency_overrides:`n  ops_pdf:`n    path: packages/ops_pdf_on`n"
$isOn = Test-Path $file

if ($Mode -eq 'status') { if ($isOn) { 'PDF on' } else { 'PDF off' }; return }
if (($Mode -eq 'on') -eq $isOn) { return }  # already so: nothing to do
if ($WhatIf) { "would switch PDF $Mode"; return }

if ($Mode -eq 'on') { Set-Content -Path $file -Value $text -NoNewline -Encoding utf8 } else { Remove-Item $file }
Push-Location $root
try {
  & $Flutter pub get *> $null
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
} finally { Pop-Location }
"switched PDF $Mode"
