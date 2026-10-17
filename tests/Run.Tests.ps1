$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $project 'Vault.Core.psm1') -Force
$root=Join-Path $project ('test-output/' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$module=Get-Module Vault.Core
& $module {
    param($root)
    $script:passed=0
    function Check($condition,$message) {
        if (!$condition) { throw "FAIL: $message" }
        $script:passed++; Write-Host "PASS: $message"
    }
    function Throws($work,$message) {
        $caught=$false
        try { & $work | Out-Null } catch { $caught=$true }
        Check $caught $message
    }
    function Put($path,$text) { Write-VaultAtomic $path ([Text.Encoding]::UTF8.GetBytes($text)) }
    $script:running=@()
    function Get-Process { param($Name,$ErrorAction) foreach ($n in $Name) { if ($n -in $script:running) { [pscustomobject]@{Name=$n} } } }
    $a=Join-Path $root 'steam/userdata/111/570'
    $b=Join-Path $root 'steam/userdata/222/570'
    $game=Join-Path $root 'game/cfg'
    $profiles=Join-Path $root 'profiles'
    $rollback=Join-Path $root 'rollback'
    foreach ($p in @($a,$b,$game,$profiles,$rollback)) { [IO.Directory]::CreateDirectory($p) | Out-Null }
    $local='local/cfg/user_convars_0_slot0.vcfg'
    $remote='remote/user_convars.vcfg'
    $keys='remote/cfg/dotakeys_personal.lst'
    Put (Join-Path $a $local) '"dota_minimap_position_option" "1"'
    Put (Join-Path $a $remote) '"dota_minimap_position_option" "1"'
    Put (Join-Path $a $keys) '中文键位 A'
    Put (Join-Path $a 'local/cfg/video.txt') 'video A'
    Put (Join-Path $a 'remote/cfg/config.cfg') ''
    Put (Join-Path $game 'autoexec.cfg') 'bind X +attack'
    $first=Save-VaultProfile -Name '小明·左侧' -AccountPath $a -Directory $profiles -GameCfg $game
    $s=Read-VaultSnapshot $first
    Check (@($s.Files | Where-Object Path -eq 'local/cfg/video.txt').Count -eq 0) 'video excluded by default'
    Check (@($s.Files | Where-Object Path -eq $local).Count -eq 1) 'local minimap settings captured'
    Check (@($s.Files | Where-Object Path -eq $remote).Count -eq 1) 'remote minimap settings captured'
    Check (@($s.Files | Where-Object { $_.Path -eq 'remote/cfg/config.cfg' -and $_.Present -and $_.Data -eq '' }).Count -eq 1) 'empty configuration captured'
    $second=Save-VaultProfile -Name '小明·左侧' -AccountPath $a -Directory $profiles -GameCfg $game
    Check ($second -ne $first) 'saving same name preserves history'
    Put (Join-Path $b $local) '"dota_minimap_position_option" "2"'
    Put (Join-Path $b $keys) 'keys B'
    Put (Join-Path $b 'remote/scripts/control_groups.txt') 'extra group'
    Put (Join-Path $b 'remote/favorite_friends.json') 'private friends'
    Put (Join-Path $b 'local/cfg/video.txt') 'video B'
    $before=[IO.File]::ReadAllText((Join-Path $b $local))
    Throws { Restore-VaultProfile $first $b $game $rollback } 'requires cloud confirmation'
    $script:running=@('steam')
    Throws { Restore-VaultProfile $first $b $game $rollback -CloudDisabled } 'blocks apply while Steam runs'
    $script:running=@('dota2')
    Throws { Save-VaultProfile -Name 'running' -AccountPath $a -Directory $profiles } 'blocks save while game runs'
    $script:running=@()
    $backup=Restore-VaultProfile $first $b $game $rollback -CloudDisabled
    Check ([IO.File]::ReadAllText((Join-Path $b $local)) -eq '"dota_minimap_position_option" "1"') 'switch applies minimap'
    Check ([IO.File]::ReadAllText((Join-Path $b $keys)) -eq '中文键位 A') 'byte-preserving Chinese keys'
    Check (!(Test-Path (Join-Path $b 'remote/scripts/control_groups.txt'))) 'absent managed file removed'
    Check ([IO.File]::ReadAllText((Join-Path $b 'local/cfg/video.txt')) -eq 'video B') 'excluded video preserved'
    Check ([IO.File]::ReadAllText((Join-Path $b 'remote/favorite_friends.json')) -eq 'private friends') 'unmanaged private files preserved'
    Restore-VaultProfile $backup $b $game $rollback -CloudDisabled | Out-Null
    Check ([IO.File]::ReadAllText((Join-Path $b $local)) -eq $before) 'rollback restores original minimap'
    Check ([IO.File]::ReadAllText((Join-Path $b 'remote/scripts/control_groups.txt')) -eq 'extra group') 'rollback restores deleted file'
    Check (!(Test-Path (Join-Path $b $remote))) 'rollback removes newly created file'
    $corrupt=Read-VaultSnapshot $first
    $corrupt.Files[0].Sha256='bad'
    Throws { Assert-VaultSnapshot $corrupt } 'rejects hash mismatch'
    $evil=Read-VaultSnapshot $first
    $evil.Files[0].Path='../outside.txt'
    Throws { Assert-VaultSnapshot $evil } 'rejects traversal'
    $evil=Read-VaultSnapshot $first
    $evil.Files += $evil.Files[0]
    Throws { Assert-VaultSnapshot $evil } 'rejects duplicate path'
    $badPath=Join-Path $root 'bad.json'
    Put $badPath ($corrupt | ConvertTo-Json -Depth 8)
    Throws { Restore-VaultProfile $badPath $b $game $rollback -CloudDisabled } 'corrupt snapshot rejected before writes'
    Check ([IO.File]::ReadAllText((Join-Path $b $local)) -eq $before) 'failed validation leaves target intact'
    # Fail exactly once after at least one target file was written, then allow rollback.
    $originalWriter=${function:Write-VaultAtomic}
    $script:injected=$false
    function Write-VaultAtomic([string]$Path,[byte[]]$Bytes) {
        if (!$script:injected -and $Path -eq (Join-Path $b $remote)) { $script:injected=$true; throw 'injected disk failure' }
        & $originalWriter $Path $Bytes
    }
    Throws { Restore-VaultProfile $first $b $game $rollback -CloudDisabled } 'write failure reported'
    Check $script:injected 'failure injection executed'
    Check ([IO.File]::ReadAllText((Join-Path $b $keys)) -eq 'keys B') 'partial write automatically rolled back'
    ${function:Write-VaultAtomic}=$originalWriter
    $empty=Join-Path $root 'empty-account'
    [IO.Directory]::CreateDirectory($empty) | Out-Null
    $emptyBackup=Restore-VaultProfile $first $empty $game $rollback -CloudDisabled
    Restore-VaultProfile $emptyBackup $empty $game $rollback -CloudDisabled | Out-Null
    Check (!(Test-Path (Join-Path $empty $keys))) 'empty destination can be restored and undone'
    $script:cloudBytes=$null
    $script:isPrivate=$true
    $script:rejectPut=$false
    function Invoke-VaultGh([string[]]$Arguments) {
        $joined=$Arguments -join ' '
        if ($joined -match '^api repos/test/settings$') { return (@{private=$script:isPrivate;default_branch='main'} | ConvertTo-Json) }
        if ($joined -match '--method PUT') {
            if ($script:rejectPut) { throw 'already exists' }
            $body=[IO.File]::ReadAllText($Arguments[-1]) | ConvertFrom-Json
            $script:cloudBytes=[Convert]::FromBase64String($body.content)
            return '{}'
        }
        if ($joined -match '/contents/backups/') { return (@{content=[Convert]::ToBase64String($script:cloudBytes)} | ConvertTo-Json) }
        if ($joined -match '/git/trees/') { return (@{truncated=$false;tree=@(@{type='blob';path="backups/$($s.Id).json";sha='testsha';size=$script:cloudBytes.Length})} | ConvertTo-Json -Depth 8) }
        if ($joined -match '/git/blobs/') { return (@{content=[Convert]::ToBase64String($script:cloudBytes)} | ConvertTo-Json) }
        throw "Unexpected mock call: $joined"
    }
    $script:isPrivate=$false
    Throws { Send-VaultProfile $first 'test/settings' } 'public repository upload refused'
    $script:isPrivate=$true
    Send-VaultProfile $first 'test/settings' | Out-Null
    Check ((Get-VaultHash $script:cloudBytes) -eq (Get-VaultHash ([IO.File]::ReadAllBytes($first)))) 'upload transports exact snapshot bytes'
    $script:rejectPut=$true
    Send-VaultProfile $first 'test/settings' | Out-Null
    Check $true 'repeat upload is idempotent'
    $download=Join-Path $root 'download'
    $count=Receive-VaultProfiles 'test/settings' $download
    Check ($count -eq 1) 'download imports snapshot'
    Check ((Receive-VaultProfiles 'test/settings' $download) -eq 0) 'repeat download is idempotent'
    $restored=Read-VaultSnapshot (Join-Path $download ($s.Id+'.json'))
    Check ($restored.Name -eq $s.Name) 'Chinese name survives cloud round trip'
    Put (Join-Path $download ($s.Id+'.json')) '{}'
    Throws { Receive-VaultProfiles 'test/settings' $download } 'download refuses local version collision'
    Throws { Assert-VaultRepo 'https://github.com/x/y' } 'repository format validated'
    Check (@(Get-VaultAccounts (Join-Path $root 'steam')).Count -eq 2) 'multiple accounts discovered'
    Put (Join-Path $a 'remote/cfg/custom_extra.cfg') 'bind Z custom_command'
    Put (Join-Path $a 'local/cfg/user_keys_0_slot0.vcfg_lastclouded') 'cloud baseline'
    Put (Join-Path $game 'boot.vcfg') 'engine boot'
    $catalog=@(Get-VaultFileCatalog -AccountPath $a -GameCfg $game -IncludeGameCfg)
    $custom=@($catalog | Where-Object Path -eq 'remote/cfg/custom_extra.cfg')[0]
    Check ($custom.Selectable -and !$custom.Recommended) 'custom cfg visible but not selected by default'
    Check ($custom.Description -match '用途待确认') 'unknown file description is explicit'
    Check (!@($catalog | Where-Object Path -like '*lastclouded')[0].Selectable) 'cloud metadata visible but not selectable'
    Check (@($catalog | Where-Object Path -eq 'remote/user_convars.vcfg').Count -eq 1) 'catalog includes key settings outside cfg'
    Check (@($catalog | Where-Object Path -eq 'boot.vcfg').Count -eq 1) 'catalog includes shared game cfg files'
    $customProfile=Save-VaultProfile -Name '高级自选' -AccountPath $a -Directory $profiles -Rules @([pscustomobject]@{Root='Account';Path='remote/cfg/custom_extra.cfg'})
    $customSnapshot=Read-VaultSnapshot $customProfile
    Check (@($customSnapshot.Files).Count -eq 1) 'advanced capture contains only selected file'
    $priorKeys=[IO.File]::ReadAllText((Join-Path $b $keys))
    $customBackup=Restore-VaultProfile $customProfile $b '' $rollback -CloudDisabled
    Check ([IO.File]::ReadAllText((Join-Path $b 'remote/cfg/custom_extra.cfg')) -eq 'bind Z custom_command') 'custom cfg restoration works'
    Check ([IO.File]::ReadAllText((Join-Path $b $keys)) -eq $priorKeys) 'advanced restore leaves unselected keys unchanged'
    Restore-VaultProfile $customBackup $b '' $rollback -CloudDisabled | Out-Null
    Check (!(Test-Path (Join-Path $b 'remote/cfg/custom_extra.cfg'))) 'custom cfg rollback restores absence'
    Check (!(Test-VaultFileAllowed 'Account' 'remote/cfg/../loginusers.vdf')) 'advanced paths cannot escape cfg'
    Check (!(Test-VaultFileAllowed 'Account' 'remote/cfg/evil.ps1')) 'executable scripts outside config formats rejected'
    Check (!(Test-VaultFileAllowed 'Account' 'remote/cfg/CON.txt')) 'reserved Windows devices rejected'
    Write-Host "ALL $script:passed TESTS PASSED"
} $root
