<#
.SYNOPSIS
DPW_Start_Teams_Post_IPU - This script attempts to allow MS Teams to start post in place upgrade of Windows 11.

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
To restore the backed up/moved folders and .ost use the following command line:
DPW_Start_Teams_Post_IPU.ps1 Restore (case sensitive).

.OUTPUTS
None. This script does not generate any output.

.NOTES
Added support for multiple primary users starting on 7/11/2025.

.LINK
https://github.com/al-lopez-techandacct/DPW_Start_Teams_Post_IPU.git

#>

param (
    [switch]$system
)>

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

Function IsDocumentsRedirected {
  param (
    [string]$HiveUser,
    [string]$RestoreVal
  )
  # Get current user's Documents folder path from registry.
    $ntuserPath = "C:\Users\$HiveUser\NTUSER.DAT"
    $hiveName = "TempHive"

    try {
      reg load "HKU\$hiveName" "$ntuserPath"
    }
    catch [System.Exception] {
      Write-Log -Message "Error Message: $($_.Exception.Message)" -LogFile $LogFileLocation -AddTimestamp
    }   

    # If this is restore then we can go into HKCU directly.
    if ($RestoreVal -eq "restore"){
      $regPath = "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
      $valueName = "Personal"
      Write-Log -Message "We're doing a restore and we're reading $regPath to determine Documents folder is being re-directed." -LogFile $LogFileLocation -AddTimestamp
    }
    else{
      $regPath = "Registry::HKEY_USERS\TempHive\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
      $valueName = "Personal"
    }

    #Adjust\translate for Primary user because the value uses an environment variable or "%USERPROFILE%\Documents".
    # Read the path
    $documentsPath = (Get-ItemProperty -Path $regPath -Name $valueName).$valueName
    # Expand any environment variables (like %USERPROFILE%)
    $expandedPath = [Environment]::ExpandEnvironmentVariables($documentsPath)
    Write-Log -Message "Personal User shell folder read from registry = $expandedPath." -LogFile $LogFileLocation -AddTimestamp

    if ($expandedPath -like "*Users*"){
      $expandedPath = "C:\Users\$HiveUser\Documents"
    }

    # Determine if it's redirected
    $userProfileDocs = "C:\Users\$HiveUser\Documents"
    Write-Log -Message "Personal User shell folder = $expandedPath compared to $userProfileDocs." -LogFile $LogFileLocation -AddTimestamp
    
    if ($expandedPath -ne $userProfileDocs) {
      Write-Log -Message "Documents folder is redirected." -LogFile $LogFileLocation -AddTimestamp
      reg unload "HKU\$hiveName"
      $global:ReDirected = "Re-Directed"
      return "Re-Directed"
    } 
    else {
      Write-Log -Message "Documents folder is NOT redirected." -LogFile $LogFileLocation -AddTimestamp
      reg unload "HKU\$hiveName"
      $global:ReDirected = "Not Re-Directed"
      return "Not Re-Directed"
    }
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

Function CleanUpProfileFolders {
  ### The Documents, Downloads, and Desktop folders must not exist for the file move below to work.
  $PrimaryUsers = FindPrimaryUser

  foreach ($PrimaryUser in $PrimaryUsers) {
    $PrimaryUser = $PrimaryUser -split '\\'
    $PrimaryUser = $PrimaryUser[1]

    $MoveFolderRestores = "$BackupFolderLocation\$PrimaryUser\Documents", "$BackupFolderLocation\$PrimaryUser\Downloads", "$BackupFolderLocation\$PrimaryUser\Desktop", "$BackupFolderLocation\$PrimaryUser\*.ost"

    $dst = "C:\Users\$PrimaryUser" 
      
    $CheckForProfileFolder = "$dst\Downloads"
    IsDocumentsRedirected $PrimaryUser

    if ($CheckForProfileFolder -and $ReDirected -eq "Re-Directed") {        
      try {
        Write-Log -Message "Removing $dst\Downloads and $dst\Desktop." -LogFile $LogFileLocation -AddTimestamp
        Remove-Item "$dst\Downloads" -Recurse -Force
        Remove-Item "$dst\Desktop" -Recurse -Force
      }
      catch [System.Exception] {
        Write-Log -Message "Error Message: $($_.Exception.Message)" -LogFile $LogFileLocation -AddTimestamp
      }
    }else {  # Documents not re-directed.
      try {
        Write-Log -Message "Removing $dst\Documents, $dst\Downloads, and $dst\Desktop." -LogFile $LogFileLocation -AddTimestamp
        Remove-Item "$dst\Documents" -Recurse -Force
        Remove-Item "$dst\Downloads" -Recurse -Force
        Remove-Item "$dst\Desktop" -Recurse -Force
      }
      catch [System.Exception] {
        Write-Log -Message "Error Message: $($_.Exception.Message)" -LogFile $LogFileLocation -AddTimestamp
      }
    }
  }
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
  $MoveFolderRestores = "$BackupFolderLocation\$PrimaryUserParam\Documents", "$BackupFolderLocation\$PrimaryUserParam\Downloads", "$BackupFolderLocation\$PrimaryUserParam\Desktop", "$BackupFolderLocation\$PrimaryUserParam\*.ost"

  $dst = "C:\Users\$PrimaryUserParam"    
  
  #IsDocumentsRedirected $PrimaryUserParam "restore"
  #Write-Log -Message "Function IsDocumentsRedirected returned $ReDirected for primary user $PrimaryUser." -LogFile $LogFileLocation -AddTimestamp

  #Write-Log -Message "*** ReDirected = $ReDirected <-end for $dst." -LogFile $LogFileLocation -AddTimestamp
  #if ($ReDirected -eq "Not Re-Directed") {
    Foreach ($MoveFolderRestore in $MoveFolderRestores) {
      Write-Log -Message "Checking if $MoveFolderRestore -like *.ost*." -LogFile $LogFileLocation -AddTimestamp

      if($MoveFolderRestore -like "*.ost*"){
        Write-Log -Message "Found that $MoveFolderRestore is -like *Outlook*. Will attempt to move the .ost that was previously backed up." -LogFile $LogFileLocation -AddTimestamp          
        # Find and move all .ost files
        try {
          Write-Log -Message "Restoring $BackupFolderLocation\$PrimaryUser\*.ost to $dst\AppData\Local\Microsoft\Outlook." -LogFile $LogFileLocation -AddTimestamp
          Copy-Item -Path "$BackupFolderLocation\$PrimaryUser\*.ost" -Destination "$dst\AppData\Local\Microsoft\Outlook" -Force
        }
        catch [System.Exception] {
          Write-Log -Message "Error Message: $($_.Exception.Message)" -LogFile $LogFileLocation -AddTimestamp
        }        
      }
      if(!($MoveFolderRestore -like "*.ost*")){
        try {
          Write-Log -Message "Found that $MoveFolderRestore is not like .ost.  Going to copy $MoveFolderRestore to $dst." -LogFile $LogFileLocation -AddTimestamp
          Copy-Item -Path $MoveFolderRestore -Destination $dst -Force
        }
        catch [System.Exception] {
          Write-Log -Message "Error Message: $($_.Exception.Message)" -LogFile $LogFileLocation -AddTimestamp
        }        
      }
    }
  #} 
  
    #Write-Log -Message "*** ReDirected = $ReDirected <-end for $dst." -LogFile $LogFileLocation -AddTimestamp

    <#if($ReDirected -eq "Re-Directed") {  ## Documents is re-directed so we don't try to restore the Documents folder.
    Write-Log -Message "Documents is re-directed so we don't try to restore the Documents folder for $dst." -LogFile $LogFileLocation -AddTimestamp
      Foreach ($MoveFolderRestore in $MoveFolderRestores) {          
        if($MoveFolderRestore -like "*ost*"){            
          # Find and move all .ost files
          Write-Log -Message "Found that $MoveFolderRestore is -like *ost*. Will attempt to move the .ost that was previously backed up." -LogFile $LogFileLocation -AddTimestamp 
          try {
            Copy-Item -Path "$BackupFolderLocation\$PrimaryUser\*.ost" -Destination "$dst\AppData\Local\Microsoft\Outlook" -Force
          }
          catch [System.Exception] {
            Write-Log -Message "Error Message: $($_.Exception.Message)" -LogFile $LogFileLocation -AddTimestamp
          }        
        }
        Write-Log -Message "Checking to see if $MoveFolderRestore contains the word Documents or contains the word Outlook for $dst.  if it doesn't then the next step is to move $MoveFolderRestore to $dst." -LogFile $LogFileLocation -AddTimestamp
        if(-not ($MoveFolderRestore -like "*Documents*" -or $MoveFolderRestore -like "*Outlook*")){
          Write-Log -Message "Detected $MoveFolderRestore does not contains the words Documents or Outlook.  Will attempt to move the Desktop and Downloads folders that were previously backed up, but not move a Documents folder." -LogFile $LogFileLocation -AddTimestamp

          try {
            Copy-Item -Path $MoveFolderRestore -Destination $dst -Force
          }
          catch [System.Exception] {
            Write-Log -Message "Error Message: $($_.Exception.Message)" -LogFile $LogFileLocation -AddTimestamp
          }        
        } 
      }       
    }#>
    Write-Log -Message "Restoring folders to primary user's profile completed." -LogFile $LogFileLocation -AddTimestamp
}

$global:LOCALAPPDAT= $env:LOCALAPPDATA
$global:regPath = ""
$global:valueName = ""
$global:LogFileLocation = "$LOCALAPPDAT\Temp\Start_Teams_Prep.ps1.log"
$global:BackupFolderLocation = "C:\Windows\DPW\logs\UserProfileBackup"

Start-Transcript -Path "$LOCALAPPDAT\Temp\StartTeamsPrep-transcript.log"

try {
  $TSEnv = New-Object -ComObject "Microsoft.SMS.TSEnvironment" -ErrorAction SilentlyContinue
}
catch [System.Exception] {
  #Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object, that will only work within a runnind TS"
  Write-Log -Message "Unable to construct Microsoft.SMS.TSEnvironment object, that will only work within a runnind TS" -LogFile $LogFileLocation -AddTimestamp
}

  Write-Log -Message "Script started." -LogFile $LogFileLocation -AddTimestamp
  $CallIsTeamsInstalled = IsTeamsInstalled
  if ($CallIsTeamsInstalled) {
    Write-Log -Message "Teams is installed." -LogFile $LogFileLocation -AddTimestamp
    RestoreProfileFolders

  }else {
    Write-Log -Message "Teams is not installed." -LogFile $LogFileLocation -AddTimestamp
  }

  Stop-Transcript