param(
    [ValidateSet('Gui','List','Save','Preview','Apply','Upload','Download','CreateRepo')][string]$Action = 'Gui',
    [string]$Name, [string]$SteamPath, [string]$AccountId, [string]$Snapshot,
    [string]$Repository, [string]$GameCfg, [switch]$IncludeVideo, [switch]$CloudDisabled,
    [string]$DataDirectory = (Join-Path $PSScriptRoot 'data'), [switch]$SmokeTest
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Vault.Core.psm1') -Force
$DataDirectory = [IO.Path]::GetFullPath($DataDirectory)
$profilesDir = Join-Path $DataDirectory 'profiles'
$backupsDir = Join-Path $DataDirectory 'rollback'
[IO.Directory]::CreateDirectory($profilesDir) | Out-Null
[IO.Directory]::CreateDirectory($backupsDir) | Out-Null
if (!$SteamPath) { $SteamPath = Get-VaultSteamPath }
if (!$GameCfg -and $SteamPath) { $GameCfg = Get-VaultGameCfg $SteamPath }

if ($Action -ne 'Gui') {
    if ($Action -in @('Save','Preview','Apply')) {
        if ($AccountId -notmatch '^\d+$') { throw '请用 -AccountId 明确指定 Steam userdata 的数字账号目录。' }
        $accountPath = Join-Path $SteamPath "userdata/$AccountId/570"
    }
    switch ($Action) {
        List {
            Get-VaultAccounts $SteamPath | ForEach-Object { [pscustomobject]@{ Kind='Account'; Name=$_.Id; Path=$_.Path } }
            Get-ChildItem $profilesDir -Filter '*.json' | ForEach-Object { $s = Read-VaultSnapshot $_.FullName; [pscustomobject]@{ Kind='Profile'; Name=$s.Name; Path=$_.FullName } }
        }
        Save { Save-VaultProfile -Name $Name -AccountPath $accountPath -Directory $profilesDir -GameCfg $GameCfg -IncludeVideo:$IncludeVideo }
        Preview { Get-VaultChanges (Read-VaultSnapshot $Snapshot) $accountPath $GameCfg }
        Apply { Restore-VaultProfile -SnapshotPath $Snapshot -AccountPath $accountPath -GameCfg $GameCfg -BackupDirectory $backupsDir -CloudDisabled:$CloudDisabled }
        Upload { Send-VaultProfile $Snapshot $Repository }
        Download { Receive-VaultProfiles $Repository $profilesDir }
        CreateRepo { New-VaultRepository $Repository }
    }
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'Dota 设置保险箱'
$form.Size = New-Object Drawing.Size(1060, 820)
$form.MinimumSize = $form.Size
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
$form.BackColor = [Drawing.Color]::FromArgb(243,245,248)
$form.AutoScaleMode = 'Dpi'

function Add-Label($text, $x, $y, $width = 950, $height = 26) {
    $c = New-Object Windows.Forms.Label
    $c.Text=$text; $c.SetBounds($x,$y,$width,$height); $form.Controls.Add($c); return $c
}
function Add-Text($text, $x, $y, $width) {
    $c = New-Object Windows.Forms.TextBox
    $c.Text=$text; $c.SetBounds($x,$y,$width,29); $form.Controls.Add($c); return $c
}
function Add-Button($text, $x, $y, $width, $handler) {
    $c = New-Object Windows.Forms.Button
    $c.Text=$text; $c.SetBounds($x,$y,$width,34); $c.Add_Click($handler); $form.Controls.Add($c); return $c
}
function Add-Check($text,$x,$y,$width,$checked) {
    $c = New-Object Windows.Forms.CheckBox
    $c.Text=$text; $c.SetBounds($x,$y,$width,28); $c.Checked=$checked; $form.Controls.Add($c); return $c
}
$title = Add-Label 'DOTA 2  /  设置保险箱' 24 18
$title.Font = New-Object Drawing.Font('Microsoft YaHei UI',18,[Drawing.FontStyle]::Bold)
$title.Height=38
Add-Label '保存你的操作习惯，在不同玩家、账号和电脑之间切换。每次保存都是独立版本。' 24 61 | Out-Null
Add-Label 'Steam 目录' 24 102 110 | Out-Null
$steamBox = Add-Text $SteamPath 140 100 560
Add-Label '账号目录 ID' 24 144 110 | Out-Null
$accountBox = New-Object Windows.Forms.ComboBox
$accountBox.SetBounds(140,142,280,30); $accountBox.DropDownStyle='DropDownList'; $form.Controls.Add($accountBox)
Add-Label '多个账号时请明确选择，工具不会猜测当前玩家。' 440 144 560 | Out-Null
Add-Label '游戏 cfg 目录' 24 184 115 | Out-Null
$gameBox = Add-Text $GameCfg 140 182 860
$gameCheck = Add-Check '保存时包含 autoexec.cfg / dota_minimap.cfg（全账号共用）' 140 219 590 $true
$videoCheck = Add-Check '保存画质 / 分辨率' 740 219 260 $false
$script:advancedRules = $null
Add-Label '方案名称' 24 264 110 | Out-Null
$nameBox = Add-Text '我的设置' 140 260 390
$advancedSummary = Add-Label '默认保存范围；高级文件选择未启用。' 24 292 976 18
$advancedSummary.Font = New-Object Drawing.Font('Microsoft YaHei UI',8)

$list = New-Object Windows.Forms.ListView
$list.SetBounds(24,310,976,220); $list.View='Details'; $list.FullRowSelect=$true
$list.MultiSelect=$false; $list.HideSelection=$false; $list.GridLines=$true
[void]$list.Columns.Add('个人方案 / 回滚备份',360)
[void]$list.Columns.Add('保存时间',220)
[void]$list.Columns.Add('文件数',90)
[void]$list.Columns.Add('类型',180)
$form.Controls.Add($list)
$cloudCheck = Add-Check '我已在 Steam 的 Dota 2 属性中关闭此游戏的云同步，且已退出 Steam' 24 540 975 $false

Add-Label 'GitHub 私有备份仓库' 24 644 190 | Out-Null
$repoBox = Add-Text '' 218 640 460
$settingsPath = Join-Path $DataDirectory 'preferences.json'
if (Test-Path -LiteralPath $settingsPath) {
    try { $prefs = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json; $repoBox.Text = $prefs.Repository } catch {}
}
$status = Add-Label '就绪。保存前退出 Dota 2；切换前关闭该游戏的云同步并彻底退出 Steam。' 24 737 976 42
$status.ForeColor = [Drawing.Color]::FromArgb(35,75,105)
function Set-Status([string]$text) { $status.Text=$text; $status.Refresh() }
function Save-Preferences {
    [IO.File]::WriteAllText($settingsPath, (@{ Repository=$repoBox.Text.Trim() } | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
}
function Invoke-Ui($work) {
    $form.UseWaitCursor=$true
    try { & $work }
    catch { Set-Status '操作未完成。'; [Windows.Forms.MessageBox]::Show($_.Exception.Message,'操作未完成','OK','Warning') | Out-Null }
    finally { $form.UseWaitCursor=$false }
}
function Refresh-Accounts {
    $accountBox.Items.Clear()
    foreach ($a in Get-VaultAccounts $steamBox.Text) { [void]$accountBox.Items.Add($a.Id) }
    if ($accountBox.Items.Count -eq 1) { $accountBox.SelectedIndex=0 }
    $gameBox.Text = Get-VaultGameCfg $steamBox.Text
}
function Refresh-Profiles {
    $list.Items.Clear()
    foreach ($dir in @($profilesDir,$backupsDir)) {
        foreach ($file in Get-ChildItem -LiteralPath $dir -Filter '*.json' | Sort-Object LastWriteTime -Descending) {
            try {
                $s=Read-VaultSnapshot $file.FullName
                $row=New-Object Windows.Forms.ListViewItem($s.Name)
                [void]$row.SubItems.Add(([DateTime]::Parse($s.CreatedUtc).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')))
                [void]$row.SubItems.Add([string]@($s.Files | Where-Object Present).Count)
                [void]$row.SubItems.Add($(if ($dir -eq $profilesDir) {'个人方案'} else {'切换前自动备份'}))
                $row.Tag=$file.FullName; [void]$list.Items.Add($row)
            } catch { Set-Status "跳过无效备份 $($file.Name)：$($_.Exception.Message)" }
        }
    }
}
function Get-SelectedPath {
    if ($list.SelectedItems.Count -ne 1) { throw '请先在列表中选择一个方案或回滚备份。' }
    return [string]$list.SelectedItems[0].Tag
}
function Get-AccountPath {
    if (!$accountBox.SelectedItem) { throw '请先选择要保存或切换的 Steam 账号目录 ID。' }
    return Join-Path $steamBox.Text "userdata/$($accountBox.SelectedItem)/570"
}
function Get-SelectedGameCfg { if ($gameCheck.Checked) { return $gameBox.Text }; return '' }

function Show-AdvancedFiles {
    param([switch]$TestDialog)
    $catalog = @(Get-VaultFileCatalog -AccountPath (Get-AccountPath) -GameCfg $gameBox.Text -IncludeVideo:$videoCheck.Checked -IncludeGameCfg:$gameCheck.Checked)
    $dialog = New-Object Windows.Forms.Form
    $dialog.Text='高级：选择保存文件'
    $dialog.Size=New-Object Drawing.Size(1180,760)
    $dialog.StartPosition='CenterParent'; $dialog.Font=$form.Font; $dialog.MinimumSize=$dialog.Size
    $enabled = New-Object Windows.Forms.CheckBox
    $enabled.Text='启用自定义文件选择（仅本次打开工具有效；未启用时使用默认范围）'
    $enabled.SetBounds(20,15,1100,28); $enabled.Checked=($null -ne $script:advancedRules)
    $dialog.Controls.Add($enabled)
    $hint = New-Object Windows.Forms.Label
    $hint.Text='列出账号 local/cfg、remote/cfg、游戏 cfg 的全部文件，以及 cfg 外的关键设置。未知文件如实标注；云同步对照副本不可选。'
    $hint.SetBounds(20,49,1120,43); $dialog.Controls.Add($hint)
    $files = New-Object Windows.Forms.ListView
    $files.SetBounds(20,96,1120,450); $files.View='Details'; $files.CheckBoxes=$true
    $files.FullRowSelect=$true; $files.MultiSelect=$false; $files.ShowItemToolTips=$true; $files.HideSelection=$false
    [void]$files.Columns.Add('文件 / 相对路径',340)
    [void]$files.Columns.Add('位置',105)
    [void]$files.Columns.Add('大小 / 状态',100)
    [void]$files.Columns.Add('内容说明',540)
    $dialog.Controls.Add($files)
    $selected = @{}
    if ($null -ne $script:advancedRules) { foreach($r in $script:advancedRules) { $selected["$($r.Root)/$($r.Path)"]=$true } }
    foreach ($entry in $catalog) {
        $row = New-Object Windows.Forms.ListViewItem($entry.Path)
        [void]$row.SubItems.Add($(if($entry.Root -eq 'Account'){'账号设置'}else{'游戏共用'}))
        [void]$row.SubItems.Add($(if(!$entry.Present){'未生成'}else{[string]$entry.Bytes+' B'}))
        [void]$row.SubItems.Add($entry.Description)
        $row.Tag=$entry; $row.ToolTipText=$entry.FullPath+"`r`n"+$entry.Description
        $row.Checked = $entry.Selectable -and $(if($null -ne $script:advancedRules){$selected.ContainsKey("$($entry.Root)/$($entry.Path)")}else{$entry.Recommended})
        if (!$entry.Selectable) { $row.ForeColor=[Drawing.Color]::Gray }
        [void]$files.Items.Add($row)
    }
    $detail = New-Object Windows.Forms.TextBox
    $detail.SetBounds(20,560,1120,83); $detail.Multiline=$true; $detail.ReadOnly=$true
    $detail.Text='选择一行查看完整路径和说明。勾选“未生成”的文件会记录其缺失状态，切换时清理目标的同名残留；切换前仍会自动备份。'
    $dialog.Controls.Add($detail)
    $files.Add_SelectedIndexChanged({
        if($files.SelectedItems.Count) {
            $e=$files.SelectedItems[0].Tag
            $detail.Text=$e.FullPath+"`r`n"+$e.Description+$(if(!$e.Selectable){"`r`n此文件类型不参与保存/恢复。"}elseif(!$e.Present){"`r`n未生成：选中会记录缺失状态，切换时移除目标同名文件。"}else{''})
        }
    })
    $files.Add_ItemCheck({ param($sender,$eventArgs)
        if (!$sender.Items[$eventArgs.Index].Tag.Selectable) { $eventArgs.NewValue=[Windows.Forms.CheckState]::Unchecked }
    })
    $default = New-Object Windows.Forms.Button
    $default.Text='恢复默认范围'; $default.SetBounds(20,665,175,34)
    $default.Add_Click({ $enabled.Checked=$false; foreach($row in $files.Items){$row.Checked=$row.Tag.Recommended -and $row.Tag.Selectable} })
    $dialog.Controls.Add($default)
    $open = New-Object Windows.Forms.Button
    $open.Text='查看所选文件'; $open.SetBounds(210,665,175,34)
    $open.Add_Click({
        if($files.SelectedItems.Count -and $files.SelectedItems[0].Tag.Present) {
            Start-Process notepad.exe -ArgumentList ('"'+$files.SelectedItems[0].Tag.FullPath+'"')
        }
    }); $dialog.Controls.Add($open)
    $ok = New-Object Windows.Forms.Button
    $ok.Text='确认保存范围'; $ok.SetBounds(780,665,175,34)
    $ok.Add_Click({
        if($enabled.Checked -and !$files.CheckedItems.Count){[Windows.Forms.MessageBox]::Show('请至少选择一个文件。') | Out-Null; return}
        $dialog.DialogResult=[Windows.Forms.DialogResult]::OK
    }); $dialog.Controls.Add($ok)
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text='取消'; $cancel.SetBounds(970,665,170,34); $cancel.DialogResult='Cancel'; $dialog.Controls.Add($cancel)
    $dialog.CancelButton=$cancel
    if ($TestDialog) {
        $dialog.Add_Shown({
            [Windows.Forms.Application]::DoEvents()
            $preview=New-Object Drawing.Bitmap($dialog.Width,$dialog.Height)
            try { $dialog.DrawToBitmap($preview,(New-Object Drawing.Rectangle(0,0,$dialog.Width,$dialog.Height))); $preview.Save((Join-Path $DataDirectory 'advanced-ui-smoke.png')) }
            finally { $preview.Dispose() }
            $enabled.Checked=$true
            foreach($row in $files.Items){$row.Checked=($row.Tag.Path -eq 'remote/cfg/dotakeys_personal.lst')}
            $ok.PerformClick()
        })
    }
    if($dialog.ShowDialog($form) -eq 'OK') {
        if($enabled.Checked) {
            $script:advancedRules=@(foreach($row in $files.CheckedItems){[pscustomobject]@{Root=$row.Tag.Root;Path=$row.Tag.Path}})
            $advancedSummary.Text="高级自选已启用：保存 $($script:advancedRules.Count) 个文件/缺失状态；上方默认范围复选框暂不生效。"
        } else {
            $script:advancedRules=$null
            $advancedSummary.Text='默认保存范围；高级文件选择未启用。'
        }
    }
    $dialog.Dispose()
}

function Reset-AdvancedSelection {
    $script:advancedRules=$null
    $advancedSummary.Text='默认保存范围；高级文件选择未启用。'
}
$accountBox.Add_SelectedIndexChanged({ Reset-AdvancedSelection })
$gameBox.Add_TextChanged({ Reset-AdvancedSelection })

Add-Button '重新扫描账号' 718 97 155 { Invoke-Ui { Refresh-Accounts; Set-Status '已扫描，请选择账号。' } } | Out-Null
Add-Button '保存当前设置' 550 256 180 { Invoke-Ui {
    Set-Status '正在保存当前设置…'
    $saveGameCfg=Get-SelectedGameCfg
    if ($null -ne $script:advancedRules) { $saveGameCfg=$gameBox.Text }
    $path=Save-VaultProfile -Name $nameBox.Text.Trim() -AccountPath (Get-AccountPath) -Directory $profilesDir -GameCfg $saveGameCfg -IncludeVideo:$videoCheck.Checked -Rules $script:advancedRules
    Refresh-Profiles; Set-Status "已保存：$path"
} } | Out-Null
Add-Button '刷新列表' 749 256 120 { Invoke-Ui { Refresh-Profiles } } | Out-Null
Add-Button '高级：文件' 880 256 120 { Invoke-Ui { Show-AdvancedFiles } } | Out-Null
Add-Button '预览更改' 24 578 150 { Invoke-Ui {
    $s=Read-VaultSnapshot (Get-SelectedPath)
    $changes=Get-VaultChanges $s (Get-AccountPath) $gameBox.Text
    $text=($changes | ForEach-Object { "$($_.Action)  $($_.File)" }) -join "`r`n"
    [Windows.Forms.MessageBox]::Show($text,'切换预览（尚未写入）','OK','Information') | Out-Null
} } | Out-Null
Add-Button '切换 / 恢复所选方案' 190 578 240 { Invoke-Ui {
    $selected=Get-SelectedPath; $target=Get-AccountPath
    $s=Read-VaultSnapshot $selected
    $changes=@(Get-VaultChanges $s $target $gameBox.Text | Where-Object Action -ne '不变')
    if (!$cloudCheck.Checked) { throw '请先关闭该游戏的 Steam 云同步、退出 Steam，再勾选上方确认。' }
    $msg="将把方案「$($s.Name)」应用到账号 $($accountBox.SelectedItem)。`r`n需要更改 $($changes.Count) 个文件。原设置会先自动备份。`r`n包含的游戏 cfg 文件会影响这台电脑上的所有账号。`r`n`r`n继续切换？"
    if ([Windows.Forms.MessageBox]::Show($msg,'确认切换','YesNo','Question') -ne 'Yes') { return }
    $backup=Restore-VaultProfile -SnapshotPath $selected -AccountPath $target -GameCfg $gameBox.Text -BackupDirectory $backupsDir -CloudDisabled:$cloudCheck.Checked
    Refresh-Profiles; Set-Status "文件切换并校验完成。可启动 Steam / Dota 2 检查；回滚备份已保存。"
} } | Out-Null
Add-Button '打开本地备份' 447 578 170 { Start-Process explorer.exe -ArgumentList ('"'+$DataDirectory+'"') } | Out-Null
Add-Button '使用说明' 634 578 140 { Start-Process notepad.exe -ArgumentList ('"'+(Join-Path $PSScriptRoot 'README.md')+'"') } | Out-Null
Add-Button '登录自己的 GitHub' 696 636 230 { Invoke-Ui {
    if (!(Get-Command gh -ErrorAction SilentlyContinue)) { throw '请先安装 GitHub CLI：https://cli.github.com/ ，重新打开工具后再登录。本地功能不需要安装它。' }
    Start-Process powershell.exe -ArgumentList '-NoProfile -NoExit -Command "gh auth login --hostname github.com --git-protocol https --web"'
    Set-Status '请在新窗口完成 GitHub 浏览器授权，然后回来上传。凭据由 GitHub CLI 管理。'
} } | Out-Null
Add-Button '新建私有备份仓库' 24 688 220 { Invoke-Ui {
    Set-Status '正在创建私有仓库…'; New-VaultRepository $repoBox.Text.Trim() | Out-Null
    Save-Preferences; Set-Status '私有仓库已创建，可以上传所选方案。'
} } | Out-Null
Add-Button '上传所选方案' 262 688 180 { Invoke-Ui {
    Set-Status '正在上传所选版本…'; $url=Send-VaultProfile (Get-SelectedPath) $repoBox.Text.Trim()
    Save-Preferences; Set-Status "上传完成：$url（仅上传选中版本）"
} } | Out-Null
Add-Button '下载云端方案' 460 688 180 { Invoke-Ui {
    Set-Status '正在下载并校验云端方案…'; $count=Receive-VaultProfiles $repoBox.Text.Trim() $profilesDir
    Save-Preferences; Refresh-Profiles; Set-Status "下载完成：新增 $count 个版本。选择方案后可预览和切换。"
} } | Out-Null

Refresh-Accounts
if ($GameCfg) { $gameBox.Text=$GameCfg }
Refresh-Profiles
if ($SmokeTest) {
    $form.Show(); [Windows.Forms.Application]::DoEvents()
    if ($form.Controls.Count -lt 25) { throw 'UI controls missing' }
    if ($AccountId) {
        $accountBox.SelectedItem = $AccountId
        if (!$accountBox.SelectedItem) { throw 'Smoke-test account not found' }
        if ($null -ne $script:advancedRules) { throw 'Advanced mode must be disabled by default' }
        Show-AdvancedFiles -TestDialog
        if (@($script:advancedRules).Count -ne 1) { throw 'Advanced file selection failed' }
        Write-Output 'GUI_ADVANCED_SELECTION_PASS'
        $nameBox.Text = 'GUI 保存测试'
        $beforeCount = $list.Items.Count
        $saveButton = $form.Controls | Where-Object { $_ -is [Windows.Forms.Button] -and $_.Text -eq '保存当前设置' }
        $saveButton.PerformClick()
        [Windows.Forms.Application]::DoEvents()
        if ($list.Items.Count -ne ($beforeCount + 1)) { throw 'GUI save button failed' }
        Write-Output 'GUI_SAVE_CLICK_PASS'
    }
    $bmp=New-Object Drawing.Bitmap($form.Width,$form.Height)
    try { $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height))); $bmp.Save((Join-Path $DataDirectory 'ui-smoke.png')) }
    finally { $bmp.Dispose(); $form.Close() }
    Write-Output 'GUI_SMOKE_PASS'; exit
}
[void]$form.ShowDialog()
$form.Dispose()
