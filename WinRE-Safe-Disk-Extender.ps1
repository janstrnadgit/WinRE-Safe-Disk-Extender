<#
.SYNOPSIS
    Kompletni automatizace rozsireni disku C: s migraci a obnovou Recovery prostredi.
    Full automation of C: drive extension with Recovery environment migration.
    Compatible with Windows Server 2022, 2025 & Windows 10/11 (GPT).

.DESCRIPTION
    1. Kontrola administratorskych prav / Admin rights check.
    2. Detekce systemoveho disku a kontrola volneho mista / System disk detection & Free space check.
    3. Dynamicke prirazeni pismene a zaloha Winre.wim / Dynamic letter assignment & Winre.wim backup.
    4. Smazani stare partition a rozsireni C: / Delete old partition & extend C:.
    5. Vytvoreni nove Recovery partition (1GB) / Create new Recovery partition (1GB).
    6. Reaktivace WinRE / WinRE reactivation.
#>

# --- 1. KONTROLA ADMINISTRATORSKYCH PRAV / ADMIN RIGHTS CHECK ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Chyba: Skript MUSITE spustit jako administrator! / Error: Run as administrator!"
    break
}

# --- 2. DETEKCE SYSTEMOVEHO DISKU / SYSTEM DISK DETECTION ---
$systemPartition = Get-Partition -DriveLetter C -ErrorAction Stop
$diskId = $systemPartition.DiskNumber
$backupPath = "C:\Windows\System32\Recovery"
$wimMissing = $false

# Kontrola nealokovaneho prostoru / Check for unallocated space
$diskInfo = Get-Disk -Number $diskId
$unallocated = $diskInfo.LargestFreeExtent

if ($unallocated -lt 512MB) {
    Write-Host "--- KONTROLA DISKU / DISK CHECK ---" -ForegroundColor White -BackgroundColor Gray
    Write-Host ">>> Zadny vyznamny volny prostor nenalezen ($([Math]::Round($unallocated/1MB, 2)) MB)." -ForegroundColor Yellow
    Write-Host ">>> Disk C: neni potreba rozsirovat. Ukoncuji... / No space to extend. Exiting..." -ForegroundColor Green
    break
}

if (-not (Test-Path $backupPath)) { New-Item -Path $backupPath -ItemType Directory -Force | Out-Null }

Write-Host "--- SPUSTENI AUTOMATIZACE ROZSIRENI DISKU / STARTING DISK EXTENSION ---" -ForegroundColor White -BackgroundColor Blue
Write-Host ">>> Nalezen volny prostor k rozsireni: $([Math]::Round($unallocated/1GB, 2)) GB." -ForegroundColor Green
Write-Host ">>> Detekovan system na Disku $diskId / System detected on Disk $diskId." -ForegroundColor Cyan

# --- ZJISTENI POCATECNIHO STAVU / CHECK INITIAL STATUS ---
$reInfo = reagentc /info 2>&1
Write-Host ">>> Aktualni stav WinRE / Current WinRE status:" -ForegroundColor Gray
$reInfo | Select-String "Windows RE status"

if ($reInfo -like "*Disabled*") {
    Write-Host ">>> Upozorneni: Recovery je jiz nyni vypnuto / Warning: Recovery is already disabled." -ForegroundColor Yellow
}

# --- 3. ZALOHA WINRE.WIM (Pojistka) / WINRE.WIM BACKUP ---
Write-Host ">>> Pokousim se zajistit soubor Winre.wim / Securing Winre.wim file..." -ForegroundColor Gray
reagentc /disable 2>&1 | Out-Null 

$localWim = "$backupPath\Winre.wim"

if (-not (Test-Path $localWim -PathType Leaf)) {
    Write-Host ">>> Winre.wim nenalezen na C:. Zkousim primy pristup / Not found on C:. Trying direct access..." -ForegroundColor Yellow
    $recPart = Get-Partition -DiskNumber $diskId | Where-Object { $_.GptType -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' -or $_.Type -eq 'Recovery' }
    
    if ($recPart) {
        try {
            $occupiedLetters = (Get-Volume).DriveLetter
            $tempDrive = ("FGHIJKLMNOPQRSTUVWXYZ".ToCharArray() | Where-Object { $occupiedLetters -notcontains $_ } | Select-Object -First 1)
            if (-not $tempDrive) { throw "Zadne volne pismeno! / No free drive letter!" }
            
            $recPart | Set-Partition -NewDriveLetter $tempDrive -ErrorAction Stop
            Start-Sleep -Seconds 2
            $sourceWim = "${tempDrive}:\Recovery\WindowsRE\Winre.wim"
            if (Test-Path $sourceWim) {
                Copy-Item -Path $sourceWim -Destination $localWim -Force
                Write-Host ">>> USPECH: Winre.wim vykopirovan z oddilu ${tempDrive}: / SUCCESS: Copied from ${tempDrive}:" -ForegroundColor Green
            }
            Get-Partition -DriveLetter $tempDrive | Remove-PartitionAccessPath -DriveLetter $tempDrive
        } catch {
            Write-Warning ">>> Nepodarilo se pripojit oddil / Failed to mount partition: $($_.Exception.Message)"
        }
    }
}
 
if (-not (Test-Path $localWim)) { 
    Write-Warning "!!! Winre.wim nenalezen / Not found!"
    $wimMissing = $true 
}
<#
    CO DELAT, POKUD CHYBI WINRE.WIM / WHAT TO DO IF WINRE.WIM IS MISSING:
    
    1. Ignorovat (u VM bezne) / Ignore (common for VMs): 
       U virtualu casto WinRE nepotrebujete - bootujete z ISO nebo obnovujete ze snapshotu.
       For VMs, WinRE is often not needed - you boot from ISO or restore from a snapshot.

    2. Kopie z jineho serveru / Copy from another server:
       Zkopirujte Winre.wim z jineho funkcniho Serveru 2022/2025 do C:\Windows\System32\Recovery.
       Copy Winre.wim from another working Server 2022/2025 to C:\Windows\System32\Recovery.

    3. Extrakce z instalacniho ISO / Extract from installation ISO:
       Pripojte ISO -> najdete 'sources\install.wim' -> vybalte Winre.wim ze slozky Windows\System32\Recovery.
       Mount ISO -> find 'sources\install.wim' -> extract Winre.wim from Windows\System32\Recovery.

    Nasledne spustte / Then run: reagentc /setreimage /path C:\Windows\System32\Recovery && reagentc /enable
#>

# --- 4. ODSTRANENI ODDILU A ROZSIRENI / DELETE PARTITION & EXTEND ---
$partToDelete = Get-Partition -DiskNumber $diskId | Where-Object { $_.GptType -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' -or $_.Type -eq 'Recovery' }

if ($partToDelete) {
    Write-Host ">>> Mazani stare Recovery partition / Deleting old Recovery partition..." -ForegroundColor Yellow
    "select disk $diskId`nselect partition $($partToDelete.PartitionNumber)`ndelete partition override" | diskpart | Out-Null
}

$sizeData = Get-PartitionSupportedSize -DriveLetter C
$newSize = $sizeData.SizeMax - 1GB

Write-Host ">>> Rozsiruji C: na $([Math]::Round($newSize/1GB, 2)) GB / Extending C:..." -ForegroundColor Green
try {
    Resize-Partition -DriveLetter C -Size $newSize -ErrorAction Stop
} catch {
    Write-Host ">>> Disk C: jiz ma maximalni velikost nebo neni co rozsirovat." -ForegroundColor Gray
}

# --- 5. VYTVORENI NOVE RECOVERY PARTITION / CREATE NEW RECOVERY ---
Write-Host ">>> Vytvarim novou Recovery partition / Creating new Recovery partition..." -ForegroundColor Cyan
$finalPart = New-Partition -DiskNumber $diskId -UseMaximumSize -GptType "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}"
Format-Volume -Partition $finalPart -FileSystem NTFS -NewFileSystemLabel "Recovery" -Confirm:$false | Out-Null
"select disk $diskId`nselect partition $($finalPart.PartitionNumber)`ngpt attributes=0x8000000000000001" | diskpart | Out-Null

# --- 6. REAKTIVACE WINRE / REWRE REACTIVATION ---
if (-not $wimMissing) {
    Write-Host ">>> Aktivuji WinRE / Enabling WinRE..." -ForegroundColor Green
    reagentc /setreimage /path $backupPath 2>&1 | Out-Null
    reagentc /enable 2>&1 | Out-Null
} else {
    Write-Host ">>> WinRE aktivace preskocena / WinRE activation skipped." -ForegroundColor Red
}

# --- FINALNI VYPIS / FINAL STATUS ---
Write-Host "`n--- OPERACE DOKONCENA / OPERATION COMPLETE ---" -ForegroundColor White
Get-Partition -DiskNumber $diskId | Select-Object PartitionNumber, Size, Type | Format-Table -AutoSize
reagentc /info 2>&1 | Out-String | Write-Host
