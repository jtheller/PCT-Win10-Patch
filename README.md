# PCT Windows 10 Patch

[![Tests](https://github.com/jtheller/PCT-Win10-Patch/actions/workflows/test.yml/badge.svg)](https://github.com/jtheller/PCT-Win10-Patch/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Add British Columbia's permanent UTC−7 time zone to Windows 10 with one standalone PowerShell script. No ESU enrollment required.**

Most of British Columbia, including Vancouver and Victoria, stays on UTC−7 year-round and does **not** turn clocks back on November 1, 2026. Older Windows installations may still use **Pacific Time (US & Canada)** and display the wrong local time. [BC government announcement](https://news.gov.bc.ca/releases/2026AG0013-000209)

This community patch adds **(UTC-07:00) Pacific Time (British Columbia)** using the registry rules extracted from Microsoft's KB5126657 time-zone component. It provides the time-zone change for Windows 10 users who cannot receive or install the cumulative update. Microsoft's official Windows update remains the recommended route when available. [Microsoft update details](https://support.microsoft.com/en-us/servicing/os/windows-10/2026/10/kb5126657-windows-10-21h2-22h2-security-update)

## Download and apply

1. **[Download Patch-BcTimeZone.ps1](https://github.com/jtheller/PCT-Win10-Patch/releases/latest/download/Patch-BcTimeZone.ps1)** from the latest release and save it in a folder you can find. The release includes a SHA-256 checksum. You only need this one script.
2. Open **Windows PowerShell → Run as administrator**. Change to the folder where you saved the script.
3. Preview the current state:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Patch-BcTimeZone.ps1
   ```

4. If your computer should use BC's UTC−7 time zone, apply:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Patch-BcTimeZone.ps1 -Mode Apply
   ```

5. Keep the backup filename printed by Apply, then verify:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Patch-BcTimeZone.ps1 -Mode Verify
   ```

Restart open applications afterward so they reload time-zone data. The script does not reboot the computer. The execution-policy option above applies only to the PowerShell process running the script; it does not change your saved execution policy.

If you already use PowerShell 7, replace `powershell.exe` with `pwsh.exe`. On 64-bit Windows, use a 64-bit PowerShell window.

**Only select this zone on computers that should use BC Pacific time.** Some eastern BC communities follow mountain-time rules. Computers elsewhere can use `-RegisterOnly` to add the BC zone for conversions while retaining their existing selected zone.

## What the script changes

- Adds the Windows time-zone ID **`British Columbia Standard Time`**, with historical seasonal rules and permanent UTC−7 going forward.
- Selects the new zone on Apply, unless `-RegisterOnly` is specified.
- Saves the original selected zone and its daylight-saving setting before making changes.
- Refuses to overwrite an existing BC definition with different rules. It also recognizes the older layout with the 2026 transitional `TZI` at the root, but only when every `Dynamic DST` entry matches the embedded Microsoft data. For compatible rules, adds missing English `MUI_Display`, `MUI_Dlt` and `MUI_Std` name values without replacing existing labels or rule bytes.
- Checks historical, transition and future offsets and the native Windows time-zone API before selecting BC; attempts recovery if applying fails.

The script uses the normal Windows `tzutil` command to select the zone. It preserves the US Pacific definition, leaves system DLLs and ESU licensing intact, and does not set the UTC clock or mark the cumulative update as installed.

## Commands

The following examples assume you opened PowerShell in the script's folder. Apply and Rollback require administrator rights.

| Action | Command |
| --- | --- |
| Read-only preview (default) | `.\Patch-BcTimeZone.ps1` |
| Preview the Apply operation without changes | `.\Patch-BcTimeZone.ps1 -Mode Apply -WhatIf` |
| Add and select BC | `.\Patch-BcTimeZone.ps1 -Mode Apply` |
| Add BC without selecting it | `.\Patch-BcTimeZone.ps1 -Mode Apply -RegisterOnly` |
| Verify installed rules, names and native API compatibility | `.\Patch-BcTimeZone.ps1 -Mode Verify` |

### Upgrading an earlier version

Earlier versions omitted `MUI_Std` and `MUI_Dlt`. These names are required by the native Windows time-zone API even when .NET offset calculations succeed. With BC selected, the omission can cause Windows date/calendar initialization to fail with `0x80070002` (file not found), crashing apps such as Phone Link, Windows Security and screen clipping.

Download the updated script from the fixed release once available, then repair a matching older definition without changing the selected zone:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Patch-BcTimeZone.ps1 -Mode Apply -RegisterOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Patch-BcTimeZone.ps1 -Mode Verify
```

Apply backs up the repair, fills only missing names, and validates the result. Restart affected apps afterward. Existing name values and all time-zone rules are preserved. The older 2026 root layout is accepted when its entire `Dynamic DST` table matches; its root bytes are retained. Other rule differences or malformed existing names are rejected for inspection.

## Rollback

Apply prints the exact backup filename. By default, backups are stored beneath:

```text
%ProgramData%\TRG\BcTimeZonePatch\Backups\
```

In administrator PowerShell, use the filename from your Apply output:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Patch-BcTimeZone.ps1 -Mode Rollback -BackupPath 'C:\ProgramData\TRG\BcTimeZonePatch\Backups\YOUR-BACKUP-FOLDER\state.json'
```

Replace `YOUR-BACKUP-FOLDER` with your actual backup folder. Add `-WhatIf` to preview the rollback first.

Rollback restores the original selected zone and its disabled-DST flag. It removes the BC definition only if this patch created it and the complete definition is unchanged. For a repair of an existing definition, it removes only the name values that Apply added, restoring the previous metadata. This also restores the earlier missing-name defect if that was the original state. A definition subsequently modified by Windows Update or another tool is preserved. Existing rules and pre-existing labels are preserved. The updated script accepts both its version 2 backups and older version 1 backups. Backups remain available after rollback, and their directories grant access to the applying account, Administrators and SYSTEM.

## Compatibility and testing

| Item | Status |
| --- | --- |
| Windows 10 Home, Pro, Enterprise and Education | Known Windows 10 client builds are accepted; physical-host testing performed on 22H2 x64, build 19045 |
| Windows 10 LTSB/LTSC | Version guard accepts their Windows 10 client builds; separate physical installations have not been tested |
| x64 | Tested on Windows 10 22H2 |
| x86 and ARM64 | Registry data is architecture-independent and native registry views are handled; physical systems have not been tested |
| Windows PowerShell 5.1 | Tested |
| PowerShell 7 | Tested with 7.6.5 |
| Windows 11 and Windows Server | Apply is blocked; use their supported update path |

The script requires **PowerShell 5.1 or later**. Older Windows 10 releases may need a compatible newer PowerShell installed first.

The isolated suite passes **1,623 checks per runtime**, including exact comparison with the extracted Microsoft rule bytes, monthly historical offsets for 2006–2025, every day in 2026, the final spring-forward boundary, the absence of a November 2026 rollback, and monthly UTC−7 offsets through 2100. It reproduces native `GetTimeZoneInformationForYear` error 2 when either required name is absent and verifies recovery when it is restored, using unique fixture IDs to avoid the native API's cache. It also tests version guards, Apply, Verify, repeated Apply, RegisterOnly, backup access controls, metadata repair and rollback, the older 2026 root layout without replacing its bytes, older backups, preservation of existing labels and later changes, rejection of malformed metadata/different rules (including changed year-specific rules under a legacy root), and recovery from simulated selection and native-validation failures.

Tests use a temporary HKCU registry tree with a process-local registry redirect. The elevation check and native zone selection are substituted in the orchestration fixture. Tests verify that the live selected zone and machine time-zone definitions remain unchanged. GitHub Actions runs the suite in Windows PowerShell and PowerShell 7; these runner tests do not represent physical testing on every Windows 10 release or CPU architecture.

## Troubleshooting

**The time zone changes back automatically.** Turn off **Set time zone automatically** in Windows Date & time settings, then select **(UTC-07:00) Pacific Time (British Columbia)**. This patch does not update Windows' geographic auto-selection data or change that setting for you.

**Windows already lists the correct BC zone.** Run Verify first. An official update may already have added it, so applying this patch may be unnecessary.

**An existing BC definition differs. Refusing to overwrite it.** Use the latest script. It accepts the older 2026 transitional root `TZI` when every `Dynamic DST` entry still matches the Microsoft BC data, and preserves that root value during metadata repair. If the latest script still refuses, another rule value differs; do not delete the existing zone to bypass the check. Capture Preview output and the existing definition for inspection.

**Phone Link, Windows Security or Win+Shift+S crashes after installing an earlier patch.** See [Upgrading an earlier version](#upgrading-an-earlier-version). The native Windows date/time API needs the `MUI_Std` and `MUI_Dlt` registry names; the earlier patch supplied only `Std` and `Dlt`. No graphics-driver rollback or app-data reset is needed to repair this metadata defect.

**Windows time is correct, but Outlook or a browser still shows the wrong time.** Applications can maintain separate calendar settings or time-zone databases. Update the affected application, review its time-zone setting, and check future recurring meetings. This script does not migrate Outlook calendar events or update bundled IANA/ICU mappings. [Microsoft product guidance](https://support.microsoft.com/en-us/servicing/os/windows/docs/2026/10/canada-2026-time-zone-changes)

**Should I disable daylight-saving adjustment?** Keep the new BC definition's rules enabled. Its transitional 2026 history requires them. Disabling daylight saving on the old US Pacific zone leaves that zone at UTC−8.

**Can I clean the component store or delete the preparation files?** Yes. The script embeds all required rule data. Running it requires no component-store source files, Internet access, or other files from this repository.

**Does this replace Windows security updates?** No. This is a custom time-zone registry patch. It does not provide KB5126657's security fixes or restore Windows support eligibility.

For an issue report, include your Windows edition/build, PowerShell version, and the output from Preview and Verify. Review diagnostic output before posting it publicly. [Open an issue](https://github.com/jtheller/PCT-Win10-Patch/issues)

## Provenance

The source was a staged Microsoft Windows component associated with signed **KB5126657**, package **19041.7807.1.49**. The time-zone component version is **Microsoft-Windows-International-TimeZones 10.0.19041.7802**.

`TZI` and all `Dynamic DST` bytes are copied exactly from the BC entries in Microsoft's component manifest. The `MUI_Display`, `MUI_Dlt` and `MUI_Std` value names are retained, with their resource references replaced by resolved English strings. The legacy `Display`, `Dlt` and `Std` values contain the same English labels. Keeping both sets allows native Windows APIs and .NET callers to work without installing a newer tzres.dll. Labels therefore appear in English on non-English installations.

- [Extracted BC registry entries](source/bc-registry-excerpt.xml)
- [Readable embedded definition](source/bc-definition.json)
- [Source component hashes and extraction metadata](source/provenance.json)

## Development

Clone or download the repository and run the tests in a fresh PowerShell process:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-BcTimeZonePatch.ps1
pwsh.exe -NoProfile -File .\Test-BcTimeZonePatch.ps1
```

The second command requires PowerShell 7. Generated results and fixture backups are excluded from Git. Keep changes focused on the BC time-zone patch, preserve the source rule bytes, and test native Apply/Rollback changes in a disposable Windows 10 environment before distributing them.

## License

The original implementation is [MIT licensed](LICENSE). See [NOTICE.md](NOTICE.md) for the Microsoft reference-data notice. This community project is not affiliated with or endorsed by Microsoft.
