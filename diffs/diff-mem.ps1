[CmdletBinding(PositionalBinding=$true)]
Param(
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args = @()
)

$HostArch, $TargetOS, $TargetArch, $JitName = ../scripts/arch-setup.ps1 @Args

$DiffJitPath = [System.IO.Path]::GetFullPath("../runtime/artifacts/bin/coreclr/windows.$HostArch.Release/$JitName", $PSScriptRoot)

$Basediffs = $Args.Contains("basediffs")

if ($Basediffs)
{
    $SavedJitsPath = . $PSScriptRoot/../scripts/saved-jits.ps1 $HostArch "Release"
    $BaseJitPath = Join-Path $SavedJitsPath $JitName
}
else
{
    $BaseJitPath = [System.IO.Path]::GetFullPath("../build/BaseCustomJits/$HostArch/Release/mem/$JitName", $PSScriptRoot)
}

if (!(Test-Path $BaseJitPath))
{
    Write-Error "Could not find the base Jit built with memory stats!"
    Write-Error "Expected location: '$BaseJitPath'"
    return
}

$Assemblies = @([System.IO.Path]::GetFullPath("..\runtime\artifacts\bin\coreclr\windows.$HostArch.Release\IL\System.Private.CoreLib.dll", $PSScriptRoot))

Write-Verbose "Assemblies to diff: $Assemblies"

Write-Host "Make sure both compilers were built with MEASURE_MEM_STATS (in jit.h) defined!" -ForegroundColor Yellow

$BaseMemDiffsDir = "$PSScriptRoot\mem-diffs"
if (!(Test-Path $BaseMemDiffsDir))
{
	mkdir $BaseMemDiffsDir | Write-Verbose
}
$ExistingMemDiffs = Get-ChildItem -Path $PSScriptRoot\mem-diffs mem-diffs* -Directory
$NewIndex = $ExistingMemDiffs.Length + 1

$NewMemDiffsDir = "$BaseMemDiffsDir\mem-diffs.$NewIndex"
mkdir $NewMemDiffsDir | Write-Verbose

$NewBaseMemDiffsDir = "$NewMemDiffsDir\base"
mkdir $NewBaseMemDiffsDir | Write-Verbose
$NewDiffMemDiffsDir = "$NewMemDiffsDir\diff"
mkdir $NewDiffMemDiffsDir | Write-Verbose

$JitOptions = "--codegenopt JitMemStats=1"

function RunCrossgen($BasePath, $JitPath, $JitOptions, $AssemblyPath)
{
	$AssemblyName = [System.IO.Path]::GetFileName($AssemblyPath)
	$OutputFilePath = "$BasePath\$AssemblyName"
	$ResultsFile = "$BasePath\$AssemblyName.memory"
    
    $RuntimePath = [System.IO.Path]::GetFullPath("..\runtime", $PSScriptRoot)
    $BaseRuntimePath = [System.IO.Path]::GetFullPath("..\runtime-base", $PSScriptRoot)    
    $CrossgenPath = "$RuntimePath\artifacts\bin\coreclr\windows.$HostArch.Release\crossgen2\crossgen2.dll"
    $CorerunPath = "$BaseRuntimePath\artifacts\tests\coreclr\windows.$HostArch.Release\Tests\Core_Root\corerun.exe"
    
    $CrossgenOptions = "-o $OutputFilePath --jitpath $JitPath $JitOptions --targetarch $TargetArch --targetos $TargetOS"
	$CrossgenOptions += " --instruction-set avx2,bmi,bmi2,lzcnt,popcnt"
    
    $Invocation = "$CorerunPath $CrossgenPath $CrossgenOptions $AssemblyPath"
	
    Write-Verbose "Crossgen path is '$CrossgenPath'"
    Write-Verbose "Corerun path is '$CorerunPath'"
    
    $SavedCoreRootEnvVar = $env:CORE_ROOT
    $env:CORE_ROOT = ""
    
	Write-Verbose "Invoking: '$Invocation'"
	Invoke-Expression $Invocation > $ResultsFile
    if (!(Test-Path $OutputFilePath))
    {
        Write-Error "Compilation failed, could not find $OutputFilePath"
        exit
    }

    $env:CORE_ROOT = $SavedCoreRootEnvVar
	Remove-Item $OutputFilePath
}

Write-Output "Invoking base compiler: $BaseJitPath"
foreach ($Assembly in $Assemblies)
{
	RunCrossgen $NewBaseMemDiffsDir $BaseJitPath $JitOptions $Assembly
}

Write-Output "Invoking diff compiler: $DiffJitPath"
foreach ($Assembly in $Assemblies)
{
	RunCrossgen $NewDiffMemDiffsDir $DiffJitPath $JitOptions $Assembly
}

Write-Output "Results saved to: $NewMemDiffsDir"

function ParseResults($ResultsContentPath)
{
    $ResultsContent = Get-Content $ResultsContentPath
    
    if (!$ResultsContent)
    {
        Write-Error "Could not read the results file from $ResultsContentPath"
        exit
    }
    if (!$ResultsContent.Contains("Alloc'd bytes by kind:"))
    {
        Write-Error "Looks like mem stats were not defined for '$ResultsContentPath'!"
        exit
    }
    
    $RequestedMemory = 0
    $RequestedMemoryAvg = 0
    $RequestedSet = $false
    
    $Index = 0;
    while (!$RequestedSet)
    {
        $Line = $ResultsContent[$Index]
        
        if ($Line.Contains("alloc size"))
        {
            $MatchInfo = $Line | Select-String " *alloc size *: *(\d+) *\(avg * (\d+) *per method\)"
            $RequestedTotal, $RequestedAvg = $MatchInfo.Matches[0].Groups[1..2].Value
            $RequestedMemory = [long]$RequestedTotal
            $RequestedMemoryAvg = [long]$RequestedAvg
            
            $RequestedSet = $true
        }
        
        $Index++
    }
    
    return @($RequestedMemory, $RequestedMemoryAvg)
}

function AggregateResults($DiffsDir)
{
    $AllRequested = 0
    $AllRequestedAvg = 0
    $NumberOfResults = 0
    foreach ($ResultFile in Get-ChildItem $DiffsDir\*.memory)
    {
        $Results = ParseResults $ResultFile
        $AllRequested += $Results[0]
        $AllRequestedAvg += $Results[1]
        $NumberOfResults++
    }
    
    $AllRequestedAvg /= $NumberOfResults
    
    return @($AllRequested, $AllRequestedAvg)
}

$BaseResults = AggregateResults $NewBaseMemDiffsDir
$BaseTotal = $BaseResults[0]
Write-Output "Base total: $BaseTotal"

$DiffResults = AggregateResults $NewDiffMemDiffsDir
$DiffTotal = $DiffResults[0]
Write-Output "Diff total: $DiffTotal"

$Delta = $DiffTotal - $BaseTotal
$RelativeDelta = [double]$Delta / [double]$BaseTotal

Write-Output "Absolute difference is: $Delta"
Write-Output "Relative difference is: $(($RelativeDelta * 100).ToString("0.000"))%"