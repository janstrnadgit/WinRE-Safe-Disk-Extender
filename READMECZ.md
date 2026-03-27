# WinRE-Safe-Disk-Extender (CZ)

**PowerShell skript pro bezpecne zvetseni disku "C:" na Windows Serveru 2022/2025 a Windows 10/11 presunutim Recovery oddilu.**

[⬅️ Back to English README](README.md)

---

## 🚩 Problem
U modernich instalaci Windows (zejmena Server 2022) se **oddil pro obnovu (Recovery Partition)** nachazi az na uplnem konci disku. Pokud zvetsite virtualni disk (v VMware/Hyper-V), volne misto vznikne az za timto oddilem. Protoze disk "C:" lze rozsirit pouze do sousediciho volneho prostoru, tento maly oddil mu stoji v ceste.

## ✨ Reseni
Tento skript plne automatizuje proces presunu Recovery oddilu na novy konec disku, aniz byste prisli o nastroje pro opravu systemu (WinRE).

## 🛠 Klicove funkce
*   **Kontrola opravneni:** Overi, zda skript bezi jako Administrator.
*   **Automaticka detekce:** Sam najde systemovy disk a oddil "C:".
*   **Trojita ochrana Winre.wim:** 
    *   Pokus o standardni presun pres `reagentc /disable`.
    *   **Dynamicke pripojeni** skryteho oddilu pod volne pismeno (F-Z).
    *   Rucni zaloha `Winre.wim` do slozky `C:\Windows\System32\Recovery`.
*   **Bezpecne skálovani:** Smaze blokujici oddil, roztahne "C:" (ponecha 1GB rezervu) a vytvori novy GPT Recovery oddil.
*   **Znovuzapnuti:** Vrathi soubor `Winre.wim` na misto a aktivuje prostredi pro obnovu.

## 🚀 Jak skript pouzit
1. Zvetsete disk ve vasi virtualizacni platforme (VMware, Hyper-V, Azure atd.).
2. Spustte PowerShell jako **Administrator**.
3. Spustte skript:

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\WinRE-Safe-Disk-Extender.ps1
