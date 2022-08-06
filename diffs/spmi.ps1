[CmdletBinding(PositionalBinding=$true)]
Param(
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args = @()
)

$ArgsLength = @($Args).Length
for ($i = 0; $i -lt $ArgsLength; $i++)
{
    $Arg = $Args[$i].ToLower()
}

$i = 0
$Action = "asmdiffs"
if ($i -le $ArgsLength -and @("replay","asmdiffs","basediffs","redownload").Contains($Args[$i]))
{
    $Action = $Args[$i]
    $i++
    Write-Verbose "Picked action: $Action"
}

$SpmiAction = $Action

$Rid = $null
if ($i -lt $ArgsLength -and @("win-x64","win-x86","linux-x64","linux-arm64","linux-arm", "win-arm", "win-arm64").Contains($Args[$i]))
{
    $Rid = $Args[$i]
    $i++
    Write-Verbose "Picked Rid: $Rid"
}

$HostArch = $null
if ($i -lt $ArgsLength -and @("x64","x86").Contains($Args[$i]))
{
    $HostArch = $Args[$i]
    $i++
    Write-Verbose "Picked host arch: $HostArch"
}
if (!$HostArch -and ${Rid}?.EndsWith("-arm"))
{
    Write-Verbose "Choosing the x86 compiler for $Rid diffs"
    $HostArch = "x86"
}

$HostArch, $TargetOS, $TargetArch, $JitName = ../scripts/arch-setup.ps1 $Rid $HostArch

$SpmiCollectionsToFiltersMap = [ordered]@{
    "aspnet" = "aspnet";
    "bench" = "benchmarks.run";
    "clrtests" = "coreclr_tests";
    "cglibs" = "libraries.crossgen2";
    "libs" = "libraries.pmi";
    "libstests" = "libraries_tests.pmi"
}

$SpmiCollections = @()
$SpmiCollectionsSpecified = $false
foreach ($Arg in $Args[$i..($ArgsLength - 1)])
{
    if ($SpmiCollectionsToFiltersMap.Contains($Arg))
    {
        $SpmiCollections += $Arg
        $SpmiCollectionsSpecified = $true
        $i++
    }
}

$JitOptions = @()
foreach ($Arg in $Args[$i..($ArgsLength - 1)])
{
    if ($Arg.Contains("="))
    {
        $JitOptions += $Arg
        $i++
    }
}

if (@($SpmiCollections).Length -gt 1 -and $Action -ne "redownload")
{
    Write-Error "Only one collection filter is currently supported for diffs/replays/timing"
    return
}

if (!$SpmiCollectionsSpecified)
{
    Write-Verbose "No SPMI collections specified, assuming all are being requested"
    foreach ($Collection in $SpmiCollectionsToFiltersMap.Keys)
    {
        $SpmiCollections += $Collection
    }
}

Write-Verbose "SPMI collections are: $SpmiCollections"

if ($i -ne $ArgsLength)
{
    Write-Verbose "Processed $i arguments while there were $ArgsLength arguments"
    Write-Error "Incorrect arguments provided, aborting!"
    return
}

function RunSpmiScript($SpmiCommandLine)
{
    $SpmiPath = [System.IO.Path]::GetFullPath("..\runtime\src\coreclr\scripts\superpmi.py", $PSScriptRoot)
    $Invocation = "py $SpmiPath $SpmiAction -target_os $TargetOS -target_arch $TargetArch $SpmiCommandLine"
    
    Write-Verbose "Running '$Invocation'"
    Invoke-Expression $Invocation
}

if ($Action -eq "redownload")
{
    $SpmiAction = "download"

    foreach ($Collection in $SpmiCollections)
    {
        do
        {
            RunSpmiScript "--force_download -filter $($SpmiCollectionsToFiltersMap[$Collection])"
        } while ($LastExitCode -ne 0)
    }
}
else
{
    $JitNameOption = "-jit_name $JitName"
    $BaseJitOption = ""
    $HostArchOption = ""
    $FilterOption = ""
    $JitOptionsOption = ""

    if ($Action -eq "basediffs")
    {
        $SpmiAction = "asmdiffs"
    }
    
    if ($SpmiAction -eq "asmdiffs")
    {
        if ($Action -eq "basediffs")
        {
            $SavedJitsPath = . $PSScriptRoot/../scripts/saved-jits.ps1 $HostArch "Checked"
            $BaseJitPath = Join-Path $SavedJitsPath $JitName
        }
        else
        {
            $BaseJitPath = Join-Path $PSScriptRoot "../runtime-base/artifacts/bin/coreclr/Windows.$HostArch.Checked/$JitName"
        }
        Write-Verbose "Base jit path is '$BaseJitPath'"

        $BaseJitOption = "-base_jit_path $BaseJitPath"
        
        $BaseJitOptions = @()
        $DiffJitOptions = @()
        foreach ($JitOption in $JitOptions)
        {
            if ($JitOption -like "base:*")
            {
                $BaseJitOptions += $JitOption.Substring("base:".Length)
            }
            elseif ($JitOption -like "diff:*")
            {
                $DiffJitOptions += $JitOption.Substring("diff:".Length)
            }
            else
            {
                $BaseJitOptions += $JitOption
                $DiffJitOptions += $JitOption
            }
        }
        $BaseJitOptionsOption = "$($BaseJitOptions | ForEach-Object { `"-base_jit_option $_`" })"
        $DiffJitOptionsOption = "$($DiffJitOptions | ForEach-Object { `"-diff_jit_option $_`" })"
        
        $JitOptionsOption = "$BaseJitOptionsOption $DiffJitOptionsOption"
    }
    elseif ($SpmiAction -eq "replay")
    {
        $JitOptionsOption = "$($JitOptions | ForEach-Object { `"-jitoption $_`" })"
    }

    if (@("replay", "asmdiffs").Contains($SpmiAction))
    {
        $HostArchOption = "-arch $HostArch"
    }

    if ($SpmiCollectionsSpecified)
    {
        $FilterOption = "-filter $($SpmiCollectionsToFiltersMap[$SpmiCollections[0]])"
    }

    RunSpmiScript "$HostArchOption $JitNameOption $FilterOption $BaseJitOption $JitOptionsOption".Trim().Replace("  ", " ")
}