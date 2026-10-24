[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Image
)

$ErrorActionPreference = 'Stop'

# Require an explicit version tag, for example gamidaliev/study-sbt-devops:hw3-v1.
$lastPart = ($Image -split '/')[-1]
if ($Image -match '@' -or $lastPart -notmatch '^[a-z0-9][a-z0-9._-]*:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$' -or $lastPart -match '(?i):latest$') {
    throw 'Specify an image with a version tag, for example gamidaliev/study-sbt-devops:hw3-v1 (not latest).'
}

function Invoke-Docker {
    param([string[]]$DockerArgs)
    & docker @DockerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker $($DockerArgs -join ' ') failed (exit code $LASTEXITCODE)."
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker CLI not found. Install and start Docker Desktop in Linux containers mode.'
}

$context = Split-Path -Parent $PSScriptRoot
Invoke-Docker -DockerArgs @('info', '--format', '{{.OSType}}')
Invoke-Docker -DockerArgs @('build', '--pull', '--target', 'runtime', '--tag', $Image, $context)
# Authentication is supplied by a prior interactive docker login, never by this script.
Invoke-Docker -DockerArgs @('push', $Image)
Write-Host "Published $Image"
