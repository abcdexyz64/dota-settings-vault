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
    $allowed = @{}
    foreach ($rule in Get-VaultRules) { $allowed["$($rule.Root)/$($rule.Path)"] = $true }
    $seen = @{}
    $total = 0
    if (@($Snapshot.Files).Count -lt 1 -or @($Snapshot.Files).Count -gt $allowed.Count) { throw '备份文件数量无效。' }
    foreach ($entry in $Snapshot.Files) {
        $key = "$($entry.Root)/$($entry.Path)"
        if (!$allowed.ContainsKey($key) -or $seen.ContainsKey($key) -or $entry.Present -isnot [bool]) {
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
        $root = if ($rule.Root -eq 'Account') { $AccountPath } else { $GameCfg }
        $path = Resolve-VaultTarget $root $rule.Path
        $exists = [IO.File]::Exists($path)
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
    param([string]$Name, [string]$AccountPath, [string]$Directory, [string]$GameCfg = '', [switch]$IncludeVideo)
    Assert-VaultIdle
    $snapshot = New-VaultSnapshot -Name $Name -AccountPath $AccountPath -GameCfg $GameCfg -IncludeVideo:$IncludeVideo
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
    New-VaultRepository, Send-VaultProfile, Receive-VaultProfiles
