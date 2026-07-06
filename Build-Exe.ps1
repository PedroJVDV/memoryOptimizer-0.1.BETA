# ============================================================
# MemoryCleaner - Build Script (PS1 → EXE)
# Compila LimparMemoria.ps1 em MemoryCleaner.exe
# ============================================================

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  MemoryCleaner - Build System" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# -- Step 1: Install ps2exe if not available --
Write-Host "[1/4] Verificando modulo ps2exe..." -ForegroundColor Yellow
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "  > Instalando NuGet provider..." -ForegroundColor Gray
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Write-Host "  > Instalando ps2exe..." -ForegroundColor Gray
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
    Write-Host "  > ps2exe instalado com sucesso!" -ForegroundColor Green
} else {
    Write-Host "  > ps2exe ja esta instalado." -ForegroundColor Green
}
Import-Module ps2exe -Force

# -- Step 2: Convert PNG icon to ICO --
$pngPath = Join-Path $scriptDir "icon.png"
$icoPath = Join-Path $scriptDir "icon.ico"

Write-Host "[2/4] Gerando icone..." -ForegroundColor Yellow
if (Test-Path $pngPath) {
    try {
        Add-Type -AssemblyName System.Drawing
        $bmp = New-Object System.Drawing.Bitmap($pngPath)
        $resized = New-Object System.Drawing.Bitmap($bmp, 256, 256)
        $icon = [System.Drawing.Icon]::FromHandle($resized.GetHicon())
        $fs = New-Object System.IO.FileStream($icoPath, [System.IO.FileMode]::Create)
        $icon.Save($fs)
        $fs.Close()
        $icon.Dispose()
        $resized.Dispose()
        $bmp.Dispose()
        Write-Host "  > Icone gerado: icon.ico" -ForegroundColor Green
    } catch {
        Write-Host "  > Aviso: Falha ao converter icone: $_" -ForegroundColor DarkYellow
        Write-Host "  > Compilando sem icone personalizado..." -ForegroundColor DarkYellow
        $icoPath = $null
    }
} elseif (Test-Path $icoPath) {
    Write-Host "  > Usando icone existente: icon.ico" -ForegroundColor Green
} else {
    Write-Host "  > Nenhum icone encontrado. Compilando sem icone." -ForegroundColor DarkYellow
    $icoPath = $null
}

# -- Step 3: Compile EXE --
$ps1Path = Join-Path $scriptDir "LimparMemoria.ps1"
$exePath = Join-Path $scriptDir "MemoryCleaner.exe"

Write-Host "[3/4] Compilando MemoryCleaner.exe..." -ForegroundColor Yellow

$params = @{
    InputFile    = $ps1Path
    OutputFile   = $exePath
    NoConsole    = $true
    RequireAdmin = $true
    Title        = "MemoryCleaner"
    Description  = "Otimizador de Memoria para Windows"
    Company      = "MemoryCleaner"
    Product      = "MemoryCleaner"
    Version      = "0.1.0"
    Copyright    = "MIT License"
    Verbose      = $true
}

if ($icoPath -and (Test-Path $icoPath)) {
    $params.IconFile = $icoPath
}

Invoke-ps2exe @params

if (Test-Path $exePath) {
    $fileInfo = Get-Item $exePath
    Write-Host "  > Compilado com sucesso!" -ForegroundColor Green
    Write-Host "  > Arquivo: $($fileInfo.Name)" -ForegroundColor Gray
    Write-Host "  > Tamanho: $([math]::Round($fileInfo.Length / 1KB, 1)) KB" -ForegroundColor Gray
} else {
    Write-Host "  > ERRO: O arquivo .exe nao foi gerado!" -ForegroundColor Red
    exit 1
}

# -- Step 4: Verify --
Write-Host "[4/4] Verificando..." -ForegroundColor Yellow
$versionInfo = (Get-Item $exePath).VersionInfo
Write-Host "  > Produto: $($versionInfo.ProductName)" -ForegroundColor Gray
Write-Host "  > Versao: $($versionInfo.FileVersion)" -ForegroundColor Gray
Write-Host "  > Descricao: $($versionInfo.FileDescription)" -ForegroundColor Gray

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  BUILD CONCLUIDO COM SUCESSO!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Arquivos para distribuicao:" -ForegroundColor Cyan
Write-Host "  1. MemoryCleaner.exe       (aplicacao principal)" -ForegroundColor White
Write-Host "  2. LimparSilencioso.ps1    (limpeza agendada)" -ForegroundColor White
Write-Host ""
Write-Host "Coloque ambos os arquivos na mesma pasta." -ForegroundColor Yellow
Write-Host ""
