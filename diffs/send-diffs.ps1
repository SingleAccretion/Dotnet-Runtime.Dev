[CmdletBinding(PositionalBinding=$true)]
Param(
    [Parameter(Mandatory=$true)][string]$PrIndex,
    [Parameter(Mandatory=$true)][int]$MdIndex,
    [string]$RepositoryName = "runtime",
    [switch][Alias('d')]$ShowDiffs
)

$MdIndexString = $MdIndex -ne 0 ? ".$MdIndex." : "."
$MdFilePath = Join-Path $PSScriptRoot "spmi" "diff_summary$($MdIndexString)md"

if (!(Test-Path $MdFilePath))
{
    Write-Error "$MdFilePath does not exist!"
    return
}

Write-Verbose "Diffs are in: $MdFilePath"

$Diffs = Get-Content $MdFilePath
$Content = $Diffs
$SomeLineWithCollection = $null
foreach ($Line in @($Content))
{
    if ($Line -match "(\w+)\.(\w+)\.checked\.mch")
    {
        $SomeLineWithCollection = $Line
        break
    }
}
if (!$SomeLineWithCollection)
{
    Write-Error "Could not determine the diffs' target"
    exit
}

$Arch = $Matches[2]
$OS = @{ "windows" = "win"; "Linux" = "linux" }[$Matches[1]]

Write-Output "Sending $OS-$Arch diffs for $RepositoryName PR number $PrIndex..."

Push-Location "$PSScriptRoot/diffs-repository"

$PrDirName = "$RepositoryName-$PrIndex"
if (!(Test-Path $PrDirName))
{
    mkdir $PrDirName | Write-Verbose
}

$DiffsFile = Join-Path $PrDirName "$OS-$Arch.md"
$Diffs > $DiffsFile

git add $DiffsFile
if ($ShowDiffs)
{
    git diff --staged    
}

$Confirmation = Read-Host "Confirm the diffs with 'y'"
if ($Confirmation -eq 'y') {
    git commit -m "Added $OS-$Arch diffs for $RepositoryName PR number $PrIndex"
    git push
}
else
{
    git reset HEAD --hard
    Write-Output "Did not commit the diffs"
}

Pop-Location
