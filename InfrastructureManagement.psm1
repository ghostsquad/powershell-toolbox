If(-not (Get-Module Operators))
{
	Import-Module Operators
}

function _Get-Size 
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		[string]$root,
		# Show the size for each descendant recursively (otherwise, only immediate children)
		[switch]$recurse = $false
	)
	
	# Get the full canonical FileSystem path:
	$root = Convert-Path $root

	$size = 0
	$files = 0
	$folders = 0

	$items = Get-ChildItem $root
	foreach($item in $items) {
		try
		{
		    if($item.PSIsContainer) {
		      # Call myself recursively to calculate subfolder size
		      # Since we're streaming output as we go, 
		      #   we only use the last output of a recursive call
		      #   because that's the summary object
		      if($recurse) {
		        Get-Size $item.FullName -ErrorAction Stop | Tee-Object -Variable subItems
		        $subItem = $subItems[-1]
		      } else {
		        $subItem = Get-Size $item.FullName -ErrorAction Stop | Select -Last 1
		      }

		      # The (recursive) size of all subfolders gets added
		      $size += $subItem.Size
		      $folders += $subItem.Folders + 1
		      $files += $subItem.Files
		      Write-Output $subItem
		    } else {
		      $files += 1
		      $size += $item.Length
		    }
		}
		catch [System.IO.IOException]
		{
			$exception = $_
			Write-Warning ((($exception.ToString() -replace "\r","") -replace "\n","; ") + " " + $item.FullName)
			#Write-Warning $exception.Exception.GetType()
		}

		catch [System.UnauthorizedAccessException]
		{
			$exception = $_
			Write-Warning $exception.ToString()
			#Write-Warning $exception.Exception.GetType()
		}
	}

	# in PS3, use the CustomObject trick to control the output order
	if($PSVersionTable.PSVersion -ge "3.0") {
		[PSCustomObject]@{ 		
		  Folders = $folders
		  Files = $Files
		  Size = $size
		  Name = $root
		}
	} else {
		New-Object PSObject -Property @{ 
		  Folders = $folders
		  Files = $Files
		  Size = $size
		  Name = $root
		}
	}
}

function Get-Size {
  #.Synopsis
  #  Calculate the size of a folder on disk
  #.Description
  #  Recursively calculate the size of a folder on disk,
  #  outputting it's size, and that of all it's children,
  #  and optionally, all of their children
  [CmdletBinding()]
  param
  (
  	[Parameter(Mandatory=$true)]
    [string]$root,
    # Show the size for each descendant recursively (otherwise, only immediate children)
    [switch]$recurse = $false,
	#Human Readable Output
	[switch]$h,
	[switch]$human
  )
  
  if($h -or $humanReadable)
  {
  	_Get-Size $root $recurse | select Folders, Files, @{n="Size";e={[float]("{0:N1}" -f ($_.Size / 1MB))}}, Name
	return
  }
  
  _Get-Size $root $recurse
}

function _Get-TopProcesses
{
	param
	(
		[int]$top,
		[string]$computerName,
		[bool]$memory,
		[bool]$cpu,
		[switch]$isHuman
	)
	
	if($memory -and $cpu)
	{
		throw "-memory or -cpu can be set, but not both."
	}
	
	$cpuExp = { ?: { $_.CPU -eq $null } { $null } { [float]("{0:N2}" -f $_.CPU) } }
	
	
	if($isHuman)
	{
		$workingSetLabel = "WorkingSet(MB)"
		$workingSetExp = { [float]("{0:N1}" -f ($_.WorkingSet / 1MB)) }
	}
	else
	{
		$workingSetLabel = "WorkingSet"
		$workingSetExp = { [float]("{0:N1}" -f $_.WorkingSet) }
	}
	
	$sortColumn = ?: { $memory } { "WorkingSet" } { "Cpu" }
	
	$counterPathStart = ?: { $computerName -eq "." -or $computerName -eq $env:COMPUTERNAME } { [string]::Empty } { "\\$computerName" }
	$counterPath = $counterPathStart + "\process({0})\% processor time"
	
	Get-Process -ComputerName $computerName `
		| Select -Property Id, Name, Handles, WorkingSet `
		| ForEach-Object {
		  		$pname = $_.name
				$counter = Get-Counter -Counter ($counterPath -f $pname)
				$procTime = [float]$counter.CounterSamples[0].CookedValue
				
				[PSCustomObject]@{ 		
				  Id = $_.Id
				  Name = $_.Name
				  Handles = $_.Handles
				  WorkingSet = $_.WorkingSet
				  Cpu = $procTime
				}
		  } `
		| Sort-Object $sortColumn -Descending `
		| Select -First $top -Property Id, Name, Handles, @{n="CPU";e=$cpuExp}, @{n=$workingSetLabel; e=$workingSetExp} `
}

function Get-TopProcesses
{
	param
	(
		[string]$computerName = ".",
		[int]$top = 10,		
		[switch]$memory,
		[switch]$cpu,
		[switch]$h,
		[switch]$human
	)
	
	if($memory -and $cpu)
	{
		throw "-memory or -cpu can be set, but not both."
	}
	
	$isHuman = ($h -or $human)	
	
	if($isHuman)
	{
		_Get-TopProcesses -computerName $computerName -top $top -memory $memory -cpu $cpu -isHuman | ft -AutoSize
		return
	}
	
	_Get-TopProcesses -computerName $computerName -top $top -memory $memory -cpu $cpu 
}

Export-ModuleMember Get-Size
Export-ModuleMember Get-TopProcesses