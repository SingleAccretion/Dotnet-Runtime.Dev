[CmdletBinding(PositionalBinding=$false)]
Param(
  [ValidateSet("x86","x64")][string][Alias('a')]$Arch = "x64",
  [switch]$CG2,
  [switch]$Ilc,
  [switch]$Mono
)

$Crossgen2DestPath = Join-Path $PSScriptRoot "crossgen2"
if ($CG2)
{
    $BaseCoreRootPath = Join-Path $PSScriptRoot "../runtime-base/artifacts/tests/coreclr/Windows.$Arch.Release/Tests/Core_Root"
    $BaseCrossgen2Dir = Join-Path $BaseCoreRootPath "crossgen2"

    robocopy $BaseCoreRootPath $Crossgen2DestPath | Write-Verbose
    robocopy $BaseCrossgen2Dir $Crossgen2DestPath | Write-Verbose
    Copy-Item $PSScriptRoot/cg2.rsp $Crossgen2DestPath

    $ClrJitPath = "$Crossgen2DestPath/clrjit.dll"
    Copy-Item $ClrJitPath $ClrJitPath.Replace("clrjit.dll", "cg2jit.dll") -Force
    Remove-Item $Crossgen2DestPath/clrjit*.dll
}

# ILC is special for us as it hardcodes most things.
if ($Ilc)
{
    $IlcDestPath = Join-Path $PSScriptRoot "ilc"

    $SourceCoreRootNativeAotPath = Join-Path $PSScriptRoot "../runtimelab/artifacts/tests/coreclr/Browser.wasm.Debug/Tests/Core_Root/nativeaot"
    $SourcePathForJits = Join-Path $PSScriptRoot "../runtimelab/artifacts/bin/coreclr/Windows.$Arch.Debug"
    
    robocopy $SourceCoreRootNativeAotPath $IlcDestPath /E | Write-Verbose
    robocopy $SourcePathForJits $IlcDestPath clrjit* | Write-Verbose
    Copy-Item $PSScriptRoot/ilc.rsp $IlcDestPath
}

$RuntimePath = [System.IO.Path]::GetFullPath("..\runtime", $PSScriptRoot)

# For Mono, we take the existing CoreCLR CoreRoot and then add Mono runtime binaries.
if ($Mono)
{
    $CoreCLRCoreRootPath = Join-Path $RuntimePath "artifacts\tests\coreclr\windows.$Arch.Release\Tests\Core_Root"
    $DestMonoCoreRootPath = Join-Path $PSScriptRoot "mono_$Arch"

    robocopy $CoreCLRCoreRootPath $DestMonoCoreRootPath /XF "coreclr.dll" "clrjit.dll" "clrgc.dll" "System.Private.CoreLib.dll" | Write-Verbose
    Move-Item "$DestMonoCoreRootPath\corerun.exe" "$DestMonoCoreRootPath\corerun_mono_$Arch.exe" -Force

    # Use the Debug runtime binaries.
    $MonoCoreLibPath = Join-Path $RuntimePath "artifacts\bin\mono\windows.$Arch.Debug\System.Private.CoreLib.dll"
    $MonoCoreCLRPath = Join-Path $RuntimePath "artifacts\obj\mono\windows.$Arch.Debug\out\bin\coreclr.dll"
    
    Copy-Item $MonoCoreLibPath $DestMonoCoreRootPath
    Copy-Item $MonoCoreCLRPath $DestMonoCoreRootPath
}

$CoreRootSuffix = "_$Arch"
if ($Arch -eq "x64")
{
    $CoreRootSuffix = ""
}

$TestsPath = "$RuntimePath\artifacts\tests\coreclr"
$SrcCheckedCoreRootPath = "$TestsPath\windows.$Arch.Checked\Tests\Core_Root"
$CoreRootDestPath = "$PSScriptRoot\CustomCoreRoot$CoreRootSuffix"
$DebugJitsPath = "$TestsPath\windows.$Arch.Debug\Tests\Core_Root"
$DebugJitsPdbPath = "$TestsPath\windows.$Arch.Debug\Tests\Core_Root\PDB"
$ClrJitGlob = "clrjit*.dll"
$ClrJitPbdGlob = "clrjit*.pdb"

# Copy the Checked bits
robocopy $SrcCheckedCoreRootPath $CoreRootDestPath /XF $ClrJitGlob | Write-Verbose
robocopy $SrcCheckedCoreRootPath\PDB $CoreRootDestPath /XF $ClrJitPbdGlob | Write-Verbose

# We overwrite the checked Jits with Debug ones.
foreach ($DestPath in @($Crossgen2DestPath, $CoreRootDestPath))
{
    robocopy $DebugJitsPath $DestPath $ClrJitGlob | Write-Verbose
    robocopy $DebugJitsPdbPath $DestPath $ClrJitPbdGlob | Write-Verbose
}
