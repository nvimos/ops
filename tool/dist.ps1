# dist.ps1: package the release build (build/windows/x64/runner/Release) for download.
#   -Zip      dist/ops-windows-x64-<version>.zip: the Release folder, unzip anywhere and run the exe
#   -Single   dist/ops-windows-x64-<version>-single.exe: one file, made by Enigma Virtual Box, which
#             serves flutter_windows.dll and data/ from inside the exe (nothing is unpacked)
# Run `flutter build windows --release` first (make dist and make single do).
param(
    [string]$Version = (Get-Date -Format 'yyyy-MM-dd'),
    [switch]$Zip,
    [switch]$Single,
    [string]$Evb = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$release = Join-Path $root 'build/windows/x64/runner/Release'
$dist = Join-Path $root 'dist'
$exe = Join-Path $release 'nvimos_poc.exe'
if (-not (Test-Path $exe)) { throw "no release build: $exe (run make build)" }
New-Item -ItemType Directory -Force $dist | Out-Null
$name = "ops-windows-x64-$Version"

if ($Zip) {
    $out = Join-Path $dist "$name.zip"
    Remove-Item $out -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $release '*') -DestinationPath $out
    '  wrote {0}' -f (Resolve-Path -Relative $out)
}

if ($Single) {
    $console = @($Evb,
        "$env:LOCALAPPDATA\Programs\EnigmaVirtualBox\enigmavbconsole.exe",
        "${env:ProgramFiles(x86)}\Enigma Virtual Box\enigmavbconsole.exe",
        "$env:ProgramFiles\Enigma Virtual Box\enigmavbconsole.exe") |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $console) { throw 'enigmavbconsole.exe not found: install Enigma Virtual Box, or pass -Evb <path>' }

    # One <File> per file under the Release folder, folders nested; the exe itself is the input.
    function Entry([System.IO.FileSystemInfo]$item) {
        $n = [System.Security.SecurityElement]::Escape($item.Name)
        if ($item.PSIsContainer) {
            $inner = (Get-ChildItem $item.FullName | ForEach-Object { Entry $_ }) -join ''
            return "<File><Type>3</Type><Name>$n</Name><Action>0</Action><OverwriteDateTime>False</OverwriteDateTime><OverwriteAttributes>False</OverwriteAttributes><HideFromDialogs>0</HideFromDialogs><Files>$inner</Files></File>"
        }
        $f = [System.Security.SecurityElement]::Escape($item.FullName)
        return "<File><Type>2</Type><Name>$n</Name><File>$f</File><ActiveX>False</ActiveX><ActiveXInstall>False</ActiveXInstall><Action>0</Action><OverwriteDateTime>False</OverwriteDateTime><OverwriteAttributes>False</OverwriteAttributes><PassCommandLine>False</PassCommandLine><HideFromDialogs>0</HideFromDialogs></File>"
    }
    $files = (Get-ChildItem $release | Where-Object { $_.FullName -ne $exe } | ForEach-Object { Entry $_ }) -join ''
    $out = Join-Path $dist "$name-single.exe"
    $project = @"
<?xml version="1.0" encoding="windows-1252"?>
<>
  <InputFile>$([System.Security.SecurityElement]::Escape($exe))</InputFile>
  <OutputFile>$([System.Security.SecurityElement]::Escape($out))</OutputFile>
  <Files>
    <Enabled>True</Enabled>
    <DeleteExtractedOnExit>False</DeleteExtractedOnExit>
    <CompressFiles>True</CompressFiles>
    <Files>
      <File><Type>3</Type><Name>%DEFAULT FOLDER%</Name><Action>0</Action><OverwriteDateTime>False</OverwriteDateTime><OverwriteAttributes>False</OverwriteAttributes><HideFromDialogs>0</HideFromDialogs><Files>$files</Files></File>
    </Files>
  </Files>
  <Registries><Enabled>False</Enabled></Registries>
  <Packaging><Enabled>False</Enabled></Packaging>
  <Options>
    <ShareVirtualSystem>False</ShareVirtualSystem>
    <MapExecutableWithTemporaryFile>True</MapExecutableWithTemporaryFile>
    <AllowRunningOfVirtualExeFiles>True</AllowRunningOfVirtualExeFiles>
  </Options>
</>
"@
    $evbFile = Join-Path $dist "$name.evb"
    Set-Content -Path $evbFile -Value $project -Encoding ascii
    & $console $evbFile
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) { throw "enigmavbconsole failed ($LASTEXITCODE)" }
    Remove-Item $evbFile
    '  wrote {0}' -f (Resolve-Path -Relative $out)
}
