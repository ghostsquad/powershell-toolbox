Push-Location $PSScriptRoot

. .\Invoke-Parallel.ps1

Pop-Location

Export-ModuleMember -Function 'Invoke-Parallel'