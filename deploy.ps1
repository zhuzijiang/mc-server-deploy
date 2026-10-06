<#
.SYNOPSIS
    Minecraft Java 版服务器一键部署（Windows）

.DESCRIPTION
    自动完成：安装 Java → 下载服务端 → 写配置 → 生成启动脚本 → 启动。
    支持 Paper / Vanilla / Fabric / NeoForge / Forge，覆盖 MC 1.7.10 ~ 26.x。

.EXAMPLE
    # 下载后运行（推荐，参数最清楚）
    iwr -useb https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.ps1 -OutFile deploy.ps1
    .\deploy.ps1 -Loader paper -Version 1.21.11 -Mem 2

.EXAMPLE
    # 真·一行命令
    & ([scriptblock]::Create((iwr -useb https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.ps1).Content)) -Loader paper -Version 1.21.11 -Mem 2

.EXAMPLE
    # 只看看会下载什么
    .\deploy.ps1 -Loader fabric -Version 1.21.1 -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet('paper','vanilla','fabric','neoforge','forge')]
    [string]$Loader = 'paper',

    [string]$Version = '1.21.11',

    [double]$Mem = 0,            # 0 = 自动按物理内存取 1/4

    [int]$Port = 25565,

    [string]$Motd = '',

    [string]$Dir = "$HOME\mc",

    [ValidateSet('true','false')]
    [string]$OnlineMode = 'true',

    [int]$ViewDistance = 0,      # 0 = 自动

    [int]$MaxPlayers = 0,        # 0 = 自动

    [ValidateSet('auto','always','never')]
    [string]$Mirror = 'never',   # Windows 桌面默认走官方源

    [string]$Plugins = '',   # 逗号分隔的插件 slug，例如 essentialsx,luckperms
    [string]$Mods = '',      # 逗号分隔的模组 slug，例如 lithium,ferrite-core

    [switch]$NoStart,
    [switch]$NoJava,
    [switch]$List,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # 加快 Invoke-WebRequest

function Write-Info { param($m) Write-Host "▸ $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "✔ $m" -ForegroundColor Green }
function Write-Warn2{ param($m) Write-Host "⚠ $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "✘ $m" -ForegroundColor Red }
function Write-Hr   { Write-Host ("─" * 52) -ForegroundColor DarkGray }

# ------------------------- 运行时进度提示 ------------------------------------
$TOTAL_STEPS = 7
$STEP = 0
function Write-Step {
    param([string]$Title)
    $script:STEP++
    Write-Host ""
    Write-Host ("━━ 第 {0}/{1} 步 · {2} ━━" -f $script:STEP, $TOTAL_STEPS, $Title) -ForegroundColor Cyan
}
function Write-Sub  { param([string]$m) Write-Host "   $m" }
function Write-Hint { param([string]$m) Write-Host "   ↳ $m" -ForegroundColor DarkGray }
function Write-WarnHint { param([string]$m) Write-Host "   ↳ $m" -ForegroundColor Yellow }

# ------------------------- Java 需求 -----------------------------------------
function Get-JavaFor {
    param([string]$v)
    $p = $v.Split('.')
    $a = [int]$p[0]; $b = if ($p.Count -gt 1) { [int]$p[1] } else { 0 }
    $c = if ($p.Count -gt 2) { [int]$p[2] } else { 0 }
    if ($a -ge 26) { return 25 }
    if ($a -eq 1 -and $b -ge 21) { return 21 }
    if ($a -eq 1 -and $b -eq 20 -and $c -ge 5) { return 21 }
    if ($a -eq 1 -and $b -ge 17) { return 17 }
    return 8
}

function Get-CurrentJava {
    try {
        $out = & java -version 2>&1 | Select-Object -First 1
        if ($out -match 'version "(\d+)') { return [int]$Matches[1] }
    } catch { }
    return 0
}

# ------------------------- 组合列表 ------------------------------------------
if ($List) {
    $raw = 'https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/data.json'
    try {
        $d = Invoke-RestMethod -Uri $raw -TimeoutSec 30
        $order = 'paper','vanilla','fabric','neoforge','forge'
        Write-Host ("{0,-10}{1,-6}{2,-7}{3,-6}{4,-8}{5,-10}{6,-6}" -f '版本','Java','Paper','原版','Fabric','NeoForge','Forge')
        Write-Host ("─" * 54)
        $tot = 0
        foreach ($v in $d.versions.PSObject.Properties.Name) {
            $info = $d.versions.$v
            $cells = foreach ($k in $order) { if ($info.loaders.PSObject.Properties.Name -contains $k) { '✓' } else { '·' } }
            $tot += $info.loaders.PSObject.Properties.Name.Count
            Write-Host ("{0,-10}{1,-6}{2,-7}{3,-6}{4,-8}{5,-10}{6,-6}" -f $v, $info.java, $cells[0], $cells[1], $cells[2], $cells[3], $cells[4])
        }
        Write-Host "`n可用组合总数: $tot"
    } catch {
        Write-Warn2 "无法获取组合列表（需要联网）：$($_.Exception.Message)"
    }
    return
}

# ------------------------- 插件与模组（数据来自 Modrinth）---------------------
function Install-Modrinth {
    param([string]$List, [string]$Kind, [string]$Target, [string[]]$Loaders)
    if (-not $List) { return }
    if (-not $Loaders -or $Loaders.Count -eq 0) { Write-Warn2 "$Loader 不支持$Kind，已跳过"; return }
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    $encL = [uri]::EscapeDataString('[' + (($Loaders | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']')
    $encV = [uri]::EscapeDataString('["' + $Version + '"]')
    $ok = 0; $skip = 0
    foreach ($raw in $List.Split(',')) {
        $sl = $raw.Trim(); if (-not $sl) { continue }
        $api = "https://api.modrinth.com/v2/project/$sl/version?loaders=$encL&game_versions=$encV"
        $v = $null
        try { $v = Invoke-RestMethod -Uri $api -TimeoutSec 60 -UseBasicParsing } catch { }
        if (-not $v -or $v.Count -eq 0) { Write-Warn2 "$sl：没有适配 $Loader + MC $Version 的版本，已跳过"; $skip++; continue }
        $ver = $v[0]
        if ($ver.environment -eq 'client_only') { Write-Warn2 "$sl：仅客户端内容，装在服务端没用，已跳过"; $skip++; continue }
        $f = $ver.files | Where-Object { $_.primary } | Select-Object -First 1
        if (-not $f) { $f = $ver.files[0] }
        if (-not $f) { Write-Warn2 "$sl：解析文件失败，已跳过"; $skip++; continue }
        Write-Sub "下载 $sl -> $($f.filename)"
        try {
            Invoke-WebRequest -Uri $f.url -OutFile (Join-Path $Target $f.filename) -UseBasicParsing
            Write-Ok "  $($f.filename)"
            $ok++
        } catch { Write-Warn2 "$sl 下载失败，已跳过"; $skip++ }
    }
    Write-Sub "结果       成功 $ok 个，跳过 $skip 个"
}

# ------------------------- 自动参数 ------------------------------------------
$needJava = Get-JavaFor $Version

if ($Mem -le 0) {
    $totalGb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $Mem = [math]::Max(1, [math]::Min(8, [math]::Floor($totalGb / 4)))
    Write-Info "未指定内存，按物理内存 ${totalGb}G 自动取 ${Mem}G"
}
if ($ViewDistance -le 0) { $ViewDistance = if ($Mem -le 1) { 5 } elseif ($Mem -le 3) { 6 } else { 8 } }
if ($MaxPlayers  -le 0) { $MaxPlayers  = if ($Mem -le 1) { 5 } elseif ($Mem -le 3) { 10 } else { 20 } }
if (-not $Motd) { $Motd = "Minecraft Server $Version" }

# Java 不接受小数堆大小，统一换算成 MB
if ($Mem -eq [math]::Floor($Mem)) { $memFlag = "$([int]$Mem)G" } else { $memFlag = "$([int]($Mem * 1024))M" }

# -XX:+UnlockExperimentalVMOptions 必须排在所有 -XX 之前：
# G1NewSizePercent / G1MaxNewSizePercent 属实验性选项，未解锁会直接拒绝启动
$jarFlags = "-XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:+ParallelRefProcEnabled " +
            "-XX:MaxGCPauseMillis=200 -XX:+DisableExplicitGC -XX:+AlwaysPreTouch " +
            "-XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M " +
            "-XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:InitiatingHeapOccupancyPercent=15 " +
            "-XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1 " +
            "-Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"

# 部署前先校验参数，不通过就降级，避免生成一个起不来的脚本
& java "-Xms$memFlag" "-Xmx$memFlag" @($jarFlags.Split(' ')) -version *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Warn2 "当前 JVM 不接受这套调优参数，自动降级为保守参数"
    $jarFlags = "-XX:+UseG1GC -XX:MaxGCPauseMillis=200"
    & java "-Xms$memFlag" "-Xmx$memFlag" @($jarFlags.Split(' ')) -version *> $null
    if ($LASTEXITCODE -ne 0) { $jarFlags = "" }
}

Write-Hr
Write-Host "Minecraft 服务器部署" -ForegroundColor White
Write-Hr
Write-Sub "服务端  $Loader $Version"
Write-Sub "环境    Windows"
Write-Sub "Java    $needJava"
Write-Sub "内存    ${Mem}G"
Write-Sub "目录    $Dir"
Write-Sub "端口    $Port"
Write-Hr
Write-Sub "本次共 $TOTAL_STEPS 步："
Write-Sub "  1 准备 Java      2 解析下载地址    3 下载服务端     4 装插件模组"
Write-Sub "  5 写入配置       6 生成启动脚本    7 启动服务器"
Write-Hint "中途 Ctrl+C 可安全中断，不会留下坏文件"

Write-Sub "已有 Java：$(if ((Get-CurrentJava) -gt 0) { "Java $(Get-CurrentJava)" } else { "未安装" })"

Write-Step "准备 Java $needJava"

# ------------------------- 安装 Java -----------------------------------------
if (-not $NoJava) {
    $cur = Get-CurrentJava
    if ($cur -ge $needJava) {
        Write-Ok "已检测到 Java $cur，满足要求（需 $needJava+）"
    } else {
        if ($cur -gt 0) { Write-Warn2 "当前 Java $cur 低于所需的 $needJava，将安装新版" }
        else { Write-Info "未检测到 Java，开始安装 Java $needJava" }

        $installed = $false
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Info "尝试用 winget 安装 Temurin $needJava"
            try {
                winget install --id "EclipseAdoptium.Temurin.$needJava.JRE" -e --accept-source-agreements --accept-package-agreements | Out-Null
                $installed = $true
            } catch { Write-Warn2 "winget 安装失败，改用直接下载" }
        }
        if (-not $installed) {
            $url = "https://api.adoptium.net/v3/binary/latest/$needJava/ga/windows/x64/jre/hotspot/normal/eclipse"
            $msi = Join-Path $env:TEMP "temurin-$needJava.msi"
            Write-Info "下载 Temurin $needJava 安装包"
            try {
                Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing
                Write-Info "静默安装（可能需要管理员权限）"
                Start-Process msiexec.exe -ArgumentList "/i", $msi, "/qn", "ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJarFileRunWith" -Wait
                $installed = $true
            } catch {
                Write-Err "Java 安装失败：$($_.Exception.Message)"
                Write-Host "  请手动安装 Java $needJava 后，加 -NoJava 参数重跑："
                Write-Host "  https://adoptium.net/temurin/releases/?version=$needJava"
                return
            }
        }
        $cur = Get-CurrentJava
        if ($cur -ge $needJava) { Write-Ok "Java $cur 就绪" }
        else {
            Write-Warn2 "安装后当前会话仍检测不到 java，请【重开一个 PowerShell 窗口】后再运行本脚本（可加 -NoJava）"
            return
        }
    }
} else { Write-Info "按参数跳过 Java 检查" }


Write-Step "解析下载地址"

# ------------------------- 解析下载地址 --------------------------------------
Write-Info "解析 $Loader $Version 的下载地址"
$srcUrl = ''; $srcName = 'server.jar'; $isInstaller = $false; $sha = ''; $algo = 'sha256'
$useMirror = ($Mirror -eq 'always')

switch ($Loader) {
    'paper' {
        $api = "https://fill.papermc.io/v3/projects/paper/versions/$Version/builds/latest"
        $j = Invoke-RestMethod -Uri $api -TimeoutSec 60
        $dl = $j.downloads.'server:default'
        $srcUrl = $dl.url; $srcName = $dl.name; $sha = $dl.checksums.sha256
        Write-Ok "Paper 构建: $srcName"
    }
    'vanilla' {
        if ($useMirror) {
            $srcUrl = "https://bmclapi2.bangbang93.com/version/$Version/server"
        } else {
            $man = Invoke-RestMethod -Uri 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json' -TimeoutSec 60
            $entry = $man.versions | Where-Object { $_.id -eq $Version } | Select-Object -First 1
            if (-not $entry) { Write-Err "在官方清单里找不到版本 $Version"; return }
            $vj = Invoke-RestMethod -Uri $entry.url -TimeoutSec 60
            $srcUrl = $vj.downloads.server.url
            $sha = $vj.downloads.server.sha1; $algo = 'sha1'
        }
    }
    'fabric' {
        $ld = (Invoke-RestMethod -Uri "https://meta.fabricmc.net/v2/versions/loader/$Version" -TimeoutSec 60)[0].loader.version
        $ins = (Invoke-RestMethod -Uri 'https://meta.fabricmc.net/v2/versions/installer' -TimeoutSec 60)[0].version
        $srcUrl = "https://meta.fabricmc.net/v2/versions/loader/$Version/$ld/$ins/server/jar"
        $srcName = "fabric-server-mc.$Version-loader.$ld-launcher.$ins.jar"
        Write-Ok "Fabric loader $ld / installer $ins"
    }
    default {
        $isInstaller = $true; $srcName = 'installer.jar'
        if ($Loader -eq 'neoforge') {
            $lst = Invoke-RestMethod -Uri "https://bmclapi2.bangbang93.com/neoforge/list/$Version" -TimeoutSec 60
            $stable = $lst | Where-Object { $_.version -notmatch 'beta' }
            $n = if ($stable) { $stable[-1].version } else { $lst[-1].version }
            $srcUrl = "https://maven.neoforged.net/releases/net/neoforged/neoforge/$n/neoforge-$n-installer.jar"
            if ($useMirror) { $srcUrl = "https://bmclapi2.bangbang93.com/maven/net/neoforged/neoforge/$n/neoforge-$n-installer.jar" }
            Write-Ok "NeoForge $n"
        } else {
            $pj = Invoke-RestMethod -Uri 'https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json' -TimeoutSec 60
            $n = $pj.promos."$Version-recommended"
            if (-not $n) { $n = $pj.promos."$Version-latest" }
            if (-not $n) { Write-Err "Forge 没有为 MC $Version 发布版本"; return }
            $srcUrl = "https://maven.minecraftforge.net/net/minecraftforge/forge/$Version-$n/forge-$Version-$n-installer.jar"
            if ($useMirror) { $srcUrl = "https://bmclapi2.bangbang93.com/maven/net/minecraftforge/forge/$Version-$n/forge-$Version-$n-installer.jar" }
            Write-Ok "Forge $n（推荐版）"
        }
    }
}

if ($DryRun) {
    Write-Hr
    Write-Info "DRY RUN：只解析地址并打印计划，不下载、不修改任何文件"
    Write-Host "   Java 需求 : $needJava（当前: $(Get-CurrentJava)）"
    Write-Host "   服务端文件: $srcName"
    Write-Host "   下载地址  : $srcUrl"
    if ($sha) { Write-Host "   校验值($algo) : $sha" }
    Write-Host "   内存参数  : -Xms$memFlag -Xmx$memFlag"
    Write-Host "   安装目录  : $Dir"
    Write-Host "   端口/视距 : $Port / $ViewDistance"
    return
}

Write-Sub "服务端     $srcName"

Write-Step "下载服务端文件"

# ------------------------- 下载与安装 ----------------------------------------
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Set-Location $Dir

if ($isInstaller) {
    Write-Info "下载安装器"
    Invoke-WebRequest -Uri $srcUrl -OutFile 'installer.jar' -UseBasicParsing
    $sz = (Get-Item installer.jar).Length
    Write-Host "   大小: $sz 字节"
    if ($sz -lt 100000) { Write-Err "安装器只有 $sz 字节，明显不是有效文件（可能被拦截）"; return }
    Write-Info "运行安装器（首次较慢，需要下载大量依赖库）"
    & java -jar installer.jar --installServer
    if ($LASTEXITCODE -ne 0) { Write-Err "安装器执行失败，请查看上方输出"; return }
    Write-Ok "安装器执行完成"
} else {
    Write-Info "下载服务端 $srcName"
    Invoke-WebRequest -Uri $srcUrl -OutFile 'server.jar' -UseBasicParsing
    $sz = (Get-Item server.jar).Length
    if ($sz -lt 1000000) { Write-Err "下载到的文件只有 $sz 字节，明显不是服务端 jar（可能被拦截成错误页面）"; return }
    Write-Ok ("下载完成（{0:N1} MB）" -f ($sz / 1MB))

    if ($sha) {
        Write-Info "校验完整性（$algo）"
        $got = (Get-FileHash server.jar -Algorithm $(if ($algo -eq 'sha1') { 'SHA1' } else { 'SHA256' })).Hash.ToLower()
        if ($got -eq $sha.ToLower()) { Write-Ok "$algo 校验通过" }
        else { Write-Warn2 "$algo 不一致（上游可能已更新构建，通常不影响使用）"; Write-Host "   期望: $sha"; Write-Host "   实际: $got" }
    }
}


Write-Step "安装插件与模组"
if (-not $Plugins -and -not $Mods) {
    Write-Sub "未选择任何插件或模组"
    Write-Hint "可用 -Plugins essentialsx,luckperms 或 -Mods lithium,jei 指定"
} else {
    switch ($Loader) {
        'paper' {
            if ($Mods) { Write-Warn2 "Paper 不能加载 Fabric / Forge 模组，-Mods 已忽略" }
            Install-Modrinth -List $Plugins -Kind '插件' -Target (Join-Path $Dir 'plugins') -Loaders @('paper','spigot','bukkit')
        }
        'vanilla' { Write-Warn2 "原版服务端既不支持插件也不支持模组，已跳过" }
        default {
            if ($Plugins) { Write-Warn2 "Bukkit 插件只能在 Paper 上运行，-Plugins 已忽略" }
            Install-Modrinth -List $Mods -Kind '模组' -Target (Join-Path $Dir 'mods') -Loaders @($Loader)
        }
    }
}

Write-Step "写入配置"

# ------------------------- 写配置 --------------------------------------------
Set-Content -Path eula.txt -Value 'eula=true' -Encoding ascii
Write-Ok "已同意 EULA（eula.txt）"

if (Test-Path server.properties) {
    Write-Info "server.properties 已存在，保留原配置"
} else {
    $cfg = @(
        "motd=$Motd"
        "server-port=$Port"
        "online-mode=$OnlineMode"
        "max-players=$MaxPlayers"
        "view-distance=$ViewDistance"
        "simulation-distance=$([math]::Max(4, $ViewDistance - 1))"
        "spawn-protection=0"
        "allow-flight=true"
        "enable-command-block=true"
        "difficulty=easy"
        "white-list=false"
    )
    # 必须写成不带 BOM 的 UTF-8：PowerShell 的 utf8 会加 BOM，破坏第一行键名并让中文 motd 变乱码
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllLines((Join-Path $Dir 'server.properties'), $cfg, $utf8)
    Write-Ok "已写入 server.properties"
}

Write-Hint "Minecraft 服务端必须显式同意许可协议才能启动，这一步是自动完成的"

Write-Step "生成启动脚本"

# ------------------------- 启动脚本 ------------------------------------------
# here-string 的闭合定界符单独占一行、不与管道同行，再用变量写出，避免解析歧义；
# 用单引号版 @' '@ 可防止内容里的 $ 被 PowerShell 展开
if ($isInstaller) {
    $bat = @'
@echo off
cd /d %~dp0
call run.bat nogui
'@
} else {
    $bat = @'
@echo off
cd /d %~dp0
java __JVM__ -jar server.jar nogui
pause
'@
    $bat = $bat.Replace('__JVM__', "-Xms$memFlag -Xmx$memFlag $jarFlags")
}
$bat | Set-Content -Path start.bat -Encoding ascii
Write-Ok "已生成启动脚本 start.bat"

Write-Hr
Write-Ok "部署完成  目录: $Dir"
Write-Hr
Write-Host "接下来你可以：" -ForegroundColor White
Write-Sub "开服        .\start.bat   （或双击运行）"
Write-Sub "安全关服     在服务器窗口输入 stop 回车"
Write-Sub "改配置      notepad $Dir\server.properties"
Write-Sub "备份世界    打包 world、world_nether、world_the_end 三个目录"
Write-Sub "自己先进    Minecraft 里添加服务器 localhost:$Port"
Write-Sub "给别人进    同一局域网用 本机IP:$Port（ipconfig 查）"
Write-Hr

if (-not $NoStart) {
    Write-Step "启动服务器"
    Write-WarnHint "首次启动要生成世界，通常 1~3 分钟，请勿中断"
    Write-Sub '成功标志：Done (xx.xxs)! For help, type "help"'
    Write-Sub "安全关服：在当前窗口输入 stop 回车"
    Write-Hr
    & .\start.bat
} else {
    Write-Info "按参数要求不自动启动。需要时运行：$Dir\start.bat"
}
