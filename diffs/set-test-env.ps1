[CmdletBinding(PositionalBinding=$true)]
Param(
    [ValidateSet("x64","x86")][string]$Arch = "x64",
    [switch]$NativeAot,
    [switch]$Checked,
    [switch]$Release,
    [switch]$TieredCompilation = $false,
    [switch]$Base = $false,
    [int]$StressLevel = -1
)

function SetEnvVar($Name, $Value)
{
    Write-Output "${Name}: '$Value'"
    [Environment]::SetEnvironmentVariable($Name, $Value)
}

$Config = $Release ? "Release" : $Checked ? "Checked" : "Debug"

if ($NativeAot)
{
    SetEnvVar "CLRCustomTestLauncher" "$PSScriptRoot/../runtimelab/src/tests/Common/scripts/nativeaottest.cmd"
    SetEnvVar "CORE_ROOT" "$PSScriptRoot/../runtimelab/artifacts/tests/coreclr/Browser.wasm.$Config/Tests/Core_Root"
}
else
{
    if (!$Base)
    {
        $env:CORE_ROOT = $Arch -eq "x64" ? $env:CUSTOM_CORE_ROOT : $env:CUSTOM_CORE_ROOT_X86
    }
    else
    {
        $env:CORE_ROOT = $Arch -eq "x64" ? $env:BASE_CORE_ROOT : $env:BASE_CORE_ROOT_X86
    }
    Write-Output "CORE_ROOT: $env:CORE_ROOT"

    SetEnvVar "DOTNET_JitStress" ($StressLevel -eq -1 ? "" : $StressLevel)
    SetEnvVar "DOTNET_TieredCompilation" ($TieredCompilation ? 1 : 0)
}
