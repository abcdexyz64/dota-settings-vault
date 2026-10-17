param(
 [ValidateSet('Gui','List','Save','Preview','Apply','Upload','Download','CreateRepo','Export','Import')][string]$Action='Gui',
 [string]$Name,[string]$SteamPath,[string]$AccountId,[string]$Snapshot,[string]$Repository,[string]$GameCfg,
 [switch]$IncludeVideo,[switch]$CloudDisabled,[string]$Destination,[string]$InputPath,
 [string]$DataDirectory=(Join-Path $PSScriptRoot 'data'),[switch]$SmokeTest
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Vault.Core.psm1') -Force
$DataDirectory=[IO.Path]::GetFullPath($DataDirectory)
$profilesDir=Join-Path $DataDirectory 'profiles'; $backupsDir=Join-Path $DataDirectory 'rollback'
foreach($dir in @($profilesDir,$backupsDir)){[IO.Directory]::CreateDirectory($dir)|Out-Null}
if(!$SteamPath){$SteamPath=Get-VaultSteamPath}
if(!$GameCfg -and $SteamPath){$GameCfg=Get-VaultGameCfg $SteamPath}
if(!$Destination){$Destination=Join-Path $DataDirectory 'exports'}
if($Action -ne 'Gui'){
 if($Action -in @('Save','Preview','Apply')){
  if($AccountId -notmatch '^\d+$'){throw '请用 -AccountId 指定 Steam userdata 的数字账号目录。'}
  $accountPath=Join-Path $SteamPath "userdata/$AccountId/570"
 }
 switch($Action){
  List {Get-VaultAccounts $SteamPath;Get-ChildItem $profilesDir -Filter '*.json'|ForEach-Object{Read-VaultSnapshot $_.FullName|Select-Object Name,Id,CreatedUtc}}
  Save {Save-VaultProfile -Name $Name -AccountPath $accountPath -Directory $profilesDir -GameCfg $GameCfg -IncludeVideo:$IncludeVideo}
  Preview {Get-VaultChanges (Read-VaultSnapshot $Snapshot) $accountPath $GameCfg}
  Apply {Restore-VaultProfile -SnapshotPath $Snapshot -AccountPath $accountPath -GameCfg $GameCfg -BackupDirectory $backupsDir -CloudDisabled:$CloudDisabled}
  Upload {Send-VaultProfile $Snapshot $Repository}
  Download {Receive-VaultProfiles $Repository $profilesDir}
  CreateRepo {New-VaultRepository $Repository}
  Export {Export-VaultPackage $Snapshot $Destination}
  Import {Import-VaultInput -Path $InputPath -Directory $profilesDir}
 }
 return
}
. (Join-Path $PSScriptRoot 'Fountain.UI.ps1')
