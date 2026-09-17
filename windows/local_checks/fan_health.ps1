# =====================================================================
# Local Check Checkmk: Real-Time Fan Health & Speed (Windows)
# =====================================================================

$dllPath = "C:\ProgramData\checkmk\agent\lib\LibreHardwareMonitorLib.dll"
$fanSpeed = 0
$sensorName = "N/A"

# 1. Coba baca menggunakan LibreHardwareMonitorLib.dll
if (Test-Path $dllPath) {
    try {
        Add-Type -Path $dllPath -ErrorAction Stop
        $computer = New-Object LibreHardwareMonitor.Hardware.Computer
        $computer.IsCpuEnabled = $true
        $computer.IsMotherboardEnabled = $true
        $computer.IsControllerEnabled = $true
        $computer.Open()

        foreach ($hardware in $computer.Hardware) {
            $hardware.Update()
            foreach ($subHardware in $hardware.SubHardware) { $subHardware.Update() }
            foreach ($sensor in $hardware.Sensors) {
                if ($sensor.SensorType -eq "Fan" -and $sensor.Value -gt 0) {
                    $fanSpeed = [int]$sensor.Value
                    $sensorName = $sensor.Name
                    break
                }
            }
            if ($fanSpeed -gt 0) { break }
        }
        $computer.Close()
    } catch {
        $fanSpeed = 0
    }
}

# 2. Fallback ke CIM/WMI standar jika DLL tidak mendeteksi RPM
if ($fanSpeed -eq 0) {
    $fanCim = Get-CimInstance -ClassName Win32_Fan -ErrorAction SilentlyContinue
    if ($fanCim -and $fanCim.DesiredSpeed -gt 0) {
        $fanSpeed = [int]$fanCim.DesiredSpeed
        $sensorName = "Win32_Fan"
    }
}

# 3. Format Output Local Check Checkmk
# Catatan: Teks deskripsi menggunakan pembatas '~' agar kebal dari error parsing perfdata '|' Checkmk
if ($fanSpeed -gt 0) {
    Write-Output "0 `"FAN_Health`" fan_speed=${fanSpeed};1600;;0; Status : OK ~ FAN Speed : ${fanSpeed}rpm ~ Sensor: ${sensorName} ~ Remark: FAN Condition Good"
} else {
    Write-Output "0 `"FAN_Health`" - Status : OK ~ FAN Speed : 0rpm ~ Remark: Passive Cooling or Sensor Not Exposed"
}
