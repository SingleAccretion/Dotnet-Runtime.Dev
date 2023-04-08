[CmdletBinding(PositionalBinding=$false)]
Param(
  [ValidateSet("x86","x64")][string][Alias('a')]$Arch = "x64",
  [switch]$CG2,
  [switch]$Ilc,
  [switch]$LlvmIlc,
  [switch]$Mono
)

# The CG2 custom core root is used both as a source of references and for running the CG2 itself (via corerun).
# This is because we employ a renaming trick which assists in debugging the Jit used for compilation.
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

# The ILC custom core root is also used for both compilation and running the ILC itself. This works because
# ILC is copied self-contained, and thus does not conflict with the NativeAOT-specific CoreLib. It also makes
# the CG2 renaming trick unnecessary. We should consider switching CG2 to the same plan.
$IlcDestPath = Join-Path $PSScriptRoot "ilc"
if ($Ilc)
{
    $SourceIlcPath = Join-Path $PSScriptRoot "../runtime/artifacts/bin/coreclr/Windows.$Arch.Release/ilc-published"
    $SourceFrameworkPath = Join-Path $PSScriptRoot "../runtime/artifacts/tests/coreclr/Windows.$Arch.Release/Tests/Core_Root"
    $SourceAotSdkPath = Join-Path $PSScriptRoot "../runtime/artifacts/bin/coreclr/Windows.$Arch.Release/aotsdk"

    # Copy "the AOT SDK" last, overwriting the CoreCLR CoreLib from the copied core root (our "framework").
    robocopy $SourceIlcPath $IlcDestPath | Write-Verbose
    robocopy $SourceFrameworkPath $IlcDestPath | Write-Verbose
    robocopy $SourceAotSdkPath $IlcDestPath | Write-Verbose
    Copy-Item $PSScriptRoot/ilc.rsp $IlcDestPath
}

if ($LlvmIlc)
{
    # We want the files from "the AOT SDK" (i. e. the runtime binaries) and "the framework" to end up in the custom core root.
    $SourceFrameworkPath = Join-Path $PSScriptRoot "../runtimelab/artifacts/tests/coreclr/Browser.wasm.Debug/Tests/Core_Root"
    $SourceAotSdkPath = Join-Path $PSScriptRoot "../runtimelab/artifacts/bin/coreclr/Browser.wasm.Debug/aotsdk"
    $LlvmIlcDestPath = Join-Path $PSScriptRoot "llvm-ilc"

    # Copy the "target" binaries into out custom core root
    robocopy $SourceFrameworkPath $LlvmIlcDestPath | Write-Verbose
    robocopy $SourceAotSdkPath $LlvmIlcDestPath | Write-Verbose
    Copy-Item $PSScriptRoot/llvm-ilc.rsp $LlvmIlcDestPath
}

$RuntimePath = [System.IO.Path]::GetFullPath("..\runtime", $PSScriptRoot)

# For Mono, we take the existing CoreCLR core root and then add Mono runtime binaries.
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

$TestsPath = "$RuntimePath\artifacts\tests\coreclr"
$SrcCheckedCoreRootPath = "$TestsPath\windows.$Arch.Checked\Tests\Core_Root"
$CoreRootSuffix = $Arch -eq "x64" ? "" : "_$Arch"
$CoreRootDestPath = "$PSScriptRoot\CustomCoreRoot$CoreRootSuffix"

$ClrJitGlob = "clrjit*.dll"
$ClrJitPbdGlob = "clrjit*.pdb"

# Copy the Checked bits
robocopy $SrcCheckedCoreRootPath $CoreRootDestPath /XF $ClrJitGlob | Write-Verbose
robocopy $SrcCheckedCoreRootPath\PDB $CoreRootDestPath /XF $ClrJitPbdGlob | Write-Verbose

$DebugJitsPath = "$TestsPath\windows.$Arch.Debug\Tests\Core_Root"
$DebugJitsPdbPath = Join-Path $DebugJitsPath "PDB"

# We overwrite the checked Jits with Debug ones.
foreach ($DestPath in @($CoreRootDestPath, $Crossgen2DestPath, $IlcDestPath))
{
    robocopy $DebugJitsPath $DestPath $ClrJitGlob | Write-Verbose
    robocopy $DebugJitsPdbPath $DestPath $ClrJitPbdGlob | Write-Verbose
}
