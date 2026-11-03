param(
    [string]$Executable = "$PSScriptRoot/../apps/client/build/windows/x64/runner/Release/helmhost.exe",
    [int]$TimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path $Executable).Path
$logDirectory = Join-Path $env:LOCALAPPDATA 'Helmhost/logs'
$dartLog = Join-Path $logDirectory 'startup-dart.log'
# Flutter tests and prior smoke attempts append to these logs. Clear them so
# readiness checks and uploaded diagnostics belong only to this process.
if (Test-Path $logDirectory) {
    Remove-Item -Recurse -Force $logDirectory
}
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$process = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$ready = $false

try {
    while ((Get-Date) -lt $deadline) {
        $process.Refresh()
        if ($process.HasExited) {
            throw "Helmhost exited during startup with code $($process.ExitCode)"
        }
        if (Test-Path $dartLog) {
            $ready = [bool](Select-String -Path $dartLog -SimpleMatch "pid=$($process.Id) hub ready" -Quiet)
            if ($ready) { break }
        }
        Start-Sleep -Milliseconds 500
    }
    if (!$ready) { throw "Helmhost did not reach hub ready within $TimeoutSeconds seconds" }
    # Catch delayed startup aborts after the first frame/registry initialization.
    Start-Sleep -Seconds 5
    $process.Refresh()
    if ($process.HasExited) { throw "Helmhost exited after initialization with code $($process.ExitCode)" }

    if (!$process.CloseMainWindow()) { throw 'Helmhost did not accept a normal window close' }
    if (!$process.WaitForExit(15000)) { throw 'Helmhost hung during normal shutdown' }
    if ($process.ExitCode -ne 0) { throw "Helmhost shutdown failed with code $($process.ExitCode)" }
    Write-Output 'Windows startup and normal shutdown passed.'
} finally {
    $process.Refresh()
    if (!$process.HasExited) { Stop-Process -Id $process.Id -Force }
    if (Test-Path $logDirectory) {
        Get-ChildItem $logDirectory -Filter '*.log' | ForEach-Object {
            Write-Output "--- $($_.Name) ---"
            Get-Content $_.FullName -Tail 60
        }
    }
    $process.Dispose()
}
