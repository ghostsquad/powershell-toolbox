If(-not (Get-Module Operators))
{
	Import-Module Operators
}

function _GetSize 
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory=$true)]
		[string]$root,
		# Show the size for each descendant recursively (otherwise, only immediate children)
		[bool]$recurse = $false
	)
	
	# Get the full canonical FileSystem path:
	$root = Convert-Path $root

	$size = 0
	$files = 0
	$folders = 0
	
	$items = Get-ChildItem $root -ErrorVariable gciError -ErrorAction SilentlyContinue -Force
	if($gciError -ne $null)
	{
		foreach($e in $gciError)
		{
			Write-Warning $e.ToString()
			if($e.ToString() -notlike "Access to the path * is denied.")
			{
				throw $e
			}						
		}
	}	
	
	foreach($item in $items) {		
	    if($item.PSIsContainer) {
	      # Call myself recursively to calculate subfolder size
	      # Since we're streaming output as we go, 
	      #   we only use the last output of a recursive call
	      #   because that's the summary object
	      if($recurse) {
	        GetSize $item.FullName -ErrorAction Stop | Tee-Object -Variable subItems
	        $subItem = $subItems[-1]
	      } else {
	        $subItem = GetSize $item.FullName -ErrorAction Stop | Select -Last 1
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

function GetSize {
  #.Synopsis
  #  Calculate the size of a folder on disk
  #.Description
  #  Recursively calculate the size of a folder on disk,
  #  outputting it's size, and that of all it's children,
  #  and optionally, all of their children
  [CmdletBinding()]
  param
  (
    [string]$root = ".",
    # Show the size for each descendant recursively (otherwise, only immediate children)
    [switch]$recurse,
	#Human Readable Output
	[switch]$h,
	[switch]$human
  )
  
  if($h -or $humanReadable)
  {
  	_GetSize $root $recurse | select Folders, Files, @{n="Size(MB)";e={[float]("{0:N1}" -f ($_.Size / 1MB))}}, Name | ft -AutoSize
	return
  }
  
  _GetSize $root $recurse
}

function _GetTopProcesses
{
	param
	(
		[int]$top,
		[string]$computerName,
		[bool]$memory,
		[bool]$cpu,
		[switch]$isHuman
	)
	
	function GetAddCounters
	{
		param
		(
			$processDictionary,
			[string]$counterPath,
			[string]$propertyName,
			[scriptblock]$cookedValueModification = $null
		)		
		
		$getcountererror = $null
		$counters = (Get-Counter -Counter $counterPath -ErrorVariable getcountererror -ErrorAction SilentlyContinue).CounterSamples				
			
		CheckForGetCounterExpectedError $getcountererror
		
		foreach($counter in $counters)
		{
			if($counter.status -ne 0)
			{
				continue;
			}
			$lastBackSlashIndex = $counter.Path.LastIndexOf("\")
			$processPath = $counter.Path.SubString(0,$lastBackSlashIndex)
			if($processDictionary.ContainsKey($processPath))
			{
				$cookedvalue = ?: {$cookedValueModification -ne $null} `
					{ Invoke-Command -ScriptBlock $cookedValueModification -ArgumentList $counter.CookedValue } `
					{ $counter.CookedValue }
								
				$processDictionary.Item($processPath).$propertyName = $cookedvalue
			}
		
		}
	}
	
	function CheckForGetCounterExpectedError
	{
		param
		(
			$getcountererror
		)
	
		if($getcountererror -ne $null)
		{
			foreach($e in $getcountererror)
			{
				if($e.ToString() -notlike "The data in one of the performance counter samples is not valid.*")
				{
					throw $e
				}
			}
		}
	}	
	
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
	[int]$numberOfLogicalProcessors = (Get-WmiObject -Class win32_processor -computername $computerName -Property NumberOfLogicalProcessors).NumberOfLogicalProcessors
	
	$processDictionary = @{}
	
	$getcountererror = $null		
	$processIdCounters = (Get-Counter -Counter ($counterPathStart + "\Process(*)\ID Process") -ErrorVariable getcountererror -ErrorAction SilentlyContinue).CounterSamples
	
	foreach($counter in $processIdCounters)
	{
		if($counter.status -ne 0 -or $counter.InstanceName -eq "_total")
		{
			continue
		}
		
		$lastBackSlashIndex = $counter.Path.LastIndexOf("\")
		$processPath = $counter.Path.SubString(0,$lastBackSlashIndex)
		if(-not $processDictionary.ContainsKey($processPath))
		{
			$valueObject = [PSCustomObject]@{
				Id = $counter.CookedValue
				Name = $counter.InstanceName
				WorkingSet = $null
				CPU = $null
			}
			$null = $processDictionary.Add($processPath,$valueObject)
		}
	}		
		
	CheckForGetCounterExpectedError $getcountererror
		
	$counterPath = ($counterPathStart + "\process(*)\% processor time")
	GetAddCounters $processDictionary $counterPath "CPU" ([scriptblock]::create("param(`$cookedvalue) `$cookedvalue / $numberOfLogicalProcessors"))
	
	$counterPath = ($counterPathStart + "\process(*)\working set")
	GetAddCounters $processDictionary $counterPath "WorkingSet"
	
	$processDictionary.Values `
		| Sort-Object $sortColumn -Descending `
		| Select -First $top -Property Id, Name, @{n="CPU";e=$cpuExp}, @{n=$workingSetLabel; e=$workingSetExp}
}

function GetTopProcesses
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
		_GetTopProcesses -computerName $computerName -top $top -memory $memory -cpu $cpu -isHuman | ft -AutoSize
		return
	}
	
	_GetTopProcesses -computerName $computerName -top $top -memory $memory -cpu $cpu 
}

Function GetRecycledItems
{	
	$Shell = New-Object -ComObject Shell.Application
	$RecBin = $Shell.Namespace(0xA)
	$RecBin.Items() | %{$_.Path}
}

Function EmptyRecycleBin
{
	GetRecycledItems | %{Remove-Item $_ -Recurse -Confirm:$false}
}

Export-ModuleMember GetSize
Export-ModuleMember GetTopProcesses
Export-ModuleMember GetRecycledItems
Export-ModuleMember EmptyRecycleBin