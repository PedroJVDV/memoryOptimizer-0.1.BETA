# ============================================================
# MemoryCleaner - Otimizador de Memoria para Windows 11
# ============================================================

# -- Auto-Elevacao: solicitar admin se necessario --
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try {
        $scriptPath = $MyInvocation.MyCommand.Definition
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    } catch {
        [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
        [System.Windows.Forms.MessageBox]::Show("Este programa precisa ser executado como Administrador.", "MemoryCleaner - Erro", "OK", "Error")
    }
    exit
}

# -- Tratamento global de erros --
$ErrorActionPreference = "Stop"
trap {
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    [System.Windows.Forms.MessageBox]::Show("Erro inesperado:`n`n$($_.Exception.Message)`n`nLinha: $($_.InvocationInfo.ScriptLineNumber)", "MemoryCleaner - Erro", "OK", "Error")
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -- Win32 API Definitions --
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.Security.Principal;

public class MemoryOptimizer
{
    [DllImport("psapi.dll", SetLastError = true)]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);

    [DllImport("ntdll.dll", SetLastError = true)]
    public static extern int NtSetSystemInformation(int InfoClass, ref int Info, int Length);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges,
        ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential)]
    public struct TOKEN_PRIVILEGES
    {
        public int PrivilegeCount;
        public long Luid;
        public int Attributes;
    }

    public const int SE_PRIVILEGE_ENABLED = 0x00000002;
    public const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
    public const uint TOKEN_QUERY = 0x0008;
    public const string SE_INCREASE_QUOTA_NAME = "SeIncreaseQuotaPrivilege";
    public const string SE_PROF_SINGLE_PROCESS_NAME = "SeProfileSingleProcessPrivilege";

    public static bool EnablePrivilege(string privilege)
    {
        IntPtr tokenHandle;
        if (!OpenProcessToken(Process.GetCurrentProcess().Handle,
            TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out tokenHandle))
            return false;

        TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
        tp.PrivilegeCount = 1;
        tp.Attributes = SE_PRIVILEGE_ENABLED;

        if (!LookupPrivilegeValue(null, privilege, out tp.Luid))
        {
            CloseHandle(tokenHandle);
            return false;
        }

        bool result = AdjustTokenPrivileges(tokenHandle, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        CloseHandle(tokenHandle);
        return result;
    }

    public static bool ClearStandbyList()
    {
        EnablePrivilege(SE_PROF_SINGLE_PROCESS_NAME);
        EnablePrivilege(SE_INCREASE_QUOTA_NAME);
        int command = 4;
        int result = NtSetSystemInformation(80, ref command, sizeof(int));
        return result == 0;
    }

    public static bool ClearModifiedPageList()
    {
        EnablePrivilege(SE_PROF_SINGLE_PROCESS_NAME);
        int command = 3;
        int result = NtSetSystemInformation(80, ref command, sizeof(int));
        return result == 0;
    }

    public static int FlushWorkingSets()
    {
        int count = 0;
        foreach (Process proc in Process.GetProcesses())
        {
            try
            {
                EmptyWorkingSet(proc.Handle);
                count++;
            }
            catch { }
        }
        return count;
    }
}
"@ -ErrorAction SilentlyContinue

# -- Color Palette & Fonts --
$bgDark       = [System.Drawing.Color]::FromArgb(18, 18, 24)
$bgPanel      = [System.Drawing.Color]::FromArgb(26, 27, 38)
$bgCard       = [System.Drawing.Color]::FromArgb(35, 37, 52)
$bgCardHover  = [System.Drawing.Color]::FromArgb(45, 47, 65)
$accentBlue   = [System.Drawing.Color]::FromArgb(99, 135, 255)
$accentPurple = [System.Drawing.Color]::FromArgb(140, 100, 255)
$accentGreen  = [System.Drawing.Color]::FromArgb(80, 220, 140)
$accentRed    = [System.Drawing.Color]::FromArgb(255, 90, 95)
$accentOrange = [System.Drawing.Color]::FromArgb(255, 170, 60)
$accentYellow = [System.Drawing.Color]::FromArgb(255, 215, 80)
$textPrimary  = [System.Drawing.Color]::FromArgb(230, 232, 240)
$textSecondary= [System.Drawing.Color]::FromArgb(140, 145, 170)
$borderColor  = [System.Drawing.Color]::FromArgb(50, 52, 70)

$fontTitle    = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$fontSubtitle = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$fontNormal   = New-Object System.Drawing.Font("Segoe UI", 10)
$fontSmall    = New-Object System.Drawing.Font("Segoe UI", 9)
$fontBig      = New-Object System.Drawing.Font("Segoe UI", 26, [System.Drawing.FontStyle]::Bold)
$fontMedium   = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)

# -- Helper: Get Memory Info --
function Get-MemoryInfo {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $totalGB  = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeGB   = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedGB   = [math]::Round($totalGB - $freeGB, 2)
    $pctUsed  = [math]::Round(($usedGB / $totalGB) * 100, 1)

    $cachedBytes = 0
    try {
        $cachedBytes = (Get-Counter '\Memory\Standby Cache Normal Priority Bytes' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
        $cachedBytes += (Get-Counter '\Memory\Standby Cache Reserve Bytes' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
        $cachedBytes += (Get-Counter '\Memory\Standby Cache Core Bytes' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
    } catch {
        try {
            $cachedBytes = (Get-Counter '\Memoria\Bytes de Cache em Espera de Prioridade Normal' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
            $cachedBytes += (Get-Counter '\Memoria\Bytes de Cache em Espera de Reserva' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
        } catch {
            $cachedBytes = 0
        }
    }
    $cachedGB = [math]::Round($cachedBytes / 1GB, 2)

    return @{
        TotalGB  = $totalGB
        FreeGB   = $freeGB
        UsedGB   = $usedGB
        CachedGB = $cachedGB
        PctUsed  = $pctUsed
    }
}

# -- Helper: Get potentially unnecessary services --
function Get-UnnecessaryServices {
    $knownUnnecessary = @{
        "DiagTrack"             = "Telemetria e Diagnostico do Windows"
        "SysMain"               = "Superfetch (Pre-carregamento de apps)"
        "WSearch"               = "Windows Search (Indexacao de arquivos)"
        "dmwappushservice"      = "Mensagens Push WAP (Telemetria)"
        "MapsBroker"            = "Gerenciador de Mapas Baixados"
        "lfsvc"                 = "Servico de Geolocalizacao"
        "RetailDemo"            = "Servico de Demonstracao de Varejo"
        "wisvc"                 = "Windows Insider Service"
        "WerSvc"                = "Relatorio de Erros do Windows"
        "Fax"                   = "Servico de Fax"
        "XblAuthManager"        = "Xbox Live Auth Manager"
        "XblGameSave"           = "Xbox Live Game Save"
        "XboxGipSvc"            = "Xbox Accessory Management"
        "XboxNetApiSvc"         = "Xbox Live Networking"
        "TabletInputService"    = "Servico de Teclado Touch e Painel"
        "WbioSrvc"              = "Servico Biometrico do Windows"
        "PhoneSvc"              = "Servico de Telefone"
        "icssvc"                = "Hotspot Movel do Windows"
        "WMPNetworkSvc"         = "Compartilhamento Windows Media Player"
        "RemoteRegistry"        = "Registro Remoto"
        "TrkWks"                = "Rastreamento de Links Distribuidos"
        "PcaSvc"                = "Assistente de Compatibilidade"
        "AJRouter"              = "Servico Roteador AllJoyn"
        "BDESVC"                = "Servico BitLocker (se nao usa)"
        "wuauserv"              = "Windows Update (parar temporariamente)"
    }

    $services = @()
    foreach ($svcName in $knownUnnecessary.Keys) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc) {
                $services += [PSCustomObject]@{
                    Name        = $svcName
                    DisplayName = $knownUnnecessary[$svcName]
                    Status      = $svc.Status.ToString()
                    CanStop     = ($svc.Status -eq 'Running')
                }
            }
        } catch { }
    }

    return $services | Sort-Object -Property Status -Descending
}

# -- Main Form --
$form = New-Object System.Windows.Forms.Form
$form.Text = "MemoryCleaner - Otimizador de Memoria"
$form.Size = New-Object System.Drawing.Size(820, 720)
$form.StartPosition = "CenterScreen"
$form.BackColor = $bgDark
$form.ForeColor = $textPrimary
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.Font = $fontNormal

# -- Title Bar --
$titlePanel = New-Object System.Windows.Forms.Panel
$titlePanel.Location = New-Object System.Drawing.Point(0, 0)
$titlePanel.Size = New-Object System.Drawing.Size(820, 70)
$titlePanel.BackColor = $bgPanel

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "[*] MemoryCleaner"
$titleLabel.Font = $fontTitle
$titleLabel.ForeColor = $accentBlue
$titleLabel.Location = New-Object System.Drawing.Point(20, 12)
$titleLabel.AutoSize = $true
$titlePanel.Controls.Add($titleLabel)

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = "Otimizador de Memoria para Windows 11"
$subtitleLabel.Font = $fontSmall
$subtitleLabel.ForeColor = $textSecondary
$subtitleLabel.Location = New-Object System.Drawing.Point(22, 45)
$subtitleLabel.AutoSize = $true
$titlePanel.Controls.Add($subtitleLabel)

$form.Controls.Add($titlePanel)

# -- Memory Stats Cards --
function New-StatCard {
    param($x, $y, $title, $value, $color)

    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point($x, $y)
    $card.Size = New-Object System.Drawing.Size(183, 100)
    $card.BackColor = $bgCard

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = $title
    $lblTitle.Font = $fontSmall
    $lblTitle.ForeColor = $textSecondary
    $lblTitle.Location = New-Object System.Drawing.Point(14, 12)
    $lblTitle.AutoSize = $true
    $card.Controls.Add($lblTitle)

    $lblValue = New-Object System.Windows.Forms.Label
    $lblValue.Text = $value
    $lblValue.Font = $fontBig
    $lblValue.ForeColor = $color
    $lblValue.Location = New-Object System.Drawing.Point(14, 38)
    $lblValue.AutoSize = $true
    $lblValue.Name = "value"
    $card.Controls.Add($lblValue)

    $lblUnit = New-Object System.Windows.Forms.Label
    $lblUnit.Text = "GB"
    $lblUnit.Font = $fontSmall
    $lblUnit.ForeColor = $textSecondary
    $lblUnit.Location = New-Object System.Drawing.Point(14, 78)
    $lblUnit.AutoSize = $true
    $lblUnit.Name = "unit"
    $card.Controls.Add($lblUnit)

    return $card
}

$memInfo = Get-MemoryInfo

$cardTotal  = New-StatCard 20 85 "TOTAL" $memInfo.TotalGB $textPrimary
$cardUsed   = New-StatCard 213 85 "EM USO" $memInfo.UsedGB $accentOrange
$cardFree   = New-StatCard 406 85 "LIVRE" $memInfo.FreeGB $accentGreen
$cardCached = New-StatCard 599 85 "CACHE" $memInfo.CachedGB $accentPurple

$form.Controls.AddRange(@($cardTotal, $cardUsed, $cardFree, $cardCached))

# -- Usage Bar --
$barPanel = New-Object System.Windows.Forms.Panel
$barPanel.Location = New-Object System.Drawing.Point(20, 200)
$barPanel.Size = New-Object System.Drawing.Size(762, 40)
$barPanel.BackColor = $bgCard

$barFill = New-Object System.Windows.Forms.Panel
$barFill.Location = New-Object System.Drawing.Point(2, 2)
$barWidth = [math]::Min([int](758 * $memInfo.PctUsed / 100), 758)
$barFill.Size = New-Object System.Drawing.Size($barWidth, 36)
if ($memInfo.PctUsed -gt 80) { $barFill.BackColor = $accentRed }
elseif ($memInfo.PctUsed -gt 60) { $barFill.BackColor = $accentOrange }
else { $barFill.BackColor = $accentGreen }
$barPanel.Controls.Add($barFill)

$barLabel = New-Object System.Windows.Forms.Label
$barLabel.Text = "$($memInfo.PctUsed)% em uso"
$barLabel.Font = $fontSmall
$barLabel.ForeColor = $textPrimary
$barLabel.BackColor = [System.Drawing.Color]::Transparent
$barLabel.Location = New-Object System.Drawing.Point(10, 10)
$barLabel.AutoSize = $true
$barPanel.Controls.Add($barLabel)
$barLabel.BringToFront()

$form.Controls.Add($barPanel)

# -- Services Section --
$svcTitleLabel = New-Object System.Windows.Forms.Label
$svcTitleLabel.Text = "[+] Servicos Identificados (marque para desativar)"
$svcTitleLabel.Font = $fontSubtitle
$svcTitleLabel.ForeColor = $textPrimary
$svcTitleLabel.Location = New-Object System.Drawing.Point(20, 255)
$svcTitleLabel.AutoSize = $true
$form.Controls.Add($svcTitleLabel)

$svcListView = New-Object System.Windows.Forms.ListView
$svcListView.Location = New-Object System.Drawing.Point(20, 285)
$svcListView.Size = New-Object System.Drawing.Size(762, 280)
$svcListView.View = [System.Windows.Forms.View]::Details
$svcListView.CheckBoxes = $true
$svcListView.FullRowSelect = $true
$svcListView.BackColor = $bgCard
$svcListView.ForeColor = $textPrimary
$svcListView.Font = $fontSmall
$svcListView.BorderStyle = "None"
$svcListView.GridLines = $false
$svcListView.HeaderStyle = "Nonclickable"
$svcListView.OwnerDraw = $false

$colName = $svcListView.Columns.Add("Nome do Servico", 180)
$colDesc = $svcListView.Columns.Add("Descricao", 400)
$colStatus = $svcListView.Columns.Add("Status", 160)

$services = Get-UnnecessaryServices
foreach ($svc in $services) {
    $item = New-Object System.Windows.Forms.ListViewItem($svc.Name)
    $item.SubItems.Add($svc.DisplayName) | Out-Null
    if ($svc.Status -eq "Running") {
        $item.SubItems.Add("[ON] Rodando") | Out-Null
        $item.ForeColor = $accentGreen
    } else {
        $item.SubItems.Add("[--] Parado") | Out-Null
        $item.ForeColor = $textSecondary
    }
    $item.Tag = $svc.Name
    $svcListView.Items.Add($item) | Out-Null
}

$form.Controls.Add($svcListView)

# -- Log TextBox --
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(20, 575)
$logBox.Size = New-Object System.Drawing.Size(540, 95)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BackColor = $bgPanel
$logBox.ForeColor = $accentGreen
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logBox.BorderStyle = "None"
$logBox.Text = "[$(Get-Date -Format 'HH:mm:ss')] Pronto. Clique em LIMPAR para otimizar.`r`n"
$form.Controls.Add($logBox)

function Write-Log {
    param([string]$message)
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $logBox.AppendText("[$timestamp] $message`r`n")
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# -- Buttons --
$btnClean = New-Object System.Windows.Forms.Button
$btnClean.Text = "LIMPAR MEMORIA"
$btnClean.Font = $fontMedium
$btnClean.Size = New-Object System.Drawing.Size(220, 48)
$btnClean.Location = New-Object System.Drawing.Point(572, 575)
$btnClean.FlatStyle = "Flat"
$btnClean.FlatAppearance.BorderSize = 0
$btnClean.BackColor = $accentBlue
$btnClean.ForeColor = [System.Drawing.Color]::White
$btnClean.Cursor = [System.Windows.Forms.Cursors]::Hand

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "ATUALIZAR"
$btnRefresh.Font = $fontSmall
$btnRefresh.Size = New-Object System.Drawing.Size(220, 40)
$btnRefresh.Location = New-Object System.Drawing.Point(572, 630)
$btnRefresh.FlatStyle = "Flat"
$btnRefresh.FlatAppearance.BorderSize = 1
$btnRefresh.FlatAppearance.BorderColor = $borderColor
$btnRefresh.BackColor = $bgCard
$btnRefresh.ForeColor = $textPrimary
$btnRefresh.Cursor = [System.Windows.Forms.Cursors]::Hand

$form.Controls.AddRange(@($btnClean, $btnRefresh))

# -- Update Memory Display --
function Update-MemoryDisplay {
    $mem = Get-MemoryInfo

    foreach ($ctrl in $cardTotal.Controls) { if ($ctrl.Name -eq "value") { $ctrl.Text = "$($mem.TotalGB)" } }
    foreach ($ctrl in $cardUsed.Controls)  { if ($ctrl.Name -eq "value") { $ctrl.Text = "$($mem.UsedGB)" } }
    foreach ($ctrl in $cardFree.Controls)  { if ($ctrl.Name -eq "value") { $ctrl.Text = "$($mem.FreeGB)" } }
    foreach ($ctrl in $cardCached.Controls) { if ($ctrl.Name -eq "value") { $ctrl.Text = "$($mem.CachedGB)" } }

    $barWidth = [math]::Min([int](758 * $mem.PctUsed / 100), 758)
    $barFill.Size = New-Object System.Drawing.Size($barWidth, 36)
    if ($mem.PctUsed -gt 80) { $barFill.BackColor = $accentRed }
    elseif ($mem.PctUsed -gt 60) { $barFill.BackColor = $accentOrange }
    else { $barFill.BackColor = $accentGreen }
    $barLabel.Text = "$($mem.PctUsed)% em uso"

    $svcListView.Items.Clear()
    $svcs = Get-UnnecessaryServices
    foreach ($svc in $svcs) {
        $item = New-Object System.Windows.Forms.ListViewItem($svc.Name)
        $item.SubItems.Add($svc.DisplayName) | Out-Null
        if ($svc.Status -eq "Running") {
            $item.SubItems.Add("[ON] Rodando") | Out-Null
            $item.ForeColor = $accentGreen
        } else {
            $item.SubItems.Add("[--] Parado") | Out-Null
            $item.ForeColor = $textSecondary
        }
        $item.Tag = $svc.Name
        $svcListView.Items.Add($item) | Out-Null
    }
}

# -- Clean Button Click --
$btnClean.Add_Click({
    $btnClean.Enabled = $false
    $btnClean.Text = "Limpando..."
    $btnClean.BackColor = $bgCardHover
    [System.Windows.Forms.Application]::DoEvents()

    $memBefore = Get-MemoryInfo

    Write-Log "Iniciando otimizacao de memoria..."

    # Step 1: Flush working sets
    Write-Log "Reduzindo working sets dos processos..."
    try {
        $count = [MemoryOptimizer]::FlushWorkingSets()
        Write-Log "  > $count processos otimizados"
    } catch {
        Write-Log "  > Erro ao otimizar working sets: $_"
    }

    # Step 2: Clear standby cache
    Write-Log "Limpando cache de memoria em espera (Standby)..."
    try {
        $result = [MemoryOptimizer]::ClearStandbyList()
        if ($result) { Write-Log "  > Cache Standby limpo com sucesso" }
        else { Write-Log "  > Aviso: limpeza parcial do cache" }
    } catch {
        Write-Log "  > Erro: $_"
    }

    # Step 3: Clear modified page list
    Write-Log "Limpando lista de paginas modificadas..."
    try {
        [MemoryOptimizer]::ClearModifiedPageList() | Out-Null
        Write-Log "  > Paginas modificadas limpas"
    } catch {
        Write-Log "  > Erro: $_"
    }

    # Step 4: .NET Garbage Collection
    Write-Log "Executando coleta de lixo .NET..."
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
    Write-Log "  > GC concluido"

    # Step 5: Clear temp files
    Write-Log "Limpando arquivos temporarios..."
    $tempPaths = @($env:TEMP, "$env:LOCALAPPDATA\Temp", "$env:WINDIR\Temp")
    $deletedCount = 0
    foreach ($tp in $tempPaths) {
        if (Test-Path $tp) {
            try {
                Get-ChildItem -Path $tp -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddHours(-1) } |
                    ForEach-Object {
                        try { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue; $deletedCount++ } catch {}
                    }
            } catch {}
        }
    }
    Write-Log "  > $deletedCount arquivos temporarios removidos"

    # Step 6: Flush DNS
    Write-Log "Limpando cache DNS..."
    try {
        ipconfig /flushdns | Out-Null
        Write-Log "  > Cache DNS limpo"
    } catch {
        Write-Log "  > Erro ao limpar DNS"
    }

    # Step 7: Stop selected services
    $checkedItems = @()
    foreach ($item in $svcListView.Items) {
        if ($item.Checked) { $checkedItems += $item }
    }

    if ($checkedItems.Count -gt 0) {
        Write-Log "Parando $($checkedItems.Count) servico(s) selecionado(s)..."
        foreach ($item in $checkedItems) {
            $svcName = $item.Tag
            try {
                $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -eq 'Running') {
                    Stop-Service -Name $svcName -Force -ErrorAction Stop
                    Set-Service -Name $svcName -StartupType Manual -ErrorAction SilentlyContinue
                    Write-Log "  > $svcName parado e definido como Manual"
                } elseif ($svc) {
                    Write-Log "  > $svcName ja esta parado"
                }
            } catch {
                Write-Log "  > Erro ao parar $svcName : $_"
            }
        }
    }

    # Results
    Start-Sleep -Seconds 1
    $memAfter = Get-MemoryInfo
    $freedMB = [math]::Round(($memAfter.FreeGB - $memBefore.FreeGB) * 1024, 0)

    Write-Log "======================================="
    if ($freedMB -gt 0) {
        Write-Log "[OK] Otimizacao concluida! $freedMB MB liberados"
    } else {
        Write-Log "[OK] Otimizacao concluida! Memoria ja estava otimizada."
    }
    Write-Log "======================================="

    Update-MemoryDisplay

    $btnClean.Enabled = $true
    $btnClean.Text = "LIMPAR MEMORIA"
    $btnClean.BackColor = $accentBlue
})

# -- Refresh Button Click --
$btnRefresh.Add_Click({
    Write-Log "Atualizando informacoes..."
    Update-MemoryDisplay
    Write-Log "Informacoes atualizadas."
})

# -- Hover Effects --
$btnClean.Add_MouseEnter({ $btnClean.BackColor = $accentPurple })
$btnClean.Add_MouseLeave({ if ($btnClean.Enabled) { $btnClean.BackColor = $accentBlue } })
$btnRefresh.Add_MouseEnter({ $btnRefresh.BackColor = $bgCardHover })
$btnRefresh.Add_MouseLeave({ $btnRefresh.BackColor = $bgCard })

# -- Show Form --
$form.Add_Shown({ $form.Activate() })
[System.Windows.Forms.Application]::Run($form)
