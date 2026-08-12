param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TestScript
)

$ErrorActionPreference = "Stop"

function Resolve-GodotExecutable {
    if ($env:GODOT_EXE -and (Test-Path $env:GODOT_EXE)) {
        return (Resolve-Path $env:GODOT_EXE).Path
    }

    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $patterns = @(
        (Join-Path $env:USERPROFILE "OneDrive\Desktop\Godot*_win64.exe\Godot*_win64.exe"),
        (Join-Path $env:USERPROFILE "Desktop\Godot*_win64.exe\Godot*_win64.exe"),
        (Join-Path $env:USERPROFILE "OneDrive\Desktop\Godot*.exe"),
        (Join-Path $env:USERPROFILE "Desktop\Godot*.exe")
    )

    foreach ($pattern in $patterns) {
        $match = Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }

    throw "Could not find Godot. Set GODOT_EXE to the full executable path, or place Godot on PATH."
}

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$godot = Resolve-GodotExecutable

$normalizedTest = $TestScript.Replace("\\", "/")
if (-not $normalizedTest.StartsWith("res://")) {
    $normalizedTest = "res://" + $normalizedTest.TrimStart("/")
}

Write-Host "Godot: $godot"
Write-Host "Test:  $normalizedTest"
Write-Host ""

& $godot --headless --path $projectRoot --script $normalizedTest
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Error "Godot test failed with exit code $exitCode."
}

exit $exitCode
