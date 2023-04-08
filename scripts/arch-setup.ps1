[CmdletBinding(PositionalBinding=$true)]
Param(
    [Parameter(ValueFromRemainingArguments=$true)]$Args
)

$ActualArgs = @()
for ($i = 0; $Args -and $i -lt @($Args).Length; $i++)
{
    if ($Args[$i])
    {
        $ActualArgs += $Args[$i].Trim().ToLower()
    }
}
$Args = $ActualArgs

Write-Verbose "Arch-setup: Args are: '$Args'"

$HostArch = "x64"
if ($Args -and $Args.Contains("x86"))
{
	$HostArch = "x86"
}

$HostArch = $null
$Rid = $null
foreach ($Arg in $Args)
{
    if (@("x64", "x86").Contains($Arg))
    {
        if ($HostArch)
        {
            Write-Error "Arch-setup: Duplicate host arch provided!"
            return
        }
        else
        {
            $HostArch = $Arg            
            Write-Verbose "Arch-setup: Found host arch: $HostArch"
        }
    }
    
    $Arg = $Arg.Replace("windows", "win")
    if (@("win-x64","win-x86","linux-x64","linux-arm64","linux-arm", "win-arm", "win-arm64").Contains($Arg))
    {
        if ($Rid)
        {
            Write-Error "Arch-setup: Duplicate target provided!"
            return
        }
        else
        {
            $Rid = $Arg
            Write-Verbose "Arch-setup: Found target: $Rid"
        }
    }
}

$HostArch = $HostArch ? $HostArch : "x64"
$Rid = $Rid ? $Rid : "win-$HostArch"

Write-Verbose "Arch-setup: Host arch: $HostArch"
Write-Verbose "Arch-setup: Target: $Rid"

$Rid = $Rid.Split("-")
$TargetArch = $Rid[1]
$TargetOS = @{ "win" = "windows"; "linux" = "linux"; "osx" = "osx" }[$Rid[0]]
$JitTargetOS = @{ "win"  = "win"; "linux" = "unix"; "osx" = "unix" }[$Rid[0]]
if (@("arm", "arm64").Contains($TargetArch))
{
    Write-Verbose "Arch-setup: Using the 'universal' compiler for $TargetArch"
    $JitTargetOS = "universal"
}

$JitName = "clrjit`_$JitTargetOS`_$TargetArch`_$HostArch.dll"
if ($TargetOS -eq "windows" -and $TargetArch -eq $HostArch)
{
    Write-Verbose "Arch-setup: Using the native clrjit.dll for win-$TargetArch"
    $JitName = "clrjit.dll"
}

Write-Verbose "Arch-setup: Target arch: $TargetArch"
Write-Verbose "Arch-setup: Target OS: $TargetOS"
Write-Verbose "Arch-setup: Jit name: $JitName"

return ($HostArch, $TargetOS, $TargetArch, $JitName)