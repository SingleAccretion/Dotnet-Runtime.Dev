[CmdletBinding(PositionalBinding=$true)]
Param(
    [string]$Download = $null, # The build id
    [string]$ZipFile = $null,
    [ValidateSet("x64","x86")][string]$Arch = "x64"
)

Write-Verbose "Arch: $Arch"

if ($Download)
{
    $BuildId = $Download
    $ArtifactName = "SuperPMI_Asmdiffs_$($Arch)_checked"
    $SrcUrl = "https://dev.azure.com/dnceng-public/public/_apis/build/builds/$BuildId/artifacts?artifactName=$ArtifactName&api-version=6.1-preview.5&%24format=zip"
    $ZipFile = "$HOME/Downloads/$ArtifactName.zip"

    Write-Verbose "Will be downloading the diffs from $SrcUrl to $ZipFile"
    Invoke-RestMethod -Uri $SrcUrl -Method Get -ContentType application/zip -OutFile $ZipFile
}

if (!$ZipFile)
{
    $DownloadsFolder = "$HOME/Downloads"
    $ZipFiles = Get-ChildItem $DownloadsFolder "SuperPMI_Asmdiffs_${Arch}_checked*.zip"

    if (@($ZipFiles).Length -eq 0)
    {
        Write-Error "No downloaded SPMI filed found for $Arch!"
        return
    }

    Write-Verbose "Zip files are: $ZipFiles"
    $ZipFiles = $ZipFiles | Sort-Object { [int][Regex]::Replace($_.Name, "SuperPMI_Asmdiffs_${Arch}_checked\(?(\d*)\)?\.zip", '$1') } -Descending

    $ZipFile = "$($ZipFiles[0])"
    Write-Verbose "The downloaded file to unpack is: $ZipFile"
}

$DiffsBaseDir = "$PSScriptRoot/spmi"
$DestPathBase = "$DiffsBaseDir/$((Get-ChildItem $ZipFile).Name.Replace('.zip', '').Replace('(', '_')).Replace(')', '')"

$SuffixIndex = 1
$DestPath = $DestPathBase
while (Test-Path $DestPath)
{
    $DestPath = "${DestPathBase}_${SuffixIndex}"
    $SuffixIndex++
}

Write-Verbose "Unpacking to $DestPath"

Expand-Archive $ZipFile $DestPath -Force > $null

# The structure is like this: $DestPath/ZipFileName/Some-Guid/{ targets }/$TargetZip/$DiffsDir
# We flatten it to this: $DestPath/$DiffsDir

$UnzippedPath = @(Get-ChildItem $DestPath "SuperPMI_Asmdiffs_${Arch}_checked" -Directory)[0]
Write-Verbose "Skipping path: $UnzippedPath"
$TargetsPath = @(Get-ChildItem $UnzippedPath -Directory)[0]
Write-Verbose "Skipping path: $TargetsPath"

foreach ($TargetPath in Get-ChildItem $TargetsPath)
{
    Write-Verbose "Processing $TargetPath"
    
    $TargetZip = @(Get-ChildItem $TargetPath -File)[0]
    Write-Verbose "Unpacking $TargetZip to $DestPath"

    # Expand-Archive, for unclear reasons, cannot deal with empty zips.
    # Alternatively, the zips may actually be corrupt (but Explorer opens them fine so what do I know).
    try
    {
        Expand-Archive $TargetZip $DestPath -Force > $null
    }
    catch [System.IO.FileFormatException]
    {
        Write-Verbose "Failed to unzip ${TargetZip}: empty file?"
    }
}

Write-Verbose "Removing $UnzippedPath"
Remove-Item $UnzippedPath -Recurse

foreach ($LeftOverZip in Get-ChildItem $DestPath "*.zip")
{
    Write-Verbose "Removing $LeftOverZip"
    Remove-Item $LeftOverZip
}

Write-Output "$DestPath"
