if(Get-Module Operators) { return }

Push-Location $PSScriptRoot

. .\Operators.ps1

Pop-Location

Export-ModuleMember -Function 'Invoke-Ternary' -Alias '?:'