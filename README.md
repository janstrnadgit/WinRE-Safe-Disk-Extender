# WinRE-Safe-Disk-Extender

**PowerShell script to extend C: drive on Windows Server 2022/2025 & Windows 10/11 by migrating the Recovery Partition.**

[🇨🇿 Dokumentace v cestine zde](READMECZ.md)

---

## 🚩 The Problem
On modern Windows systems, the **Recovery Partition** is located at the very end of the system disk. This prevents the "C:" drive from being extended into unallocated space (e.g., after increasing the disk size in VMware/Hyper-V), as "C:" requires contiguous free space.

## ✨ Solution
This script automates the entire process of moving the Recovery partition to the end of the newly expanded disk while ensuring no data loss for the Recovery Environment (WinRE).

## 🛠 Key Features
*   **Admin Check:** Verifies elevated privileges before execution.
*   **Auto-Detection:** Automatically identifies the system disk and "C:" partition.
*   **Triple WinRE Protection:**
    *   Attempts standard `reagentc /disable` migration.
    *   If fails, it **dynamically mounts** the hidden recovery partition to a free drive letter (F-Z).
    *   Manually backs up `Winre.wim` to `C:\Windows\System32\Recovery`.
*   **Safe Resizing:** Deletes the blocking partition, extends "C:" (leaving 1GB buffer), and creates a new proper GPT Recovery partition.
*   **Re-activation:** Restores the `Winre.wim` and re-enables the Recovery Environment.
*   **No Diacritics:** Script comments and outputs are safe for all encoding types (ASCII/UTF-8).
 
## 🚀 Usage
1. Increase the disk size in your virtualization platform (VMware, Hyper-V, Azure, etc.).
2. Run PowerShell as **Administrator**.
3. Execute the script:
 
```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\WinRE-Safe-Disk-Extender.ps1
