[CmdletBinding(PositionalBinding=$false)]
Param(
  [switch][Alias('f')]$DiffFramework,
  [switch][Alias('p')]$RunPmi,
  [switch][Alias('pc')]$RunPmiWithCctors,
  [string][Alias('a')]$Arch = "x64",
  [int][ValidateRange("Positive")][Alias('c')]$Count = $null
)

$Base = [System.IO.Path]::GetFullPath("..\runtime-base\artifacts\bin\coreclr\Windows.$Arch.Checked", $PSScriptRoot)
$Diff = [System.IO.Path]::GetFullPath("..\runtime\artifacts\bin\coreclr\Windows.$Arch.Checked", $PSScriptRoot)
$CoreRoot = [System.IO.Path]::GetFullPath("..\runtime\artifacts\tests\coreclr\windows.$Arch.Checked\Tests\Core_Root", $PSScriptRoot)

$WhatToDiff = "-c"
if ($DiffFramework)
{
    $WhatToDiff = "-f"
}
$PmiOption = ""
if ($RunPmi -or $RunPmiWithCctors)
{
    $PmiOption = "--pmi"
    if ($RunPmiWithCctors)
    {
        $PmiOption = "$PmiOption --cctors"
    }
}
$CountOption = ""
if ($Count)
{
    $CountOption = "--count $Count"
}

pushd ..\runtime
$JitDiffInvocation = "jit-diff diff -o $PSScriptRoot -b $Base -d $Diff --core_root $CoreRoot $WhatToDiff $PmiOption $CountOption"
"Running $JitDiffInvocation"
Invoke-Expression $JitDiffInvocation
popd