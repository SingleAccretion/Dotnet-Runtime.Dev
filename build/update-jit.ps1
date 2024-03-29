[CmdletBinding(PositionalBinding=$false)]
Param(
  [ValidateSet("x86","x64")][string][Alias('a')]$HostArch = "x64",
  [switch]$All = $false,
  [switch][Alias('r')]$Release,
  [switch][Alias('p')]$RefreshPdb,
  [switch][Alias('b')]$UpdateBaseJits,
  [switch]$LlvmRyuJit,
  [switch]$Pgo,
  [ValidateSet("Debug","Checked","Release")][string[]]$Configs = $null,
  [string[]]$Stats = @()
)

$RuntimeRepoName = $LlvmRyuJit ? "runtimelab" : "runtime"
$RuntimePath = [System.IO.Path]::GetFullPath("../$RuntimeRepoName", $PSScriptRoot)

$Subset = $All ? "Clr.AllJits" : $LlvmRyuJit ? "Clr.WasmJit" : "Clr.Jit"
$ClrComponent = @{ "Clr.AllJits" = "alljits"; "Clr.Jit" = "jit"; "Clr.WasmJit" = "wasmjit" }[$Subset]
$UseBuildRuntimeScript = $ClrComponent -ne $null -and !$Pgo # build-runtime.cmd needs the paths to PGO data, etc.

if (!$Configs)
{
    $Configs = $Release ? @("Release") : @("Checked", "Debug")
}
$HostOS = "Windows"

Write-Verbose "Subset built: $Subset"
Write-Verbose "CLR component built: $ClrComponent"
Write-Verbose "Using build-runtime.cmd: $UseBuildRuntimeScript"
Write-Verbose "Configs built: $Configs"
Write-Verbose "Host arch: $HostArch"
Write-Verbose "Host OS: $HostOS"

foreach ($Config in $Configs)
{
    if ($RefreshPdb)
    {
        Write-Verbose "Deleting the old PDBs so that the incremental build regenerates them"
        Remove-Item "$RuntimePath\artifacts\obj\coreclr\$HostOS.$HostArch.$Config\jit\clrjit*.pdb"
    }

    if (@($Stats).Length -gt 0)
    {
        if ($LlvmRyuJit)
        {
            Write-Error "Defining stats not supported for the LLVM RyuJit at the moment!"
            return
        }

        Write-Host "Building custom $Config Jits with $([string]::Join(", ", $Stats)) stats" -ForegroundColor Yellow
        ./build-jit-with-stats-defined.ps1 -JitSubset $Subset -Arch $HostArch -Config $Config -Stats $Stats
    }
    else
    {
        # Speed up the build by using build-runtime.cmd, if possible, directly.
        if ($UseBuildRuntimeScript)
        {
            $BuildExpression = "$RuntimePath\src\coreclr\build-runtime.cmd $Config $HostArch -component $ClrComponent"
        }
        else
        {
            $BuildExpression = "$RuntimePath\build.cmd $Subset -c $Config -a $HostArch"
        }

        if ($Config -eq "Release")
        {
            Write-Host "Building Release Jits with PGO $($Pgo ? 'on' : 'off')" -ForegroundColor Yellow
            if (!$UseBuildRuntimeScript)
            {
                $BuildExpression += " /p:NoPgoOptimize=$($Pgo ? 'false' : 'true')"
            }
        }

        Write-Verbose "Running: '$BuildExpression'"
        Invoke-Expression $BuildExpression
    }

    $ClrBuildDir = "$RuntimePath/artifacts/bin/coreclr/$HostOS.$HostArch.$Config"
    $TargetJitDir = $LlvmRyuJit ? "$RuntimePath/artifacts/bin/coreclr/$HostOS.$HostArch.$Config/ilc"
                                : "$RuntimePath/artifacts/tests/coreclr/$HostOS.$HostArch.$Config/Tests/Core_Root"
    $JitsToCopyGlob = $LlvmRyuJit ? ($All ? "clrjit_*" : "clrjit_browser_wasm32_*") : ($All ? "clrjit*" : "clrjit")

    robocopy $ClrBuildDir $TargetJitDir "${JitsToCopyGlob}.dll" | Write-Verbose
    robocopy $ClrBuildDir\PDB $TargetJitDir "${JitsToCopyGlob}.pdb" | Write-Verbose

    if ($UpdateBaseJits -and $Config -ne "Debug")
    {
        ./save-base-jits.ps1 -HostArch $HostArch -Config $Config -BuiltJitsPath $ClrBuildDir
    }
}

if (!$Configs.Contains("Release"))
{
    $UpdateCoreRootExpression = "$PSScriptRoot/update-custom-core-root.ps1 -a $HostArch"
    if ($LlvmRyuJit)
    {
        # Unlike CG2 and ILC, LLVM ILC core root is not updated automatically, so we have to request it explicitly.
        $UpdateCoreRootExpression += " -llvmIlc"
    }

    Write-Verbose "Invoking: $UpdateCoreRootExpression"
    Invoke-Expression $UpdateCoreRootExpression
}
