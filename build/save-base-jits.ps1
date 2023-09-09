[CmdletBinding(PositionalBinding=$false)]
Param(
  [ValidateSet("x86","x64")][string][Alias('a')]$HostArch = "x64",
  [ValidateSet("Debug","Checked","Release")][string]$Config = "Checked",
  [string]$BuiltJitsPath = $null
)

if (!$BuiltJitsPath)
{
    $BuiltJitsPath = [IO.Path]::GetFullPath("../runtime/artifacts/bin/coreclr/Windows.$HostArch.$Config", $PSScriptRoot)
}

$SavedJitsPath = . $PSScriptRoot/../scripts/saved-jits.ps1 $HostArch $Config
mkdir $SavedJitsPath -Force > $null
robocopy $BuiltJitsPath $SavedJitsPath clrjit* | Write-Verbose
robocopy $BuiltJitsPath/PDB $SavedJitsPath clrjit* | Write-Verbose

Write-Host "" -ForegroundColor Yellow
Write-Host "Copied Jits from $BuiltJitsPath to $SavedJitsPath" -ForegroundColor Yellow
Write-Host "" -ForegroundColor Yellow
