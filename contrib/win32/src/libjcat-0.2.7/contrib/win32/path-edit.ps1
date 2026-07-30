<#
.SYNOPSIS
    Adds or removes a directory from the machine PATH.

.DESCRIPTION
    Called by the NSIS installer and uninstaller. This lives outside the
    installer for two reasons: NSIS truncates strings at 1024 characters in its
    default build, which silently corrupts a long PATH, and the registry value
    must be read *unexpanded* so that entries like %SystemRoot%\system32 are
    not baked into literal paths on the way back out.

    Dry run first if you want to see the result without touching anything:
      powershell -ExecutionPolicy Bypass -File path-edit.ps1 `
        -Dir 'C:\Program Files\libjcat\bin' -Action Add -DryRun

.NOTES
    Requires elevation, since it writes to HKLM.
#>
param(
    [Parameter(Mandatory = $true)][string] $Dir,
    [Parameter(Mandatory = $true)][ValidateSet('Add', 'Remove')][string] $Action,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$subkey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'

function Normalize([string] $p) {
    # compare case-insensitively and ignore a trailing separator
    return $p.Trim().TrimEnd('\').ToLowerInvariant()
}

$key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subkey, $true)
if ($null -eq $key) {
    throw "cannot open HKLM\$subkey for writing (are you elevated?)"
}

try {
    # DoNotExpandEnvironmentNames is the important part: reading this value the
    # ordinary way returns %SystemRoot% already expanded, and writing that back
    # permanently replaces the variable references with literals
    $current = $key.GetValue(
        'Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)

    $parts = @($current -split ';' | Where-Object { $_.Trim() -ne '' })
    $target = Normalize $Dir
    $kept = @($parts | Where-Object { (Normalize $_) -ne $target })

    if ($Action -eq 'Add') {
        $new = $kept + $Dir
    } else {
        $new = $kept
    }
    $value = $new -join ';'

    if ($value -eq $current) {
        Write-Output "PATH already correct, no change"
        exit 0
    }

    Write-Output "old PATH ($($parts.Count) entries, $($current.Length) chars)"
    Write-Output "new PATH ($($new.Count) entries, $($value.Length) chars)"

    if ($DryRun) {
        Write-Output "--- dry run, not written ---"
        Write-Output $value
        exit 0
    }

    $key.SetValue('Path', $value, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    Write-Output "PATH updated"
} finally {
    $key.Close()
}
