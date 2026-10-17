function Export-VaultPackage([string]$SnapshotPath,[string]$Destination) {
    $s=Read-VaultSnapshot $SnapshotPath
    if (![IO.Path]::IsPathRooted($Destination)) { throw '请选择绝对路径作为保存位置。' }
    $safe=[regex]::Replace($s.Name,'[\\/:*?"<>|\x00-\x1f]','_').Trim('.',' ')
    if($safe.Length -gt 36){$safe=$safe.Substring(0,36)}
    $folder=Join-Path $Destination ('泉印-'+$safe+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    foreach($entry in $s.Files){
        if($entry.Present){
            $root=Join-Path $folder $entry.Root
            $target=Resolve-VaultTarget $root $entry.Path
            Write-VaultAtomic $target ([Convert]::FromBase64String($entry.Data))
        }
    }
    Write-VaultAtomic (Join-Path $folder 'backup.json') ([IO.File]::ReadAllBytes($SnapshotPath))
    $instructions="泉印 · Dota 2 配置管家`r`n`r`n将整个文件夹拖入泉印即可导入。Account 是账号设置，GameCfg 是游戏共用配置。`r`nbackup.json 是导出时的完整快照；直接导入它会恢复导出时的内容。`r`n导入整个文件夹时，读取清单内对应的原始文件（允许你先编辑这些文件）。不要删除清单中的原文件。`r`n新增但不在清单里的文件需单独导入；不会自动执行配置中的任何命令。`r`n此文件夹可能含个人绑定文本，请自行决定是否分享。"
    Write-VaultAtomic (Join-Path $folder '使用说明.txt') ([Text.Encoding]::UTF8.GetBytes($instructions))
    return $folder
}

function Import-VaultInput {
    param([string]$Path,[string]$Directory,[string]$TargetRoot='', [string]$TargetPath='',
        [ValidateSet('','Account570','LocalCfg','RemoteCfg','GameCfg')][string]$FolderScope='')
    $Path=[IO.Path]::GetFullPath($Path.Trim('"'))
    $item=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '不支持从符号链接导入。'}
    if(!$item.PSIsContainer -and $item.Extension -eq '.json'){
        try{$object=[IO.File]::ReadAllText($Path) | ConvertFrom-Json}catch{$object=$null}
        if($null -ne $object -and $object.PSObject.Properties['Schema']){
            $s=Read-VaultSnapshot $Path
            $existing=Join-Path $Directory ($s.Id+'.json')
            if(Test-Path -LiteralPath $existing){
                if((Get-VaultHash ([IO.File]::ReadAllBytes($existing))) -eq (Get-VaultHash ([IO.File]::ReadAllBytes($Path)))){return $existing}
                # Different encoding of the same ID must not silently replace history.
                $s.Id=[guid]::NewGuid().ToString('N')
            }
            return Save-VaultSnapshot $s $Directory
        }
    }
    $entries=@(); $name='导入 · '+$item.Name
    if($item.PSIsContainer -and (Test-Path -LiteralPath (Join-Path $Path 'backup.json'))){
        $manifest=Read-VaultSnapshot (Join-Path $Path 'backup.json')
        $name='导入 · '+$manifest.Name
        foreach($entry in $manifest.Files){
            $source=Resolve-VaultTarget (Join-Path $Path $entry.Root) $entry.Path
            if($entry.Present -and ![IO.File]::Exists($source)){throw "备份文件夹缺少文件：$($entry.Root)/$($entry.Path)。如需恢复原快照，可直接导入 backup.json。"}
            $entries+=@{Root=$entry.Root;Path=$entry.Path;Source=$source;Present=[IO.File]::Exists($source)}
        }
    } elseif($item.PSIsContainer){
        if(!$FolderScope){throw '普通文件夹需要明确指定它对应账号 570、local/cfg、remote/cfg 还是游戏 cfg。'}
        $root=if($FolderScope -eq 'GameCfg'){'GameCfg'}else{'Account'}
        $prefix=switch($FolderScope){LocalCfg{'local/cfg/'} RemoteCfg{'remote/cfg/'} default{''}}
        $base=$Path.TrimEnd('\','/')
        foreach($file in Get-ChildItem -LiteralPath $Path -File -Recurse){
            $rel=$file.FullName.Substring($base.Length+1).Replace('\','/')
            $target=$prefix+$rel
            if(Test-VaultFileAllowed $root $target){
                $source=Resolve-VaultTarget $Path $rel
                $entries+=@{Root=$root;Path=$target;Source=$source;Present=$true}
            }
        }
    }else{
        if(!$TargetRoot -or !$TargetPath){
            $rules=@(Get-VaultRules | Where-Object {($_.Path -split '/')[-1] -eq $item.Name})
            if($rules.Count -ne 1){throw '此文件无法唯一判断安装位置，请指定目标目录和相对文件名。'}
            $TargetRoot=$rules[0].Root; $TargetPath=$rules[0].Path
        }
        if(!(Test-VaultFileAllowed $TargetRoot $TargetPath)){throw '目标配置路径或文件类型不受支持。'}
        $entries+=@{Root=$TargetRoot;Path=$TargetPath;Source=$Path;Present=$true}
    }
    if(!$entries.Count){throw '没有找到可导入的配置文件。'}
    $totalBytes=0
    $files=@(foreach($e in $entries){
        $bytes=[byte[]]@()
        if($e.Present){
            $length=(Get-Item -LiteralPath $e.Source).Length
            if($length -gt 2000000){throw '单个配置超过 2 MB。'}
            $totalBytes+=$length;if($totalBytes -gt 8000000){throw '导入内容总大小超过 8 MB。'}
            $bytes=[IO.File]::ReadAllBytes($e.Source)
        }
        [pscustomobject]@{Root=$e.Root;Path=$e.Path;Present=[bool]$e.Present;Data=[Convert]::ToBase64String($bytes);Sha256=if($e.Present){Get-VaultHash $bytes}else{''}}
    })
    if($name.Length -gt 80){$name=$name.Substring(0,80)}
    $s=[pscustomobject]@{Schema=1;Id=[guid]::NewGuid().ToString('N');Name=$name;CreatedUtc=[DateTime]::UtcNow.ToString('o');Files=$files}
    return Save-VaultSnapshot $s $Directory
}
