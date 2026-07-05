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
$form.Size = New-Object System.Drawing.Size(820, 800)
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

# -- TabControl --
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(0, 70)
$tabControl.Size = New-Object System.Drawing.Size(804, 690)
$tabControl.Font = $fontNormal
$tabControl.BackColor = $bgDark
$tabControl.Appearance = "FlatButtons"
$tabControl.ItemSize = New-Object System.Drawing.Size(200, 36)
$tabControl.SizeMode = "Fixed"

$tabLimpeza = New-Object System.Windows.Forms.TabPage
$tabLimpeza.Text = "Limpeza"
$tabLimpeza.BackColor = $bgDark
$tabLimpeza.ForeColor = $textPrimary
$tabLimpeza.Padding = New-Object System.Windows.Forms.Padding(0)

$tabAgendamento = New-Object System.Windows.Forms.TabPage
$tabAgendamento.Text = "Agendamento"
$tabAgendamento.BackColor = $bgDark
$tabAgendamento.ForeColor = $textPrimary
$tabAgendamento.Padding = New-Object System.Windows.Forms.Padding(0)

$tabControl.TabPages.Add($tabLimpeza)
$tabControl.TabPages.Add($tabAgendamento)
$form.Controls.Add($tabControl)

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

$cardTotal  = New-StatCard 20 15 "TOTAL" $memInfo.TotalGB $textPrimary
$cardUsed   = New-StatCard 213 15 "EM USO" $memInfo.UsedGB $accentOrange
$cardFree   = New-StatCard 406 15 "LIVRE" $memInfo.FreeGB $accentGreen
$cardCached = New-StatCard 599 15 "CACHE" $memInfo.CachedGB $accentPurple

$tabLimpeza.Controls.AddRange(@($cardTotal, $cardUsed, $cardFree, $cardCached))

# -- Usage Bar --
$barPanel = New-Object System.Windows.Forms.Panel
$barPanel.Location = New-Object System.Drawing.Point(20, 130)
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

$tabLimpeza.Controls.Add($barPanel)

# -- Services Section --
$svcTitleLabel = New-Object System.Windows.Forms.Label
$svcTitleLabel.Text = "[+] Servicos Identificados (marque para desativar)"
$svcTitleLabel.Font = $fontSubtitle
$svcTitleLabel.ForeColor = $textPrimary
$svcTitleLabel.Location = New-Object System.Drawing.Point(20, 185)
$svcTitleLabel.AutoSize = $true
$tabLimpeza.Controls.Add($svcTitleLabel)

$svcListView = New-Object System.Windows.Forms.ListView
$svcListView.Location = New-Object System.Drawing.Point(20, 215)
$svcListView.Size = New-Object System.Drawing.Size(762, 250)
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

$tabLimpeza.Controls.Add($svcListView)

# -- Log TextBox --
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(20, 475)
$logBox.Size = New-Object System.Drawing.Size(540, 95)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BackColor = $bgPanel
$logBox.ForeColor = $accentGreen
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logBox.BorderStyle = "None"
$logBox.Text = "[$(Get-Date -Format 'HH:mm:ss')] Pronto. Clique em LIMPAR para otimizar.`r`n"
$tabLimpeza.Controls.Add($logBox)

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
$btnClean.Location = New-Object System.Drawing.Point(572, 475)
$btnClean.FlatStyle = "Flat"
$btnClean.FlatAppearance.BorderSize = 0
$btnClean.BackColor = $accentBlue
$btnClean.ForeColor = [System.Drawing.Color]::White
$btnClean.Cursor = [System.Windows.Forms.Cursors]::Hand

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "ATUALIZAR"
$btnRefresh.Font = $fontSmall
$btnRefresh.Size = New-Object System.Drawing.Size(220, 40)
$btnRefresh.Location = New-Object System.Drawing.Point(572, 530)
$btnRefresh.FlatStyle = "Flat"
$btnRefresh.FlatAppearance.BorderSize = 1
$btnRefresh.FlatAppearance.BorderColor = $borderColor
$btnRefresh.BackColor = $bgCard
$btnRefresh.ForeColor = $textPrimary
$btnRefresh.Cursor = [System.Windows.Forms.Cursors]::Hand

$tabLimpeza.Controls.AddRange(@($btnClean, $btnRefresh))

# ================================================================
# -- SCHEDULING TAB (Windows Task Scheduler) --
# ================================================================

$script:taskName = "MemoryCleanerAutoClean"
$script:silentScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "LimparSilencioso.ps1"
$script:logFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "cleaner_log.txt"
$script:scheduleRunning = $false
$script:nextRunTime = $null
$script:lastLogWriteTime = if (Test-Path $script:logFile) { (Get-Item $script:logFile).LastWriteTime } else { $null }
$script:lastLogLinesCount = if (Test-Path $script:logFile) { @(Get-Content $script:logFile -ErrorAction SilentlyContinue).Count } else { 0 }


# -- Countdown timer (updates every second for visual feedback) --
$script:countdownTimer = New-Object System.Windows.Forms.Timer
$script:countdownTimer.Interval = 1000

# -- Helper: Check if task exists --
function Get-CleanerTask {
    try {
        $task = Get-ScheduledTask -TaskName $script:taskName -ErrorAction SilentlyContinue
        return $task
    } catch {
        return $null
    }
}

# -- Helper: Get execution count from log --
function Get-ExecCount {
    if (Test-Path $script:logFile) {
        $lines = Select-String -Path $script:logFile -Pattern "Limpeza automatica iniciada" -ErrorAction SilentlyContinue
        if ($lines) { return $lines.Count }
    }
    return 0
}

# -- Helper: Get last run time from log --
function Get-LastRunTime {
    if (Test-Path $script:logFile) {
        $lines = Select-String -Path $script:logFile -Pattern "Limpeza concluida" -ErrorAction SilentlyContinue
        if ($lines -and $lines.Count -gt 0) {
            $lastLine = $lines[-1].Line
            if ($lastLine -match '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') {
                return $matches[1]
            }
        }
    }
    return $null
}

# -- Schedule Header --
$schedHeaderPanel = New-Object System.Windows.Forms.Panel
$schedHeaderPanel.Location = New-Object System.Drawing.Point(20, 15)
$schedHeaderPanel.Size = New-Object System.Drawing.Size(762, 60)
$schedHeaderPanel.BackColor = $bgPanel

$schedHeaderLabel = New-Object System.Windows.Forms.Label
$schedHeaderLabel.Text = "[#] Agendamento de Limpeza Automatica"
$schedHeaderLabel.Font = $fontTitle
$schedHeaderLabel.ForeColor = $accentPurple
$schedHeaderLabel.Location = New-Object System.Drawing.Point(16, 8)
$schedHeaderLabel.AutoSize = $true
$schedHeaderPanel.Controls.Add($schedHeaderLabel)

$schedSubLabel = New-Object System.Windows.Forms.Label
$schedSubLabel.Text = "A limpeza continua rodando mesmo com o programa fechado"
$schedSubLabel.Font = $fontSmall
$schedSubLabel.ForeColor = $textSecondary
$schedSubLabel.Location = New-Object System.Drawing.Point(18, 38)
$schedSubLabel.AutoSize = $true
$schedHeaderPanel.Controls.Add($schedSubLabel)

$tabAgendamento.Controls.Add($schedHeaderPanel)

# -- Interval Input Card --
$intervalCard = New-Object System.Windows.Forms.Panel
$intervalCard.Location = New-Object System.Drawing.Point(20, 90)
$intervalCard.Size = New-Object System.Drawing.Size(370, 160)
$intervalCard.BackColor = $bgCard

$intervalTitle = New-Object System.Windows.Forms.Label
$intervalTitle.Text = "INTERVALO (MINUTOS)"
$intervalTitle.Font = $fontSubtitle
$intervalTitle.ForeColor = $textSecondary
$intervalTitle.Location = New-Object System.Drawing.Point(16, 14)
$intervalTitle.AutoSize = $true
$intervalCard.Controls.Add($intervalTitle)

$intervalInput = New-Object System.Windows.Forms.NumericUpDown
$intervalInput.Location = New-Object System.Drawing.Point(16, 50)
$intervalInput.Size = New-Object System.Drawing.Size(338, 40)
$intervalInput.Font = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)
$intervalInput.Minimum = 1
$intervalInput.Maximum = 1440
$intervalInput.Value = 15
$intervalInput.BackColor = $bgPanel
$intervalInput.ForeColor = $accentBlue
$intervalInput.BorderStyle = "None"
$intervalInput.TextAlign = "Center"
$intervalCard.Controls.Add($intervalInput)

$intervalHint = New-Object System.Windows.Forms.Label
$intervalHint.Text = "Min: 1 min  |  Max: 1440 min (24h)  |  Padrao: 15 min"
$intervalHint.Font = $fontSmall
$intervalHint.ForeColor = $textSecondary
$intervalHint.Location = New-Object System.Drawing.Point(16, 120)
$intervalHint.AutoSize = $true
$intervalCard.Controls.Add($intervalHint)

# -- Quick Presets --
$presetTitle = New-Object System.Windows.Forms.Label
$presetTitle.Text = "Atalhos:"
$presetTitle.Font = $fontSmall
$presetTitle.ForeColor = $textSecondary
$presetTitle.Location = New-Object System.Drawing.Point(16, 140)
$presetTitle.AutoSize = $true
$intervalCard.Controls.Add($presetTitle)

$tabAgendamento.Controls.Add($intervalCard)

# -- Preset Buttons --
$presetPanel = New-Object System.Windows.Forms.Panel
$presetPanel.Location = New-Object System.Drawing.Point(20, 260)
$presetPanel.Size = New-Object System.Drawing.Size(370, 45)
$presetPanel.BackColor = $bgDark

$presetValues = @(5, 15, 30, 60)
$presetLabels = @("5 min", "15 min", "30 min", "1 hora")
$presetBtnWidth = 85
for ($i = 0; $i -lt $presetValues.Count; $i++) {
    $pb = New-Object System.Windows.Forms.Button
    $pb.Text = $presetLabels[$i]
    $pb.Font = $fontSmall
    $pb.Size = New-Object System.Drawing.Size($presetBtnWidth, 35)
    $pb.Location = New-Object System.Drawing.Point(($i * ($presetBtnWidth + 8)), 5)
    $pb.FlatStyle = "Flat"
    $pb.FlatAppearance.BorderSize = 1
    $pb.FlatAppearance.BorderColor = $borderColor
    $pb.BackColor = $bgCard
    $pb.ForeColor = $textPrimary
    $pb.Cursor = [System.Windows.Forms.Cursors]::Hand
    $pb.Tag = $presetValues[$i]
    $pb.Add_Click({
        $intervalInput.Value = [int]$this.Tag
    })
    $pb.Add_MouseEnter({ $this.BackColor = $bgCardHover })
    $pb.Add_MouseLeave({ $this.BackColor = $bgCard })
    $presetPanel.Controls.Add($pb)
}
$tabAgendamento.Controls.Add($presetPanel)

# -- Status Card --
$statusCard = New-Object System.Windows.Forms.Panel
$statusCard.Location = New-Object System.Drawing.Point(410, 90)
$statusCard.Size = New-Object System.Drawing.Size(372, 215)
$statusCard.BackColor = $bgCard

$statusTitle = New-Object System.Windows.Forms.Label
$statusTitle.Text = "STATUS"
$statusTitle.Font = $fontSubtitle
$statusTitle.ForeColor = $textSecondary
$statusTitle.Location = New-Object System.Drawing.Point(16, 14)
$statusTitle.AutoSize = $true
$statusCard.Controls.Add($statusTitle)

$statusIndicator = New-Object System.Windows.Forms.Label
$statusIndicator.Text = "INATIVO"
$statusIndicator.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$statusIndicator.ForeColor = $textSecondary
$statusIndicator.Location = New-Object System.Drawing.Point(16, 42)
$statusIndicator.AutoSize = $true
$statusCard.Controls.Add($statusIndicator)

$countdownLabel = New-Object System.Windows.Forms.Label
$countdownLabel.Text = "Proxima limpeza: --:--:--"
$countdownLabel.Font = $fontNormal
$countdownLabel.ForeColor = $textSecondary
$countdownLabel.Location = New-Object System.Drawing.Point(16, 85)
$countdownLabel.Size = New-Object System.Drawing.Size(340, 25)
$statusCard.Controls.Add($countdownLabel)

$execCountLabel = New-Object System.Windows.Forms.Label
$execCountLabel.Text = "Execucoes realizadas: 0"
$execCountLabel.Font = $fontNormal
$execCountLabel.ForeColor = $textSecondary
$execCountLabel.Location = New-Object System.Drawing.Point(16, 115)
$execCountLabel.Size = New-Object System.Drawing.Size(340, 25)
$statusCard.Controls.Add($execCountLabel)

$intervalShowLabel = New-Object System.Windows.Forms.Label
$intervalShowLabel.Text = "Intervalo: -- min"
$intervalShowLabel.Font = $fontNormal
$intervalShowLabel.ForeColor = $textSecondary
$intervalShowLabel.Location = New-Object System.Drawing.Point(16, 145)
$intervalShowLabel.Size = New-Object System.Drawing.Size(340, 25)
$statusCard.Controls.Add($intervalShowLabel)

$lastRunLabel = New-Object System.Windows.Forms.Label
$lastRunLabel.Text = "Ultima limpeza: --"
$lastRunLabel.Font = $fontNormal
$lastRunLabel.ForeColor = $textSecondary
$lastRunLabel.Location = New-Object System.Drawing.Point(16, 175)
$lastRunLabel.Size = New-Object System.Drawing.Size(340, 25)
$statusCard.Controls.Add($lastRunLabel)

$tabAgendamento.Controls.Add($statusCard)

# -- Start/Stop Button --
$btnSchedule = New-Object System.Windows.Forms.Button
$btnSchedule.Text = "INICIAR AGENDAMENTO"
$btnSchedule.Font = $fontMedium
$btnSchedule.Size = New-Object System.Drawing.Size(370, 55)
$btnSchedule.Location = New-Object System.Drawing.Point(20, 320)
$btnSchedule.FlatStyle = "Flat"
$btnSchedule.FlatAppearance.BorderSize = 0
$btnSchedule.BackColor = $accentGreen
$btnSchedule.ForeColor = [System.Drawing.Color]::FromArgb(20, 20, 30)
$btnSchedule.Cursor = [System.Windows.Forms.Cursors]::Hand
$tabAgendamento.Controls.Add($btnSchedule)

# -- Schedule Log --
$schedLogBox = New-Object System.Windows.Forms.TextBox
$schedLogBox.Location = New-Object System.Drawing.Point(20, 390)
$schedLogBox.Size = New-Object System.Drawing.Size(762, 250)
$schedLogBox.Multiline = $true
$schedLogBox.ScrollBars = "Vertical"
$schedLogBox.ReadOnly = $true
$schedLogBox.BackColor = $bgPanel
$schedLogBox.ForeColor = $accentGreen
$schedLogBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$schedLogBox.BorderStyle = "None"
$schedLogBox.Text = "[$(Get-Date -Format 'HH:mm:ss')] Agendamento pronto. Defina o intervalo e clique em INICIAR.`r`n"
$tabAgendamento.Controls.Add($schedLogBox)

function Write-ScheduleLog {
    param([string]$message)
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $schedLogBox.AppendText("[$timestamp] $message`r`n")
    $schedLogBox.SelectionStart = $schedLogBox.Text.Length
    $schedLogBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# -- Check for existing task on startup --
$existingTask = Get-CleanerTask
if ($existingTask -and $existingTask.State -ne 'Disabled') {
    $script:scheduleRunning = $true

    # Extract interval from task trigger
    $trigger = $existingTask.Triggers[0]
    $repInterval = $trigger.Repetition.Interval
    $taskMinutes = 15
    if ($repInterval -match 'PT(\d+)M') { $taskMinutes = [int]$matches[1] }
    elseif ($repInterval -match 'PT(\d+)H') { $taskMinutes = [int]$matches[1] * 60 }

    $intervalInput.Value = $taskMinutes
    $intervalInput.Enabled = $false

    $statusIndicator.Text = "ATIVO"
    $statusIndicator.ForeColor = $accentGreen
    $intervalShowLabel.Text = "Intervalo: $taskMinutes min"

    $execCount = Get-ExecCount
    $execCountLabel.Text = "Execucoes realizadas: $execCount"

    $lastRun = Get-LastRunTime
    if ($lastRun) { $lastRunLabel.Text = "Ultima limpeza: $lastRun" }

    $script:nextRunTime = (Get-Date).AddMinutes($taskMinutes)
    if ($existingTask.LastRunTime -and $existingTask.LastRunTime -gt (Get-Date).AddDays(-1)) {
        $script:nextRunTime = $existingTask.LastRunTime.AddMinutes($taskMinutes)
        if ($script:nextRunTime -lt (Get-Date)) {
            $script:nextRunTime = (Get-Date).AddMinutes(1)
        }
    }
    $countdownLabel.ForeColor = $accentBlue
    $script:countdownTimer.Start()

    $btnSchedule.Text = "PARAR AGENDAMENTO"
    $btnSchedule.BackColor = $accentRed
    $btnSchedule.ForeColor = [System.Drawing.Color]::White

    Write-ScheduleLog "Tarefa agendada detectada: limpeza a cada $taskMinutes min"
    Write-ScheduleLog "A limpeza continua rodando mesmo com o programa fechado."
    if ($lastRun) { Write-ScheduleLog "Ultima execucao registrada: $lastRun" }
}

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

# -- Reusable Clean Function --
function Invoke-MemoryClean {
    param(
        [scriptblock]$LogFunc = { param($msg) Write-Log $msg },
        [bool]$StopServices = $true
    )

    $memBefore = Get-MemoryInfo

    & $LogFunc "Iniciando otimizacao de memoria..."

    # Step 1: Flush working sets
    & $LogFunc "Reduzindo working sets dos processos..."
    try {
        $count = [MemoryOptimizer]::FlushWorkingSets()
        & $LogFunc "  > $count processos otimizados"
    } catch {
        & $LogFunc "  > Erro ao otimizar working sets: $_"
    }

    # Step 2: Clear standby cache
    & $LogFunc "Limpando cache de memoria em espera (Standby)..."
    try {
        $result = [MemoryOptimizer]::ClearStandbyList()
        if ($result) { & $LogFunc "  > Cache Standby limpo com sucesso" }
        else { & $LogFunc "  > Aviso: limpeza parcial do cache" }
    } catch {
        & $LogFunc "  > Erro: $_"
    }

    # Step 3: Clear modified page list
    & $LogFunc "Limpando lista de paginas modificadas..."
    try {
        [MemoryOptimizer]::ClearModifiedPageList() | Out-Null
        & $LogFunc "  > Paginas modificadas limpas"
    } catch {
        & $LogFunc "  > Erro: $_"
    }

    # Step 4: .NET Garbage Collection
    & $LogFunc "Executando coleta de lixo .NET..."
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
    & $LogFunc "  > GC concluido"

    # Step 5: Clear temp files
    & $LogFunc "Limpando arquivos temporarios..."
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
    & $LogFunc "  > $deletedCount arquivos temporarios removidos"

    # Step 6: Flush DNS
    & $LogFunc "Limpando cache DNS..."
    try {
        ipconfig /flushdns | Out-Null
        & $LogFunc "  > Cache DNS limpo"
    } catch {
        & $LogFunc "  > Erro ao limpar DNS"
    }

    # Step 7: Stop selected services (only from manual button)
    if ($StopServices) {
        $checkedItems = @()
        foreach ($item in $svcListView.Items) {
            if ($item.Checked) { $checkedItems += $item }
        }

        if ($checkedItems.Count -gt 0) {
            & $LogFunc "Parando $($checkedItems.Count) servico(s) selecionado(s)..."
            foreach ($item in $checkedItems) {
                $svcName = $item.Tag
                try {
                    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                    if ($svc -and $svc.Status -eq 'Running') {
                        Stop-Service -Name $svcName -Force -ErrorAction Stop
                        Set-Service -Name $svcName -StartupType Manual -ErrorAction SilentlyContinue
                        & $LogFunc "  > $svcName parado e definido como Manual"
                    } elseif ($svc) {
                        & $LogFunc "  > $svcName ja esta parado"
                    }
                } catch {
                    & $LogFunc "  > Erro ao parar $svcName : $_"
                }
            }
        }
    }

    # Results
    Start-Sleep -Seconds 1
    $memAfter = Get-MemoryInfo
    $freedMB = [math]::Round(($memAfter.FreeGB - $memBefore.FreeGB) * 1024, 0)

    & $LogFunc "======================================="
    if ($freedMB -gt 0) {
        & $LogFunc "[OK] Otimizacao concluida! $freedMB MB liberados"
    } else {
        & $LogFunc "[OK] Otimizacao concluida! Memoria ja estava otimizada."
    }
    & $LogFunc "======================================="

    Update-MemoryDisplay
    return $freedMB
}

# -- Clean Button Click --
$btnClean.Add_Click({
    $btnClean.Enabled = $false
    $btnClean.Text = "Limpando..."
    $btnClean.BackColor = $bgCardHover
    [System.Windows.Forms.Application]::DoEvents()

    Invoke-MemoryClean -LogFunc { param($msg) Write-Log $msg } -StopServices $true

    $btnClean.Enabled = $true
    $btnClean.Text = "LIMPAR MEMORIA"
    $btnClean.BackColor = $accentBlue
})

# -- Countdown Timer Tick (visual feedback and log sync) --
$script:countdownTimer.Add_Tick({
    # 1. Sync logs from background task
    if (Test-Path $script:logFile) {
        $currentWriteTime = (Get-Item $script:logFile).LastWriteTime
        if ($script:lastLogWriteTime -eq $null -or $currentWriteTime -gt $script:lastLogWriteTime) {
            $allLines = @(Get-Content $script:logFile -ErrorAction SilentlyContinue)
            if ($allLines.Count -gt 0) {
                if ($allLines.Count -lt $script:lastLogLinesCount) { $script:lastLogLinesCount = 0 }
                if ($allLines.Count -gt $script:lastLogLinesCount) {
                    $newLines = $allLines[$script:lastLogLinesCount..($allLines.Count - 1)]
                    foreach ($line in $newLines) {
                        $schedLogBox.AppendText("$line`r`n")
                    }
                    $schedLogBox.SelectionStart = $schedLogBox.Text.Length
                    $schedLogBox.ScrollToCaret()
                    Update-MemoryDisplay
                }
                $script:lastLogLinesCount = $allLines.Count
            }
            $script:lastLogWriteTime = $currentWriteTime
        }
    }

    # 2. Update countdown visuals
    if ($script:nextRunTime -ne $null -and $script:scheduleRunning) {
        $remaining = $script:nextRunTime - (Get-Date)
        if ($remaining.TotalSeconds -gt 0) {
            $countdownLabel.Text = "Proxima limpeza: $($remaining.ToString('hh\:mm\:ss'))"
        } else {
            # Reset countdown for next cycle
            $mins = [int]$intervalInput.Value
            $script:nextRunTime = (Get-Date).AddMinutes($mins)
            $countdownLabel.Text = "Proxima limpeza: executando..."

            # Update exec count from log
            $execCount = Get-ExecCount
            $execCountLabel.Text = "Execucoes realizadas: $execCount"
            $lastRun = Get-LastRunTime
            if ($lastRun) { $lastRunLabel.Text = "Ultima limpeza: $lastRun" }
        }
    }
})

# -- Schedule Button Click (Windows Task Scheduler) --
$btnSchedule.Add_Click({
    if (-not $script:scheduleRunning) {
        # START: Register Windows Scheduled Task
        $minutes = [int]$intervalInput.Value

        try {
            # Remove existing task if any
            Unregister-ScheduledTask -TaskName $script:taskName -Confirm:$false -ErrorAction SilentlyContinue

            # Clear previous log
            if (Test-Path $script:logFile) { Remove-Item $script:logFile -Force -ErrorAction SilentlyContinue }

            # Create task action
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($script:silentScript)`"" -WorkingDirectory (Split-Path -Parent $script:silentScript)

            # Create trigger with repetition
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $minutes) -RepetitionDuration (New-TimeSpan -Days 10000)

            # Task settings
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

            # Create principal (run as current user with highest privileges)
            $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -RunLevel Highest -LogonType S4U

            # Register the task
            Register-ScheduledTask -TaskName $script:taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "MemoryCleaner - Limpeza automatica de memoria a cada $minutes minutos" -Force | Out-Null

            $script:scheduleRunning = $true
            $script:nextRunTime = (Get-Date).AddMinutes($minutes)
            $script:countdownTimer.Start()

            $statusIndicator.Text = "ATIVO"
            $statusIndicator.ForeColor = $accentGreen
            $countdownLabel.ForeColor = $accentBlue
            $execCountLabel.Text = "Execucoes realizadas: 0"
            $intervalShowLabel.Text = "Intervalo: $minutes min"
            $lastRunLabel.Text = "Ultima limpeza: --"

            $btnSchedule.Text = "PARAR AGENDAMENTO"
            $btnSchedule.BackColor = $accentRed
            $btnSchedule.ForeColor = [System.Drawing.Color]::White
            $intervalInput.Enabled = $false

            Write-ScheduleLog "Tarefa registrada no Agendador do Windows!"
            Write-ScheduleLog "Limpeza a cada $minutes minutos (mesmo com o programa fechado)"
            Write-ScheduleLog "Proxima execucao: $(Get-Date $script:nextRunTime -Format 'HH:mm:ss')"
            Write-ScheduleLog "Nome da tarefa: $($script:taskName)"
        } catch {
            Write-ScheduleLog "[ERRO] Falha ao criar tarefa agendada: $_"
            [System.Windows.Forms.MessageBox]::Show("Erro ao criar tarefa agendada:`n$_", "MemoryCleaner - Erro", "OK", "Error")
        }
    } else {
        # STOP: Unregister Windows Scheduled Task
        try {
            Unregister-ScheduledTask -TaskName $script:taskName -Confirm:$false -ErrorAction Stop

            $script:countdownTimer.Stop()
            $script:scheduleRunning = $false
            $script:nextRunTime = $null

            $statusIndicator.Text = "INATIVO"
            $statusIndicator.ForeColor = $textSecondary
            $countdownLabel.Text = "Proxima limpeza: --:--:--"
            $countdownLabel.ForeColor = $textSecondary

            $btnSchedule.Text = "INICIAR AGENDAMENTO"
            $btnSchedule.BackColor = $accentGreen
            $btnSchedule.ForeColor = [System.Drawing.Color]::FromArgb(20, 20, 30)
            $intervalInput.Enabled = $true

            $execCount = Get-ExecCount
            Write-ScheduleLog "Tarefa removida do Agendador do Windows."
            Write-ScheduleLog "Total de execucoes registradas: $execCount"
        } catch {
            Write-ScheduleLog "[ERRO] Falha ao remover tarefa: $_"
        }
    }
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
$btnSchedule.Add_MouseEnter({
    if ($script:scheduleRunning) { $btnSchedule.BackColor = [System.Drawing.Color]::FromArgb(200, 60, 60) }
    else { $btnSchedule.BackColor = [System.Drawing.Color]::FromArgb(60, 200, 120) }
})
$btnSchedule.Add_MouseLeave({
    if ($script:scheduleRunning) { $btnSchedule.BackColor = $accentRed }
    else { $btnSchedule.BackColor = $accentGreen }
})

# -- Cleanup on form close --
$form.Add_FormClosing({
    if ($script:countdownTimer) { $script:countdownTimer.Stop(); $script:countdownTimer.Dispose() }
    # NOTA: A tarefa agendada no Windows Task Scheduler NAO e removida ao fechar.
    # Ela continua rodando em segundo plano. Para parar, use o botao PARAR AGENDAMENTO.
})

# -- Show Form --
$form.Add_Shown({ $form.Activate() })
[System.Windows.Forms.Application]::Run($form)
