[CmdletBinding(PositionalBinding=$true)]
Param(
    [ValidateSet("x64","x86")][string]$Arch = "x64",
    [switch]$TieredCompilation = $false,
    [switch]$Base = $false,
    [int]$StressLevel = -1
)

if (!$Base)
{
    $env:CORE_ROOT = $Arch -eq "x64" ? $env:CUSTOM_CORE_ROOT : $env:CUSTOM_CORE_ROOT_X86
}
else
{
    $env:CORE_ROOT = $Arch -eq "x64" ? $env:BASE_CORE_ROOT : $env:BASE_CORE_ROOT_X86
}
Write-Output "CORE_ROOT: $env:CORE_ROOT"

if ($StressLevel -ne -1)
{
    $env:DOTNET_JitStress = $StressLevel
    Write-Output "DOTNET_JitStress: $env:DOTNET_JitStress"
}

if (!$TieredCompilation)
{
    $env:DOTNET_TieredCompilation = 0
    Write-Output "DOTNET_TieredCompilation: $env:DOTNET_TieredCompilation"
}