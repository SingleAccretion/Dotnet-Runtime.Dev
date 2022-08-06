[CmdletBinding(PositionalBinding=$true)]
Param(
    [string]$HostArch,
    [string]$BuildConfig
)

$JitsDir = Join-Path "../diffs/base-jits-$HostArch" $BuildConfig.ToLower()

return [IO.Path]::GetFullPath($JitsDir, $PSScriptRoot)