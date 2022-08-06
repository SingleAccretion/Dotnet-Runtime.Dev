[CmdletBinding(PositionalBinding=$true)]
Param(
    [string]$Command,
    [string]$Toggle = "DOTNET_JitMinOptsRange",
    [int]$SuccessExitCode = 100,
    [switch]$Quiet = $false
)

if (!$Command)
{
    Write-Error "The command to run must be provided!"
    exit
}

function TestRange($Low, $High)
{    
    $Range = "{0:X8}" -f $Low + "-" + "{0:X8}" -f $High

    Write-Host "Testing: $Range"

    [Environment]::SetEnvironmentVariable($Toggle, $Range)

    if ($Quiet)
    {
        & $Command > $null
    }
    else
    {
        & $Command | Write-Host
    }

    Write-Host "Exit code: $LastExitCode"
    
    return $LastExitCode -eq $SuccessExitCode
}

[uint64]$Low = 0
[uint64]$High = 0xFFFFFFFFu

do
{
    $Success = TestRange $Low $High
    Write-Verbose "Success: $Success"

    if ($Success)
    {
        # If we've hit success, continue the (downwards) search
        $Diff = $High - $Low
        
        if ($Diff -le 1)
        {
            break
        }

        $High -= [uint64]($Diff / 2)
    }
    else
    {
        # In case of a failure, we need to step back up
        $Low = $High
        $High += $Low
        if ($High -gt 0xFFFFFFFFu)
        {
            $High = 0xFFFFFFFFu
        }
    }
} while ($true)

# One or two cases remaining
$Offender = (TestRange $Low $Low) ? $Low : $High

Write-Host $("Found the offending method: 0x" + "{0:X8}" -f $Offender)
