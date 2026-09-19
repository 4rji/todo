#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules ScheduledTasks

[CmdletBinding()]
param(
    [uri]$DownloadUrl = "http://172.16.101.77:8087/apollo1.exe",
    [string]$InstallDirectory = (Join-Path $env:ProgramData "redhavi"),
    [string]$TaskName = "Redhavi-Apollo1",
    [ValidateRange(1, 1440)][int]$IntervalMinutes = 3,
    [ValidatePattern("^$|^[A-Fa-f0-9]{64}$")][string]$ExpectedSha256 = "",
    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$executablePath = Join-Path $InstallDirectory "apollo1.exe"

function Remove-ApolloTask {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[apollo1] Tarea programada eliminada: $TaskName"
    }

    if (Test-Path -LiteralPath $executablePath -PathType Leaf) {
        Remove-Item -LiteralPath $executablePath -Force
        Write-Host "[apollo1] Ejecutable eliminado: $executablePath"
    }
}

function Install-ApolloTask {
    New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
    $temporaryPath = Join-Path $InstallDirectory "apollo1.exe.download"

    try {
        Write-Host "[apollo1] Descargando $DownloadUrl ..."
        Invoke-WebRequest -UseBasicParsing -Uri $DownloadUrl -OutFile $temporaryPath

        $downloadedFile = Get-Item -LiteralPath $temporaryPath
        if ($downloadedFile.Length -eq 0) {
            throw "La descarga produjo un archivo vacio."
        }

        $actualSha256 = (Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash
        if ($ExpectedSha256 -and $actualSha256 -ne $ExpectedSha256) {
            throw "SHA-256 inesperado. Esperado: $ExpectedSha256; recibido: $actualSha256"
        }

        Move-Item -LiteralPath $temporaryPath -Destination $executablePath -Force
        Unblock-File -LiteralPath $executablePath -ErrorAction SilentlyContinue
        Write-Host "[apollo1] Instalado en $executablePath"
        Write-Host "[apollo1] SHA-256: $actualSha256"
    } finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }

    $action = New-ScheduledTaskAction `
        -Execute $executablePath `
        -WorkingDirectory $InstallDirectory
    $trigger = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval ([TimeSpan]::FromMinutes($IntervalMinutes)) `
        -RepetitionDuration ([TimeSpan]::FromDays(3650))
    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Description "Ejecuta apollo1.exe cada $IntervalMinutes minutos para el laboratorio Redhavi." `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Settings $settings `
        -Force | Out-Null

    Write-Host "[apollo1] Tarea creada: $TaskName (cada $IntervalMinutes minutos, como SYSTEM)."
    Write-Host "[apollo1] Primera ejecucion aproximada: $((Get-Date).AddMinutes(1))"
}

if ($Remove) {
    Remove-ApolloTask
} else {
    Install-ApolloTask
}
