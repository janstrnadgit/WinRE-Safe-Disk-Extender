<#
.SYNOPSIS
    Kompletní automatizace rozšíření disku C: s migrací a obnovou Recovery prostředí.
    Kompatibilní s Windows Server 2022 a 2025 (GPT).

.DESCRIPTION
    1. Kontrola administrátorských práv.
    2. Detekce systémového disku (podle jednotky C:).
    3. Pokus o zálohu Winre.wim (z C:\ i přímo z Recovery oddílu).
    4. Smazání bloku (Recovery partition), rozšíření C: (ponechání 1GB).
    5. Vytvoření nové Recovery partition na konci disku.
    6. Obnova a aktivace WinRE prostředí.
#>

# --- 1. KONTROLA ADMINISTRÁTORSKÝCH PRÁV ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Chyba: Skript MUSÍTE spustit jako administrátor (Pravým tlačítkem -> Spustit jako správce)."
    break
}

# --- 2. DETEKCE SYSTÉMOVÉHO DISKU ---
$systemPartition = Get-Partition -DriveLetter C -ErrorAction Stop
$diskId = $systemPartition.DiskNumber
$backupPath = "C:\Windows\System32\Recovery"
$wimMissing = $false

if (-not (Test-Path $backupPath)) { New-Item -Path $backupPath -ItemType Directory -Force | Out-Null }

Write-Host "--- SPUŠTĚNÍ AUTOMATIZACE ROZŠÍŘENÍ DISKU ---" -ForegroundColor White -BackgroundColor Blue
Write-Host ">>> Detekován systém na Disku $diskId." -ForegroundColor Cyan

# --- ZJIŠTĚNÍ POČÁTEČNÍHO STAVU ---
$reInfo = reagentc /info
Write-Host ">>> Aktuální stav WinRE:" -ForegroundColor Gray
$reInfo | Select-String "Windows RE status"

if ($reInfo -like "*Disabled*") {
    Write-Host ">>> Upozornění: Recovery je již nyní vypnuto. Pokusím se o zálohu, ale soubor nemusí existovat." -ForegroundColor Yellow
}

# --- 3. ZÁLOHA WINRE.WIM (Pojistka před smazáním) ---
Write-Host ">>> Pokouším se zajistit soubor Winre.wim..." -ForegroundColor Gray
reagentc /disable | Out-Null # Standardní uvolnění souboru na C:

$localWim = "$backupPath\Winre.wim"

# Pokud soubor není v System32, zkusíme ho vytáhnout přímo z partition
if (-not (Test-Path $localWim -PathType Leaf)) {
    Write-Host ">>> Winre.wim nenalezen v System32. Zkouším přímý přístup k Recovery oddílu..." -ForegroundColor Yellow
    
    $recPart = Get-Partition -DiskNumber $diskId | Where-Object { $_.GptType -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' -or $_.Type -eq 'Recovery' }
    
    if ($recPart) {
        try {
            $tempDrive = "Z"
            # Dočasné připojení oddílu
            $recPart | Set-Partition -NewDriveLetter $tempDrive -ErrorAction Stop
            Start-Sleep -Seconds 2
            
            $sourceWim = "$($tempDrive):\Recovery\WindowsRE\Winre.wim"
            if (Test-Path $sourceWim) {
                Copy-Item -Path $sourceWim -Destination $localWim -Force
                Write-Host ">>> ÚSPĚCH: Soubor Winre.wim byl vykopírován z oddílu ${tempDrive}:" -ForegroundColor Green
            }
            # Odpojení dočasného písmene
            Get-Partition -DriveLetter $tempDrive | Remove-PartitionAccessPath -DriveLetter $tempDrive
        } catch {
            Write-Warning ">>> Nepodařilo se připojit skrytý oddíl."
        }
    }
}

# Kontrola, zda jsme soubor nakonec získali
if (-not (Test-Path $localWim)) {
    Write-Warning "!!! VAROVÁNÍ: Winre.wim nebyl nalezen. Recovery prostředí nebude po rozšíření funkční!"
    $wimMissing = $true
} else {
    Write-Host ">>> OK: Winre.wim je připraven k migraci." -ForegroundColor Green
}

<#
Jak to vyřešit (Možnosti):
Ignorovat to (u VM běžné): U virtuálních strojů často WinRE nepotřebujete, protože v případě havárie bootujete z ISO obrazu nebo obnovujete ze snapshotu/zálohy na úrovni hypervizoru.
Zkopírovat soubor z jiného serveru: Pokud máte jiný běžící Windows Server 2022, můžete z něj soubor Winre.wim (ze složky C:\Windows\System32\Recovery) zkopírovat na tento server a poté znovu spustit příkaz reagentc /setreimage /path C:\Windows\System32\Recovery.
Vytáhnout soubor z instalačního ISO:
Připojte ISO Windows Serveru 2022.
V souboru sources\install.wim (nebo .esd) se ve složce Windows\System32\Recovery nachází originální Winre.wim.
Můžete ho vybalit pomocí nástroje 7-Zip nebo příkazu dism /mount-wim.
#>


# --- 4. ODSTRANĚNÍ STARÉHO ODDÍLU A ROZŠÍŘENÍ ---
$partToDelete = Get-Partition -DiskNumber $diskId | Where-Object { $_.GptType -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' -or $_.Type -eq 'Recovery' }

if ($partToDelete) {
    Write-Host ">>> Odstraňuji blokující Recovery partition (číslo $($partToDelete.PartitionNumber))..." -ForegroundColor Yellow
    "select disk $diskId`nselect partition $($partToDelete.PartitionNumber)`ndelete partition override" | diskpart | Out-Null
}

# Výpočet nové velikosti (Maximum - 1GB rezerva)
$sizeData = Get-PartitionSupportedSize -DriveLetter C
$newSize = $sizeData.SizeMax - 1GB

Write-Host ">>> Rozšiřuji oddíl C: na $([Math]::Round($newSize/1GB, 2)) GB..." -ForegroundColor Green
Resize-Partition -DriveLetter C -Size $newSize

# --- 5. VYTVOŘENÍ NOVÉ RECOVERY PARTITION ---
Write-Host ">>> Vytvářím novou Recovery partition na konci disku..." -ForegroundColor Cyan
$finalPart = New-Partition -DiskNumber $diskId -UseMaximumSize -GptType "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}"
Format-Volume -Partition $finalPart -FileSystem NTFS -NewFileSystemLabel "Recovery" -Confirm:$false | Out-Null

# Nastavení GPT atributů (Hidden + No Drive Letter)
"select disk $diskId`nselect partition $($finalPart.PartitionNumber)`ngpt attributes=0x8000000000000001" | diskpart | Out-Null

# --- 6. REAKTIVACE WINRE ---
if (-not $wimMissing) {
    Write-Host ">>> Aktivuji Recovery prostředí (WinRE)..." -ForegroundColor Green
    reagentc /setreimage /path $backupPath
    reagentc /enable
} else {
    Write-Host ">>> Přeskakuji aktivaci WinRE (chybí zdrojový soubor)." -ForegroundColor Red
}

# --- FINÁLNÍ VÝPIS ---
Write-Host "`n--- OPERACE DOKONČENA ---" -ForegroundColor White
Get-Partition -DiskNumber $diskId | Select-Object PartitionNumber, Size, Type | Format-Table -AutoSize
reagentc /info

if ($wimMissing) {
    Write-Host "TIP: Pokud chcete WinRE zprovoznit, vložte Winre.wim do $backupPath a spusťte 'reagentc /enable'." -ForegroundColor Yellow
}