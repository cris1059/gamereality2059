[CmdletBinding()]
param(
    [int]$Port = 34872
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$projectFile = Join-Path $projectRoot 'default.project.json'
$localRojo = Join-Path $projectRoot 'tools\rojo\rojo.exe'
$rojoCommand = Get-Command rojo -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $localRojo) {
    $rojoExecutable = $localRojo
} elseif ($rojoCommand) {
    $rojoExecutable = $rojoCommand.Source
} else {
    Write-Error 'Rojo is not installed or is not on PATH. Follow the README installation steps, then reopen this terminal.'
}

& $rojoExecutable serve $projectFile --port $Port
