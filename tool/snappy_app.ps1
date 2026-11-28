# make snappy-app: the Tasks mode's frame timings in the profile app on Windows
# (integration_test/snappy_app_test.dart, driver test_driver/integration_test.dart).
# The app runs with APPDATA in a temp folder, so it never touches the user's state.json or
# ui-timing.json; the folder is removed afterwards. -Strict: drift against the baseline fails too.
param(
    [string]$Flutter = 'C:/tools/flutter/bin/flutter.bat',
    [switch]$Strict
)
$ErrorActionPreference = 'Stop'
$appData = Join-Path ([System.IO.Path]::GetTempPath()) ('nvimos_appdata_snappy_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $appData | Out-Null
$saved = $env:APPDATA
try {
    $env:APPDATA = $appData
    $env:SNAPPY_STRICT = if ($Strict) { '1' } else { '0' }
    & $Flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/snappy_app_test.dart
    $code = $LASTEXITCODE
} finally {
    $env:APPDATA = $saved
    Remove-Item -Recurse -Force $appData -ErrorAction SilentlyContinue
}
exit $code
