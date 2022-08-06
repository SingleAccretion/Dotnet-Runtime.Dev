[CmdletBinding(PositionalBinding=$false)]
Param(
  [ValidateSet("x86","x64")][string][Alias('a')]$HostArch = "x64",
  [switch]$All = $false,
  [switch][Alias('r')]$Release,
  [switch][Alias('p')]$RefreshPdb,
  [switch][Alias('b')]$UpdateBaseJits,
  [switch]$LlvmRyuJit,
  [switch]$CG2,
  [switch]$Pgo,
  [string[]]$Stats = @()
)

$RuntimeRepoName = $LlvmRyuJit ? "runtimelab" : "runtime"
$RuntimePath = [System.IO.Path]::GetFullPath("../$RuntimeRepoName", $PSScriptRoot)

$Subset = $All ? "Clr.AllJits" : $LlvmRyuJit ? "Clr.WasmJit" : "Clr.Jit"
$ClrComponent = @{ "Clr.AllJits" = "alljits"; "Clr.Jit" = "jit"; "Clr.WasmJit" = "wasmjit" }[$Subset]
$UseBuildRuntimeScript = $ClrComponent -ne $null -and !$Pgo # build-runtime.cmd needs the paths to PGO data, etc.

$Configs = $Release ? @("Release") : $LlvmRyuJit ? @("Debug") : @("Checked", "Debug")
$BuildArch = $HostArch
$HostOS = "Windows"

Write-Verbose "Subset built: $Subset"
Write-Verbose "CLR component built: $ClrComponent"
Write-Verbose "Using build-runtime.cmd: $UseBuildRuntimeScript"
Write-Verbose "Configs built: $Configs"
Write-Verbose "Build arch: $BuildArch"
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
            $BuildExpression = "$RuntimePath\src\coreclr\build-runtime.cmd $Config $BuildArch -component $ClrComponent"
        }
        else
        {
            $BuildExpression = "$RuntimePath\build.cmd $Subset -c $Config -a $BuildArch"
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

    $ClrBuildDir = "$RuntimePath\artifacts\bin\coreclr\$HostOS.$HostArch.$Config"
    $CoreRootJitDir = "$RuntimePath\artifacts\tests\coreclr\$HostOS.$BuildArch.$Config\Tests\Core_Root"
    $JitsToCopyGlob = $All ? "clrjit*.dll" : "clrjit.dll"

    robocopy $ClrBuildDir $CoreRootJitDir $JitsToCopyGlob | Write-Verbose

    if ($UpdateBaseJits -and $Config -ne "Debug")
    {
        ./save-base-jits.ps1 -HostArch $HostArch -Config $Config -BuiltJitsPath $ClrBuildDir
    }
}

if (!$Release)
{
    $UpdateCoreRootExpression = ".\update-custom-core-root.ps1 -a $HostArch"
    if ($LlvmRyuJit)
    {
        $UpdateCoreRootExpression += " -ilc"
    }
    if ($CG2)
    {
        $UpdateCoreRootExpression += " -cg2"
    }

    Write-Verbose "Invoking: $UpdateCoreRootExpression"
    Invoke-Expression $UpdateCoreRootExpression
}
