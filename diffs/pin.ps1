[CmdletBinding(PositionalBinding=$true)]
Param(
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args = @()
)

$HostArch, $TargetOS, $TargetArch, $JitName = . $PSScriptRoot/../scripts/arch-setup.ps1 @Args

$InstrumentBase = $true
$PinToolPath = $null
$Basediffs = $false
$TraceInstrumentation = $false
$JitOptions = @()
$UserContextNumbers = @()
$MchPaths = @()
for ($i = 0; $i -lt @($Args).Length; $i++)
{
    $Arg = $Args[$i]
    Write-Verbose "Processing arg: '$Arg'"

    if ($Arg.EndsWith(".mch"))
    {
        $MchPaths += [System.IO.Path]::GetFullPath($Arg, $Pwd)
    }
    $ContextNumber = 0
    if ($Arg -match "^\d+$" -or $Arg -match "^(\d+-\d+ ?)+")
    {
        $UserContextNumbers += $Arg.Split(" ")
    }
    if ($Arg -match "^\w+=(\w|\d)+$")
    {
        $JitOptions += $Arg
    }
    if ($Arg -eq "basediffs")
    {
        $Basediffs = $true
    }
    if ($Arg.Contains(".dll"))
    {
        $PinToolPath = $Arg
    }
    if ($Arg -eq "trace")
    {
        $TraceInstrumentation = $true
    }
    if ($Arg -eq "tracediff")
    {
        $TraceInstrumentation = $true
        $InstrumentBase = $false
    }
}

if (@($MchPaths).Length -eq 0)
{
    Write-Verbose "No explicit MCH files to replay specified, falling back to collections"
    $MchPaths = . $PSScriptRoot/../scripts/spmi-collections.ps1 $TargetOS $TargetArch @Args
}

if (@($MchPaths).Length -lt 1)
{
    Write-Verbose "No explicit collections to replay specified, falling back to benchmarks"
    $MchPaths = . $PSScriptRoot/../scripts/spmi-collections.ps1 $TargetOS $TargetArch "bench"
}
elseif (@($MchPaths).Length -gt 1)
{
    Write-Error "Only one replay for the PIN tool is currently supported"
    return
}

$MchPath = @($MchPaths)[0]

$PinArch = $HostArch -eq "x86" ? "ia32" : "intel64"
$PinPath = [System.IO.Path]::GetFullPath("pin\pin-3.19-98425-gd666b2bee-msvc-windows\$PinArch\bin\pin.exe", $PSScriptRoot)
$PinToolArgs = "-m $JitName"
if ($TraceInstrumentation)
{
    $PinToolArgs += " -trace"
}
if (!$PinToolPath)
{
    $PinToolPath = [System.IO.Path]::GetFullPath("pin\pin-3.19-98425-gd666b2bee-msvc-windows\source\tools\SingleAccretionPinTool\obj-$PinArch\SingleAccretionPinTool.dll", $PSScriptRoot)
}

$SpmiPath = [System.IO.Path]::GetFullPath("..\runtime\artifacts\bin\coreclr\windows.$HostArch.Release\superpmi.exe", $PSScriptRoot)
$DiffJitPath = [System.IO.Path]::GetFullPath("..\runtime\artifacts\bin\coreclr\windows.$HostArch.Release\$JitName", $PSScriptRoot)

if ($Basediffs)
{
    $SavedJitsPath = . $PSScriptRoot/../scripts/saved-jits.ps1 $HostArch "Release"
    $BaseJitPath = Join-Path $SavedJitsPath $JitName
}
else
{
    $BaseJitPath = [System.IO.Path]::GetFullPath("..\runtime-base\artifacts\bin\coreclr\windows.$HostArch.Release\$JitName", $PSScriptRoot)
}

$SpmiMissingDataResult = -1.0;

function InvokeSpmi($FilePath, $InvokeCmd, $ContextNumbers, $SpmiKind)
{
    if (@($ContextNumbers)?.Length -gt 0)
    {
        $ContextsList = [string]::Join(",", $ContextNumbers)
        $InvokeCmd += " -c $ContextsList"   
    }

    Write-Verbose $InvokeCmd
    Invoke-Expression "$InvokeCmd" *> $FilePath

    if ($LastExitCode -ne 0)
    {
        if ($LastExitCode -eq 3)
        {
            return $SpmiMissingDataResult
        }
        else
        {
            Write-Error "$SpmiKind SPMI exit code was $LastExitCode, see $FilePath for details"
            exit
        }
    }

    if ($TraceInstrumentation)
    {
        return
    }

    $SpmiOutput = Get-Content $FilePath
    $LastLine = $SpmiOutput[$SpmiOutput.Length - 1]
    if ($LastLine -match "Count (\d+)")
    {
        return [double]$Matches[1]
    }
    else
    {
        Write-Error "results from $BaseResultsFile are not in the expected format!"
        exit
    }
}

function ExtractSuccessfulContexts($SpmitOutputFilePath)
{
    Write-Verbose "Missing data, building a list of failed MCs..."

    $SpmiOutput = Get-Content $SpmitOutputFilePath
    $SuccessfulContextsRanges = @()
    $PreviousFailedMcIndex = 0
    foreach ($Line in $SpmiOutput)
    {
        $FirstSuccessfulMcIndex = 1
        $LastSuccessfulMcIndex = -1

        if ($Line -match "MISSING: Method context (\d+) failed to replay")
        {
            $FailedMcIndex = [int]$Matches[1]
            Write-Verbose "MISSING data in MC: $FailedMcIndex"

            $FirstSuccessfulMcIndex = $PreviousFailedMcIndex + 1
            $LastSuccessfulMcIndex = $FailedMcIndex - 1

            $PreviousFailedMcIndex = $FailedMcIndex
        }
        elseif ($Line -match "Jitted (\d+)" -and !$Line.Contains("%"))
        {
            $FirstSuccessfulMcIndex = $PreviousFailedMcIndex + 1
            $LastSuccessfulMcIndex = [int]$Matches[1]
            Write-Verbose "Final MC: $LastSuccessfulMcIndex"
        }

        if ($FirstSuccessfulMcIndex -lt $LastSuccessfulMcIndex)
        {
            Write-Verbose "Adding MCs: $FirstSuccessfulMcIndex-$LastSuccessfulMcIndex"
            $SuccessfulContextsRanges += "$FirstSuccessfulMcIndex-$LastSuccessfulMcIndex"
        }
        elseif ($FirstSuccessfulMcIndex -eq $LastSuccessfulMcIndex)
        {
            Write-Verbose "Adding MCs: $FirstSuccessfulMcIndex"
            $SuccessfulContextsRanges += "$FirstSuccessfulMcIndex"
        }
    }

    return $SuccessfulContextsRanges
}

$SpmiCommonCmd = "$MchPath"
if (@($JitOptions).Length -ne 0)
{
    $SpmiCommonCmd += " -jitoption $([string]::Join(' -jitoption', $JitOptions))"
}

$BaseSpmiCmd = "$SpmiPath $BaseJitPath $SpmiCommonCmd"
$DiffSpmiCmd = "$SpmiPath $DiffJitPath $SpmiCommonCmd"

$PinInvokeCmd = "$PinPath -t $PinToolPath $PinToolArgs --"
$BaseInvokeCmd = "$PinInvokeCmd $BaseSpmiCmd"
$DiffInvokeCmd = "$PinInvokeCmd $DiffSpmiCmd"

if ($InstrumentBase)
{
    Write-Output "Base Jit is: $BaseJitPath"
}
Write-Output "Diff Jit is: $DiffJitPath"

$BaseResultsFile = $TraceInstrumentation ? "$PSScriptRoot/basetp.txt" : $(New-TemporaryFile)
$DiffResultsFile = $TraceInstrumentation ? "$PSScriptRoot/difftp.txt" : $(New-TemporaryFile)
$SpmiContextNumbers = $UserContextNumbers

Write-Verbose "Base results file: $BaseResultsFile"
Write-Verbose "Diff results file: $DiffResultsFile"

function StringizeContexts($ContextsList) { return [string]::Join(',', $ContextsList) }

function RunSpmi($Cmd, $SpmiKind)
{
    if ($TraceInstrumentation)
    {
        Write-Host "Running $($SpmiKind.ToLower()) Jit..."
    }

    $ResultsFile = $SpmiKind -eq "Base" ? $BaseResultsFile : $DiffResultsFile
    $Count = InvokeSpmi $ResultsFile $Cmd $SpmiContextNumbers $SpmiKind

    if (!$TraceInstrumentation)
    {
        Write-Host "${SpmiKind}: $Count"
    }
    return $Count
}

function RunBaseSpmi() { return RunSpmi $BaseInvokeCmd "Base" }
function RunDiffSpmi() { return RunSpmi $DiffInvokeCmd "Diff" }

if ($InstrumentBase)
{
    $BaseResult = RunBaseSpmi
    if ($BaseResult -eq $SpmiMissingDataResult)
    {
        $SpmiContextNumbers = ExtractSuccessfulContexts $BaseResultsFile
        Write-Output "Encountered MISSING data, rerunning with clean contexts: $(StringizeContexts $SpmiContextNumbers)"

        $BaseResult = RunBaseSpmi
    }
}

$DiffResult = RunDiffSpmi
if ($DiffResult -eq $SpmiMissingDataResult)
{
    $SpmiContextNumbers = ExtractSuccessfulContexts $DiffResultsFile
    Write-Output "Encountered MISSING data for the diff run, rerunning with clean contexts: $(StringizeContexts $SpmiContextNumbers)"

    $BaseResult = RunBaseSpmi
    $DiffResult = RunDiffSpmi
}

if ($TraceInstrumentation)
{
    . $PSScriptRoot/analyze-pin-trace-diff.ps1 -Base $BaseResultsFile -Diff $DiffResultsFile
}
else
{
    $Delta = $DiffResult - $BaseResult
    Write-Output "Delta: $Delta"
    Write-Output "Relative delta: $((($Delta / $BaseResult) * 100).ToString("0.0000"))%"

    Remove-Item $BaseResultsFile
    Remove-Item $DiffResultsFile
}