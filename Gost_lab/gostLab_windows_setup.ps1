$LabPath = "C:\Users\Administrator\Desktop\Labs\GostLab"


if (!(Test-Path $LabPath)) {
    New-Item -ItemType Directory -Path $LabPath -Force | Out-Null
    Write-Host "[+] Folder creat: $LabPath" -ForegroundColor Green
}


$Data = @"
ID,Full_Name,IBAN,Card_Number,CVV,Expiry,Account_Balance_EUR
1,Admin_Master,RO12INGB0000111122223333,4556-8888-1234-5678,123,12/28,450000.00
2,CEO_Finance,RO99BCR9999888877776666,5122-4444-9999-0000,456,10/25,1250000.50
3,IT_Department_Backups,RO00BRD0000999900008888,4111-2222-3333-4444,000,01/30,500.25
"@

$Data | Out-File -FilePath "$LabPath\financial_records.csv" -Encoding UTF8

Write-Host "[+] Financial 'data' to for exfil: $LabPath\financial_records.csv" -ForegroundColor Cyan
Write-Host "[!] Windows VM configurated." -ForegroundColor Yellow
