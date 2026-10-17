# Dota 设置保险箱

Windows 中文小工具，保存与切换 Dota 2 的个人键位、界面和操作设置。零运行依赖：本地功能使用系统自带 Windows PowerShell 5.1 / WinForms。GitHub 功能需要 [GitHub CLI](https://cli.github.com/)。

## 开始使用

双击 **Start.cmd**。不需要管理员权限。

1. 游戏中调好自己的键位、小地图位置等，然后正常退出 Dota 2，等待 Steam 云同步结束。
2. 打开工具，选择正确的 Steam 账号目录 ID（不是昵称）。多个账号时不会自动猜选。
3. 输入方案名，例如「小明·左小地图」，点击 **保存当前设置**。
4. 另一位玩家调好设置、退出游戏后，用另一个方案名保存。相同名称再次保存也会生成新版本。
5. 要切换时：Steam → 库 → Dota 2 → 属性 → 通用，关闭该游戏的 Steam 云同步，然后从托盘正常退出 Steam。
6. 选中保存的方案，勾选已关闭云同步，先 **预览更改**，再 **切换 / 恢复所选方案**。工具自动备份原设置、写入、校验。
7. 启动 Steam 和 Dota 2，检查键位和小地图位置。需要撤销时，退出 Steam 和游戏，在列表中选「切换前自动备份」恢复。

关闭窗口并不等于退出 Steam。工具遇到仍在运行的 Steam 会拒绝切换，不会强杀进程。

## 保存哪些内容

从 `Steam/userdata/<账号目录>/570` 按固定白名单保存：

- `remote/cfg/dotakeys_personal.lst`：通用和英雄独立键位。
- `remote/user_convars.vcfg`、`remote/user_keys.vcfg`：远端缓存的操作设置和绑定。
- `local/cfg/user_convars_0_slot0..3.vcfg`、`user_keys_0_slot0..3.vcfg`：本地设置和绑定。小地图位置等设置在 convars 中。
- `local/cfg/machine_convars.vcfg`：镜头边缘移动等机器级选项；也可能包含硬件相关设置，跨电脑切换后请检查。
- `remote/cfg/config.cfg`（旧版兼容）、英雄网格、命石偏好、控制编组。
- 可选：`local/cfg/video.txt`，默认不保存画质和分辨率。
- 默认包含、可取消：游戏 `game/dota/cfg` 下的 `autoexec.cfg` 和 `dota_minimap.cfg`。这些文件在同一游戏安装内由所有账号共用。

完整保留文件原始字节、编码及换行。不会只替换一个键位列表，也不会硬编码当前版本的“小地图左右”数值。

未保存聊天记录、好友、登录信息、饰品数据、屏蔽名单、Steam 登录令牌或 `remotecache.vdf`。不修改 `*.vcfg_lastclouded` 同步状态文件。Steam 启动参数、外部脚本、autoexec 通过 exec 引用的其他文件和自定义英雄攻略暂不包含。autoexec 是游戏命令，恢复云端方案前应确认它是自己的可信备份。

**方案内记录为“不存在”的白名单文件，在切换时会移除目标上的同名文件**，避免混入另一位玩家残留的编组、键位或 autoexec。移除前也会备份。方案范围外的文件不变；不含画质的方案不会移除画质文件。

## Steam 云同步边界

Dota 2 同时有本地文件、Steam 云和游戏运行时状态。外部脚本不能保证在云同步开启时战胜旧云端副本。因此切换必须关闭该游戏的 Steam 云同步，并在 Steam / Dota 2 都退出时执行。勾选框是用户确认，程序不会假装已经自动检测到云开关。

频繁共用账号时建议保持此游戏云同步关闭，由本工具和 GitHub 管理方案。以后重新打开云同步时，先再保存一次当前正确设置；若 Steam 提示冲突，需要自行核对时间并选择正确的本地设置。不同客户端版本的冲突流程可能不同，本工具不修改 Steam 云元数据来伪造同步成功。

## 使用自己的 GitHub

1. 安装 GitHub CLI 后重新打开工具，点击 **登录自己的 GitHub**，按浏览器授权流程登录自己的账号。也可在终端运行 `gh auth login`；切换已登录账号可用 `gh auth switch`。
2. 填写 `你的用户名/dota2-settings-backup`。已有可写私有仓库可直接用；否则点击 **新建私有备份仓库**。
3. 选中一个本地方案，点击 **上传所选方案**。每个版本保存为仓库 `backups/<版本ID>.json`，包含原文件字节和 SHA-256。重复上传同一版本不会覆盖其他版本。
4. 换电脑后登录自己的 GitHub，填同一个仓库，点击 **下载云端方案**，再选择新电脑的 Steam 账号并切换。下载不会自动应用设置。

仅允许上传至私有仓库。凭据交给 GitHub CLI 管理，程序不读取或保存 token。支持自己的仓库或自己有写权限的私有组织仓库。上传不需要 Git；快照上限 900 KB。空仓库尚无备份时，先上传一个方案再下载。

**程序源码仓库与个人备份仓库分开。** 本项目 `.gitignore` 排除 `data/`，公开分享源码不会顺带提交键位。快照不是加密容器：拥有备份仓库访问权的人可以读取设置及 autoexec 中的文本。

## 数据、迁移和命令行

`data/profiles/` 为个人版本，`data/rollback/` 为自动回滚版本，`data/preferences.json` 仅保存仓库名称。复制整个工具文件夹即可迁移本地库；GitHub 只上传你选中的版本，不会自动上传所有账号或回滚记录。

```powershell
.\DotaSettings.ps1 -Action List
.\DotaSettings.ps1 -Action Save -Name '我的设置' -AccountId '你的数字目录ID'
.\DotaSettings.ps1 -Action Preview -AccountId '你的数字目录ID' -Snapshot 'C:\备份\版本.json'
.\DotaSettings.ps1 -Action Apply -AccountId '你的数字目录ID' -Snapshot 'C:\备份\版本.json' -CloudDisabled
.\DotaSettings.ps1 -Action Upload -Snapshot 'C:\备份\版本.json' -Repository '用户/仓库'
.\DotaSettings.ps1 -Action Download -Repository '用户/仓库'
```

支持 `-SteamPath`、`-GameCfg`、`-DataDirectory` 自定义路径。执行策略阻止脚本时使用 Start.cmd，或 `powershell -NoProfile -ExecutionPolicy Bypass -File .\DotaSettings.ps1`。

## 验证

运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run.Tests.ps1`。测试使用临时模拟目录，不切换真实账号；覆盖保存/切换/回滚、缺失文件、损坏备份、路径限制、写入失败回滚和 GitHub API 模拟往返。GUI 冒烟可用 `DotaSettings.ps1 -SmokeTest -DataDirectory <临时绝对路径>`。

真实游戏内是否生效需要在退出 Steam、关闭云同步后完成一次切换并启动游戏核对；文件级验证不代表已验证 Steam 云端或游戏运行时状态。
