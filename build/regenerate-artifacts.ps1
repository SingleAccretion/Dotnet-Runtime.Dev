[CmdletBinding(PositionalBinding=$false)]
Param(
  [string[]][Alias('a')]$Arches = @("x64", "x86"),
  [switch]$Save = $false,
  [switch]$Pull = $false,
  [switch]$BaseOnly = $false
)

$RegenerateBase = $true
$RegenerateDiff = !$BaseOnly

if (!$Save)
{
    $Pull = $true
}

$RuntimePath = [System.IO.Path]::GetFullPath("..\runtime", $PSScriptRoot)
$BuildScript = "$RuntimePath\build.cmd"

$BaseRuntimePath = [System.IO.Path]::GetFullPath("..\runtime-base", $PSScriptRoot)
$BaseBuildScript = "$BaseRuntimePath\build.cmd"

function RunCommand($Directory, $Command)
{
    Push-Location $Directory
    $Result = Invoke-Expression "$Command"
    Pop-Location

    return $Result
}

if ($RegenerateDiff)
{
    $CurrentBranch = RunCommand $RuntimePath "git status"
    if (!$CurrentBranch.Contains("nothing to commit, working tree clean"))
    {
        Write-Error "runtime: must be on a clean branch to regenerate artifacts!"
        return
    }

    RunCommand $RuntimePath "git switch main"
    if ($Pull)
    {
        RunCommand $RuntimePath "git pull upstream main"
        RunCommand $RuntimePath "git push origin main"
    }
    if (!$Save)
    {
        RunCommand $RuntimePath "git clean -xdf"
    }
}

if ($RegenerateBase)
{
    $CurrentBranch = RunCommand $BaseRuntimePath "git status"
    if (!$CurrentBranch.Contains("nothing to commit, working tree clean"))
    {
        Write-Error "runtime-base: must be on a clean branch to regenerate artifacts!"
        return
    }

    RunCommand $BaseRuntimePath "git switch main"
    if ($Pull)
    {
        RunCommand $BaseRuntimePath "git pull origin main"
    }
    if (!$Save)
    {
        RunCommand $BaseRuntimePath "git clean -xdf"
    }
}

foreach ($Arch in $Arches)
{
    if (!@("x86","x64").Contains($Arch))
    {
        Write-Error "Architecture not supported: $Arch"
        return
    }

    if ($RegenerateDiff)
    {
        Invoke-Expression "$BuildScript clr -c Checked -a $Arch"
        Invoke-Expression "$BuildScript clr -c Debug -a $Arch"
        Invoke-Expression "$BuildScript clr -c Release -a $Arch"
        Invoke-Expression "$BuildScript libs -c Release -a $Arch"

        Invoke-Expression "$RuntimePath\src\tests\build.cmd checked generatelayoutonly $Arch"
        Invoke-Expression "$RuntimePath\src\tests\build.cmd debug generatelayoutonly $Arch"
        Invoke-Expression "$RuntimePath\src\tests\build.cmd release generatelayoutonly $Arch"
    }

    if ($RegenerateBase)
    {
        # We define NoPgoOptimize=true for the Release builds as we want to use them for PIN diffs
        Invoke-Expression "$BaseBuildScript clr -c Checked -a $Arch"
        Invoke-Expression "$BaseBuildScript clr -c Debug -a $Arch"
        Invoke-Expression "$BaseBuildScript clr -c Release -a $Arch /p:NoPgoOptimize=true"
        ./build-jit-with-stats-defined.ps1 -Base -Save -JitSubset "clr.alljits" -Arch $Arch -Config "Release" -Stats "mem"

        Invoke-Expression "$BaseBuildScript libs -c Release -a $Arch"
        Invoke-Expression "$BaseRuntimePath\src\tests\build.cmd checked generatelayoutonly $Arch"
        Invoke-Expression "$BaseRuntimePath\src\tests\build.cmd debug generatelayoutonly $Arch"
        Invoke-Expression "$BaseRuntimePath\src\tests\build.cmd release generatelayoutonly $Arch"
    }

    Invoke-Expression "$PSScriptRoot/update-custom-core-root.ps1 -a $Arch -cg2"
}
