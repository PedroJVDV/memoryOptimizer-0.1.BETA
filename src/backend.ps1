param (
    [Parameter(Mandatory=$true)]
    [string]$Action
)

$ErrorActionPreference = "SilentlyContinue"

# -- Auto-Elevacao: se for limpar, deve ter admin --
if ($Action -eq "CleanMemory") {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Output ( @{ Error = "AdminRequired" } | ConvertTo-Json )
        exit
    }
}

# -- Win32 API Definitions for Memory Cleaning --
if (-not ([System.Management.Automation.PSTypeName]'MemoryOptimizer').Type) {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    using System.Diagnostics;

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
            if (!OpenProcessToken(Process.GetCurrentProcess().Handle, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out tokenHandle))
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
            return NtSetSystemInformation(80, ref command, sizeof(int)) == 0;
        }

        public static bool ClearModifiedPageList()
        {
            EnablePrivilege(SE_PROF_SINGLE_PROCESS_NAME);
            int command = 3;
            return NtSetSystemInformation(80, ref command, sizeof(int)) == 0;
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
}

# ==========================================
# FUNÇÕES DE COLETA DE DADOS
# ==========================================

function Get-MemoryInfoJSON {
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
        } catch { }
    }
    $cachedGB = [math]::Round($cachedBytes / 1GB, 2)

    return @{ TotalGB = $totalGB; FreeGB = $freeGB; UsedGB = $usedGB; CachedGB = $cachedGB; PctUsed = $pctUsed }
}

function Get-SystemHealthJSON {
    $health = @{}
    
    $basePath = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $dllPath = Join-Path $basePath "LibreHardwareMonitorLib.dll"
    
    $lhmComputer = $null
    if (Test-Path $dllPath) {
        try {
            Add-Type -Path $dllPath
            $lhmComputer = New-Object LibreHardwareMonitor.Hardware.Computer
            $lhmComputer.IsCpuEnabled = $true
            $lhmComputer.IsGpuEnabled = $true
            $lhmComputer.IsMemoryEnabled = $true
            $lhmComputer.IsStorageEnabled = $true
            $lhmComputer.IsBatteryEnabled = $true
            $lhmComputer.IsNetworkEnabled = $true
            $lhmComputer.Open()
        } catch { }
    }

    # Helper function to get LHM sensor value
    function Get-SensorValue {
        param($hwType, $sensorType, $sensorNameMatch)
        if (-not $lhmComputer) { return 0 }
        foreach ($hw in $lhmComputer.Hardware) {
            if ($hw.HardwareType.ToString() -match $hwType) {
                $hw.Update()
                foreach ($sensor in $hw.Sensors) {
                    if ($sensor.SensorType.ToString() -match $sensorType -and $sensor.Name -match $sensorNameMatch) {
                        return $sensor.Value
                    }
                }
            }
        }
        return 0
    }

    # -- DISCO --
    try {
        $diskInfo = @{ Name = "Disco Principal"; Score = 100; Status = "Bom"; Alerts = @(); Age = "N/D"; Wear = "N/D" }
        
        # WMI para uso livre
        $ld = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        if ($ld) {
            $freePct = [math]::Round(($ld.FreeSpace / $ld.Size) * 100, 1)
            if ($freePct -lt 15) { $diskInfo.Status = "Atencao"; $diskInfo.Alerts += "Apenas $freePct% livre" }
        }

        # LHM para SSD Life e Power On
        $life = Get-SensorValue "Storage" "Level" "Life|Percentage Used"
        $poh = Get-SensorValue "Storage" "Factor" "Power On Hours"
        
        if ($life -gt 0) { 
            # Se for Percentage Used, invertemos
            if ((Get-SensorValue "Storage" "Level" "Percentage Used") -gt 0) { $life = 100 - $life }
            $diskInfo.Score = $life
            $diskInfo.Wear = "$life% Restante"
            if ($life -lt 30) { $diskInfo.Status = "Critico"; $diskInfo.Alerts += "Desgaste alto do SSD" }
        }
        if ($poh -gt 0) {
            $months = [math]::Round($poh / 24 / 30, 1)
            $diskInfo.Age = "$months meses de uso ativo"
        } else {
            # Fallback age via Windows Install Date
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
            if ($os.InstallDate) {
                $months = [math]::Round(((Get-Date) - $os.InstallDate).TotalDays / 30, 1)
                $diskInfo.Age = "$months meses (desde install)"
            }
        }
        
        $health.Disco = $diskInfo
    } catch { $health.Disco = @{ Name = "Erro"; Score = 0; Status = "Critico"; Alerts = @("Erro leitura"); Age="N/D"; Wear="N/D" } }

    # -- BATERIA --
    try {
        $bat = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($bat) {
            $c = if ($bat.EstimatedChargeRemaining) { [int]$bat.EstimatedChargeRemaining } else { 0 }
            $bScore = $c; $bStatus = "Bom"; $bAlerts = @()
            if ($c -lt 20) { $bStatus = "Critico"; $bAlerts += "Bateria baixa!" }
            elseif ($c -lt 50) { $bStatus = "Atencao"; $bAlerts += "Bateria < 50%" }
            $health.Bateria = @{ Name = "Bateria"; Details = "Carga: $c%"; Score = $bScore; Status = $bStatus; Alerts = $bAlerts; Load="N/D"; Power="N/D" }
        } else { $health.Bateria = @{ Name = "Desktop"; Details = "Desktop conectado a tomada. Medicao irrelevante."; Score = 100; Status = "Bom"; Alerts = @(); Load="N/D"; Power="N/D" } }
    } catch { $health.Bateria = @{ Name = "Erro"; Details = "Erro"; Score = 0; Status = "Critico"; Alerts = @() } }

    # -- CPU --
    try {
        $cpuName = "Processador"
        $wmiCpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($wmiCpu) { $cpuName = $wmiCpu.Name.Trim() }

        $cpuPower = Get-SensorValue "Cpu" "Power" "Package"
        $cpuTemp = Get-SensorValue "Cpu" "Temperature" "Package|Core"
        $cpuClock = Get-SensorValue "Cpu" "Clock" "Core"
        $cpuLoad = Get-SensorValue "Cpu" "Load" "Total"
        if ($cpuLoad -eq 0 -and $wmiCpu) { $cpuLoad = $wmiCpu.LoadPercentage }

        $cScore = 100; $cStatus = "Bom"; $cAlerts = @()
        if ($cpuTemp -gt 85) { $cScore -= 30; $cStatus = "Critico"; $cAlerts += "Temperatura perigosa ($([math]::Round($cpuTemp)) C)" }
        elseif ($cpuTemp -gt 75) { $cScore -= 10; $cStatus = "Atencao"; $cAlerts += "Temperatura alta ($([math]::Round($cpuTemp)) C)" }
        
        if ($cpuLoad -gt 90) { $cScore -= 15; if($cStatus -ne "Critico"){$cStatus = "Atencao"}; $cAlerts += "Carga alta ($([math]::Round($cpuLoad))%)" }

        # Age from BIOS
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
        $cpuAge = "N/D"
        if ($bios.ReleaseDate) {
            $years = [math]::Round(((Get-Date) - $bios.ReleaseDate).TotalDays / 365, 1)
            $cpuAge = "~ $years Anos"
        }

        $health.CPU = @{ 
            Name = $cpuName; 
            Score = [math]::Max(10, $cScore); 
            Status = $cStatus; 
            Alerts = $cAlerts;
            Age = $cpuAge;
            Power = if($cpuPower -gt 0){"$([math]::Round($cpuPower)) W"}else{"-- W"};
            Clock = if($cpuClock -gt 0){"$([math]::Round($cpuClock)) MHz"}else{"-- MHz"};
            Load = "$([math]::Round($cpuLoad)) %"
        }
    } catch { $health.CPU = @{ Name = "Erro"; Score = 0; Status = "Critico"; Alerts = @(); Age="N/D" } }

    # -- RAM --
    try {
        $mem = Get-MemoryInfoJSON
        $rScore = 100; $rStatus = "Bom"; $rAlerts = @()
        if ($mem.PctUsed -gt 90) { $rScore -= 40; $rStatus = "Critico"; $rAlerts += "Uso acima de 90%" }
        elseif ($mem.PctUsed -gt 75) { $rScore -= 20; $rStatus = "Atencao"; $rAlerts += "Uso elevado ($($mem.PctUsed)%)" }

        $health.RAM = @{ 
            Name = "$($mem.TotalGB) GB RAM"; 
            Score = [math]::Max(10, $rScore); 
            Status = $rStatus; 
            Alerts = $rAlerts;
            Load = "$($mem.PctUsed) %";
            Wear = "Desgaste irrelevante"
        }
    } catch { $health.RAM = @{ Name = "Erro"; Score = 0; Status = "Critico"; Alerts = @() } }

    # -- GPU --
    try {
        $gpuPower = Get-SensorValue "Gpu" "Power" "GPU|Package"
        $gpuTemp = Get-SensorValue "Gpu" "Temperature" "Core|GPU"
        $gpuClock = Get-SensorValue "Gpu" "Clock" "Core|GPU"
        $gpuLoad = Get-SensorValue "Gpu" "Load" "Core|GPU"
        
        $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue
        $gpuInfo = @($gpus) | Where-Object { $_.AdapterRAM -and $_.AdapterRAM -gt 0 } | Select-Object -First 1
        if (-not $gpuInfo) { $gpuInfo = @($gpus) | Select-Object -First 1 }
        
        $gScore = 100; $gStatus = "Bom"; $gAlerts = @()
        if ($gpuTemp -gt 85) { $gScore -= 30; $gStatus = "Critico"; $gAlerts += "GPU superaquecida ($([math]::Round($gpuTemp)) C)" }
        elseif ($gpuTemp -gt 75) { $gScore -= 10; $gStatus = "Atencao" }

        $vram = if ($gpuInfo.AdapterRAM) { "$([math]::Round($gpuInfo.AdapterRAM / 1GB, 1)) GB" } else { "Integrada" }
        
        $health.GPU = @{ 
            Name = if ($gpuInfo) { $gpuInfo.Name } else { "GPU" }; 
            Score = $gScore; 
            Status = $gStatus; 
            Alerts = $gAlerts;
            Power = if($gpuPower -gt 0){"$([math]::Round($gpuPower)) W"}else{"-- W"};
            Clock = if($gpuClock -gt 0){"$([math]::Round($gpuClock)) MHz"}else{"-- MHz"};
            Load = "$([math]::Round($gpuLoad)) %"
        }
    } catch { $health.GPU = @{ Name = "Erro"; Score = 0; Status = "Critico"; Alerts = @() } }

    if ($lhmComputer) {
        $lhmComputer.Close()
    }

    return $health
}

# ==========================================
# ROTEDOR DE AÇÕES
# ==========================================

switch ($Action) {
    "GetMemory" {
        Get-MemoryInfoJSON | ConvertTo-Json -Depth 2 -Compress
    }
    "GetHealth" {
        Get-SystemHealthJSON | ConvertTo-Json -Depth 5 -Compress
    }
    "CleanMemory" {
        $memBefore = Get-MemoryInfoJSON
        $logs = @()

        $count = [MemoryOptimizer]::FlushWorkingSets(); $logs += "Processos otimizados: $count"
        if ([MemoryOptimizer]::ClearStandbyList()) { $logs += "Cache Standby limpo" }
        [MemoryOptimizer]::ClearModifiedPageList() | Out-Null; $logs += "Paginas modificadas limpas"

        [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers(); [System.GC]::Collect()

        ipconfig /flushdns | Out-Null; $logs += "Cache DNS limpo"

        Start-Sleep -Seconds 1
        $memAfter = Get-MemoryInfoJSON
        $freedMB = [math]::Round(($memAfter.FreeGB - $memBefore.FreeGB) * 1024, 0)

        @{ FreedMB = $freedMB; Logs = $logs; NewMemory = $memAfter } | ConvertTo-Json -Depth 3 -Compress
    }
    "SetSchedule" {
        $intervalMinutes = [int]$env:SCHEDULE_MINUTES
        if ($intervalMinutes -le 0) { $intervalMinutes = 15 }
        $threshold = [int]$env:SCHEDULE_THRESHOLD
        if ($threshold -le 0) { $threshold = 0 }

        $taskName = "MemoryCleanerAutoClean"
        $scriptPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "LimparSilencioso.ps1"
        
        if (-not (Test-Path $scriptPath)) {
            @{ Error = "LimparSilencioso.ps1 nao encontrado na pasta do backend" } | ConvertTo-Json
            exit
        }

        # Cria a acao com argumentos passando o threshold
        $actionArgs = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -Threshold $threshold"
        $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs
        
        # Check admin
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            @{ Error = "AdminRequired" } | ConvertTo-Json
            exit
        }

        try {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($intervalMinutes) -RepetitionInterval (New-TimeSpan -Minutes $intervalMinutes)
            $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

            Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $taskAction -Settings $settings -Principal $principal -Force | Out-Null

            @{ Status = "Success"; Interval = $intervalMinutes } | ConvertTo-Json
        } catch {
            @{ Error = $_.Exception.Message } | ConvertTo-Json
        }
    }
    "RemoveSchedule" {
        $taskName = "MemoryCleanerAutoClean"
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            @{ Error = "AdminRequired" } | ConvertTo-Json
            exit
        }

        try {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            @{ Status = "Removed" } | ConvertTo-Json
        } catch {
            @{ Error = $_.Exception.Message } | ConvertTo-Json
        }
    }
    "CheckSchedule" {
        $taskName = "MemoryCleanerAutoClean"
        try {
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
            if ($task.State -ne 'Disabled') {
                $trigger = $task.Triggers[0]
                $repInterval = $trigger.Repetition.Interval
                $taskMinutes = 15
                if ($repInterval -match 'PT(\d+)M') { $taskMinutes = [int]$matches[1] }
                elseif ($repInterval -match 'PT(\d+)H') { $taskMinutes = [int]$matches[1] * 60 }
                
                $lastRun = if ($task.LastRunTime) { $task.LastRunTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
                
                @{ IsScheduled = $true; Interval = $taskMinutes; LastRun = $lastRun } | ConvertTo-Json
            } else {
                @{ IsScheduled = $false } | ConvertTo-Json
            }
        } catch {
            @{ IsScheduled = $false } | ConvertTo-Json
        }
    }
    default {
        @{ Error = "Unknown action" } | ConvertTo-Json
    }
}
