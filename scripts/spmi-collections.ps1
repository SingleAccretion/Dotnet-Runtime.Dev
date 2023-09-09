[CmdletBinding(PositionalBinding=$true)]
Param(
    [string]$TargetOS,
    [string]$TargetArch,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args = @()
)

$SpmiCollectionNames = @()

function AddName([string[]] $SetOfNames, $Name)
{
    if ($SetOfNames.Contains($Name))
    {
        Write-Error "Duplicate name for an SPMI collection: '$Name'!"
    }
    else
    {
        $SetOfNames += $Name    
    }
    
    return $SetOfNames
}

switch ($Args)
{
    "aspnet" { $SpmiCollectionNames = AddName $SpmiCollectionNames "aspnet.run" }
    "bench" { $SpmiCollectionNames = AddName $SpmiCollectionNames "benchmarks.run" }
    "pgobench" { $SpmiCollectionNames = AddName $SpmiCollectionNames "benchmarks.run_pgo" }
    "tierbench" { $SpmiCollectionNames = AddName $SpmiCollectionNames "benchmarks.run_tiered" }
    "clrtests" { $SpmiCollectionNames = AddName $SpmiCollectionNames "coreclr_tests.run" }
    "cglibs" { $SpmiCollectionNames = AddName $SpmiCollectionNames "libraries.crossgen2" }
    "libs" { $SpmiCollectionNames = AddName $SpmiCollectionNames "libraries.pmi" }
    "libstests" { $SpmiCollectionNames = AddName $SpmiCollectionNames "libraries_tests.pmi" }
}

Write-Verbose "Spmi-collections: Detected the following collections: $SpmiCollectionNames"

$MchBasePath = Join-Path $PSScriptRoot "../diffs/spmi/mch"
$MchBasePaths = Get-ChildItem -Path $MchBasePath -Filter "*$TargetOS.$TargetArch"

if (@($MchBasePaths).Length -ne 1)
{
	Write-Error "Ambigious or no paths for MCH files: $MchBasePaths"
	return
}

$MchBasePath = @($MchBasePaths)[0]
$SpmiCollectionsPaths = @()
foreach ($CollectionName in $SpmiCollectionNames)
{
    $CollectionFileName = "$CollectionName.$TargetOS.$TargetArch.checked.mch"
    $CollectionPath = Join-Path $MchBasePath $CollectionFileName
    
    if (!(Test-Path $CollectionPath))
    {
        Write-Error "Could not find '$CollectionFileName' in '$MchBasePath'"
    }
    
    $SpmiCollectionsPaths += $CollectionPath
}

return $SpmiCollectionsPaths