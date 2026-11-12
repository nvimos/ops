# tee-log.ps1: copy stdin to the console and to a file (live.ps1 pipes flutter's output through it).
param([Parameter(Mandatory)][string]$Path)
$writer = [System.IO.StreamWriter]::new($Path, $false, [System.Text.UTF8Encoding]::new($false))
$writer.AutoFlush = $true
try {
    while ($null -ne ($line = [Console]::In.ReadLine())) {
        [Console]::Out.WriteLine($line)
        $writer.WriteLine($line)
    }
} finally {
    $writer.Dispose()
}
