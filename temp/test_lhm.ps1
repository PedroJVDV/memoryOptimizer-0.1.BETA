$dllPath = "C:\Users\T-GAMER\Downloads\antigrav\MemoryCleaner\lhm_extracted\LibreHardwareMonitorLib.dll"
Add-Type -Path $dllPath
$computer = New-Object LibreHardwareMonitor.Hardware.Computer
$computer.IsCpuEnabled = $true
$computer.IsGpuEnabled = $true
$computer.IsMemoryEnabled = $true
$computer.IsMotherboardEnabled = $true
$computer.IsControllerEnabled = $true
$computer.IsNetworkEnabled = $true
$computer.IsStorageEnabled = $true
$computer.Open()

foreach ($hardware in $computer.Hardware) {
    Write-Host "Hardware: $($hardware.Name) ($($hardware.HardwareType))"
    $hardware.Update()
    foreach ($sensor in $hardware.Sensors) {
        if ($sensor.Value -ne $null) {
            Write-Host "  $($sensor.SensorType) - $($sensor.Name): $($sensor.Value)"
        }
    }
}
$computer.Close()
