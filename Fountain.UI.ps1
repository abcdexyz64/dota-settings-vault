Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
$xaml=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Fountain.xaml'))
$reader=New-Object Xml.XmlNodeReader ([xml]$xaml)
$window=[Windows.Markup.XamlReader]::Load($reader)
$ui=@{}
foreach($m in [regex]::Matches($xaml,'x:Name="([^"]+)"')){$ui[$m.Groups[1].Value]=$window.FindName($m.Groups[1].Value)}
$icon=Join-Path $PSScriptRoot 'assets/fountain.png'
if(Test-Path $icon){$ui.BrandImage.Source=New-Object Windows.Media.Imaging.BitmapImage ([uri]$icon);$window.Icon=$ui.BrandImage.Source}
$script:steamRoot=$SteamPath; $script:gameRoot=$GameCfg; $script:level=1
$script:library=@();$script:catalog=@();$script:parameters=@();$script:lastExport=''
$settingsPath=Join-Path $DataDirectory 'preferences.json'
$ui.ExportPath.Text=$Destination
if(Test-Path $settingsPath){
 try{$prefs=[IO.File]::ReadAllText($settingsPath)|ConvertFrom-Json
  if($prefs.PSObject.Properties['Repository']){$ui.Repository.Text=$prefs.Repository}
  if(!$SmokeTest -and $prefs.PSObject.Properties['ExportPath'] -and $prefs.ExportPath){$ui.ExportPath.Text=$prefs.ExportPath}
 }catch{}
}
function Set-Status([string]$Text){$ui.Status.Text=$Text;$window.Dispatcher.Invoke([action]{},[Windows.Threading.DispatcherPriority]::Render)}
function Invoke-Ui([scriptblock]$Work){
 $window.Cursor=[Windows.Input.Cursors]::Wait
 try{& $Work}catch{if($SmokeTest){throw};Set-Status '操作未完成。';[Windows.MessageBox]::Show($window,$_.Exception.Message,'泉印','OK','Warning')|Out-Null}
 finally{$window.Cursor=$null}
}
function Save-Preferences {
 [IO.File]::WriteAllText($settingsPath,(@{Repository=$ui.Repository.Text.Trim();ExportPath=$ui.ExportPath.Text.Trim()}|ConvertTo-Json),(New-Object Text.UTF8Encoding $false))
}
function Get-AccountPath {
 if(!$ui.Accounts.SelectedItem){throw '请先选择一个 Steam 账号目录。'}
 return Join-Path $script:steamRoot "userdata/$($ui.Accounts.SelectedItem)/570"
}
function Get-SelectedPath {
 if(!$ui.Profiles.SelectedItem){throw '请先在本地方案库里选择一个方案。'}
 return $ui.Profiles.SelectedItem.Path
}
function Refresh-Accounts {
 $previous=$ui.Accounts.SelectedItem
 $ui.Accounts.ItemsSource=@(Get-VaultAccounts $script:steamRoot|ForEach-Object{$_.Id})
 if($previous -in $ui.Accounts.Items){$ui.Accounts.SelectedItem=$previous}
 elseif($ui.Accounts.Items.Count -eq 1){$ui.Accounts.SelectedIndex=0}
}
function Refresh-Profiles([string]$SelectPath=''){
 if(!$SelectPath -and $ui.Profiles.SelectedItem){$SelectPath=$ui.Profiles.SelectedItem.Path}
 $script:library=@(foreach($dir in @($profilesDir,$backupsDir)){
  foreach($file in Get-ChildItem -LiteralPath $dir -Filter '*.json'|Sort-Object LastWriteTime -Descending){
   try{$s=Read-VaultSnapshot $file.FullName
    $time=[DateTime]::Parse($s.CreatedUtc).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
    [pscustomobject]@{Name=$s.Name;Time=$time;Count=@($s.Files|Where-Object Present).Count;Kind=if($dir -eq $profilesDir){'个人方案'}else{'自动回滚备份'};Path=$file.FullName;Label=$s.Name+'  /  '+$time}
   }catch{Set-Status "跳过无效备份：$($file.Name)"}
  }
 })
 $ui.Profiles.ItemsSource=$script:library;$ui.CloudProfiles.ItemsSource=$script:library
 $selected=$script:library|Where-Object Path -eq $SelectPath|Select-Object -First 1
 if($selected){$ui.Profiles.SelectedItem=$selected;$ui.CloudProfiles.SelectedItem=$selected}
 elseif($script:library.Count){$ui.Profiles.SelectedIndex=0;$ui.CloudProfiles.SelectedIndex=0}
}
function Open-Folder([string]$Path){
 if(!(Test-Path -LiteralPath $Path -PathType Container)){throw "文件夹尚不存在：$Path"}
 if(!$SmokeTest){Start-Process explorer.exe -ArgumentList ('"'+$Path+'"')}
}
function Pick-Folder([string]$Initial=''){
 $picker=New-Object Windows.Forms.FolderBrowserDialog
 $picker.Description='选择文件夹';if($Initial){$picker.SelectedPath=$Initial}
 try{if($picker.ShowDialog() -eq 'OK'){return $picker.SelectedPath}}finally{$picker.Dispose()}
 return ''
}
function Show-Text([string]$Title,[string]$Text){
 $dialog=New-Object Windows.Window
 $dialog.Title=$Title;$dialog.Width=860;$dialog.Height=680;$dialog.Owner=$window;$dialog.WindowStartupLocation='CenterOwner'
 $dialog.Background=$window.Background;$dialog.Foreground=$window.Foreground
 $box=New-Object Windows.Controls.TextBox
 $box.Text=$Text;$box.IsReadOnly=$true;$box.TextWrapping='Wrap';$box.VerticalScrollBarVisibility='Auto'
 $box.FontFamily='Microsoft YaHei UI';$box.FontSize=14;$box.Padding=24;$box.Background=$window.Background;$box.Foreground=$window.Foreground
 $dialog.Content=$box
 if(!$SmokeTest){[void]$dialog.ShowDialog()}
}
function Show-ImportScope([bool]$Folder){
 $dialog=New-Object Windows.Window
 $dialog.Title='指定配置对应的位置';$dialog.Width=520;$dialog.Height=250;$dialog.Owner=$window;$dialog.WindowStartupLocation='CenterOwner';$dialog.ResizeMode='NoResize'
 $panel=New-Object Windows.Controls.StackPanel;$panel.Margin=24
 $text=New-Object Windows.Controls.TextBlock;$text.Text='请选择这些文件原本属于哪个位置。只导入实际存在的文件，不会删除目标上其他设置。';$text.TextWrapping='Wrap';$text.Margin='0,0,0,16';$panel.Children.Add($text)|Out-Null
 $combo=New-Object Windows.Controls.ComboBox;$combo.DisplayMemberPath='Label';$combo.MinHeight=34
 $choices=@([pscustomobject]@{Label='账号 local/cfg（本地设置）';Scope='LocalCfg'},[pscustomobject]@{Label='账号 remote/cfg（云端缓存配置）';Scope='RemoteCfg'},[pscustomobject]@{Label='游戏 game/dota/cfg（安装内共用）';Scope='GameCfg'})
 if($Folder){$choices+= [pscustomobject]@{Label='整个账号 570 目录（保留 local/remote 结构）';Scope='Account570'}}
 $combo.ItemsSource=$choices;$panel.Children.Add($combo)|Out-Null
 $button=New-Object Windows.Controls.Button;$button.Content='确认位置并导入';$button.Margin='0,18,0,0';$button.Padding=8
 $button.Add_Click({if($combo.SelectedItem){$dialog.DialogResult=$true}});$panel.Children.Add($button)|Out-Null;$dialog.Content=$panel
 if($dialog.ShowDialog()){return $combo.SelectedItem.Scope};return ''
}
function Invoke-ImportPath([string]$Path){
 $Path=$Path.Trim().Trim('"');if(!$Path){throw '请选择或拖入一个文件/文件夹。'}
 $item=Get-Item -LiteralPath $Path
 $arguments=@{Path=$Path;Directory=$profilesDir}
 if($item.PSIsContainer -and !(Test-Path (Join-Path $Path 'backup.json'))){
  if((Test-Path (Join-Path $Path 'local/cfg')) -or (Test-Path (Join-Path $Path 'remote/cfg'))){$arguments.FolderScope='Account570'}
  else{$scope=Show-ImportScope $true;if(!$scope){return};$arguments.FolderScope=$scope}
 }elseif(!$item.PSIsContainer){
  $isSnapshot=$false
  if($item.Extension -eq '.json'){try{$o=[IO.File]::ReadAllText($Path)|ConvertFrom-Json;$isSnapshot=$null -ne $o.PSObject.Properties['Schema']}catch{}}
  $matches=@(Get-VaultRules|Where-Object {($_.Path -split '/')[-1] -eq $item.Name})
  if(!$isSnapshot -and $matches.Count -ne 1){
   $scope=Show-ImportScope $false;if(!$scope){return}
   $arguments.TargetRoot=if($scope -eq 'GameCfg'){'GameCfg'}else{'Account'}
   $prefix=switch($scope){LocalCfg{'local/cfg/'} RemoteCfg{'remote/cfg/'} default{''}}
   $arguments.TargetPath=$prefix+$item.Name
  }
 }
 $imported=Import-VaultInput @arguments
 Refresh-Profiles $imported;$ui.Pages.SelectedItem=$ui.LocalTab
 Set-Status '已导入方案库，尚未覆盖游戏设置。可以预览后再替换。'
}
function Reset-Scope {
 $ui.CustomScope.IsChecked=$false
 $ui.ScopeHint.Text='默认范围：键位、界面选项、编组和自定义启动配置；不含画质。'
}
function Load-Catalog {
 $script:catalog=@(Get-VaultFileCatalog -AccountPath (Get-AccountPath) -GameCfg $script:gameRoot -IncludeGameCfg|ForEach-Object {
  [pscustomobject]@{Root=$_.Root;Path=$_.Path;FullPath=$_.FullPath;Present=$_.Present;Selectable=$_.Selectable;Checked=($_.Recommended -and $_.Selectable);Description=$_.Description;State=if($_.Present){[string]$_.Bytes+' B'}else{'未生成'};Label=$(if($_.Root -eq 'GameCfg'){'游戏 / '}else{'账号 / '})+$_.Path}
 })
 $ui.Files.ItemsSource=$script:catalog;$script:parameters=@();$ui.Parameters.ItemsSource=$null;Reset-Scope
}
function Filter-Parameters {
 $q=$ui.ParameterSearch.Text.Trim()
 $rows=@($script:parameters|Where-Object { !$q -or ($_.Key+' '+$_.Value+' '+$_.Description+' '+$_.Scope).IndexOf($q,[StringComparison]::OrdinalIgnoreCase) -ge 0 })
 $ui.Parameters.ItemsSource=$rows;$ui.ParameterCount.Text="参数条目：$($rows.Count) / $($script:parameters.Count)"
}
function Set-Level([int]$Level){
 $script:level=$Level
 $ui.CloudTab.Visibility=if($Level -ge 2){'Visible'}else{'Collapsed'}
 $ui.InspectTab.Visibility=if($Level -ge 3){'Visible'}else{'Collapsed'}
 $buttons=@($ui.SimpleMode,$ui.CloudMode,$ui.AdvancedMode)
 for($i=0;$i -lt 3;$i++){$buttons[$i].Background=if($i -eq $Level-1){[Windows.Media.BrushConverter]::new().ConvertFromString('#8D4038')}else{[Windows.Media.BrushConverter]::new().ConvertFromString('#263240')}}
 if($Level -lt 3){Reset-Scope}
 switch($Level){
  1{$ui.Pages.SelectedItem=$ui.LocalTab;$ui.ModeHint.Text='简单操作：打开目录、保存、导出、导入和替换。全部在本地完成。'}
  2{$ui.Pages.SelectedItem=$ui.CloudTab;$ui.ModeHint.Text='进阶包含全部简单操作，再增加自己的 GitHub 私有备份。'}
  3{$ui.Pages.SelectedItem=$ui.InspectTab;$ui.ModeHint.Text='高级包含全部进阶功能，并展示文件内部参数。自选保存范围仍需手动启用。';if($ui.Accounts.SelectedItem -and !$script:catalog.Count){Load-Catalog}}
 }
}
function Save-Current {
 $rules=$null
 if($script:level -eq 3 -and $ui.CustomScope.IsChecked){
  [void]$ui.Files.CommitEdit();$rules=@($script:catalog|Where-Object { $_.Checked -and $_.Selectable }|Select-Object Root,Path)
  if(!$rules.Count){throw '高级自选范围为空，请至少勾选一个文件或关闭自选范围。'}
 }
 $saved=Save-VaultProfile -Name $ui.ProfileName.Text.Trim() -AccountPath (Get-AccountPath) -Directory $profilesDir -GameCfg $script:gameRoot -Rules $rules
 Refresh-Profiles $saved
 $script:lastExport=Export-VaultPackage $saved $ui.ExportPath.Text.Trim()
 Save-Preferences;Open-Folder $script:lastExport
 Set-Status "已保存并导出：$script:lastExport"
}
function Export-Selected([string]$Destination){
 $script:lastExport=Export-VaultPackage (Get-SelectedPath) $Destination
 Open-Folder $script:lastExport;Set-Status "已导出：$script:lastExport"
}
$ui.SimpleMode.Add_Click({Invoke-Ui {Set-Level 1}})
$ui.CloudMode.Add_Click({Invoke-Ui {Set-Level 2}})
$ui.AdvancedMode.Add_Click({Invoke-Ui {Set-Level 3}})
$ui.Accounts.Add_SelectionChanged({
 Reset-Scope;$script:catalog=@();$ui.Files.ItemsSource=$null;$ui.Parameters.ItemsSource=$null
 if($ui.Accounts.SelectedItem){$ui.AccountHint.Text="目标：userdata / $($ui.Accounts.SelectedItem) / 570"}
})
$ui.Profiles.Add_SelectionChanged({if($ui.Profiles.SelectedItem -and $ui.CloudProfiles.SelectedItem -ne $ui.Profiles.SelectedItem){$ui.CloudProfiles.SelectedItem=$ui.Profiles.SelectedItem}})
$ui.CloudProfiles.Add_SelectionChanged({if($ui.CloudProfiles.SelectedItem -and $ui.Profiles.SelectedItem -ne $ui.CloudProfiles.SelectedItem){$ui.Profiles.SelectedItem=$ui.CloudProfiles.SelectedItem}})
$ui.OpenLocal.Add_Click({Invoke-Ui {Open-Folder (Join-Path (Get-AccountPath) 'local/cfg')}})
$ui.OpenRemote.Add_Click({Invoke-Ui {Open-Folder (Join-Path (Get-AccountPath) 'remote/cfg')}})
$ui.OpenAccount.Add_Click({Invoke-Ui {Open-Folder (Get-AccountPath)}})
$ui.OpenGame.Add_Click({Invoke-Ui {Open-Folder $script:gameRoot}})
$ui.SaveButton.Add_Click({Invoke-Ui {Save-Current}})
$ui.BrowseExport.Add_Click({Invoke-Ui {$path=Pick-Folder $ui.ExportPath.Text;if($path){$ui.ExportPath.Text=$path;Save-Preferences}}})
$ui.ExportSelected.Add_Click({Invoke-Ui {Export-Selected $ui.ExportPath.Text.Trim()}})
$ui.DesktopExport.Add_Click({Invoke-Ui {Export-Selected ([Environment]::GetFolderPath('Desktop'))}})
$ui.RefreshButton.Add_Click({Invoke-Ui {Refresh-Profiles}})
$ui.BrowseImport.Add_Click({$picker=New-Object Microsoft.Win32.OpenFileDialog;$picker.Filter='配置与快照|*.json;*.cfg;*.vcfg;*.lst;*.txt;*.kv;*.vdf;*.dat;*.bak|所有文件|*.*';if($picker.ShowDialog($window)){$ui.ImportPath.Text=$picker.FileName}})
$ui.BrowseFolder.Add_Click({$path=Pick-Folder;if($path){$ui.ImportPath.Text=$path}})
$ui.ImportButton.Add_Click({Invoke-Ui {Invoke-ImportPath $ui.ImportPath.Text}})
$ui.DropZone.Add_PreviewDragOver({param($sender,$eventArgs);$eventArgs.Effects=if($eventArgs.Data.GetDataPresent([Windows.DataFormats]::FileDrop)){[Windows.DragDropEffects]::Copy}else{[Windows.DragDropEffects]::None};$eventArgs.Handled=$true})
$ui.DropZone.Add_PreviewDrop({param($sender,$eventArgs);$eventArgs.Handled=$true;Invoke-Ui {$paths=@($eventArgs.Data.GetData([Windows.DataFormats]::FileDrop));if($paths.Count -ne 1){throw '每次请拖入一个文件或文件夹。'};$ui.ImportPath.Text=$paths[0];Invoke-ImportPath $paths[0]}})
$ui.PreviewButton.Add_Click({Invoke-Ui {$s=Read-VaultSnapshot (Get-SelectedPath);$lines=Get-VaultChanges $s (Get-AccountPath) $script:gameRoot|ForEach-Object{"$($_.Action)  $($_.File)"};Show-Text '替换预览 · 尚未写入' ($lines -join "`r`n")}})
$ui.ApplyButton.Add_Click({Invoke-Ui {
 if(!$ui.CloudOff.IsChecked){throw '请先关闭 Dota 2 的 Steam 云同步，正常退出 Steam 和游戏，再勾选确认。'}
 $selected=Get-SelectedPath;$s=Read-VaultSnapshot $selected;$account=Get-AccountPath
 $changes=@(Get-VaultChanges $s $account $script:gameRoot|Where-Object Action -ne '不变')
 $message="将把「$($s.Name)」应用到账号 $($ui.Accounts.SelectedItem)，更改 $($changes.Count) 个文件。原设置会先自动备份。`r`n`r`n继续替换？"
 if([Windows.MessageBox]::Show($window,$message,'泉印 · 确认替换','YesNo','Question') -ne 'Yes'){return}
 Restore-VaultProfile -SnapshotPath $selected -AccountPath $account -GameCfg $script:gameRoot -BackupDirectory $backupsDir -CloudDisabled|Out-Null
 Refresh-Profiles $selected;Set-Status '替换并校验完成，原设置已自动备份。请启动游戏检查实际效果。'
}})
$ui.ScanFiles.Add_Click({Invoke-Ui {Load-Catalog}})
$ui.CustomScope.Add_Checked({$ui.ScopeHint.Text='高级自选范围已启用：下次保存仅包含“文件与参数”中勾选的文件。'})
$ui.CustomScope.Add_Unchecked({$ui.ScopeHint.Text='默认范围：键位、界面选项、编组和自定义启动配置；不含画质。'})
$ui.Files.Add_SelectionChanged({Invoke-Ui {
 $file=$ui.Files.SelectedItem
 if(!$file){return}
 $ui.ParameterSearch.Text=''
 $script:parameters=@(if($file.Present){Get-VaultParameters $file.FullPath})
 Filter-Parameters;$ui.ParameterDetail.Text=$file.FullPath+"`r`n"+$file.Description
}})
$ui.ParameterSearch.Add_TextChanged({Filter-Parameters})
$ui.Parameters.Add_SelectionChanged({if($ui.Parameters.SelectedItem){$p=$ui.Parameters.SelectedItem;$ui.ParameterDetail.Text="$($p.File)  ·  行 $($p.Line)  ·  $($p.Scope)`r`n$($p.Key) = $($p.Value)`r`n$($p.Description)"}})
$ui.ManualButton.Add_Click({Show-Text '泉印说明书 · 文件夹、文件与操作流程' ([IO.File]::ReadAllText((Join-Path $PSScriptRoot '使用说明.txt')))})
$ui.PathsButton.Add_Click({Invoke-Ui {
 $chosen=Pick-Folder $script:steamRoot
 if(!$chosen){return}
 if(!(Test-Path (Join-Path $chosen 'userdata'))){throw '请选择包含 userdata 的 Steam 安装目录。'}
 $script:steamRoot=$chosen;$script:gameRoot=Get-VaultGameCfg $chosen;Reset-Scope;Refresh-Accounts
 Set-Status "已选择 Steam：$chosen；游戏 cfg：$script:gameRoot"
}})
$ui.LoginButton.Add_Click({Invoke-Ui {
 if(!(Get-Command gh -ErrorAction SilentlyContinue)){throw '请先从 https://cli.github.com/ 安装 GitHub CLI，再重新打开泉印。本地功能不需要它。'}
 Start-Process powershell.exe -ArgumentList '-NoProfile -NoExit -Command "gh auth login --hostname github.com --git-protocol https --web"'
 Set-Status '请在新窗口完成 GitHub 授权。已有多个账号可使用 gh auth switch 切换。'
}})
$ui.CreateRepoButton.Add_Click({Invoke-Ui {Set-Status '正在创建私有仓库…';New-VaultRepository $ui.Repository.Text.Trim()|Out-Null;Save-Preferences;Set-Status '私有仓库已创建，可以上传所选方案。'}})
$ui.UploadButton.Add_Click({Invoke-Ui {Set-Status '正在上传所选方案…';Send-VaultProfile (Get-SelectedPath) $ui.Repository.Text.Trim()|Out-Null;Save-Preferences;Set-Status '上传完成，当前版本已保存在自己的私有仓库。'}})
$ui.DownloadButton.Add_Click({Invoke-Ui {Set-Status '正在下载并校验…';$count=Receive-VaultProfiles $ui.Repository.Text.Trim() $profilesDir;Save-Preferences;Refresh-Profiles;Set-Status "新增 $count 个方案；到“本地方案”查看、导出或替换。"}})
Refresh-Accounts
if($AccountId){$ui.Accounts.SelectedItem=$AccountId}
Refresh-Profiles;Set-Level 1
if($SmokeTest){
 . (Join-Path $PSScriptRoot 'tests/Gui.Smoke.ps1')
}else{[void]$window.ShowDialog()}
