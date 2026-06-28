# ==========================================
# ShimGen Lab - Proof of Concept Payload
# ==========================================

$LogPath = "C:\Users\Public\shimgen_poc.log"
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# 1. Write the execution log to disk (IoC for Blue Team detection)
"[$Timestamp] Payload successfully executed in memory via ShimGen proxy." | Out-File -FilePath $LogPath -Append

# 2. Maintain the illusion by launching the real PuTTY application
$RealPutty = "C:\Program Files\PuTTY\putty.exe"

if (Test-Path $RealPutty) {
    Start-Process $RealPutty
} else {
    Write-Warning "Real PuTTY executable not found at expected location."
}