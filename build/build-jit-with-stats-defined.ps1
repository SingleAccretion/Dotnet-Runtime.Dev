[CmdletBinding(PositionalBinding=$false)]
Param(
  [switch]$Base,
  [switch]$Save,
  [string]$JitSubset,
  [string]$Arch,
  [string]$Config,
  [ValidateSet("mem","hoist","args","blocks","loops","block-sizes","node-sizes","emit","bashing","opers")][string[]]$Stats = @()
)

if (@($Defines).Length -eq 0)
{
    Write-Verbose "No stats specified!"
    return
}

$RuntimePath = Join-Path $PSScriptRoot "../runtime"
if ($Base)
{
    $RuntimePath += "-base"
}

$Stats = $Stats | Sort-Object | Get-Unique

$Defines = @()
switch ($Stats)
{
    "mem" { $Defines += "MEASURE_MEM_ALLOC" }
    "hoist" { $Defines += "LOOP_HOIST_STATS" }
    "args" { $Defines += "CALL_ARG_STATS" }
    "blocks" { $Defines += "COUNT_BASIC_BLOCKS" }
    "loops" { $Defines += "COUNT_LOOPS" }
    "block-sizes" { $Defines += "MEASURE_BLOCK_SIZE" }
    "node-sizes" { $Defines += "MEASURE_NODE_SIZE" }
    "emit" { $Defines += "EMITTER_STATS" }
    "bashing" { $Defines += "NODEBASH_STATS" }
    "opers" { $Defines += "COUNT_AST_OPERS" }
}

$JitHeaderPath = "$RuntimePath\src\coreclr\jit\jit.h"
$JitHeader = Get-Content $JitHeaderPath -Raw
$PatchedJitHeader = $JitHeader

foreach ($Define in $Defines)
{
    $PatchedJitHeader = $PatchedJitHeader.Replace("#define $Define 0", "#define $Define 1")
}

Write-Verbose "Patching jit.h to define: $Defines"
$PatchedJitHeader > $JitHeaderPath

$SavedJitsDir = $null
$BuiltJitsPath = "$RuntimePath/artifacts/bin/coreclr/windows.$Arch.$Config"
if ($Save)
{
    $SavedJitsDir = [System.IO.Path]::GetTempPath()
    $SavedJitsDir = Join-Path $SavedJitsDir "SavedJits"
    if (!(Test-Path $SavedJitsDir))
    {
        mkdir $SavedJitsDir | Write-Verbose
    }
    
    Write-Verbose "Saving the built Jits to $SavedJitsDir"
    robocopy $BuiltJitsPath $SavedJitsDir clrjit* | Write-Verbose
}

$BuildExpression = "$RuntimePath\build $JitSubset -c $Config -a $Arch"
Write-Verbose "Building the patched Jit(s): '$BuildExpression'"
Invoke-Expression $BuildExpression

Write-Verbose "Patching jit.h back..."
# Remove the trailing \r\n...
$JitHeader = $JitHeader.Substring(0, $JitHeader.Length - [System.Environment]::NewLine.Length)
$JitHeader > $JitHeaderPath

if ($Save)
{
    $CustomJitsDirName = "$($Base ? 'Base' : '')CustomJits"
    $CustomJitsDir = "$PSScriptRoot/$CustomJitsDirName/$Arch/$Config/$([string]::Join("-", $Stats))"
    
    if (!(Test-Path $CustomJitsDir))
    {
        mkdir $CustomJitsDir
    }
    
    Write-Verbose "Copying custom Jits to $CustomJitsDir"
    robocopy $BuiltJitsPath $CustomJitsDir clrjit* | Write-Verbose
    Write-Verbose "Restoring the original Jits"
    robocopy $SavedJitsDir $BuiltJitsPath clrjit* | Write-Verbose
}

