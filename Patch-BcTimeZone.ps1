#requires -Version 5.1
<#
.SYNOPSIS
Installs only the British Columbia time-zone definition from KB5126657.
.DESCRIPTION
Default: read-only preview. Apply requires an elevated PowerShell on Windows 10.
Use native 64-bit PowerShell on 64-bit Windows, or 32-bit PowerShell on x86 Windows.
Works with Windows PowerShell 5.1 and PowerShell 7.
TZI/Dynamic DST bytes were extracted from Microsoft's staged component
10.0.19041.7802. English labels replace unavailable tzres.dll MUI references.
Does not install the cumulative update, change ESU, replace DLLs or set UTC.
.EXAMPLE
.\Patch-BcTimeZone.ps1
.EXAMPLE
.\Patch-BcTimeZone.ps1 -Mode Apply -WhatIf
.EXAMPLE
.\Patch-BcTimeZone.ps1 -Mode Apply
.EXAMPLE
.\Patch-BcTimeZone.ps1 -Mode Apply -RegisterOnly
.EXAMPLE
.\Patch-BcTimeZone.ps1 -Mode Verify
.EXAMPLE
.\Patch-BcTimeZone.ps1 -Mode Rollback -BackupPath 'C:\path\to\state.json'
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
param(
    [ValidateSet('Preview','Apply','Verify','Rollback')][string]$Mode = 'Preview',
    [switch]$RegisterOnly,
    [string]$BackupPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Definition = @'
{
    "Id":  "British Columbia Standard Time",
    "Values":  {
                   "Display":  "(UTC-07:00) Pacific Time (British Columbia)",
                   "Dlt":  "British Columbia Daylight Time",
                   "Std":  "British Columbia Standard Time",
                   "MUI_Display":  "(UTC-07:00) Pacific Time (British Columbia)",
                   "MUI_Dlt":  "British Columbia Daylight Time",
                   "MUI_Std":  "British Columbia Standard Time",
                   "TZI":  "A401000000000000C4FFFFFF0000000000000000000000000000000000000000000000000000000000000000"
               },
    "Dynamic":  {
                    "FirstEntry":  2006,
                    "LastEntry":  2027,
                    "2006":  "E001000000000000C4FFFFFF00000A0000000500020000000000000000000400000001000200000000000000",
                    "2007":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2008":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2009":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2010":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2011":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2012":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2013":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2014":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2015":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2016":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2017":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2018":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2019":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2020":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2021":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2022":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2023":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2024":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2025":  "E001000000000000C4FFFFFF00000B0000000100020000000000000000000300000002000200000000000000",
                    "2026":  "E001000000000000C4FFFFFF0000010004000100000000000000000000000300000002000200000000000000",
                    "2027":  "A401000000000000C4FFFFFF0000000000000000000000000000000000000000000000000000000000000000"
                }
}
'@ | ConvertFrom-Json
$script:ZonePath = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Time Zones\British Columbia Standard Time'
$script:ZoneId = 'British Columbia Standard Time'

function Get-BcRegistryView {
    if ([Environment]::Is64BitOperatingSystem) { return [Microsoft.Win32.RegistryView]::Registry64 }
    return [Microsoft.Win32.RegistryView]::Registry32
}

function Assert-BcWindows10([Microsoft.Win32.RegistryKey]$Root) {
    $version = $Root.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion')
    if ($null -eq $version) { throw 'Cannot identify the Windows installation.' }
    try {
        $build = [string]$version.GetValue('CurrentBuildNumber')
        $windows10Builds = @('10240','10586','14393','15063','16299','17134','17763','18362','18363','19041','19042','19043','19044','19045')
        if ($version.GetValue('InstallationType') -ne 'Client' -or $build -notin $windows10Builds) {
            throw 'Apply supports Windows 10 client releases, including LTSB/LTSC. Windows 11 and Windows Server are outside this patch scope.'
        }
    } finally { $version.Dispose() }
}

function ConvertFrom-BcHex([string]$Hex) {
    if ($Hex.Length -ne 88 -or $Hex -notmatch '^[0-9A-Fa-f]+$') { throw 'Invalid 44-byte TZI data.' }
    $bytes = New-Object byte[] 44
    for ($i=0; $i -lt 44; $i++) { $bytes[$i] = [Convert]::ToByte($Hex.Substring($i*2,2),16) }
    return ,$bytes
}

function Get-BcFingerprint([Microsoft.Win32.RegistryKey]$Key) {
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $names = [string[]]$Key.GetValueNames(); [Array]::Sort($names,[StringComparer]::Ordinal)
    foreach ($name in $names) {
        $kind = $Key.GetValueKind($name).ToString()
        $value = $Key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($kind -eq 'Binary') { $value = [BitConverter]::ToString($value) }
        $parts.Add(($name,$kind,$value | ConvertTo-Json -Compress -Depth 5))
    }
    $children = [string[]]$Key.GetSubKeyNames(); [Array]::Sort($children,[StringComparer]::Ordinal)
    foreach ($name in $children) {
        $child = $Key.OpenSubKey($name)
        try { $parts.Add($name + ':' + (Get-BcFingerprint $child)) } finally { $child.Dispose() }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($parts -join "`n")))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Test-BcRules([Microsoft.Win32.RegistryKey]$Key) {
    if ($null -eq $Key) { return $false }
    if ('TZI' -notin $Key.GetValueNames()) { return $false }
    if ($Key.GetValueKind('TZI') -ne [Microsoft.Win32.RegistryValueKind]::Binary) { return $false }
    # Earlier BC registrations used the 2026 transitional rule at the root.
    # It is compatible only when every Dynamic DST value below still matches;
    # those year-specific rules supply the historical and permanent offsets.
    $rootTzi = [BitConverter]::ToString($Key.GetValue('TZI')).Replace('-','')
    if ($rootTzi -notin @($script:Definition.Values.TZI,$script:Definition.Dynamic.'2026')) { return $false }
    $dynamic = $Key.OpenSubKey('Dynamic DST')
    if ($null -eq $dynamic) { return $false }
    try {
        foreach ($prop in $script:Definition.Dynamic.PSObject.Properties) {
            if ($prop.Name -notin $dynamic.GetValueNames()) { return $false }
            if ($prop.Name -in @('FirstEntry','LastEntry')) {
                if ($dynamic.GetValueKind($prop.Name) -ne [Microsoft.Win32.RegistryValueKind]::DWord -or $dynamic.GetValue($prop.Name) -ne $prop.Value) { return $false }
            } else {
                if ($dynamic.GetValueKind($prop.Name) -ne [Microsoft.Win32.RegistryValueKind]::Binary) { return $false }
                if ([BitConverter]::ToString($dynamic.GetValue($prop.Name)).Replace('-','') -ne $prop.Value) { return $false }
            }
        }
        return $true
    } finally { $dynamic.Dispose() }
}

function Get-BcMissingNames([Microsoft.Win32.RegistryKey]$Key) {
    foreach ($name in @('MUI_Display','MUI_Dlt','MUI_Std')) {
        if ($name -notin $Key.GetValueNames()) { $name }
    }
}

function Test-BcDefinition([Microsoft.Win32.RegistryKey]$Key) {
    if (-not (Test-BcRules $Key)) { return $false }
    foreach ($name in @('MUI_Display','MUI_Dlt','MUI_Std')) {
        if ($name -notin $Key.GetValueNames()) { return $false }
        if ($Key.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]::String -or
            [string]::IsNullOrWhiteSpace([string]$Key.GetValue($name))) { return $false }
    }
    return $true
}

function Remove-BcAddedNames([Microsoft.Win32.RegistryKey]$Root, [object[]]$Added) {
    $key = $Root.OpenSubKey($script:ZonePath,$true)
    if ($null -eq $key) { return }
    try {
        foreach ($entry in $Added) {
            # Do not remove values that another tool changed after this write.
            if ($entry.Name -in $key.GetValueNames() -and
                $key.GetValueKind($entry.Name) -eq [Microsoft.Win32.RegistryValueKind]::String -and
                $key.GetValue($entry.Name) -eq $entry.Value) { $key.DeleteValue($entry.Name) }
        }
    } finally { $key.Dispose() }
}

function Initialize-BcNativeApi {
    if ('BcTimeZonePatch.NativeApi' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace BcTimeZonePatch {
    public static class NativeApi {
        [StructLayout(LayoutKind.Sequential)]
        public struct SystemTime { public ushort Year, Month, DayOfWeek, Day, Hour, Minute, Second, Milliseconds; }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        public struct Zone {
            public int Bias;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string StandardName;
            public SystemTime StandardDate; public int StandardBias;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DaylightName;
            public SystemTime DaylightDate; public int DaylightBias;
        }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        public struct DynamicZone {
            public int Bias;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string StandardName;
            public SystemTime StandardDate; public int StandardBias;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DaylightName;
            public SystemTime DaylightDate; public int DaylightBias;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string TimeZoneKeyName;
            [MarshalAs(UnmanagedType.U1)] public bool DynamicDaylightTimeDisabled;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetTimeZoneInformationForYear(ushort year, ref DynamicZone zone, out Zone result);
        public static void Check(string id, ushort year) {
            DynamicZone zone = new DynamicZone(); zone.TimeZoneKeyName = id;
            Zone result;
            if (!GetTimeZoneInformationForYear(year, ref zone, out result)) {
                int error = Marshal.GetLastWin32Error();
                throw new Win32Exception(error, "GetTimeZoneInformationForYear failed for " + id + " (" + year + "): " + new Win32Exception(error).Message);
            }
        }
    }
}
'@
}

function Test-BcNativeTimeZone([string]$Id = $script:ZoneId) {
    Initialize-BcNativeApi
    foreach ($year in @(2006,2026,2027,2030)) { [BcTimeZonePatch.NativeApi]::Check($Id,[uint16]$year) }
    Write-Output 'PASS: 4 native Windows time-zone API checks.'
}

function New-BcDefinition([Microsoft.Win32.RegistryKey]$Root, [string]$Path) {
    # Root/path are explicit so the same writer can be tested in an isolated HKCU tree.
    $existing = $Root.OpenSubKey($Path)
    if ($null -ne $existing) { $existing.Dispose(); throw 'Refusing to overwrite an existing time-zone definition.' }
    $key = $Root.CreateSubKey($Path)
    try {
        foreach ($prop in $script:Definition.Values.PSObject.Properties) {
            if ($prop.Name -eq 'TZI') { $key.SetValue('TZI',(ConvertFrom-BcHex $prop.Value),[Microsoft.Win32.RegistryValueKind]::Binary) }
            else { $key.SetValue($prop.Name,[string]$prop.Value,[Microsoft.Win32.RegistryValueKind]::String) }
        }
        $dynamic = $key.CreateSubKey('Dynamic DST')
        try {
            foreach ($prop in $script:Definition.Dynamic.PSObject.Properties) {
                if ($prop.Name -in @('FirstEntry','LastEntry')) { $dynamic.SetValue($prop.Name,[int]$prop.Value,[Microsoft.Win32.RegistryValueKind]::DWord) }
                else { $dynamic.SetValue($prop.Name,(ConvertFrom-BcHex $prop.Value),[Microsoft.Win32.RegistryValueKind]::Binary) }
            }
        } finally { $dynamic.Dispose() }
    } catch {
        $key.Dispose()
        $Root.DeleteSubKeyTree($Path,$false)
        throw
    } finally { $key.Dispose() }
}

function Assert-BcAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { $principal = New-Object Security.Principal.WindowsPrincipal $identity
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run Apply/Rollback in an elevated PowerShell window (Run as administrator).' }
    } finally { $identity.Dispose() }
}

function Get-BcCurrentSelection {
    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,(Get-BcRegistryView))
    try {
        $key = $root.OpenSubKey('SYSTEM\CurrentControlSet\Control\TimeZoneInformation')
        try { return [pscustomobject]@{ Id=[string]$key.GetValue('TimeZoneKeyName'); DstDisabled=([int]$key.GetValue('DynamicDaylightTimeDisabled',0) -ne 0) } }
        finally { $key.Dispose() }
    } finally { $root.Dispose() }
}

function Set-BcSelection([string]$Id,[bool]$DstDisabled=$false) {
    $argument = $Id
    if ($DstDisabled) { $argument += '_dstoff' }
    & "$env:SystemRoot\System32\tzutil.exe" /s $argument
    if ($LASTEXITCODE -ne 0) { throw "tzutil failed with exit code $LASTEXITCODE." }
    [TimeZoneInfo]::ClearCachedData()
    $actual = Get-BcCurrentSelection
    if ($actual.Id -ne $Id -or $actual.DstDisabled -ne $DstDisabled) { throw 'Windows did not retain the requested time-zone selection.' }
}

function Test-BcOffsets {
    [TimeZoneInfo]::ClearCachedData()
    $zone = [TimeZoneInfo]::FindSystemTimeZoneById($script:ZoneId)
    $cases = @(
        @('2006-01-15T12:00:00Z',-8), @('2006-07-15T12:00:00Z',-7),
        @('2025-12-15T12:00:00Z',-8), @('2026-03-08T09:59:59Z',-8),
        @('2026-03-08T10:00:00Z',-7), @('2026-11-01T08:59:59Z',-7),
        @('2026-11-01T09:00:00Z',-7), @('2026-12-15T12:00:00Z',-7),
        @('2027-01-01T08:00:00Z',-7), @('2027-07-15T12:00:00Z',-7),
        @('2030-12-15T12:00:00Z',-7), @('2100-07-15T12:00:00Z',-7)
    )
    foreach ($case in $cases) {
        $offset = $zone.GetUtcOffset([DateTimeOffset]::Parse($case[0])).TotalHours
        if ($offset -ne $case[1]) { throw "Time-zone verification failed at $($case[0]): expected $($case[1]), got $offset." }
    }
    Write-Output "PASS: $($cases.Count) historical, transition and future offset checks."
}

function New-BcBackup([psobject]$State, [string]$BaseDirectory = (Join-Path $env:ProgramData 'TRG\BcTimeZonePatch\Backups')) {
    $directory = Join-Path $BaseDirectory ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { $ownerSid = $owner.User.Value } finally { $owner.Dispose() }
    foreach ($sid in @('S-1-5-18','S-1-5-32-544',$ownerSid) | Select-Object -Unique) {
        $identity = New-Object Security.Principal.SecurityIdentifier $sid
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','ContainerInherit, ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $directory -AclObject $acl
    $path = Join-Path $directory 'state.json'
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Invoke-BcPatch {
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)][Microsoft.Win32.RegistryKey]$Root,
    [ValidateSet('Preview','Apply','Verify','Rollback')][string]$Mode = 'Preview',
    [switch]$RegisterOnly,
    [string]$BackupPath
)
if ($RegisterOnly -and $Mode -ne 'Apply') { throw '-RegisterOnly is for Apply mode.' }
if ($BackupPath -and $Mode -ne 'Rollback') { throw '-BackupPath is for Rollback mode.' }
    if ($Mode -eq 'Rollback') {
        if (-not $BackupPath) { throw 'Rollback requires -BackupPath pointing to the state.json printed by Apply.' }
        $state = Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json
        if ($state.Format -notin @('TRG.BcTimeZonePatch.v1','TRG.BcTimeZonePatch.v2') -or $state.ZoneId -ne $script:ZoneId) { throw 'This is not a BC patch backup.' }
        if (-not $PSCmdlet.ShouldProcess($script:ZoneId,'Restore the original selection and undo unchanged definition or name-metadata additions made by this patch')) { return }
        Assert-BcAdministrator
        if ($state.SelectionChanged) { Set-BcSelection $state.Original.Id ([bool]$state.Original.DstDisabled) }
        if ($state.CreatedZone) {
            $key = $root.OpenSubKey($script:ZonePath)
            $unchanged = $false
            if ($null -ne $key) {
                try { $unchanged = (Get-BcFingerprint $key) -eq $state.InstalledFingerprint } finally { $key.Dispose() }
                if ($unchanged) {
                    if ((Get-BcCurrentSelection).Id -eq $script:ZoneId) { throw 'BC is still selected. Select another time zone before removing it.' }
                    $root.DeleteSubKeyTree($script:ZonePath)
                } else { Write-Warning 'BC definition changed since Apply (possibly by Windows Update); it was preserved.' }
            }
        } elseif ($state.Format -eq 'TRG.BcTimeZonePatch.v2' -and @($state.AddedNameValues).Count -gt 0) {
            $key = $root.OpenSubKey($script:ZonePath)
            if ($null -ne $key) {
                try { $unchanged = (Get-BcFingerprint $key) -eq $state.InstalledFingerprint } finally { $key.Dispose() }
                if ($unchanged) { Remove-BcAddedNames $root @($state.AddedNameValues) }
                else { Write-Warning 'BC definition changed since Apply; its name metadata was preserved.' }
            }
        }
        [TimeZoneInfo]::ClearCachedData()
        Write-Output 'Rollback complete. The backup is retained.'
        return
    }
    $key = $root.OpenSubKey($script:ZonePath)
    $exists = $null -ne $key
    $matches = $false
    $rulesMatch = $false
    $missingNames = @()
    if ($exists) {
        try {
            $rulesMatch = Test-BcRules $key
            $matches = Test-BcDefinition $key
            $missingNames = @(Get-BcMissingNames $key)
        } finally { $key.Dispose() }
    }
    if ($Mode -eq 'Verify') {
        if (-not $matches) { throw 'BC definition is missing, differs from the extracted rules, or lacks required MUI name metadata. Run Preview for details.' }
        Test-BcOffsets
        Test-BcNativeTimeZone
        $current = Get-BcCurrentSelection
        Write-Output "Selected zone: $($current.Id); DST disabled: $($current.DstDisabled)."
        if ($current.Id -ne $script:ZoneId -or $current.DstDisabled) { Write-Warning 'The BC definition exists, but is not selected with its rules enabled.' }
        return
    }
    $original = Get-BcCurrentSelection
    if ($Mode -eq 'Preview') {
        Write-Output "Current: $($original.Id); DST disabled: $($original.DstDisabled); displayed time: $([DateTimeOffset]::Now.ToString('o'))"
        Write-Output "BC definition exists: $exists; compatible BC rules: $rulesMatch; names and rules valid: $matches."
        if ($missingNames.Count -gt 0) { Write-Output "Missing name metadata: $($missingNames -join ', ')." }
        Write-Output 'Apply: back up; add BC if absent or repair missing names on matching rules; select BC (or use -RegisterOnly).'
        Write-Output 'Scope: BC registry definition and selected zone only. US Pacific rules and system DLLs stay intact.'
        return
    }
    Assert-BcWindows10 $root
    if ($exists -and -not $rulesMatch) { throw 'An existing BC definition differs. Refusing to overwrite it.' }
    if ($exists) {
        # Missing values may be repaired, but malformed existing ones are never overwritten.
        $key = $root.OpenSubKey($script:ZonePath)
        try {
            foreach ($name in @('MUI_Display','MUI_Dlt','MUI_Std')) {
                if ($name -in $key.GetValueNames() -and
                    ($key.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]::String -or
                    [string]::IsNullOrWhiteSpace([string]$key.GetValue($name)))) { throw "Existing $name is invalid; refusing to overwrite it." }
            }
        } finally { $key.Dispose() }
    }
    if (-not $PSCmdlet.ShouldProcess($script:ZoneId,'Back up, register BC or repair missing name metadata on matching rules, and select BC unless -RegisterOnly')) { return }
    Assert-BcAdministrator
    $changeSelection = -not $RegisterOnly -and ($original.Id -ne $script:ZoneId -or $original.DstDisabled)
    if ($matches -and -not $changeSelection) { Test-BcOffsets; Test-BcNativeTimeZone; Write-Output 'Already configured; no changes.'; return }
    $state = [pscustomobject]@{ Format='TRG.BcTimeZonePatch.v2'; ZoneId=$script:ZoneId; CreatedUtc=[DateTime]::UtcNow.ToString('o'); Original=$original; CreatedZone=(-not $exists); SelectionChanged=$changeSelection; InstalledFingerprint=$null; AddedNameValues=@() }
    $savedBackup = New-BcBackup $state
    Write-Output "Backup: $savedBackup"
    $created = $false
    $selectionAttempted = $false
    try {
        if (-not $exists) {
            New-BcDefinition $root $script:ZonePath
            $created = $true
        } elseif ($missingNames.Count -gt 0) {
            $key = $root.OpenSubKey($script:ZonePath,$true)
            try {
                if (-not (Test-BcRules $key)) { throw 'BC rules changed before the metadata repair; rerun Preview.' }
                foreach ($name in $missingNames) {
                    if ($name -in $key.GetValueNames()) { throw "$name appeared before the metadata repair; refusing to overwrite it." }
                    $value = [string]$script:Definition.Values.$name
                    $state.AddedNameValues += [pscustomobject]@{Name=$name;Value=$value}
                    $key.SetValue($name,$value,[Microsoft.Win32.RegistryValueKind]::String)
                }
            } finally { $key.Dispose() }
        }
        $key = $root.OpenSubKey($script:ZonePath)
        try { $state.InstalledFingerprint = Get-BcFingerprint $key } finally { $key.Dispose() }
        $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $savedBackup -Encoding UTF8
        Test-BcOffsets
        Test-BcNativeTimeZone
        if ($changeSelection) { $selectionAttempted = $true; Set-BcSelection $script:ZoneId }
        Write-Output "Apply complete. Current displayed time: $([DateTimeOffset]::Now.ToString('o'))"
        Write-Output 'Restart open applications so they reload time-zone data. Review Outlook calendar settings separately.'
    } catch {
        $failure = $_
        try {
            if ($selectionAttempted) { Set-BcSelection $original.Id ([bool]$original.DstDisabled) }
            if ($created) {
                if ((Get-BcCurrentSelection).Id -eq $script:ZoneId) { throw 'BC is still selected; keeping its definition.' }
                $root.DeleteSubKeyTree($script:ZonePath,$false)
            } elseif ($state.AddedNameValues.Count -gt 0) { Remove-BcAddedNames $root @($state.AddedNameValues) }
        } catch { Write-Warning "Automatic recovery could not finish: $_. Backup: $savedBackup" }
        throw $failure
    }
}

if ($env:OS -ne 'Windows_NT') { throw 'This script requires Windows.' }
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { throw 'Use native 64-bit PowerShell on 64-bit Windows.' }
$root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,(Get-BcRegistryView))
try { Invoke-BcPatch -Root $root @PSBoundParameters } finally { $root.Dispose() }
