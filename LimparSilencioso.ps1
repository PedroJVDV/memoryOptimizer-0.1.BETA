# ============================================================
# MemoryCleaner - Script de Limpeza Silenciosa (sem GUI)
# Executado pelo Agendador de Tarefas do Windows
# ============================================================

# -- Verificar admin --
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { exit 1 }

# -- Win32 API --
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Diagnostics;

public class MemOptSilent
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

    public static bool EnablePrivilege(string privilege)
    {
        IntPtr tokenHandle;
        if (!OpenProcessToken(Process.GetCurrentProcess().Handle, 0x0020 | 0x0008, out tokenHandle))
            return false;
        TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
        tp.PrivilegeCount = 1;
        tp.Attributes = 0x00000002;
        if (!LookupPrivilegeValue(null, privilege, out tp.Luid))
        { CloseHandle(tokenHandle); return false; }
        bool result = AdjustTokenPrivileges(tokenHandle, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        CloseHandle(tokenHandle);
        return result;
    }

    public static bool ClearStandbyList()
    {
        EnablePrivilege("SeProfileSingleProcessPrivilege");
        EnablePrivilege("SeIncreaseQuotaPrivilege");
        int command = 4;
        return NtSetSystemInformation(80, ref command, sizeof(int)) == 0;
    }

    public static bool ClearModifiedPageList()
    {
        EnablePrivilege("SeProfileSingleProcessPrivilege");
        int command = 3;
        return NtSetSystemInformation(80, ref command, sizeof(int)) == 0;
    }

    public static int FlushWorkingSets()
    {
        int count = 0;
        foreach (Process proc in Process.GetProcesses())
        {
            try { EmptyWorkingSet(proc.Handle); count++; }
            catch { }
        }
        return count;
    }
}
"@ -ErrorAction SilentlyContinue

# -- Log file --
$logDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$logFile = Join-Path $logDir "cleaner_log.txt"

function Write-CleanerLog {
    param([string]$msg)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] $msg"
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

# -- Keep log file manageable (last 500 lines) --
if (Test-Path $logFile) {
    $lines = Get-Content $logFile -ErrorAction SilentlyContinue
    if ($lines.Count -gt 500) {
        $lines[-200..-1] | Set-Content $logFile -ErrorAction SilentlyContinue
    }
}

Write-CleanerLog "=== Limpeza automatica iniciada ==="

# Step 1: Flush working sets
try {
    $count = [MemOptSilent]::FlushWorkingSets()
    Write-CleanerLog "Working sets: $count processos otimizados"
} catch {
    Write-CleanerLog "Erro working sets: $_"
}

# Step 2: Clear standby cache
try {
    $result = [MemOptSilent]::ClearStandbyList()
    if ($result) { Write-CleanerLog "Standby cache limpo com sucesso" }
    else { Write-CleanerLog "Standby cache: limpeza parcial" }
} catch {
    Write-CleanerLog "Erro standby: $_"
}

# Step 3: Clear modified page list
try {
    [MemOptSilent]::ClearModifiedPageList() | Out-Null
    Write-CleanerLog "Paginas modificadas limpas"
} catch {
    Write-CleanerLog "Erro paginas: $_"
}

# Step 4: GC
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
[System.GC]::Collect()

# Step 5: Temp files
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
Write-CleanerLog "Arquivos temporarios removidos: $deletedCount"

# Step 6: DNS
try { ipconfig /flushdns | Out-Null; Write-CleanerLog "Cache DNS limpo" } catch {}

# Results
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$pctFree = [math]::Round(($freeGB / $totalGB) * 100, 1)
Write-CleanerLog "Memoria livre: $freeGB GB / $totalGB GB ($pctFree% livre)"
Write-CleanerLog "=== Limpeza concluida ==="
