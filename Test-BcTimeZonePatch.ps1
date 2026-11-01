#requires -Version 5.1
# All test registry writes are restricted to one temporary HKCU subtree.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Security
. "$PSScriptRoot\Patch-BcTimeZone.ps1" -Mode Preview
$zonePath = $script:ZonePath
$definition = $script:Definition
$before = Get-BcCurrentSelection | ConvertTo-Json -Compress
$machine = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,(Get-BcRegistryView))
$pacificKey = $machine.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Time Zones\Pacific Standard Time')
try { $pacificBefore = Get-BcFingerprint $pacificKey } finally { $pacificKey.Dispose() }
$initialBc = $machine.OpenSubKey($zonePath)
$initialBcFingerprint = $null
if ($initialBc) { try {$initialBcFingerprint=Get-BcFingerprint $initialBc} finally {$initialBc.Dispose()} }
$legacy = [TimeZoneInfo]::FindSystemTimeZoneById('Pacific Standard Time')
Initialize-BcNativeApi
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BcTestRegistry {
    [DllImport("advapi32.dll")] static extern int RegOverridePredefKey(IntPtr key,IntPtr replacement);
    public static void Override(IntPtr replacement) {
        int error=RegOverridePredefKey(new IntPtr(unchecked((int)0x80000002)),replacement);
        if(error!=0) throw new System.ComponentModel.Win32Exception(error);
    }
}
'@
$user = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,(Get-BcRegistryView))
$sandboxPath = 'SOFTWARE\TRG\BcTimeZonePatchTests\' + [Guid]::NewGuid().ToString('N')
$sandbox = $user.CreateSubKey($sandboxPath)
$overridden = $false
$checks = 0
try {
    New-BcDefinition $sandbox $zonePath
    $key = $sandbox.OpenSubKey($zonePath)
    try {
        if (-not (Test-BcDefinition $key)) { throw 'Writer did not produce the expected rules.' }
        $fingerprint = Get-BcFingerprint $key
        # Compare against the independent extracted CBS XML, not just script constants.
        [xml]$source = Get-Content -Raw "$PSScriptRoot\source\bc-registry-excerpt.xml"
        $nodes = @($source.SelectNodes('//*[local-name()="registryKey"]'))
        foreach ($node in $nodes) {
            $target=$key
            if ($node.keyName -match 'Dynamic DST') { $target=$key.OpenSubKey('Dynamic DST') }
            try {
                foreach ($value in $node.registryValue) {
                    if ($value.name -like 'MUI_*') { $actual=$target.GetValue($value.name); $expected=$definition.Values.($value.name.Substring(4)) }
                    elseif ($value.valueType -eq 'REG_BINARY') { $actual=[BitConverter]::ToString($target.GetValue($value.name)).Replace('-',''); $expected=$value.value }
                    else { $actual=[int]$target.GetValue($value.name); $expected=[Convert]::ToInt32($value.value.Substring(2),16) }
                    if ($actual -ne $expected) { throw "Extracted value mismatch: $($value.name)" }
                    $checks++
                }
            } finally { if ($target -ne $key) {$target.Dispose()} }
        }
    } finally { $key.Dispose() }
    $refused=$false
    try { New-BcDefinition $sandbox $zonePath } catch { $refused=$true }
    if (-not $refused) { throw 'Writer failed to refuse an existing definition.' }
    $key=$sandbox.OpenSubKey($zonePath)
    try { if ((Get-BcFingerprint $key) -ne $fingerprint) { throw 'Refused write changed the definition.' } } finally {$key.Dispose()}
    $empty=$sandbox.CreateSubKey('Empty')
    try {if (Test-BcDefinition $empty) {throw 'An empty key passed validation.'}} finally {$empty.Dispose()}
    # Redirect HKLM only inside this process. No machine registry data is written.
    [BcTestRegistry]::Override($sandbox.Handle.DangerousGetHandle())
    $overridden=$true
    # Each unique ID avoids the native per-process cache. Missing either name
    # must reproduce ERROR_FILE_NOT_FOUND even though .NET offset checks pass.
    foreach ($missing in @('MUI_Dlt','MUI_Std')) {
        $nativeId='BcPatchNativeTest-' + [Guid]::NewGuid().ToString('N')
        $nativePath='SOFTWARE\Microsoft\Windows NT\CurrentVersion\Time Zones\' + $nativeId
        New-BcDefinition $sandbox $nativePath
        $key=$sandbox.OpenSubKey($nativePath,$true)
        try {
            $key.DeleteValue($missing)
            if (-not (Test-BcRules $key) -or (Test-BcDefinition $key)) {throw 'Incomplete names were not distinguished from valid rules.'}
        } finally {$key.Dispose()}
        $failed=$false
        try {Test-BcNativeTimeZone $nativeId | Out-Null} catch {
            $cause=$_.Exception.GetBaseException()
            if ($cause -isnot [ComponentModel.Win32Exception] -or $cause.NativeErrorCode -ne 2) {throw}
            $failed=$true
        }
        if (-not $failed) {throw "Missing $missing did not reproduce the native API failure."}
        $key=$sandbox.OpenSubKey($nativePath,$true)
        try {$key.SetValue($missing,[string]$definition.Values.$missing,[Microsoft.Win32.RegistryValueKind]::String)} finally {$key.Dispose()}
        Test-BcNativeTimeZone $nativeId | Out-Null
        $checks+=6
    }
    Test-BcNativeTimeZone | Out-Null
    $checks+=4
    Test-BcOffsets
    $checks+=12
    $zone=[TimeZoneInfo]::FindSystemTimeZoneById('British Columbia Standard Time')
    for ($year=2006; $year -le 2025; $year++) {
        for ($month=1; $month -le 12; $month++) {
            $date=[DateTimeOffset]::Parse(('{0:D4}-{1:D2}-15T12:00:00Z' -f $year,$month))
            if ($zone.GetUtcOffset($date) -ne $legacy.GetUtcOffset($date)) {throw "Historical mismatch: $date"}
            $checks++
        }
    }
    $date=[DateTimeOffset]::Parse('2026-01-01T12:00:00Z')
    while ($date.Year -eq 2026) {
        $expected=-7
        if ($date -lt [DateTimeOffset]::Parse('2026-03-08T10:00:00Z')) {$expected=-8}
        if ($zone.GetUtcOffset($date).TotalHours -ne $expected) {throw "2026 mismatch: $date"}
        $date=$date.AddDays(1); $checks++
    }
    for ($year=2027; $year -le 2100; $year++) {
        for ($month=1; $month -le 12; $month++) {
            $date=[DateTimeOffset]::Parse(('{0:D4}-{1:D2}-15T12:00:00Z' -f $year,$month))
            if ($zone.GetUtcOffset($date).TotalHours -ne -7) {throw "Future mismatch: $date"}
            $checks++
        }
    }
    if (-not $zone.IsInvalidTime([datetime]'2026-03-08T02:30:00')) {throw 'The last spring-forward gap was lost.'}
    if ($zone.IsAmbiguousTime([datetime]'2026-11-01T01:30:00')) {throw 'Unexpected fall-back ambiguity in November 2026.'}
    $checks+=2
    # Exercise the complete Apply/Rollback control flow against the same HKCU
    # registry fixture. Only elevation and native zone selection are substituted.
    $sandbox.DeleteSubKeyTree($zonePath)
    $version=$sandbox.CreateSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion')
    try {
        $version.SetValue('InstallationType','Client')
        foreach ($build in @('10240','10586','14393','15063','16299','17134','17763','18362','18363','19041','19042','19043','19044','19045')) {
            $version.SetValue('CurrentBuildNumber',$build)
            Assert-BcWindows10 $sandbox
            $checks++
        }
        foreach ($build in @('7601','22000','26100','unknown')) {
            $version.SetValue('CurrentBuildNumber',$build)
            $rejected=$false
            try {Assert-BcWindows10 $sandbox} catch {$rejected=$true}
            if (-not $rejected) {throw "Unsupported Windows build accepted: $build"}
            $checks++
        }
        $version.SetValue('CurrentBuildNumber','17763')
        $version.SetValue('InstallationType','Server')
        $rejected=$false
        try {Assert-BcWindows10 $sandbox} catch {$rejected=$true}
        if (-not $rejected) {throw 'Windows Server was accepted.'}
        $checks++
        $version.SetValue('CurrentBuildNumber','19045')
        $version.SetValue('InstallationType','Client')
    } finally {$version.Dispose()}
    $script:FixtureRoot=$sandbox
    $script:FixtureBackupDir=Join-Path $PSScriptRoot 'test-backups'
    $script:OriginalBackupWriter=(Get-Command New-BcBackup).ScriptBlock
    $script:FailSelection=$false
    function Assert-BcAdministrator { }
    function New-BcBackup([psobject]$State) {
        $script:LastBackup=& $script:OriginalBackupWriter $State $script:FixtureBackupDir
        return $script:LastBackup
    }
    function Set-BcSelection([string]$Id,[bool]$DstDisabled=$false) {
        $selection=$script:FixtureRoot.CreateSubKey('SYSTEM\CurrentControlSet\Control\TimeZoneInformation')
        try {
            $selection.SetValue('TimeZoneKeyName',$Id)
            $selection.SetValue('DynamicDaylightTimeDisabled',[int]$DstDisabled,[Microsoft.Win32.RegistryValueKind]::DWord)
        } finally {$selection.Dispose()}
        if ($script:FailSelection -and $Id -eq 'British Columbia Standard Time') {throw 'Injected selection failure.'}
    }
    $initial=[pscustomobject]@{Id='Pacific Standard Time';DstDisabled=$true}
    $fixtureBefore=$initial | ConvertTo-Json -Compress
    Set-BcSelection $initial.Id $initial.DstDisabled
    Invoke-BcPatch -Root $sandbox -Mode Apply -WhatIf
    $key=$sandbox.OpenSubKey($zonePath)
    if ($key) {$key.Dispose(); throw 'WhatIf created a definition.'}
    $checks++
    Invoke-BcPatch -Root $sandbox -Mode Apply | Out-Null
    if ((Get-BcCurrentSelection).Id -ne 'British Columbia Standard Time' -or (Get-BcCurrentSelection).DstDisabled) {throw 'Apply did not select BC with its rules enabled.'}
    $applyBackup=$script:LastBackup
    $saved=Get-Content -LiteralPath $applyBackup -Raw | ConvertFrom-Json
    if ($saved.Original.Id -ne $initial.Id -or $saved.Original.DstDisabled -ne $initial.DstDisabled) {throw 'Original selection was not backed up.'}
    $acl=Get-Acl -LiteralPath (Split-Path -Parent $applyBackup)
    if (-not $acl.AreAccessRulesProtected) {throw 'Backup directory inherited access rules.'}
    $checks+=3
    Invoke-BcPatch -Root $sandbox -Mode Verify | Out-Null
    Invoke-BcPatch -Root $sandbox -Mode Apply | Out-Null
    if ($script:LastBackup -ne $applyBackup) {throw 'Idempotent Apply created another backup.'}
    $checks++
    Invoke-BcPatch -Root $sandbox -Mode Rollback -BackupPath $applyBackup | Out-Null
    if ((Get-BcCurrentSelection | ConvertTo-Json -Compress) -ne $fixtureBefore) {throw 'Rollback failed to restore selection and disabled-DST flag.'}
    $key=$sandbox.OpenSubKey($zonePath)
    if ($key) {$key.Dispose(); throw 'Rollback failed to remove its definition.'}
    $checks+=2
    Invoke-BcPatch -Root $sandbox -Mode Apply -RegisterOnly | Out-Null
    if ((Get-BcCurrentSelection | ConvertTo-Json -Compress) -ne $fixtureBefore) {throw 'RegisterOnly changed the selection.'}
    Invoke-BcPatch -Root $sandbox -Mode Rollback -BackupPath $script:LastBackup | Out-Null
    $checks++
    Invoke-BcPatch -Root $sandbox -Mode Apply | Out-Null
    $key=$sandbox.OpenSubKey($zonePath,$true)
    try {$key.SetValue('Display','Simulated later Windows update')} finally {$key.Dispose()}
    Invoke-BcPatch -Root $sandbox -Mode Rollback -BackupPath $script:LastBackup -WarningAction SilentlyContinue | Out-Null
    $key=$sandbox.OpenSubKey($zonePath)
    if (-not $key) {throw 'Rollback deleted a changed definition.'}
    $key.Dispose(); $sandbox.DeleteSubKeyTree($zonePath)
    $checks++
    $script:FailSelection=$true
    $failed=$false
    try {Invoke-BcPatch -Root $sandbox -Mode Apply | Out-Null} catch {if ($_ -notmatch 'Injected selection failure') {throw}; $failed=$true}
    if (-not $failed) {throw 'Injected failure did not reach the caller.'}
    if ((Get-BcCurrentSelection | ConvertTo-Json -Compress) -ne $fixtureBefore) {throw 'Failure recovery did not restore the selection.'}
    $key=$sandbox.OpenSubKey($zonePath)
    if ($key) {$key.Dispose(); throw 'Failure recovery left a partial BC definition.'}
    $checks+=3
    $script:FailSelection=$false
    # Upgrade a matching old definition without replacing any rule bytes or
    # changing selection, including when BC is already selected.
    New-BcDefinition $sandbox $zonePath
    $key=$sandbox.OpenSubKey($zonePath,$true)
    try {
        foreach ($name in @('MUI_Display','MUI_Dlt','MUI_Std')) {$key.DeleteValue($name)}
        $oldFingerprint=Get-BcFingerprint $key
    } finally {$key.Dispose()}
    Set-BcSelection 'British Columbia Standard Time' $false
    Invoke-BcPatch -Root $sandbox -Mode Apply -RegisterOnly -WhatIf
    $key=$sandbox.OpenSubKey($zonePath)
    try {if ((Get-BcFingerprint $key) -ne $oldFingerprint) {throw 'WhatIf repaired metadata.'}} finally {$key.Dispose()}
    $failed=$false
    try {Invoke-BcPatch -Root $sandbox -Mode Verify | Out-Null} catch {$failed=$true}
    if (-not $failed) {throw 'Verify accepted missing name metadata.'}
    $checks+=2
    Invoke-BcPatch -Root $sandbox -Mode Apply -RegisterOnly | Out-Null
    $repairBackup=$script:LastBackup
    $repairState=Get-Content -LiteralPath $repairBackup -Raw | ConvertFrom-Json
    if ($repairState.CreatedZone -or $repairState.SelectionChanged -or @($repairState.AddedNameValues).Count -ne 3) {throw 'Metadata repair backup is incorrect.'}
    $key=$sandbox.OpenSubKey($zonePath)
    try {if (-not (Test-BcDefinition $key)) {throw 'Apply failed to repair missing names.'}} finally {$key.Dispose()}
    Invoke-BcPatch -Root $sandbox -Mode Apply -RegisterOnly | Out-Null
    if ($script:LastBackup -ne $repairBackup) {throw 'Repeated metadata repair created a new backup.'}
    Invoke-BcPatch -Root $sandbox -Mode Rollback -BackupPath $repairBackup | Out-Null
    $key=$sandbox.OpenSubKey($zonePath)
    try {if ((Get-BcFingerprint $key) -ne $oldFingerprint) {throw 'Metadata rollback did not restore the exact original definition.'}} finally {$key.Dispose()}
    $checks+=4
    # A failed post-write validation removes only the names just added.
    $script:OriginalNativeCheck=(Get-Command Test-BcNativeTimeZone).ScriptBlock
    function Test-BcNativeTimeZone {throw 'Injected native API validation failure.'}
    try {
        $failed=$false
        try {Invoke-BcPatch -Root $sandbox -Mode Apply -RegisterOnly | Out-Null} catch {if ($_ -notmatch 'Injected native API validation failure') {throw}; $failed=$true}
        if (-not $failed) {throw 'Native API validation failure was ignored.'}
    } finally {Set-Item -LiteralPath Function:\Test-BcNativeTimeZone -Value $script:OriginalNativeCheck}
    $key=$sandbox.OpenSubKey($zonePath)
    try {if ((Get-BcFingerprint $key) -ne $oldFingerprint) {throw 'Failed repair changed the original definition.'}} finally {$key.Dispose()}
    $checks+=2
    # Preserve a later update to an entry repaired by this patch.
    Invoke-BcPatch -Root $sandbox -Mode Apply -RegisterOnly | Out-Null
    $key=$sandbox.OpenSubKey($zonePath,$true)
    try {$key.SetValue('Display','Later official update')} finally {$key.Dispose()}
    Invoke-BcPatch -Root $sandbox -Mode Rollback -BackupPath $script:LastBackup -WarningAction SilentlyContinue | Out-Null
    $key=$sandbox.OpenSubKey($zonePath)
    try {if (-not (Test-BcDefinition $key) -or $key.GetValue('Display') -ne 'Later official update') {throw 'Rollback modified a later update after metadata repair.'}} finally {$key.Dispose()}
    $sandbox.DeleteSubKeyTree($zonePath)
    $checks++
    # Older backup files remain usable by the updated rollback implementation.
    Set-BcSelection $initial.Id $initial.DstDisabled
    Invoke-BcPatch -Root $sandbox -Mode Apply -RegisterOnly | Out-Null
    $saved=Get-Content -LiteralPath $script:LastBackup -Raw | ConvertFrom-Json
    $saved.Format='TRG.BcTimeZonePatch.v1'
    $saved.PSObject.Properties.Remove('AddedNameValues')
    $saved | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:LastBackup -Encoding UTF8
    Invoke-BcPatch -Root $sandbox -Mode Rollback -BackupPath $script:LastBackup | Out-Null
    $key=$sandbox.OpenSubKey($zonePath)
    if ($key) {$key.Dispose();throw 'Legacy backup rollback failed.'}
    $checks++
    # Repair never replaces existing labels or malformed values, and refuses
    # different rule data even if that definition also lacks name metadata.
    New-BcDefinition $sandbox $zonePath
    $key=$sandbox.OpenSubKey($zonePath,$true)
    try {
        $key.DeleteValue('MUI_Dlt'); $key.DeleteValue('MUI_Display')
        $key.SetValue('MUI_Std',42,[Microsoft.Win32.RegistryValueKind]::DWord)
        $malformedFingerprint=Get-BcFingerprint $key
    } finally {$key.Dispose()}
    $failed=$false
    try {Invoke-BcPatch -Root $sandbox -Mode Apply -RegisterOnly | Out-Null} catch {$failed=$true}
    if (-not $failed) {throw 'Malformed existing metadata was accepted.'}
    $key=$sandbox.OpenSubKey($zonePath,$true)
    try {
        if ((Get-BcFingerprint $key) -ne $malformedFingerprint) {throw 'Malformed metadata refusal changed the definition.'}
        $key.SetValue('MUI_Std','Existing standard label',[Microsoft.Win32.RegistryValueKind]::String)
        $partialFingerprint=Get-BcFingerprint $key
    } finally {$key.Dispose()}
    $checks+=2
    Invoke-BcPatch -Root $sandbox -Mode Apply -RegisterOnly | Out-Null
    $key=$sandbox.OpenSubKey($zonePath)
    try {if ($key.GetValue('MUI_Std') -ne 'Existing standard label') {throw 'Repair replaced an existing label.'}} finally {$key.Dispose()}
    Invoke-BcPatch -Root $sandbox -Mode Rollback -BackupPath $script:LastBackup | Out-Null
    $key=$sandbox.OpenSubKey($zonePath,$true)
    try {
        if ((Get-BcFingerprint $key) -ne $partialFingerprint) {throw 'Partial repair rollback changed a pre-existing value.'}
        $badTzi=ConvertFrom-BcHex $definition.Values.TZI
        $badTzi[0]=$badTzi[0] -bxor 1
        $key.SetValue('TZI',$badTzi,[Microsoft.Win32.RegistryValueKind]::Binary)
        $differentFingerprint=Get-BcFingerprint $key
    } finally {$key.Dispose()}
    $checks+=2
    $failed=$false
    try {Invoke-BcPatch -Root $sandbox -Mode Apply -RegisterOnly | Out-Null} catch {$failed=$true}
    if (-not $failed) {throw 'Metadata repair accepted different rules.'}
    $key=$sandbox.OpenSubKey($zonePath)
    try {if ((Get-BcFingerprint $key) -ne $differentFingerprint) {throw 'Refusing different rules changed the definition.'}} finally {$key.Dispose()}
    $checks+=2
} finally {
    if ($overridden) {[BcTestRegistry]::Override([IntPtr]::Zero)}
    [TimeZoneInfo]::ClearCachedData()
    $sandbox.Dispose()
    $user.DeleteSubKeyTree($sandboxPath,$false)
    $user.Dispose()
}
try {
    if ((Get-BcCurrentSelection | ConvertTo-Json -Compress) -ne $before) {throw 'The live selection changed.'}
    $key=$machine.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Time Zones\Pacific Standard Time')
    try {if ((Get-BcFingerprint $key) -ne $pacificBefore) {throw 'Live US Pacific data changed.'}} finally {$key.Dispose()}
    $key=$machine.OpenSubKey($zonePath)
    $afterBcFingerprint=$null
    if ($key) {try {$afterBcFingerprint=Get-BcFingerprint $key} finally {$key.Dispose()}}
    if ($afterBcFingerprint -ne $initialBcFingerprint) {throw 'Live BC data changed.'}
} finally {$machine.Dispose()}
$result=[ordered]@{Passed=$true;Checks=$checks;PowerShell=$PSVersionTable.PSVersion.ToString();LiveSelectionUnchanged=$true;LivePacificUnchanged=$true;LiveBcUnchanged=$true;TemporaryRegistryTreeRemoved=$true;Utc=[DateTime]::UtcNow.ToString('o')}
$result | ConvertTo-Json | Set-Content -Encoding UTF8 "$PSScriptRoot\test-results.json"
$result | ConvertTo-Json
