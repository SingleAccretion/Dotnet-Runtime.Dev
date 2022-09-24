using namespace System.Collections.Generic

[CmdletBinding(PositionalBinding=$true)]
Param(
    [string]$BaseTracePath,
    [string]$DiffTracePath,
    [double]$NoiseFilter = 0.1,
    [string[]]$FunctionsFilter = @()
)

function ParseTrace($TraceText)
{
    $Trace = @{}

    foreach ($Line in $TraceText)
    {
        if (!($Line -match "(\d+) +: (.*)"))
        {
            continue;
        }

        $InstructionCount = [double]$Matches[1]
        $Name = $Matches[2]

        if ($Name -in $FunctionsFilter)
        {
            continue;
        }

        $Trace.Add($Name, $InstructionCount)
    }

    return $Trace
}

function CountTotalInstructions($Trace)
{
    $Total = 0.0
    foreach ($FunctionTrace in $Trace.GetEnumerator())
    {
        $Total += $FunctionTrace.Value
    }

    return $Total
}

function GetPercentageDiff($BaseValue, $DiffValue)
{
    return (($DiffValue - $BaseValue) / $BaseValue) * 100;
}

function FormatPercentageDiff($PercentageDiff, $Precision = "00")
{
    return ($PercentageDiff -gt 0 ? '+' : '') + $PercentageDiff.ToString("0.$Precision") + "%"
}

$BaseTrace = ParseTrace (Get-Content $BaseTracePath)
$DiffTrace = ParseTrace (Get-Content $DiffTracePath)
$AllRecodedFunctions = [HashSet[string]]::new()
foreach ($FunctionTrace in $BaseTrace.GetEnumerator())
{
    $AllRecodedFunctions.Add($FunctionTrace.Key) > $null
}
foreach ($FunctionTrace in $DiffTrace.GetEnumerator())
{
    $AllRecodedFunctions.Add($FunctionTrace.Key) > $null
}

$BaseTotalInsCount = CountTotalInstructions $BaseTrace
$DiffTotalInsCount = CountTotalInstructions $DiffTrace
$TotalPercentageDiff = GetPercentageDiff $BaseTotalInsCount $DiffTotalInsCount

Write-Output "Base: $BaseTotalInsCount, Diff: $DiffTotalInsCount, $(FormatPercentageDiff $TotalPercentageDiff '0000')"
Write-Output ""

# Now create a list of functions which contributed to the difference
$FunctionDiffs = New-Object List[Object]
$TotalAbsInsCountDiff = 0
foreach ($FunctionName in $AllRecodedFunctions)
{
    $DiffInsCount = $DiffTrace[$FunctionName]
    $BaseInsCount = $BaseTrace[$FunctionName]
    $InsCountDiff = $DiffInsCount - $BaseInsCount
    if ($InsCountDiff -eq 0.0)
    {
        continue;
    }

    $InsPercentageDiff = GetPercentageDiff $BaseInsCount $DiffInsCount
    $TotalInsPercentageDiff = ($InsCountDiff / $BaseTotalInsCount) * 100

    $FunctionDiffs.Add([PSCustomObject]@{
        Name = $FunctionName
        InsCountDiff = $InsCountDiff
        InsPercentageDiff = $InsPercentageDiff
        TotalInsPercentageDiff = $TotalInsPercentageDiff
    })

    $TotalAbsInsCountDiff += [Math]::Abs($InsCountDiff)
}

foreach ($Diff in $FunctionDiffs)
{
    $Diff | Add-Member -NotePropertyName ContributionPercentage -NotePropertyValue ([Math]::Abs($Diff.InsCountDiff * 100) / $TotalAbsInsCountDiff)
}

$FunctionDiffs = $FunctionDiffs | Where-Object ContributionPercentage -gt $NoiseFilter | Sort-Object InsCountDiff -Descending

$MaxNameLength = 0
$MaxInsCountDiffLength = 0
$MaxInsPercentageDiffLength = 0
foreach ($Diff in $FunctionDiffs)
{
    $MaxNameLength = [Math]::Max($MaxNameLength, $Diff.Name.Length)
    $MaxInsCountDiffLength = [Math]::Max($MaxInsCountDiffLength, "$($Diff.InsCountDiff)".Length)
    $MaxInsPercentageDiffLength = [Math]::Max($MaxInsPercentageDiffLength, (FormatPercentageDiff $Diff.InsPercentageDiff).Length)
}

foreach ($Diff in $FunctionDiffs)
{
    $InsPercentageDiffString = FormatPercentageDiff $Diff.InsPercentageDiff
    if ([double]::IsInfinity($Diff.InsPercentageDiff))
    {
        $InsPercentageDiffString = "NA"
    }

    $OutputString = "{0,-$MaxNameLength} : {1,-$MaxInsCountDiffLength} : {2,-$MaxInsPercentageDiffLength} : {3,-6:P2} : {4}" -f @(
        $Diff.Name,
        $Diff.InsCountDiff,
        $InsPercentageDiffString,
        ($Diff.ContributionPercentage / 100),
        (FormatPercentageDiff $Diff.TotalInsPercentageDiff "0000")
    )
    Write-Output $OutputString
}