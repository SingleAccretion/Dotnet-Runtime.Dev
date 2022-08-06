$McsPath = [System.IO.Path]::GetFullPath("..\runtime\artifacts\bin\coreclr\Windows.x64.Checked\mcs.exe", $PSScriptRoot)

Invoke-Expression "$McsPath $Args"