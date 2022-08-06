[CmdletBinding(PositionalBinding=$true)]
Param(
    [string[]]$Rids = @("win-x64","win-x86","win-arm64","linux-arm","linux-x64")
)

foreach ($Rid in $Rids)
{
    & $PSScriptRoot/spmi.ps1 redownload $Rid
}