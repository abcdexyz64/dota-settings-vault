$script:ParameterNotes=@{
    dota_minimap_position_option='小地图位置选项。枚举含义随游戏版本变化，请以游戏内左右位置选项为准。'
    dota_hud_flip='旧版/兼容界面翻转选项，可能与小地图位置相关；当前版本需结合 position_option 查看。'
    dota_camera_speed='镜头移动速度。'; dota_camera_accelerate='镜头移动加速度。'
    dota_camera_edgemove='鼠标移到屏幕边缘时移动镜头。'; dota_camera_reverse='镜头拖动方向反转。'
    dota_camera_disable_zoom='限制镜头缩放的选项。'; dota_camera_deatheffect='死亡时镜头效果开关。'
    dota_camera_hold_select_to_follow='按住选择英雄键时跟随英雄的选项。'
    dota_ability_quick_cast='技能快速施法选项。'; dota_ability_legacy_mode_quick_cast='传统键位模式下的快速施法选项。'
    dota_quickcast_onkeydown='快速施法在按键按下时触发的选项。'
    dota_enable_direct_quickcast_bindings='独立快速施法绑定相关选项。'
    dota_hud_colorblind='色盲辅助配色模式。'; dota_hud_netgraph='网络/性能信息显示。'
    dota_hud_extra_large_minimap='小地图尺寸相关选项。'; dota_minimap_hero_size='小地图英雄标记大小。'
    dota_minimap_always_draw_hero_icons='小地图始终显示英雄头像的选项。'
    dota_minimap_show_hero_icon='小地图英雄头像显示选项。'
    dota_minimap_simple_colors='小地图简化配色选项。'; dota_minimap_hide_background='隐藏小地图背景的选项。'
    dota_minimap_misclick_time='小地图防误点时间阈值。'
    dota_minimap_disable_rightclick='禁用小地图右键操作的选项。'
    dota_player_units_auto_attack='玩家单位自动攻击模式。'
    dota_player_teleport_requires_halt='传送动作是否需要停止命令才能中断的选项。'
    dota_force_right_click_attack='右键攻击/反补行为相关选项。'
    dota_player_add_summoned_to_selection='召唤单位加入当前选择的选项。'
    dota_player_auto_repeat_right_mouse='按住右键持续重复命令的选项。'
    dota_shop_force_hotkeys='商店快捷键相关选项。'
    dota_health_per_vertical_marker='生命条每个刻度所代表的生命值。'
    dota_reset_camera_on_spawn='重生时重置镜头的选项。'
    dota_unit_multiple_selection='多单位选择相关选项。'
    dota_hud_contextual_tips_disable='禁用情境教学提示。'
    dota_hud_disable_damage_numbers='禁用伤害数字显示。'
    dota_show_range_finder_on_quickcast='快速施法时显示范围提示的选项。'
    volume='主音量。'; snd_musicvolume='音乐音量。'; snd_gamevolume='游戏音效音量。'
    snd_voipvolume='语音聊天音量。'; voice_enable='语音功能开关。'
    fps_max='最大帧率限制。'; fps_max_ui='界面帧率限制。'; cl_showfps='显示帧率信息。'
    chat_sound='聊天提示音开关。'; con_enable='开发者控制台开关。'
    UseHeroBindings='是否使用英雄独立键位。'; LinkPlayerToSpectator='玩家和观战键位关联选项。'
    Version='配置格式版本，不是玩家操作选项。'; AlgorithmicUpdateVersion='游戏自动迁移配置的版本记录。'
    unitname='控制编组中的单位内部名称。'; illusion='控制编组中的幻象标记。'; unitindex='控制编组中的单位索引。'
}
$script:BindingNotes=@{
    CameraUp='向上移动镜头';CameraDown='向下移动镜头';CameraLeft='向左移动镜头';CameraRight='向右移动镜头'
    CameraGrip='拖动镜头';CameraZoomIn='镜头放大';CameraZoomOut='镜头缩小';ActivateGlyph='防御符文';ActivateRadar='雷达扫描'
    ChatTeam='队伍聊天';ChatTeam2='队伍聊天备用绑定';ChatAll='所有人聊天';ChatWheel='聊天轮盘';HeroChatWheel='英雄聊天轮盘'
    HeroAttack='攻击命令';HeroMove='移动命令';HeroStop='停止';HeroHold='保持位置';HeroSelect='选择英雄'
    CourierSelect='选择信使';CourierDeliver='信使运送物品';Shop='打开商店';Pause='暂停';Scoreboard='计分板'
    AbilityPrimary1='第一主要技能';AbilityPrimary2='第二主要技能';AbilityPrimary3='第三主要技能';AbilitySecondary1='第一附加技能';AbilitySecondary2='第二附加技能';AbilityUltimate='终极技能';LearnAbilities='升级技能';LearnStats='升级属性';ControlGroupCycle='循环切换编组'
}
function Get-VaultParameterNote([string]$Key,[string]$Scope) {
    if($script:ParameterNotes.ContainsKey($Key)){return @($script:ParameterNotes[$Key],'已知用途')}
    $parent=($Scope -split '/')[-1]
    if($Key -in @('Key','Mode','QuickCast','CastMode')){
        $action=if($script:BindingNotes.ContainsKey($parent)){$script:BindingNotes[$parent]}else{$parent}
        if($parent -match '^Inventory(\d+)$'){$action='物品槽位 '+$Matches[1]}
        if($parent -match '^ControlGroup(\d+)$'){$action='控制编组 '+$Matches[1]}
        if($Key -eq 'Key'){return @("「$action」的实际按键绑定。",'结构说明')}
        return @("「$action」的施法/绑定模式字段；数值含义由当前游戏版本决定。",'结构说明')
    }
    if($Scope -match '(^|/)bindings($|/)'){return @('按键名称 → 控制台命令/自定义别名。','结构说明')}
    if($Key -match '^(bind|alias) '){return @('按键绑定或命令别名；仅显示文本，不会执行。','结构说明')}
    if($Key -eq 'exec'){return @('引用另一个 cfg 文件；查看器不会执行或自动导入引用目标。','已知用途')}
    if($Key -match '^dota_minimap_'){return @('小地图相关参数；具体字段尚未核实，请结合名称和游戏设置确认。','按名称归类')}
    if($Key -match '^dota_camera_'){return @('镜头相关参数；具体字段尚未核实。','按名称归类')}
    if($Key -match '^chat_wheel_'){return @('聊天轮盘槽位或内容编号；编号不直接等于显示文字。','按名称归类')}
    if($Key -match '^(snd_|voice_)'){return @('声音/语音相关参数；具体字段尚未核实。','按名称归类')}
    if($Key -match '^setting\.'){return @('画质/显示配置字段；具体数值请以游戏内设置为准。','按名称归类')}
    return @('用途待确认；保留原始名称和值，不猜测含义。','待确认')
}
function New-VaultParameterRow($Key,$Value,$Scope,$Line,$File) {
    $note=Get-VaultParameterNote ([string]$Key) ([string]$Scope)
    [pscustomobject]@{Key=[string]$Key;Value=[string]$Value;Scope=[string]$Scope;Line=[int]$Line;File=$File;Description=$note[0];Confidence=$note[1]}
}
function Get-VaultParameters([string]$Path) {
    $file=Get-Item -LiteralPath $Path
    if($file.Length -gt 2000000){throw '文件超过 2 MB，暂不在参数查看器中展开。'}
    $text=[IO.File]::ReadAllText($Path)
    if($text.IndexOf([char]0) -ge 0){return [pscustomobject]@{Key='[二进制内容]';Value='';Scope='';Line=0;File=$file.Name;Description='此文件含二进制数据，不能可靠解释为参数条目。';Confidence='未解析'}}
    if($file.Extension -eq '.json'){
        try{
            $json=$text | ConvertFrom-Json
            function Expand-Json($Value,$Scope){
                if($null -eq $Value){New-VaultParameterRow (($Scope -split '/')[-1]) 'null' $Scope 0 $file.Name}
                elseif($Value -is [System.Management.Automation.PSCustomObject]){foreach($p in $Value.PSObject.Properties){Expand-Json $p.Value ($Scope+'/'+$p.Name)}}
                elseif($Value -is [array]){for($j=0;$j -lt $Value.Count;$j++){Expand-Json $Value[$j] ($Scope+'/'+$j)}}
                else{New-VaultParameterRow (($Scope -split '/')[-1]) ([string]$Value) $Scope 0 $file.Name}
            }
            return @(Expand-Json $json '')
        }catch{throw "JSON 无法解析：$($_.Exception.Message)"}
    }
    $stack=New-Object 'Collections.Generic.List[string]'; $pending=''; $number=0
    foreach($line in ($text -split '\r?\n')){
        $number++; $trim=$line.Trim()
        if(!$trim -or $trim.StartsWith('//') -or $trim.StartsWith('#')){continue}
        if($trim -match '^"([^"]*)"\s*\{\s*$'){$stack.Add($Matches[1]);continue}
        if($trim -eq '{'){$stack.Add($pending);$pending='';continue}
        if($trim -match '^}\s*(?://.*)?$'){if($stack.Count){$stack.RemoveAt($stack.Count-1)};continue}
        if($trim -match '^"([^"]*)"\s*(?://.*)?$'){$pending=$Matches[1];continue}
        $scope=$stack -join '/'
        if($trim -match '^"([^"]*)"\s+"(.*)"\s*(?://.*)?$'){
            New-VaultParameterRow $Matches[1] $Matches[2] $scope $number $file.Name
        }elseif($trim -match '^(bind|alias)\s+"?([^"\s]+)"?\s+(.+)$'){
            New-VaultParameterRow ($Matches[1]+' '+$Matches[2]) $Matches[3] $scope $number $file.Name
        }elseif($trim -match '^([+\-\w.]+)\s+(.+)$'){
            New-VaultParameterRow $Matches[1] $Matches[2] $scope $number $file.Name
        }else{
            [pscustomobject]@{Key='[未解析原文]';Value=$trim;Scope=$scope;Line=$number;File=$file.Name;Description='此行不是受支持的简单键值/命令形式，原文完整保留。';Confidence='未解析'}
        }
    }
}
