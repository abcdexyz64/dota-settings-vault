Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-VaultRules {
    $paths = @('remote/cfg/dotakeys_personal.lst', 'remote/user_convars.vcfg', 'remote/user_keys.vcfg',
        'remote/cfg/config.cfg', 'remote/cfg/hero_grid_config.json', 'remote/cfg/hero_facet_config.cfg',
        'remote/scripts/control_groups.txt', 'local/cfg/machine_convars.vcfg')
    foreach ($slot in 0..3) {
        $paths += "local/cfg/user_convars_0_slot$slot.vcfg"
        $paths += "local/cfg/user_keys_0_slot$slot.vcfg"
    }
    foreach ($path in $paths) { [pscustomobject]@{ Root = 'Account'; Path = $path } }
    [pscustomobject]@{ Root = 'Account'; Path = 'local/cfg/video.txt' }
    foreach ($path in @('autoexec.cfg', 'dota_minimap.cfg')) {
        [pscustomobject]@{ Root = 'GameCfg'; Path = $path }
    }
}

function Get-VaultHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Test-VaultFileAllowed([string]$Root, [string]$Path) {
    if (@(Get-VaultRules | Where-Object { $_.Root -ceq $Root -and $_.Path -ceq $Path }).Count) { return $true }
    if ($Path.Length -gt 220 -or $Path -match '[\\\x00-\x1f<>:"|?*]' -or $Path.StartsWith('/')) { return $false }
    foreach ($part in $Path.Split('/')) {
        if (!$part -or $part -in @('.','..') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or
            $part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') { return $false }
    }
    if ($Root -ceq 'Account') {
        if ($Path -cnotmatch '^(local|remote)/cfg/.+') { return $false }
    } elseif ($Root -cne 'GameCfg') { return $false }
    # Last-clouded files are Steam synchronization metadata, not a user profile.
    return [IO.Path]::GetExtension($Path).ToLowerInvariant() -in @('.cfg','.vcfg','.lst','.json','.txt','.kv','.vdf','.dat','.bak')
}

function Get-VaultFileDescription([string]$Path) {
    $leaf = ($Path -split '/')[-1]
    switch -Regex ($leaf) {
        '^dotakeys_personal\.lst$' { return '通用及英雄独立技能、物品等键位。' }
        '^user_convars.*\.vcfg$' { return '玩家操作与界面选项，如小地图位置、施法方式、镜头参数。' }
        '^user_keys.*\.vcfg$' { return '按键绑定；与 dotakeys_personal.lst 配合保存。' }
        'vcfg_lastclouded$' { return 'Steam 上次云同步的对照副本，不是当前设置；不参与切换。' }
        '^machine_convars.*\.vcfg$' { return '机器级选项，含镜头、音频等；跨电脑可能需要重新调整。' }
        '^video\.txt$' { return '画质、分辨率、显示模式等硬件相关设置。' }
        '\.bak$' { return '游戏或其他工具生成的旧备份，通常不是当前生效设置。' }
        '^autoexec\.cfg$' { return '启动时执行的自定义控制台命令/绑定；此安装下所有账号共用。' }
        '^dota_minimap\.cfg$' { return '小地图样式预设；实际玩家当前选项还在 user_convars 中。' }
        '^config\.cfg$' { return '旧版或自定义综合配置，可能含绑定和控制台选项。' }
        '^control_groups\.txt$' { return '单位控制编组；位于 remote/scripts，不能只备份 cfg。' }
        '^hero_grid_config\.json$' { return '自定义英雄选择网格/分组。' }
        '^hero_facet_config\.cfg$' { return '英雄命石选择偏好。' }
        '^chat\.cfg$' { return '聊天相关状态/配置，可能含频道等个人信息；非核心键位。' }
        '^herobuilds\.cfg$' { return '英雄出装/攻略选择相关配置；不是攻略文件本体。' }
        '^dota_armory_filters\.txt$' { return '军械库物品筛选偏好。' }
        '^dota_player_loadout_shuffle\.txt$' { return '饰品装备随机轮换配置。' }
        '^saved_sets\.kv$' { return '保存的饰品套装/装备组合配置。' }
        '^fantasy_crafting\.lst$' { return '梦幻挑战制作相关状态，非键位。' }
        '^challenge_selections\.cfg$' { return '挑战选择相关状态，非核心操作设置。' }
        '^(contextual_tips_history\.json|dismissed_help_tips\.txt)$' { return '已显示/已关闭的游戏教学提示记录。' }
        '^viewedheropatches\.cfg$' { return '已查看的英雄更新说明记录。' }
        '^pending_replay_requests\.lst$' { return '待处理录像请求列表，非操作设置。' }
        '^last_match\.dat$' { return '最近比赛相关状态；内部字段未解析。' }
        '^stats\.dat$' { return '本地统计状态文件；内部字段未解析，非核心键位。' }
        '^dota_player_scratchpad\.txt$' { return '玩家临时/草稿状态；具体用途未确认。' }
        '^trustedlaunch\.cfg$' { return '可信启动相关诊断记录；通常不需要随个人方案保存。' }
        '^latest_conduct_.*\.txt$' { return '账号行为评价相关缓存，通常无需保存。' }
        '^change_logs_viewed\.txt$' { return '已查看的更新日志记录。' }
        '^boot\.vcfg$' { return '游戏启动配置，属于安装级文件，不建议随玩家方案切换。' }
        '^(configdefaults\.|configschema\.|user_keys_(default|dev_default)\.)' { return '游戏自带默认值/配置定义；通常不应由个人方案覆盖。' }
        '^lan_server\.cfg$' { return '局域网服务器配置，通常不是个人操作设置。' }
        '^perftest\.cfg$' { return '性能测试配置，通常不是个人操作设置。' }
        default { return '未识别的自定义或游戏配置；用途待确认，可先打开查看内容。' }
    }
}

function Get-VaultFileCatalog {
    param([string]$AccountPath, [string]$GameCfg = '', [switch]$IncludeVideo, [switch]$IncludeGameCfg)
    $catalog = @{}
    foreach ($rule in Get-VaultRules) {
        if ($rule.Root -eq 'GameCfg' -and !$GameCfg) { continue }
        $recommended = ($rule.Path -ne 'local/cfg/video.txt' -or $IncludeVideo) -and
            ($rule.Root -ne 'GameCfg' -or $IncludeGameCfg)
        $catalog["$($rule.Root)/$($rule.Path)"] = [pscustomobject]@{ Root=$rule.Root; Path=$rule.Path; Recommended=$recommended }
    }
    $scan = @(
        @{Root='Account'; Base=$AccountPath; Prefix='local/cfg'},
        @{Root='Account'; Base=$AccountPath; Prefix='remote/cfg'}
    )
    if ($GameCfg) { $scan += @{Root='GameCfg';Base=$GameCfg;Prefix=''} }
    foreach ($location in $scan) {
        $dir = if ($location.Prefix) { Join-Path $location.Base $location.Prefix } else { $location.Base }
        if (!(Test-Path -LiteralPath $dir -PathType Container)) { continue }
        $base = [IO.Path]::GetFullPath($location.Base).TrimEnd('\','/')
        # Deliberately enumerate these cfg folders only, never the game asset tree.
        foreach ($file in Get-ChildItem -LiteralPath $dir -File -Recurse) {
            $relative = $file.FullName.Substring($base.Length+1).Replace('\','/')
            $key = "$($location.Root)/$relative"
            if (!$catalog.ContainsKey($key)) {
                $catalog[$key] = [pscustomobject]@{ Root=$location.Root; Path=$relative; Recommended=$false }
            }
        }
    }
    foreach ($entry in $catalog.Values | Sort-Object Root,Path) {
        $base = if ($entry.Root -eq 'Account') { $AccountPath } else { $GameCfg }
        $path = Resolve-VaultTarget $base $entry.Path
        $exists = [IO.File]::Exists($path)
        [pscustomobject]@{ Root=$entry.Root; Path=$entry.Path; FullPath=$path; Present=$exists
            Bytes=if($exists){(Get-Item -LiteralPath $path).Length}else{0}
            Recommended=$entry.Recommended; Selectable=(Test-VaultFileAllowed $entry.Root $entry.Path)
            Description=(Get-VaultFileDescription $entry.Path) }
    }
}

function Write-VaultAtomic([string]$Path, [byte[]]$Bytes) {
    $parent = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temp = Join-Path $parent ('.vault-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllBytes($temp, $Bytes)
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temp, $Path) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function Assert-VaultIdle([switch]$Applying) {
    $names = @('dota2')
    if ($Applying) { $names += 'steam' }
    if (@(Get-Process -Name $names -ErrorAction SilentlyContinue).Count) {
        throw '请先正常退出 Dota 2；切换或回滚前还需从托盘彻底退出 Steam。工具不会强制结束进程。'
    }
}

function Get-VaultSteamPath {
    try { (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath }
    catch { '' }
}

function Get-VaultAccounts([string]$SteamPath) {
    $userdata = Join-Path $SteamPath 'userdata'
    if (!(Test-Path -LiteralPath $userdata)) { return }
    foreach ($dir in Get-ChildItem -LiteralPath $userdata -Directory) {
        if ($dir.Name -match '^\d+$' -and (Test-Path -LiteralPath (Join-Path $dir.FullName '570'))) {
            [pscustomobject]@{ Id = $dir.Name; Path = Join-Path $dir.FullName '570' }
        }
    }
}

function Get-VaultGameCfg([string]$SteamPath) {
    $libraries = @($SteamPath)
    $vdf = Join-Path $SteamPath 'steamapps/libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
            $libraries += $match.Groups[1].Value.Replace('\\', '\')
        }
    }
    foreach ($library in $libraries | Select-Object -Unique) {
        $cfg = Join-Path $library 'steamapps/common/dota 2 beta/game/dota/cfg'
        if (Test-Path -LiteralPath $cfg) { return $cfg }
    }
    return ''
}

function Resolve-VaultTarget([string]$Root, [string]$Relative) {
    if (!$Root -or ![IO.Path]::IsPathRooted($Root)) { throw '配置根目录必须是绝对路径。' }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $path = [IO.Path]::GetFullPath((Join-Path $base $Relative))
    if (!$path.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw '配置路径越界。'
    }
    $cursor = $path
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "不支持符号链接或目录联接：$cursor"
            }
        }
        $cursor = Split-Path -Parent $cursor
    }
    return $path
}

function Assert-VaultSnapshot($Snapshot) {
    if ($Snapshot.Schema -ne 1 -or $Snapshot.Id -cnotmatch '^[a-f0-9]{32}$' -or
        [string]::IsNullOrWhiteSpace($Snapshot.Name) -or $Snapshot.Name.Length -gt 80) { throw '备份格式不受支持。' }
    $seen = @{}
    $total = 0
    if (@($Snapshot.Files).Count -lt 1 -or @($Snapshot.Files).Count -gt 1000) { throw '备份文件数量无效。' }
    foreach ($entry in $Snapshot.Files) {
        $key = "$($entry.Root)/$($entry.Path)"
        if (!(Test-VaultFileAllowed $entry.Root $entry.Path) -or $seen.ContainsKey($key) -or $entry.Present -isnot [bool]) {
            throw "备份包含重复或未授权的路径：$key"
        }
        $seen[$key] = $true
        if ($entry.Present) {
            if ($entry.Data.Length -gt 2800000) { throw '单个配置文件过大。' }
            $bytes = [Convert]::FromBase64String($entry.Data)
            $total += $bytes.Length
            if ((Get-VaultHash $bytes) -cne $entry.Sha256) { throw "文件校验失败：$key" }
        }
    }
    if ($total -gt 8000000) { throw '备份总大小超过限制。' }
}

function Read-VaultSnapshot([string]$Path) {
    if ((Get-Item -LiteralPath $Path).Length -gt 12000000) { throw '备份文件过大。' }
    $snapshot = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
    Assert-VaultSnapshot $snapshot
    return $snapshot
}

function New-VaultSnapshot {
    param([string]$Name, [string]$AccountPath, [string]$GameCfg = '', [switch]$IncludeVideo, $Rules, [switch]$AllowEmpty)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 80) { throw '方案名称需为 1–80 个字符。' }
    if (!(Test-Path -LiteralPath $AccountPath -PathType Container)) { throw 'Steam 账号配置目录不存在。' }
    if (!$Rules) {
        $Rules = @(Get-VaultRules | Where-Object {
            ($_.Root -ne 'GameCfg' -or $GameCfg) -and ($_.Path -ne 'local/cfg/video.txt' -or $IncludeVideo)
        })
    }
    $files = @(foreach ($rule in $Rules) {
        if (!(Test-VaultFileAllowed $rule.Root $rule.Path)) { throw '不允许保存该路径或文件类型。' }
        $root = if ($rule.Root -eq 'Account') { $AccountPath } else { $GameCfg }
        $path = Resolve-VaultTarget $root $rule.Path
        $exists = [IO.File]::Exists($path)
        if ($exists -and (Get-Item -LiteralPath $path).Length -gt 2000000) { throw "单个配置文件超过 2 MB：$($rule.Path)" }
        $bytes = [byte[]]@()
        if ($exists) { $bytes = [IO.File]::ReadAllBytes($path) }
        [pscustomobject]@{ Root = $rule.Root; Path = $rule.Path; Present = $exists
            Sha256 = if ($exists) { Get-VaultHash $bytes } else { '' }
            Data = if ($exists) { [Convert]::ToBase64String($bytes) } else { '' } }
    })
    if (!$AllowEmpty -and !@($files | Where-Object Present).Count) { throw '没有找到可保存的设置文件。' }
    $snapshot = [pscustomobject]@{ Schema = 1; Id = [guid]::NewGuid().ToString('N'); Name = $Name
        CreatedUtc = [DateTime]::UtcNow.ToString('o'); Files = $files }
    Assert-VaultSnapshot $snapshot
    return $snapshot
}

function Save-VaultSnapshot($Snapshot, [string]$Directory) {
    Assert-VaultSnapshot $Snapshot
    $path = Join-Path $Directory ($Snapshot.Id + '.json')
    if (Test-Path -LiteralPath $path) { throw '该版本已存在；历史版本不可覆盖。' }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Snapshot | ConvertTo-Json -Depth 8))
    Write-VaultAtomic $path $bytes
    return $path
}

function Save-VaultProfile {
    param([string]$Name, [string]$AccountPath, [string]$Directory, [string]$GameCfg = '', [switch]$IncludeVideo, $Rules)
    Assert-VaultIdle
    $snapshot = New-VaultSnapshot -Name $Name -AccountPath $AccountPath -GameCfg $GameCfg -IncludeVideo:$IncludeVideo -Rules $Rules
    # Reject a mixed snapshot if the game/cloud writes while we are copying.
    foreach ($entry in $snapshot.Files) {
        $root = if ($entry.Root -eq 'Account') { $AccountPath } else { $GameCfg }
        $target = Resolve-VaultTarget $root $entry.Path
        if ([IO.File]::Exists($target) -ne $entry.Present) { throw '保存期间配置发生变化，请等待 Steam 同步完成后重试。' }
        if ($entry.Present -and (Get-VaultHash ([IO.File]::ReadAllBytes($target))) -ne $entry.Sha256) {
            throw '保存期间配置发生变化，请重试。'
        }
    }
    Assert-VaultIdle
    Save-VaultSnapshot $snapshot $Directory
}

function Get-VaultChanges($Snapshot, [string]$AccountPath, [string]$GameCfg = '') {
    Assert-VaultSnapshot $Snapshot
    foreach ($entry in $Snapshot.Files) {
        $root = if ($entry.Root -eq 'Account') { $AccountPath } else { $GameCfg }
        $path = Resolve-VaultTarget $root $entry.Path
        $exists = [IO.File]::Exists($path)
        $action = '不变'
        if ($entry.Present -and (!$exists -or (Get-VaultHash ([IO.File]::ReadAllBytes($path))) -ne $entry.Sha256)) { $action = '写入' }
        if (!$entry.Present -and $exists) { $action = '移除' }
        [pscustomobject]@{ Action = $action; File = "$($entry.Root)/$($entry.Path)" }
    }
}

function Write-VaultSnapshotFiles($Snapshot, [string]$AccountPath, [string]$GameCfg) {
    foreach ($entry in $Snapshot.Files) {
        $root = if ($entry.Root -eq 'Account') { $AccountPath } else { $GameCfg }
        $path = Resolve-VaultTarget $root $entry.Path
        if ($entry.Present) { Write-VaultAtomic $path ([Convert]::FromBase64String($entry.Data)) }
        elseif ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
    }
    if (@(Get-VaultChanges $Snapshot $AccountPath $GameCfg | Where-Object Action -ne '不变').Count) {
        throw '写入后的文件校验失败。'
    }
}

function Restore-VaultProfile {
    param([string]$SnapshotPath, [string]$AccountPath, [string]$GameCfg = '',
        [string]$BackupDirectory, [switch]$CloudDisabled)
    if (!$CloudDisabled) { throw '请先在 Steam → Dota 2 → 属性 → 通用中关闭此游戏的 Steam 云同步，再勾选确认。' }
    Assert-VaultIdle -Applying
    $snapshot = Read-VaultSnapshot $SnapshotPath
    Get-VaultChanges $snapshot $AccountPath $GameCfg | Out-Null
    $rollback = New-VaultSnapshot -Name ('切换前备份 ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) `
        -AccountPath $AccountPath -GameCfg $GameCfg -Rules $snapshot.Files -AllowEmpty
    $backup = Save-VaultSnapshot $rollback $BackupDirectory
    Assert-VaultIdle -Applying
    try { Write-VaultSnapshotFiles $snapshot $AccountPath $GameCfg }
    catch {
        $reason = $_.Exception.Message
        try { Write-VaultSnapshotFiles $rollback $AccountPath $GameCfg }
        catch { throw "切换失败，自动回滚也失败。请勿启动游戏。备份：$backup。原错误：$reason；回滚错误：$($_.Exception.Message)" }
        throw "切换失败，已自动回滚。原因：$reason"
    }
    return $backup
}

function Invoke-VaultGh([string[]]$Arguments) {
    $gh = (Get-Command gh -ErrorAction Stop).Source
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $gh @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "GitHub 操作失败：$($output -join [Environment]::NewLine)" }
    return ($output -join "`n")
}

function Assert-VaultRepo([string]$Repository) {
    if ($Repository -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$' -or $Repository.Split('/')[1] -in @('.', '..')) {
        throw '仓库请填写 用户名/仓库名，例如 abcdexyz64/dota2-settings-backup。'
    }
}

function New-VaultRepository([string]$Repository) {
    Assert-VaultRepo $Repository
    Invoke-VaultGh @('repo', 'create', $Repository, '--private', '--description', 'Personal Dota 2 settings snapshots')
}

function Send-VaultProfile([string]$SnapshotPath, [string]$Repository) {
    Assert-VaultRepo $Repository
    $snapshot = Read-VaultSnapshot $SnapshotPath
    $repo = Invoke-VaultGh @('api', "repos/$Repository") | ConvertFrom-Json
    if (!$repo.private) { throw '个人配置只允许上传到私有仓库。请使用私有仓库。' }
    $bytes = [IO.File]::ReadAllBytes($SnapshotPath)
    # GitHub Contents API has a 1 MB content-read limit; keep round trips within it.
    if ($bytes.Length -gt 900000) { throw '此备份超过 GitHub 单快照上传上限 900 KB；请减少自定义配置大小。' }
    $body = @{ message = "Save Dota settings $($snapshot.Id)"; content = [Convert]::ToBase64String($bytes) } | ConvertTo-Json
    $temp = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($temp, $body, (New-Object Text.UTF8Encoding $false))
        $endpoint = "repos/$Repository/contents/backups/$($snapshot.Id).json"
        try { Invoke-VaultGh @('api', '--method', 'PUT', $endpoint, '--input', $temp) | Out-Null }
        catch {
            $reason = $_
            $existing = Invoke-VaultGh @('api', $endpoint) | ConvertFrom-Json
            if ((Get-VaultHash ([Convert]::FromBase64String($existing.content))) -ne (Get-VaultHash $bytes)) { throw $reason }
        }
    } finally { [IO.File]::Delete($temp) }
    return "https://github.com/$Repository"
}

function Receive-VaultProfiles([string]$Repository, [string]$Directory) {
    Assert-VaultRepo $Repository
    $repo = Invoke-VaultGh @('api', "repos/$Repository") | ConvertFrom-Json
    $branch = [Uri]::EscapeDataString($repo.default_branch)
    $tree = Invoke-VaultGh @('api', "repos/$Repository/git/trees/${branch}?recursive=1") | ConvertFrom-Json
    if ($tree.truncated) { throw '仓库目录过大，GitHub 返回了截断列表，未开始导入。' }
    $count = 0
    foreach ($item in $tree.tree) {
        if ($item.type -ne 'blob' -or $item.path -cnotmatch '^backups/([a-f0-9]{32})\.json$') { continue }
        $id = $Matches[1]
        if ($item.size -gt 900000) { throw "云端备份过大：$id" }
        # Read immutable blob SHAs so a concurrent push cannot change this download.
        $blob = Invoke-VaultGh @('api', "repos/$Repository/git/blobs/$($item.sha)") | ConvertFrom-Json
        $bytes = [Convert]::FromBase64String($blob.content)
        $snapshot = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
        Assert-VaultSnapshot $snapshot
        if ($snapshot.Id -cne $id) { throw '云端文件名与备份 ID 不一致。' }
        $path = Join-Path $Directory ($id + '.json')
        if (Test-Path -LiteralPath $path) {
            if ((Get-VaultHash ([IO.File]::ReadAllBytes($path))) -ne (Get-VaultHash $bytes)) { throw '相同 ID 的本地和云端版本不同，已保留本地版本。' }
        } else { Write-VaultAtomic $path $bytes; $count++ }
    }
    return $count
}

Export-ModuleMember -Function Get-VaultSteamPath, Get-VaultAccounts, Get-VaultGameCfg, Get-VaultRules, `
    Read-VaultSnapshot, Save-VaultProfile, Restore-VaultProfile, Get-VaultChanges, `
    New-VaultRepository, Send-VaultProfile, Receive-VaultProfiles, Get-VaultFileCatalog
