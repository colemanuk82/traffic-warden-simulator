# Finds Godot 4.3 or newer and runs the game. If Godot is missing, downloads a
# portable copy into the game's "godot" folder (about 55 MB, first run only).
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$localDir = Join-Path $project 'godot'
$downloadUrl = 'https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_win64.exe.zip'

function Test-GodotName($name) {
    # Godot_v4.3-stable_win64.exe and newer; skip console, .NET and 4.0-4.2 builds
    if ($name -match 'console|mono') { return $false }
    if ($name -match '^Godot_v4\.(\d+)') { return [int]$Matches[1] -ge 3 }
    return $false
}

function Find-Godot {
    $found = Get-ChildItem $localDir -Filter 'Godot_v4*.exe' -ErrorAction SilentlyContinue |
        Where-Object { Test-GodotName $_.Name } | Select-Object -First 1
    if ($found) { return $found.FullName }

    foreach ($cmd in 'godot', 'godot4') {
        $c = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }

    $roots = @(
        "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads", "$env:USERPROFILE\OneDrive\Desktop",
        "$env:ProgramFiles", "${env:ProgramFiles(x86)}", "$env:LOCALAPPDATA\Programs",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages", "$env:USERPROFILE\scoop\apps", 'C:\Godot'
    )
    $all = foreach ($r in $roots) {
        if ($r -and (Test-Path $r)) {
            Get-ChildItem $r -Recurse -Depth 3 -Filter 'Godot_v4*.exe' -ErrorAction SilentlyContinue |
                Where-Object { Test-GodotName $_.Name }
        }
    }
    $best = $all | Sort-Object Name -Descending | Select-Object -First 1
    if ($best) { return $best.FullName }
    return $null
}

$godot = Find-Godot
if (-not $godot) {
    Write-Host 'Godot 4.3+ was not found, so downloading a portable copy (about 55 MB, first run only)...'
    New-Item -ItemType Directory -Force $localDir | Out-Null
    # Stops the Godot editor from scanning this folder as part of the game
    New-Item -ItemType File -Force (Join-Path $localDir '.gdignore') | Out-Null
    $zip = Join-Path $localDir 'godot.zip'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $localDir -Force
    Remove-Item $zip
    $godot = Find-Godot
    if (-not $godot) { throw 'Download finished but Godot could not be found in the godot folder.' }
}

Write-Host "Starting the game with $godot"
Start-Process -FilePath $godot -ArgumentList @('--path', "`"$project`"") -WorkingDirectory $project
