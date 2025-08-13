<#
.SYNOPSIS
Start_Teams_Prep - This script attempts to allow MS Teams to start post in place upgrade of Windows 11.

.DESCRIPTION
- See if MS Teams is installed.
- See who is the primary user of the machine.  We capture the Primary User of a PC in HKEY_LOCAL_MACHINE\SOFTWARE\DPW\Build | [REG_SZ] PrimaryUser
- See if Documents is re-directed.  If yes, then skip moving documents folder to temp holding local folder.
- If Documents is not re-directed move Documents and Desktop folders to temp holding local folder.
- Delete the primary user's profile.
- The second phase of this script will attempt to move the primary user's .OST if feasible along with the 2 folders mentioned above.
-07/13/2025 Added deleting locally cached profiles except for system profiles.  Added support for multiple primary users.

.EXAMPLE
powershell.exe -File DPW_Start_Teams_Post_IPU.ps1 -DeployMode Silent -executionpolicy bypass
    Sample calls to write to log
      Write-Log -Message "Script started." -LogFile $LogFileLocation -AddTimestamp
      Write-Log -Message "Doing something..." -LogFile "C:\Logs\MyScript.log"
      Write-Log -Message "Default path log entry." -AddTimestamp

.INPUTS
To restore the backed up/moved folders and .ost running in SYSTEM context use the following command line:
Start_Teams_Prep.ps1 -system.

.OUTPUTS
None. This script does not generate any output.

.NOTES
Added support for multiple primary users starting on 7/11/2025.

.LINK
https://github.com/al-lopez-techandacct/DPW_Start_Teams_Post_IPU.git

#>

param (
    [switch]$system
)

Function IsTeamsInstalled {
  try {
    $IsTeamsInstalled = Get-AppxPackage -AllUsers -Name "*MSTeams*" | Select Name, PackageFullName
  
  	If ($IsTeamsInstalled) {
  		return $IsTeamsInstalled.PackageFullName
  	}
  }
  catch [System.Exception] {
    Write-Log -Message "Error Message: $($_.Exception.Message)" -LogFile $LogFileLocation -AddTimestamp
  }    
}

Function FindPrimaryUser {
  # Define the registry path and value name
  $regPath = "HKLM:\SOFTWARE\DPW\Build"
  $valueName = "PrimaryUser"

  # Read the value
  $PrimaryUserNames = Get-ItemProperty -Path $regPath -Name $valueName

  # Output the value
  $PrimaryUserNames = $PrimaryUserNames.$valueName
  $PrimaryUserNames = $PrimaryUserNames -split ' '
  return $PrimaryUserNames
}

function Write-Log {
  param (
      [string]$Message,
      [string]$LogFile = "$PSScriptRoot\script.log",
      [switch]$AddTimestamp
  )

  if ($AddTimestamp) {
      $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
      $entry = "[$timestamp] $Message"
  } else {
      $entry = $Message
  }

  # Create log file directory if it doesn't exist
  $logDir = Split-Path $LogFile
  if (-not (Test-Path $logDir)) {
      New-Item -ItemType Directory -Path $logDir -Force | Out-Null
  }

  # Write to the log
  Add-Content -Path $LogFile -Value $entry
}

Function RestoreProfileFolders {
  if ($system) {
    $PrimaryUsers = FindPrimaryUser
    foreach ($PrimaryUser in $PrimaryUsers) {
      $PrimaryUser = $PrimaryUser -split '\\'
      $PrimaryUser = $PrimaryUser[1]
      ProcessProfileFolders $PrimaryUser
    }
  }
  else{
    $PrimaryUser = $env:USERNAME
    ProcessProfileFolders $PrimaryUser
  }
}

Function ProcessProfileFolders{
  param (
    [string]$PrimaryUserParam
  )

  Write-Log -Message "RestoreProfileFolders is working on Primary user $PrimaryUserParam." -LogFile $LogFileLocation -AddTimestamp
  $OstCopy = "$BackupFolderLocation\$PrimaryUserParam\*.ost"

  # Copy folders from C:\Windows\DPW\logs\UserProfileBackup to the user profile not overwriting items.
  $dst = "C:\Users\$PrimaryUserParam"

  if ($OstCopy -like "*.ost*"){
    Write-Log -Message "Restoring $OstCopy to $dst\AppData\Local\Microsoft\Outlook." -LogFile $LogFileLocation -AddTimestamp
    Copy-Item -Path $OstCopy -Destination "$dst\AppData\Local\Microsoft\Outlook" -Force
  }

  Write-Log -Message "Calling xcopy $BackupFolderLocation\$PrimaryUserParam $dst /E /D." -LogFile $LogFileLocation -AddTimestamp
  xcopy "$BackupFolderLocation\$PrimaryUserParam" $dst /E /D /y

  Write-Log -Message "Restoring folders to primary user's profile completed." -LogFile $LogFileLocation -AddTimestamp
} 
  
$global:LOCALAPPDAT= $env:LOCALAPPDATA
$global:regPath = ""
$global:valueName = ""
$global:LogFileLocation = "$LOCALAPPDAT\Temp\Start_Teams_Prep.ps1.log"
$global:BackupFolderLocation = "C:\Windows\DPW\logs\UserProfileBackup"

try {
  $TSEnv = New-Object -ComObject "Microsoft.SMS.TSEnvironment" -ErrorAction SilentlyContinue
}
catch [System.Exception] {
  Write-Log -Message "Unable to construct Microsoft.SMS.TSEnvironment object, that will only work within a runnind TS" -LogFile $LogFileLocation -AddTimestamp
}

  Write-Log -Message "Script started." -LogFile $LogFileLocation -AddTimestamp
  RestoreProfileFolders
