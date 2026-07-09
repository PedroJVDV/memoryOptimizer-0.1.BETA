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

switch ($Action) {
    "GetMemory" {
        Get-MemoryInfoJSON | ConvertTo-Json -Depth 2 -Compress
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
    default {
        @{ Error = "Unknown action" } | ConvertTo-Json
    }
}
