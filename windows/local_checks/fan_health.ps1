# =====================================================================
# Local Check Checkmk: Real-Time Fan Health & Speed (Windows)
# =====================================================================

 = "C:\ProgramData\checkmkgent\lib\LibreHardwareMonitorLib.dll"
 = 
 = 

# 1. Coba baca via LibreHardwareMonitorLib.dll (.NET Assembly)
if (Test-Path ) {
    try {
        Add-Type -Path  -ErrorAction Stop
        
         = New-Object LibreHardwareMonitor.Hardware.Computer
        .IsCpuEnabled = 
        .IsMotherboardEnabled = 
        .IsControllerEnabled = 
        .Open()
        
        foreach ( in .Hardware) {
            .Update()
            foreach ( in .SubHardware) {
                .Update()
            }
            foreach ( in .Sensors) {
                if (.SensorType -eq "Fan" -and .Value -gt 0) {
                     = [int].Value
                     = .Name
                    break
                }
            }
            if () { break }
        }
        .Close()
    } catch {
        # Silent fallback
    }
}

# 2. Jika DLL gagal/kosong, coba baca via WMI Namespace LibreHardwareMonitor
if (-not ) {
     = Get-CimInstance -Namespace "root\LibreHardwareMonitor" -ClassName "Sensor" -ErrorAction SilentlyContinue | 
              Where-Object { .SensorType -eq "Fan" -and .Value -gt 0 } | Select-Object -First 1
    if () {
         = [int].Value
         = .Name
    }
}

# 3. Jika masih kosong, coba baca via CIM Win32_Fan standar
if (-not ) {
     = Get-CimInstance -ClassName Win32_Fan -ErrorAction SilentlyContinue | 
                Where-Object { .DesiredSpeed -gt 0 } | Select-Object -First 1
    if () {
         = [int].DesiredSpeed
         = "System Fan"
    }
}

# 4. Format Output Checkmk menggunakan pemisah "~"
if ( -and  -gt 0) {
    # Ambang batas Checkmk (Standar): >1600 RPM = OK, <1600 RPM = Warning
     = 0
    if ( -lt 1600) {  = 1 }
    
     = " " - Status : OK ~ FAN Speed : rpm ~ Sensor:  ~ Remark: FAN Condition Good"
} else {
    # Fallback jika hardware/laptop tidak mengekspos sensor RPM (Passive Cooling / WMI unavailable)
     = "0 " - Status : OK ~ FAN Speed : 0rpm ~ Remark: Passive Cooling or Sensor Not Exposed"
}

Write-Output 
