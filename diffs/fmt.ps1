[CmdletBinding(PositionalBinding=$true)]
Param(
    [string][Parameter(Mandatory=$true)]$Download, # The build id
    [switch]$Linux = $false
)

$BuildId = $Download
$PatchName = "format.$($Linux ? 'Linux' : 'windows').x64.patch"
$SrcUrl = "https://dev.azure.com/dnceng/public/_apis/build/builds/$BuildId/artifacts?artifactName=$PatchName&api-version=6.1-preview.5&%24format=zip"
$TempZipFile = "$(New-TemporaryFile).zip"

Write-Verbose "Will be downloading the patch from $SrcUrl to $TempZipFile"
Invoke-RestMethod -Uri $SrcUrl -Method Get -ContentType application/zip -OutFile $TempZipFile

$DestPath = "${TempZipFile}Dir"

Write-Verbose "Unpacking to $DestPath"
Expand-Archive $TempZipFile $DestPath -Force

$PatchFilePath = "$DestPath/$PatchName/format.patch"
Write-Verbose "Applying $PatchFilePath"

Push-Location "$PSScriptRoot/../runtime"
git apply $PatchFilePath
Pop-Location

Remove-Item $TempZipFile -Recurse -Force