[CmdletBinding(PositionalBinding=$true)]
Param(
    [Parameter(Mandatory=$false)][int]$SpmiIndex,
    [switch]$PerfScore,
    [switch]$Log,
    [switch]$Native,
    [switch]$Basediffs,
    [switch]$Asm,
    [switch]$WordDiff,
    [string[]]$Options
)

$CurrentDir = "$(Get-Location)"
$CurrentDirName = [System.IO.Path]::GetFileName($CurrentDir)
$CurrentDirParts = $CurrentDirName.Split(".")

function ShowDiff($BaseFile, $DiffFile)
{
    $GitDiffExpression = "git diff --no-index $BaseFile $DiffFile"

    if ($WordDiff)
    {
        $GitDiffExpression += " --word-diff"
    }

    Invoke-Expression $GitDiffExpression
}

if ($PerfScore)
{
    Invoke-Expression "jit-analyze -b base -d diff -m PerfScore"
    return
}

if (!$SpmiIndex)
{
    if ($Log)
    {
        ShowDiff "baselog.cs" "log.cs"
    }
    else
    {
        Write-Error "Spmi index must be supplied!"
    }

    return
}

$ShowDiff = !$Log -and !$Asm

Write-Verbose "Current directory name is: '$CurrentDirName'"

$IsSpmiDir = $CurrentDir.Contains("spmi") -and @("asm", "repro").Contains($CurrentDirParts[0])
$IsWasmJitDiffDir = $CurrentDir.Contains("wasmjit-diff")
if (!$IsSpmiDir -and !$IsWasmJitDiffDir)
{
    Write-Error "Must be in the SPMI/wasmjit-diff results directory to obtain diffs!"
    return
}

if ($ShowDiff)
{
    ShowDiff "base/$SpmiIndex.dasm" "diff/$SpmiIndex.dasm"
    return
}

# "asm.libraries_tests.pmi.windows.x64.checked.1"
# "repro.benchmarks.run.Linux.arm.checked"

$BuildType = $CurrentDirParts[5]
Write-Verbose "Build type is: '$BuildType'"
if ($BuildType -ne "checked")
{
    Write-Error "Must be a checked build to get diffs!"
    return
}

$Arch = $CurrentDirParts[4]
$OS = $CurrentDirParts[3]

$HostArchPreference = ""
if (!$Native -and @("x86", "arm").Contains($Arch))
{
    $HostArchPreference = "x86"
}

$HostArch, $TargetOS, $TargetArch, $JitName = . $PSScriptRoot/../scripts/arch-setup.ps1 "$($OS.ToLower())-$Arch" $HostArchPreference

$DiffCoreRootPath = Join-Path $PSScriptRoot "../runtime/artifacts/tests/coreclr/Windows.$HostArch.$BuildType/Tests/Core_Root"
$BaseCoreRootPath = Join-Path $PSScriptRoot "../runtime-base/artifacts/tests/coreclr/Windows.$HostArch.$BuildType/Tests/Core_Root"

$SpmiPath = Join-Path $BaseCoreRootPath "superpmi.exe"
$DiffJitPath = Join-Path $DiffCoreRootPath $JitName
$BaseJitsPath = $Basediffs ? (. $PSScriptRoot/../scripts/saved-jits.ps1 $HostArch "checked") : $BaseCoreRootPath
$BaseJitPath = Join-Path $BaseJitsPath $JitName

$MchFilesRootDir = Join-Path $PSScriptRoot "spmi\mch"
$MchDirs = Get-ChildItem $MchFilesRootDir -Filter "*$OS.$Arch" -Directory

Write-Verbose "MCH directories: $MchDirs"
if (@($MchDirs).Length -ne 1)
{
    Write-Error "Could not find MCH files or found too many!"
    return
}

$MchFileName = ([string]::Join(".", $CurrentDirParts[1..5] + "mch"))
$MchFile = Join-Path @($MchDirs)[0] $MchFileName

$DisplayDiffFile = $null
$OutputConfigs = @()

if ($Log)
{
    $DisplayOption = "JitDump=*"
    $FileName = "log.cs"
    $OutputConfigs += ,($DisplayOption, $FileName)
    
    $DisplayDiffFile = $FileName
}
if ($Asm)
{
    $DisplayOption = "JitDisasm=*"
    $FileName = "asm.dasm"
    $OutputConfigs += ,($DisplayOption, $FileName)
    
    if (!$DisplayDiffFile)
    {
        $DisplayDiffFile = $FileName
    }
}

$DisplayBaseFile = "base$DisplayDiffFile"
$UserOptions = $Options ? [string]::Join(" ", (@($Options) | ForEach-Object { "-jitoption $_" })) : $null
$OverallOptions = $UserOptions

if (!${UserOptions}?.Contains("JitDiffableDasm="))
{
    $OverallOptions += " -jitoption JitDiffableDasm=1"
}

foreach ($OutputConfig in $OutputConfigs)
{
    $DisplayOption = $OutputConfig[0]
    $OutFileName = $OutputConfig[1]
    $DiffOutFile = $OutFileName
    $BaseOutFile = "base$OutFileName"

    $SpmiArgs = "$BaseJitPath $MchFile -c $SpmiIndex -jitoption $DisplayOption $OverallOptions"
    Write-Verbose "Running: '$SpmiPath $SpmiArgs'"
    Write-Output "Running base compiler with $DisplayOption..."
    Invoke-Expression "$SpmiPath $SpmiArgs" > $BaseOutFile
    
    $SpmiArgs = "$DiffJitPath $MchFile -c $SpmiIndex -jitoption $DisplayOption $OverallOptions"
    Write-Verbose "Running: '$SpmiPath $SpmiArgs'"
    Write-Output "Running diff compiler with $DisplayOption..."
    Invoke-Expression "$SpmiPath $SpmiArgs" > $DiffOutFile
}

ShowDiff $DisplayBaseFile $DisplayDiffFile