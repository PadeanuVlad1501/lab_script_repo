$LabsPath = "C:\Users\Administrator\Desktop\Labs\Havoc"

Write-Host "[*] Starting lab environment setup..."

Write-Host "[*] Creating Labs/Havoc directory on Desktop..."
New-Item -Path $LabsPath -ItemType Directory -Force | Out-Null

Write-Host "[*] Generating decoy files..."

$PasswordsContent = @"
Finance Portal: admin / SuperSecret2026!
Corporate Bank Account: director / MoneyIsHere123
Main Backup Server: root / ToTheMoonAndBack
"@
Set-Content -Path "$LabsPath\finance_passwords.txt" -Value $PasswordsContent

$CsvContent = @"
ID,Customer_Name,Credit_Card,CVV,Account_Balance
1,John Doe,4580-1234-5678-9012,123,$5400.00
2,Jane Smith,4580-9876-5432-1098,456,$1200.50
3,Michael Johnson,4580-1111-2222-3333,789,$95000.00
"@
Set-Content -Path "$LabsPath\customer_database.csv" -Value $CsvContent

Write-Host "[+] Windows setup complete! Decoy files are located in $LabsPath"
