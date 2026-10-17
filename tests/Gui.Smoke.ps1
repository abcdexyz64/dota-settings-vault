$window.Show()
$window.Dispatcher.Invoke([action]{},[Windows.Threading.DispatcherPriority]::Render)
function Check-Gui($condition,$name){if(!$condition){throw "GUI FAIL: $name"};Write-Output "GUI PASS: $name"}
function Click-Gui($control){$control.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))}
function Capture-Gui([string]$name){
 $window.UpdateLayout();$window.Dispatcher.Invoke([action]{},[Windows.Threading.DispatcherPriority]::Render)
 $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$window.ActualWidth),([int]$window.ActualHeight),96,96,([Windows.Media.PixelFormats]::Pbgra32)
 $bitmap.Render($window);$encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
 $file=[IO.File]::Create((Join-Path $DataDirectory $name));try{$encoder.Save($file)}finally{$file.Dispose()}
}
try {
 Check-Gui ($script:level -eq 1 -and $ui.CloudTab.Visibility -eq 'Collapsed' -and $ui.InspectTab.Visibility -eq 'Collapsed') 'simple mode is default'
 Check-Gui ($ui.ExportPath.Text -eq (Join-Path $DataDirectory 'exports')) 'exports default to app data folder'
 if($AccountId){
  $ui.ProfileName.Text='界面流程测试';Click-Gui $ui.SaveButton
  Check-Gui (Test-Path (Join-Path $script:lastExport 'backup.json')) 'save button exports portable folder'
  $package=$script:lastExport;$saved=Get-SelectedPath
  $ui.ImportPath.Text=$package;Click-Gui $ui.ImportButton
  Check-Gui ($ui.Profiles.SelectedItem.Name -like '导入*') 'path import button imports folder'
  $beforeDrop=$ui.Profiles.Items.Count
  $dropData=New-Object Windows.DataObject
  $dropData.SetData([Windows.DataFormats]::FileDrop,[string[]]@($package))
  $constructor=[Windows.DragEventArgs].GetConstructors([Reflection.BindingFlags]'Instance,NonPublic,Public')[0]
  $dropArguments=[object[]]@($dropData,[Windows.DragDropKeyStates]::None,[Windows.DragDropEffects]::Copy,$ui.DropZone,(New-Object Windows.Point(10,10)))
  for($di=0;$di -lt $dropArguments.Length;$di++){$dropArguments[$di]=$dropArguments[$di].PSObject.BaseObject}
  $dropEvent=$constructor.Invoke($dropArguments)
  $dropEvent.RoutedEvent=[Windows.DragDrop]::PreviewDropEvent
  $ui.DropZone.RaiseEvent($dropEvent)
  Check-Gui ($dropEvent.Handled -and $ui.Profiles.Items.Count -eq $beforeDrop+1) 'routed file-drop event imports portable folder'
  Click-Gui $ui.CloudMode
  Check-Gui ($ui.CloudTab.Visibility -eq 'Visible' -and $ui.LocalTab.Visibility -eq 'Visible' -and $ui.InspectTab.Visibility -eq 'Collapsed') 'intermediate includes simple'
  Click-Gui $ui.AdvancedMode
  Check-Gui ($ui.CloudTab.Visibility -eq 'Visible' -and $ui.LocalTab.Visibility -eq 'Visible' -and $ui.InspectTab.Visibility -eq 'Visible') 'advanced includes intermediate'
  $target=$script:catalog|Where-Object Path -eq 'local/cfg/user_convars_0_slot0.vcfg'|Select-Object -First 1
  $ui.Files.SelectedItem=$target
  $window.UpdateLayout();$window.Dispatcher.Invoke([action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
  Check-Gui ($script:parameters.Count -gt 0) 'file selection populates parameter rows'
  $ui.ParameterSearch.Text='minimap';Check-Gui ($ui.Parameters.Items.Count -gt 0) 'parameter search works'
  $ui.ParameterSearch.Text='';Capture-Gui 'advanced-ui.png'
  $ui.CustomScope.IsChecked=$true
  foreach($entry in $script:catalog){$entry.Checked=$entry.Path -eq 'remote/cfg/dotakeys_personal.lst'}
  $ui.Pages.SelectedItem=$ui.LocalTab;Click-Gui $ui.SaveButton
  Check-Gui (@((Read-VaultSnapshot (Get-SelectedPath)).Files).Count -eq 1) 'advanced selection controls same save button'
  Click-Gui $ui.SimpleMode
  Check-Gui (!$ui.CustomScope.IsChecked) 'downgrading resets custom scope'
  Check-Gui ($ui.Profiles.Items.Count -ge 3) 'mode changes preserve shared library'
 }
 Capture-Gui 'simple-ui.png'
 Write-Output 'WPF_GUI_SMOKE_PASS'
}finally{$window.Close()}
