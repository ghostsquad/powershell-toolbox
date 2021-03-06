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
	[switch]$humanReadable
  )
  
  if($h -or $humanReadable)
  {
  	_Get-Size $root $recurse | ft Folders, Files, @{n="Size";e={"{0:N1}" -f ($_.Size / 1MB)};a="right"}, Name -AutoSize
	return
  }
  
  _Get-Size $root $recurse
}

Export-ModuleMember Get-Size