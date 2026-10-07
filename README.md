# Minecraft Java 服务器 · 一键部署

一条命令在 **Android/Termux**、**proot 发行版**、**Linux**、**macOS**、**Windows** 上装好 Minecraft Java 版服务端。

- 支持 **Paper / 原版 / Fabric / NeoForge / Forge** 五种服务端
- 覆盖 **MC 1.7.10 ~ 26.x 共 76 个版本**，自动匹配所需 Java 版本
- 官方直链 + 国内镜像（BMCLAPI），自动选路、自动重试、可选校验
- 附带一个**离线可用的网页控制台** `index.html`，点点选选就能生成命令

> 全部下载地址由官方接口实时解析，不写死任何可能过期的链接。
>
> **在线版网页控制台：<https://zhuzijiang.github.io/mc-server-deploy/>**（也可以下载 `index.html` 离线用）

---

## 一条命令完成所有操作

```bash
curl -fsSL https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.sh | bash -s -- --loader paper --version 1.21.11 --mem 2
```

把 `--loader` / `--version` / `--mem` 换掉即可。例如：

```bash
# Fabric 1.21.1 模组服，4G 内存
curl -fsSL https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.sh | bash -s -- --loader fabric --version 1.21.1 --mem 4

# Forge 1.20.1（老整合包），3G，强制国内镜像
curl -fsSL https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.sh | bash -s -- --loader forge --version 1.20.1 --mem 3 --mirror always

# 原版 1.20.1，2.5G（支持小数，自动换算成 MB）
curl -fsSL https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.sh | bash -s -- --loader vanilla --version 1.20.1 --mem 2.5

# 先看看会下载什么，不做任何改动
curl -fsSL https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.sh | bash -s -- --loader paper --version 1.21.11 --dry-run

# 不带参数运行，进入交互式向导
curl -fsSL https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.sh | bash
```

**在 Termux 里粘贴后回车即可**，脚本会自动完成：装 Java → 下载服务端 → 写配置 → 生成启动脚本 → 启动。

### Windows

```powershell
iwr -useb https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.ps1 -OutFile deploy.ps1
.\deploy.ps1 -Loader paper -Version 1.21.11 -Mem 2
```

真·一行命令（内容直接执行）：

```powershell
& ([scriptblock]::Create((iwr -useb https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.ps1).Content)) -Loader paper -Version 1.21.11 -Mem 2
```

---

## 网络不通？换镜像通道

`raw.githubusercontent.com` 在部分网络下会被阻断（表现为 `curl: (35) Connection reset` 或一直超时）。
下面四条通道内容完全相同，**任选一条能连通的**即可，把命令里的域名换掉就行：

| 通道 | 地址前缀 | 说明 |
|---|---|---|
| GitHub 官方 | `https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main` | 最实时，但国内常被阻断 |
| jsDelivr CDN | `https://cdn.jsdelivr.net/gh/zhuzijiang/mc-server-deploy@main` | 全球 CDN，国内通常可用；有约 12 小时缓存 |
| ghproxy.net | `https://ghproxy.net/https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main` | 实时代理，无缓存 |
| gh-proxy.com | `https://gh-proxy.com/https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main` | 实时代理，无缓存 |

例如把官方通道换成 jsDelivr：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/zhuzijiang/mc-server-deploy@main/deploy.sh | bash -s -- --loader paper --version 1.21.11 --mem 2
```

脚本内部的 `--list` 也会自动按「官方 → jsDelivr → ghproxy → gh-proxy」的顺序重试，无需手动指定。

---

## 参数

| 参数 | 说明 | 默认 |
|---|---|---|
| `--loader <名称>` | `paper` / `vanilla` / `fabric` / `neoforge` / `forge` | `paper` |
| `--version <版本>` | Minecraft 版本，如 `1.21.11`、`1.20.1`、`1.12.2` | `1.21.11` |
| `--mem <GB>` | 分配给服务器的内存，支持小数如 `2.5` | 按物理内存自动取 1/4 |
| `--port <端口\|auto>` | 监听端口，`auto` = 静默探测空闲端口 | `auto` |
| `--loader-version <v>` | 指定加载器版本（fabric / forge / neoforge） | 最新稳定版 |
| `--motd <文字>` | 服务器列表里显示的名称 | `Minecraft Server <版本>` |
| `--dir <路径>` | 安装目录 | `~/mc` |
| `--online-mode <true\|false>` | 正版验证 | `true` |
| `--view-distance <n>` | 视野距离 | 按内存自动（5/6/8） |
| `--max-players <n>` | 最大玩家数 | 按内存自动（5/10/20） |
| `--mirror <auto\|always\|never>` | 是否优先走国内镜像 | Termux/proot 为 `auto`，桌面为官方源 |
| `--no-start` | 只安装配置，不立即启动 | — |
| `--no-java` | 跳过 Java 检查与安装 | — |
| `--dry-run` | 只解析地址并打印计划 | — |
| `--ask` | 强制进入交互式向导 | — |
| `--plugins <列表>` | 安装插件（逗号分隔），仅 Paper 支持 | — |
| `--mods <列表>` | 安装模组（逗号分隔），Fabric / NeoForge / Forge | — |
| `--pick` | 交互式挑选插件与模组 | — |
| `--list-plugins` / `--list-mods` | 列出全部候选后退出 | — |
| `-l, --list` | 列出全部可用「版本 × 服务端」组合 | — |
| `-h, --help` | 显示帮助 | — |

---

## 插件与模组

内置 **33 个常用插件** 和 **48 个常用模组**目录，元数据取自 Modrinth（按下载量筛选），
安装时按你选的**加载器 + MC 版本**实时匹配可用文件，不写死地址。

```bash
# 装插件（仅 Paper 支持）
curl -fsSL https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.sh | bash -s -- --loader paper --version 1.21.11 --mem 2 --plugins essentialsx,luckperms,coreprotect

# 装模组（Fabric / NeoForge / Forge）
curl -fsSL https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.sh | bash -s -- --loader fabric --version 1.21.1 --mem 4 --mods lithium,ferrite-core,jei

# 交互式挑选：列出候选让你输编号
curl -fsSL https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.sh | bash -s -- --pick

# 先看看有哪些可选
curl -fsSL https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.sh | bash -s -- --list-plugins
curl -fsSL https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.sh | bash -s -- --list-mods
```

脚本会自动跳过**仅客户端**的内容（装在服务端没有作用），并把文件放进 `plugins/` 或 `mods/`。
标记说明：**★** 需要客户端也装同样的模组；**⚠** 仅客户端，服务端装了没用。

### 插件（33 个）

| 分类 | 内容 |
|---|---|
| 基础管理 | `lmd`、`luckperms`、`tab-was-taken`、`essentialsx`、`placeholderapi`、`deluxemenus`、`towny`、`chestshop` |
| 世界与保护 | `worldedit`、`worldguard`、`multiverse-core`、`fastasyncworldedit`、`coreprotect`、`multiverse-inventories`、`griefprevention`、`multiverse-portals` |
| 性能与维护 | `spark`、`chunky`、`bluemap`、`squaremap` |
| 兼容与联机 | `viaversion`、`viabackwards`、`skinsrestorer`、`geyser`、`floodgate` |
| 玩法与社交 | `simple-voice-chat` ★、`packetevents`、`grimac`、`discordsrv`、`dynmap`、`crazycrates`、`excellentcrates`、`mythicmobs` |

### 模组（48 个）

| 分类 | 内容 |
|---|---|
| 性能优化 | `ferrite-core` ★、`lithium` ★、`modernfix` ★、`krypton` ★、`clumps` ★、`c2me-fabric`、`memoryleakfix` ★、`noisium`、`servercore`、`fastload` ★、`threadtweak` ★、`async-locator`、`tt20` |
| 前置库 | `fabric-api` ★、`cloth-config` ★、`fabric-language-kotlin` ★、`architectury-api` ★、`geckolib` ★、`forge-config-api-port` ★、`puzzles-lib` ★、`balm` ★、`midnightlib` ★、`trinkets` ★、`cardinal-components-api` |
| 玩法内容 | `veinminer`、`supplementaries` ★、`create` ★、`waystones` ★、`quark` ★、`farmers-delight` ★、`terralith`、`comforts` ★、`sophisticated-backpacks` ★、`rightclickharvest`、`aether` ★、`botania` ★、`ars-nouveau` ★、`mekanism` ★、`immersiveengineering` ★、`iron-chests` ★ |
| 信息显示 | `xaeros-minimap` ★、`appleskin` ★、`jei` ★、`jade` ★、`emi` ★、`wthit` ★ |
| 仅客户端 | `sodium` ⚠、`iris` ⚠ |

> 插件只能在 Paper 上运行；模组需要 Fabric / NeoForge / Forge。选错时脚本会提示并跳过，不会静默失败。

---

## 版本 × 服务端 可用性矩阵

共 **309 个可用组合**，下表为逐个探测的真实结果（✅ 可用，— 该服务端未发布此版本）：

| 版本 | Java | Paper | Folia | Purpur | 原版 | Fabric | NeoForge | Forge |
|---|---|---|---|---|---|---|
| `26.3` | Java 25 | ✅ | — | ✅ | ✅ | ✅ | ✅ | ✅ |
| `26.2` | Java 25 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `26.1.2` | Java 25 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `26.1.1` | Java 25 | ✅ | — | — | ✅ | ✅ | ✅ | ✅ |
| `26.1` | Java 25 | — | — | — | ✅ | ✅ | — | ✅ |
| `1.21.11` | Java 21 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.21.10` | Java 21 | ✅ | — | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.21.9` | Java 21 | ✅ | — | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.21.8` | Java 21 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.21.7` | Java 21 | ✅ | — | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.21.6` | Java 21 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.21.5` | Java 21 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.21.4` | Java 21 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.21.3` | Java 21 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.21.2` | Java 21 | — | — | — | ✅ | ✅ | ✅ | — |
| `1.21.1` | Java 21 | ✅ | — | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.21` | Java 21 | ✅ | — | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.20.6` | Java 21 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.20.5` | Java 21 | ✅ | — | — | ✅ | ✅ | ✅ | — |
| `1.20.4` | Java 17 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.20.3` | Java 17 | — | — | — | ✅ | ✅ | ✅ | ✅ |
| `1.20.2` | Java 17 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.20.1` | Java 17 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `1.20` | Java 17 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.19.4` | Java 17 | ✅ | ✅ | ✅ | ✅ | ✅ | — | ✅ |
| `1.19.3` | Java 17 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.19.2` | Java 17 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.19.1` | Java 17 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.19` | Java 17 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.18.2` | Java 17 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.18.1` | Java 17 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.18` | Java 17 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.17.1` | Java 17 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.17` | Java 17 | ✅ | — | ✅ | ✅ | ✅ | — | — |
| `1.16.5` | Java 8 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.16.4` | Java 8 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.16.3` | Java 8 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.16.2` | Java 8 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.16.1` | Java 8 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.16` | Java 8 | — | — | — | ✅ | ✅ | — | — |
| `1.15.2` | Java 8 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.15.1` | Java 8 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.15` | Java 8 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.14.4` | Java 8 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.14.3` | Java 8 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.14.2` | Java 8 | ✅ | — | ✅ | ✅ | ✅ | — | ✅ |
| `1.14.1` | Java 8 | ✅ | — | ✅ | ✅ | ✅ | — | — |
| `1.14` | Java 8 | ✅ | — | — | ✅ | ✅ | — | — |
| `1.13.2` | Java 8 | ✅ | — | — | ✅ | — | — | ✅ |
| `1.13.1` | Java 8 | ✅ | — | — | ✅ | — | — | — |
| `1.13` | Java 8 | ✅ | — | — | ✅ | — | — | — |
| `1.12.2` | Java 8 | ✅ | — | — | ✅ | — | — | ✅ |
| `1.12.1` | Java 8 | ✅ | — | — | ✅ | — | — | ✅ |
| `1.12` | Java 8 | ✅ | — | — | ✅ | — | — | ✅ |
| `1.11.2` | Java 8 | ✅ | — | — | ✅ | — | — | ✅ |
| `1.11.1` | Java 8 | — | — | — | ✅ | — | — | — |
| `1.11` | Java 8 | — | — | — | ✅ | — | — | ✅ |
| `1.10.2` | Java 8 | ✅ | — | — | ✅ | — | — | ✅ |
| `1.10.1` | Java 8 | — | — | — | ✅ | — | — | — |
| `1.10` | Java 8 | — | — | — | ✅ | — | — | ✅ |
| `1.9.4` | Java 8 | ✅ | — | — | ✅ | — | — | ✅ |
| `1.9.3` | Java 8 | — | — | — | ✅ | — | — | — |
| `1.9.2` | Java 8 | — | — | — | ✅ | — | — | — |
| `1.9.1` | Java 8 | — | — | — | ✅ | — | — | — |
| `1.9` | Java 8 | — | — | — | ✅ | — | — | ✅ |
| `1.8.9` | Java 8 | — | — | — | ✅ | — | — | ✅ |
| `1.8.8` | Java 8 | ✅ | — | — | ✅ | — | — | ✅ |
| `1.8.7` | Java 8 | — | — | — | ✅ | — | — | — |
| `1.8.6` | Java 8 | — | — | — | ✅ | — | — | — |
| `1.8.5` | Java 8 | — | — | — | ✅ | — | — | — |
| `1.8.4` | Java 8 | — | — | — | ✅ | — | — | — |
| `1.8.3` | Java 8 | — | — | — | ✅ | — | — | — |
| `1.8.2` | Java 8 | — | — | — | ✅ | — | — | — |
| `1.8.1` | Java 8 | — | — | — | ✅ | — | — | — |
| `1.8` | Java 8 | — | — | — | ✅ | — | — | ✅ |
| `1.7.10` | Java 8 | ✅ | — | — | ✅ | — | — | ✅ |

各服务端覆盖版本数：

| 服务端 | 覆盖版本数 |
|---|---|
| Paper | 55 |
| Folia | 12 |
| Purpur | 41 |
| 原版 | 76 |
| Fabric | 48 |
| NeoForge | 21 |
| Forge | 56 |

### 推荐组合

| 版本 | Java | 可用服务端 |
|---|---|---|
| `1.21.11` | Java 21 | Paper、Folia、Purpur、原版、Fabric、NeoForge、Forge |
| `1.21.1` | Java 21 | Paper、Purpur、原版、Fabric、NeoForge、Forge |
| `1.20.1` | Java 17 | Paper、Folia、Purpur、原版、Fabric、NeoForge、Forge |
| `1.12.2` | Java 8 | Paper、原版、Forge |

**怎么选：**

- 只开原版联机、想装插件 → **Paper**（性能最好，生态最成熟）
- 想装模组、追求轻量 → **Fabric**（1.14 起支持）
- 玩 1.20.2 之后的新整合包 → **NeoForge**
- 玩 1.20.1 及更早的老整合包 → **Forge**
- 什么都不装、只要原汁原味 → **原版**

---

## 网页控制台

仓库里的 `index.html` 是**纯静态单文件网页，无任何外部依赖，离线可用**。
下载后用浏览器打开，点点选选就能生成和你的设备匹配的命令，并列出所有直链与镜像。

- 自动探测访问设备（系统、内存、CPU 核心数），给出推荐配置
- 5 种运行环境 × 5 种服务端 × 76 个版本自由组合，不支持的组合自动置灰
- 6 步傻瓜式流程，每一步都有「操作 / 成功标志 / 常见错误」
- `server.properties` 与 JVM 参数的逐项中文说明
- 12 条报错信息对照表、内网穿透方案对比、备份与运维指引

---

## 工作原理

脚本不做任何黑盒操作，全部是标准流程：

1. **探测环境** — 通过 `$PREFIX` 识别 Termux，通过内核串 / `PROOT_TMP_DIR` 识别 proot，其余按 `uname` 区分 Linux 与 macOS
2. **匹配 Java** — 按 Minecraft 官方要求：`26.x → 25`，`1.20.5~1.21.x → 21`，`1.17~1.20.4 → 17`，`≤1.16.5 → 8`
3. **解析直链** — 从各项目官方接口实时取地址，从不硬编码
   - Paper：`fill.papermc.io/v3`（旧的 `api.papermc.io/v2` 已 410 下线，网上老教程照抄会失败）
   - 原版：Mojang 版本清单，或 BMCLAPI 镜像
   - Fabric：`meta.fabricmc.net` 解析 loader 与 installer 版本
   - Forge：官方 `promotions_slim.json` 的 recommended 优先
   - NeoForge：BMCLAPI 版本列表，优先取非 beta
4. **下载并校验** — 断点续传（`-C -`）+ 重试；有校验值就比对，文件明显过小会直接判定为拦截页
5. **写配置** — `eula.txt`、`server.properties`（已存在则不覆盖，避免冲掉自定义配置）
6. **生成启动脚本** — Aikar 调优参数；Forge/NeoForge 走安装器生成的 `run.sh` / `run.bat`

---

## 常见问题

**Java 版本报错 `UnsupportedClassVersionError`**
Java 版本低于该 MC 版本要求。重跑脚本会自动装对应版本，或按上表手动装。

**Termux 里装不了 Java 8（想玩 1.12.2 / 1.16.5）**
Termux 官方仓库只提供 JDK 17 / 21 / 25。请改用 proot 发行版（Ubuntu）环境，脚本会自动走 `apt` 安装 `openjdk-8-jre-headless`。

**下载很慢或失败**
加 `--mirror always` 强制走国内镜像。Paper 官方没有国内镜像，`fill-data.papermc.io` 走 Cloudflare，国内多数情况可直连。

**内存给多少合适**
经验值：1~1.5G 够 1~3 人原版；2~3G 够 3~8 人；4~5G 可跑中型模组整合。**不要超过物理内存的一半**，否则会被系统杀掉，表现为日志里毫无征兆地出现 `Killed`。

**服务器莫名消失**
Android 会回收后台进程。`termux-wake-lock`（脚本自动执行）之外，还要在系统设置里把 Termux 的电池优化设为「无限制」，并关闭 Android 12+ 的幽灵进程限制。

**怎么安全关服**
在服务器窗口输入 `stop` 回车，等日志出现存档完成再关窗口。直接关窗口可能损坏世界。

---

## 数据更新

`data.json` 由 `tools/gen_matrix.py` 生成，逐版本探测五种服务端的可用性并采集直链；
`README.md` 的矩阵表由 `tools/gen_readme.py` 从 `data.json` 渲染，两者不会不一致。

```bash
python3 tools/gen_matrix.py    # 重新探测全部版本 × 服务端
python3 tools/gen_catalog.py   # 重新采集插件与模组目录
python3 tools/gen_readme.py    # 重新渲染 README 矩阵表

# 仓库的「介绍信息」（描述 / 主题 / 主页）也从数据现算，避免介绍与内容脱节
GITHUB_TOKEN=xxx python3 tools/set_repo_meta.py --check   # 先看要改成什么
GITHUB_TOKEN=xxx python3 tools/set_repo_meta.py           # 实际写入
```

数据来源：PaperMC Fill API v3 · Mojang 版本清单 · Fabric Meta · Forge promotions · NeoForge maven · BMCLAPI。

---

## 授权

MIT
