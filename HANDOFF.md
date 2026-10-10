# 接手说明（HANDOFF）

给继续开发这个项目的人看的。读完这份 + `README.md` 就能接手。

---

## 这是什么

Minecraft Java 版服务器的一键部署工具。给 Android/Termux、proot 发行版、Linux、macOS、Windows 用。

- **仓库**：https://github.com/zhuzijiang/mc-server-deploy
- **在线网页**：https://zhuzijiang.github.io/mc-server-deploy/
- **一条命令**：
  ```bash
  curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/deploy.sh | bash -s -- --loader paper --version 1.21.11 --mem 2
  ```

> `raw.githubusercontent.com` 在国内常被阻断，所以用 `gh-proxy.com/` 前缀。
> 另有等价通道：`cdn.jsdelivr.net/gh/zhuzijiang/mc-server-deploy@main`（有缓存）、
> `ghproxy.net/https://raw.githubusercontent.com/...`（有缓存）、`gh-proxy.com/...`（实时，推荐）。

## 当前状态

| 项 | 数值 |
|---|---|
| 游戏版本 | 76（Mojang 全部正式版，1.7.10 起） |
| 服务端类型 | 7：Paper / Folia / Purpur / 原版 / Fabric / NeoForge / Forge |
| 可用组合 | 309 |
| 插件 | 33 |
| 模组 | 48 |
| 支持加载器版本选择 | 是（Fabric / Forge / NeoForge） |

## 文件地图

| 文件 | 作用 |
|---|---|
| `deploy.sh` | 主脚本。Termux/proot/Linux/macOS 一键部署，8 个步骤 |
| `deploy.ps1` | Windows 版 |
| `mcctl` | 服务器管理工具，部署时自动装进服务器目录 |
| `index.html` | 离线网页控制台（也是 GitHub Pages 首页） |
| `data.json` | 版本 × 服务端 实测矩阵 + 加载器版本表（112 KB） |
| `catalog.json` | 插件与模组目录（25 KB） |
| `tools/gen_matrix.py` | 重新探测版本矩阵 |
| `tools/gen_catalog.py` | 重新采集插件模组目录 |
| `tools/gen_readme.py` | 从 data.json + catalog.json 渲染 README |
| `tools/set_repo_meta.py` | 同步仓库介绍（描述/主题/主页），数值从数据现算 |
| `tools/export_chat.py` | 导出 DSH 会话记录为 Markdown（含凭据脱敏） |

## 数据怎么来的

**所有下载地址都是运行时从官方接口解析的，不写死在代码里**：

- Paper / Folia：`fill.papermc.io/v3`（旧的 `api.papermc.io/v2` 已 410 下线）
- Purpur：`api.purpurmc.org/v2`
- 原版：Mojang 版本清单 / BMCLAPI 镜像
- Fabric：`meta.fabricmc.net`
- Forge：官方 `promotions_slim.json`
- NeoForge：BMCLAPI 版本列表
- 插件与模组：`api.modrinth.com/v2`，按「加载器 + MC 版本」匹配

重新生成数据：

```bash
python3 tools/gen_matrix.py     # 约 3-5 分钟，500+ 次请求
python3 tools/gen_catalog.py
python3 tools/gen_readme.py
GITHUB_TOKEN=xxx python3 tools/set_repo_meta.py
```

## 部署流程（8 步）

`deploy.sh` 的 `do_install()`：

1. 检查运行环境（**含 curl 可用性预检**）
2. 准备 Java（26.x→25，1.20.5+→21，1.17+→17，其余→8）
3. 解析下载地址
4. 下载服务端（带进度条、PK 魔法字节校验）
5. 安装插件与模组（Modrinth 实时匹配，自动跳过仅客户端内容）
6. 写入配置（`eula.txt`、`server.properties`）
7. 生成启动脚本与 `mcctl`
8. 启动

## 踩过的坑（改代码前务必看）

这些是真踩出来的，注释里也标了：

1. **`-XX:+UnlockExperimentalVMOptions` 必须在所有 `-XX` 之前**。`G1NewSizePercent`
   被 JVM 标记为实验性选项，Java 8/11/17/21 都会因此拒绝启动。少这一个参数**每次部署都会失败**。
2. **Java 不接受小数堆大小**。`-Xmx2.5G` 直接报错，必须换算成 `2560M`。网页滑块步长 0.5，所以这条很重要。
3. **bash 不会把变量的内容当重定向符**。`red="2>/dev/null"; curl ... $red` 会把 `2>/dev/null`
   当成第二个 URL，curl 报 `Bad hostname` 且退出码 3（但文件其实下完了）。必须写字面量重定向。
4. **不能用 1MB 体积阈值判断 jar 是否有效**。Fabric 的启动器 jar 只有约 177 KB，会被误杀。
   正确做法是校验 ZIP 魔法字节（`PK` 开头）。
5. **Android 上 `/proc/net/tcp` 是 Permission denied**，不能作为端口检测的主要手段。
   现按 `python3 bind > /dev/tcp > ss/netstat/lsof > /proc/net/tcp` 依次回退。
6. **`while read` 会丢掉没有换行符的最后一行**。解析 `catalog.json` 时踩到过，必须 `printf '%s\n'`。
7. **`jget` 的第二个参数才是 JSON 本体**，不能写成管道（`printf ... | jget url` 会取到空值）。
8. **默认值赋值必须在参数解析之前**。放在之后会把用户传入的 `--plugins` 等全部重置。
9. **Termux 上不要 `pkg install curl`**。Termux 官方要求统一 `pkg upgrade`，单独升级 curl 会让
   libcurl 与 openssl 版本错配，报 `CANNOT LINK EXECUTABLE "curl"`。脚本里已去掉这个包。
10. **`/proc/stat` 的 btime 在 proot 下不可靠**，算运行时长要用 PID 文件的 mtime。
11. **PowerShell 用反引号转义引号**，不是反斜杠；here-string 的闭合定界符要单独占一行。

## 推送注意

**这台机器上 `github.com` 的 git 端口不通**（`GnuTLS recv error` / 超时），
但 `api.github.com` 正常。所以推送走 GitHub Contents API：

```python
# 逐文件 PUT，已存在的要带 sha，新建的不能带
GET  /repos/{owner}/{repo}/contents/{path}?ref=main   -> sha
PUT  /repos/{owner}/{repo}/contents/{path}
     {"message": "...", "content": base64, "sha": sha, "branch": "main"}
```

注意：大文件（`index.html` 240 KB）的 JSON 要通过 **stdin**（`curl -d @-`）传，
直接放命令行会 `Argument list too long`。

## 已知待办

- **Windows 版缺少部分功能**：`deploy.ps1` 没有插件/模组安装、没有 `--loader-version`、
  没有 mcctl。目前只有端口自动探测与 8 步流程。
- **Folia 兼容性没收紧**：Folia 需要专门适配的插件，但脚本目前不区分，选 Folia 时
  仍会允许装普通 Bukkit 插件（会启动失败）。可以在 `install_contents` 里加白名单。
- **没有真正的开服实测**：验证到「下载完成 + 配置生成 + 脚本语法 + JVM 参数可用」，
  没有在真机上跑起一个完整世界（受限于测试环境的网络与内存）。
- **网页排版没有真实渲染验证过**：开发环境没有浏览器，只做了逻辑层验证（桩 DOM 跑内嵌 JS）。
- **`mcctl` 的 TPS 显示**依赖日志里的 `/tps` 输出，需要玩家或控制台执行过才有。

## 安全提醒

开发过程中用过两个 GitHub PAT，都是明文出现在对话里的，**应当视为已泄露**：

1. 第一个（`github_pat_` 开头）—— 长度不足 93 位，无效
2. 第二个（`ghp_` 开头，40 位）—— 有效，已被多次使用

导出到别处的聊天记录里，这两个凭据的所有 ≥6 位片段都已替换为 `<已脱敏>`，
`tools/export_chat.py` 里有完整的片段生成逻辑。

**接手后第一件事：去 GitHub 设置里把旧 token 删掉，换一个只放在环境变量里的新 token。**
