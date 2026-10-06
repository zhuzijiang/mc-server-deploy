#!/usr/bin/env bash
# =============================================================================
#  Minecraft Java 版服务器 —— 一键部署脚本
#  支持环境：Android/Termux、proot 发行版(Ubuntu/Debian)、普通 Linux、macOS
#  支持服务端：Paper / Vanilla(原版) / Fabric / NeoForge / Forge
#  适配版本：MC 1.7.10 ~ 26.x（自动匹配所需 Java 版本）
#
#  用法（一条命令）：
#    curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/deploy.sh | bash -s -- \
#         --loader paper --version 1.21.11 --mem 2
#
#  不带任何参数运行会进入交互式向导。
#  查看全部可用组合：  ... | bash -s -- --list
# =============================================================================
set -uo pipefail

REPO_RAW="https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main"

# 数据文件的多条获取通道：某些网络会阻断 raw.githubusercontent.com，
# 按顺序尝试，用第一个成功的。jsDelivr 有缓存（约 12 小时），ghproxy 系列是实时代理。
DATA_MIRRORS="
https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main
https://cdn.jsdelivr.net/gh/zhuzijiang/mc-server-deploy@main
https://ghproxy.net/https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main
https://gh-proxy.com/https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main"

# ------------------------------- 输出样式 -----------------------------------
if [ -t 1 ]; then
  C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_B=$'\033[36m'
  C_D=$'\033[2m';  C_0=$'\033[0m';  C_BOLD=$'\033[1m'
else
  C_R=; C_G=; C_Y=; C_B=; C_D=; C_0=; C_BOLD=
fi
info(){ printf '%s\n' "${C_B}▸${C_0} $*"; }
ok(){   printf '%s\n' "${C_G}✔${C_0} $*"; }
warn(){ printf '%s\n' "${C_Y}⚠${C_0} $*" >&2; }
die(){  printf '%s\n' "${C_R}✘ $*${C_0}" >&2; exit 1; }
hr(){   printf '%s\n' "${C_D}────────────────────────────────────────────────${C_0}"; }

# ------------------------------- 进度提示 -----------------------------------
# 运行时的分步进度，让用户随时知道「做到哪了、还要多久、卡住该怎么办」
TOTAL_STEPS=8
STEP=0
step(){
  STEP=$((STEP+1))
  printf '\n%s\n' "${C_BOLD}${C_B}━━ 第 ${STEP}/${TOTAL_STEPS} 步 · $* ━━${C_0}"
}
sub(){       printf '   %s\n' "$*"; }
hint(){      printf '   %s\n' "${C_D}↳ $*${C_0}"; }
warn_hint(){ printf '   %s\n' "${C_Y}↳ $*${C_0}"; }

env_desc(){
  case "$1" in
    termux) printf '%s' "（Termux 原生）";;
    proot)  printf '%s' "（proot 发行版）";;
    macos)  printf '%s' "（macOS）";;
    *)      printf '%s' "（Linux）";;
  esac
}

current_java_human(){
  local c; c="$(current_java)"
  [ "$c" = "0" ] && printf '未安装' || printf 'Java %s' "$c"
}

file_size(){
  local b; b="$(wc -c < "$1" 2>/dev/null || echo 0)"
  if [ "$b" -ge 1048576 ] 2>/dev/null; then
    awk -v b="$b" 'BEGIN{printf "%.1f MB", b/1048576}'
  else
    printf '%s 字节' "$b"
  fi
}

tty_progress(){ [ -t 2 ] && echo 1 || echo 0; }

# 尽力探测远端文件大小：跟随跳转后取最后一个 content-length
probe_size(){
  local cl
  cl="$(curl -sIL -m 20 "$1" 2>/dev/null \
        | awk 'tolower($1)=="content-length:"{v=$2} END{gsub(/\r/,"",v); print v}')"
  case "$cl" in ''|*[!0-9]*) return 1;; esac
  awk -v b="$cl" 'BEGIN{printf "约 %.1f MB", b/1048576}'
}

check_disk_space(){
  local avail mb
  avail="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"
  [ -z "$avail" ] && return 0
  mb=$(( avail / 1024 ))
  if [ "$mb" -lt 1024 ]; then
    warn "可用磁盘只有 ${mb} MB，服务端加世界存档通常需要 1 GB 以上"
    hint "先清理空间，或换个大点的目录：--dir /其它/路径"
  else
    sub "可用磁盘   $(( mb / 1024 )) GB"
  fi
}

check_memory_sanity(){
  local total_kb total_gb whole
  total_kb="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  [ "$total_kb" = "0" ] && return 0
  total_gb=$(( total_kb / 1024 / 1024 ))
  whole="${MEM%.*}"
  if [ "$whole" -gt $(( total_gb / 2 )) ] 2>/dev/null; then
    warn "你分配了 ${MEM}G，超过物理内存 ${total_gb}G 的一半"
    hint "服务端可能被系统强制结束（日志里表现为毫无征兆的 Killed）。建议降到 $(( total_gb / 2 ))G 以内"
  fi
}

print_plan(){
  hr
  printf '%s\n' "${C_BOLD}Minecraft 服务器部署${C_0}"
  hr
  printf '%s\n' "  服务端  ${C_BOLD}${LOADER}${C_0} ${VERSION}"
  printf '%s\n' "  环境    ${ENVK}$(env_desc "$ENVK")"
  printf '%s\n' "  Java    ${NEED_JAVA}"
  printf '%s\n' "  内存    ${MEM}G"
  printf '%s\n' "  目录    ${DIR}"
  printf '%s\n' "  端口    ${PORT}"
  hr
  printf '%s\n' "本次共 ${TOTAL_STEPS} 步："
  printf '%s\n' "  1 检查运行环境    2 准备 Java      3 解析下载地址    4 下载服务端"
  printf '%s\n' "  5 安装插件与模组  6 写入配置      7 生成启动脚本与管理工具   8 启动服务器"
  printf '%s\n' "${C_D}  视网速约 1~5 分钟。中途 Ctrl+C 可安全中断，不会留下坏文件${C_0}"
}

print_summary(){
  hr
  ok "${C_BOLD}部署完成${C_0}  目录: ${C_BOLD}${DIR}${C_0}"
  hr
  printf '%s\n' "${C_BOLD}接下来你可以：${C_0}"
  printf '%s\n' "  开服        cd ${DIR} && ./mcctl start"
  printf '%s\n' "  安全关服    ./mcctl stop          （自动存档，推荐）"
  printf '%s\n' "  看状态      ./mcctl status        （运行时长/内存/端口/日志）"
  printf '%s\n' "  备份世界    ./mcctl backup        （存到 ~/mc-backups，保留 7 份）"
  printf '%s\n' "  看日志      ./mcctl logs"
  printf '%s\n' "  改配置      nano ${DIR}/server.properties"
  printf '%s\n' "  自己先进    Minecraft 里「多人游戏 → 添加服务器」填 localhost:${PORT}"
  printf '%s\n' "  给别人进    同一 WiFi 下用 本机IP:${PORT}（ip addr 或 ifconfig 查）"
  hr
}


# ------------------------------- 默认参数 -----------------------------------
LOADER="paper"
VERSION="1.21.11"
MEM=""
PORT="auto"
MOTD=""
DIR=""
ONLINE_MODE="true"
VIEW_DIST=""
MAX_PLAYERS=""
DO_START=1
ASK=0
USE_MIRROR="auto"      # auto | always | never
NO_JAVA=0

# 插件与模组（默认值必须在参数解析之前，否则会把用户传入的值覆盖掉）
LOADER_VERSION=""     # 指定加载器版本（fabric/forge/neoforge），空=自动
PLUGINS=""
MODS=""
PICK=0
LIST_PLUGINS=0
LIST_MODS=0

# ------------------------------- 参数解析 -----------------------------------
usage(){
cat <<'EOF'
用法: deploy.sh [选项]

  --loader <名称>     paper | vanilla | fabric | neoforge | forge      (默认 paper)
  --version <版本>    Minecraft 版本，如 1.21.11 / 1.20.1 / 1.12.2    (默认 1.21.11)
  --mem <GB>          分配给服务器的内存，如 2 或 2.5                  (默认按设备自动)
  --port <端口>       监听端口                                        (默认 25565)
  --motd <文字>       服务器列表显示的名称
  --dir <路径>        安装目录                                        (默认 ~/mc)
  --online-mode <bool> 正版验证 true|false                            (默认 true)
  --view-distance <n> 视野距离                                        (默认按内存自动)
  --max-players <n>   最大玩家数                                      (默认按内存自动)
  --mirror <模式>     auto | always | never  优先使用国内镜像         (默认 auto)
  --no-start          只安装和配置，不立即启动
  --no-java           跳过 Java 检查与安装（已自行装好时使用）
  --dry-run           只解析并打印将要执行的步骤，不安装、不下载
  --ask               强制进入交互式向导
  --port <端口|auto>  监听端口，auto 表示静默探测一个空闲端口（默认 auto）
  --loader-version <v> 指定加载器版本（fabric / forge / neoforge），默认取最新
  --plugins <列表>    安装插件，逗号分隔，如 essentialsx,luckperms,worldedit
  --mods <列表>       安装模组，逗号分隔，如 lithium,ferrite-core,jei
  --pick              交互式挑选插件与模组（列出候选让你选编号）
  --list-plugins      列出全部候选插件后退出
  --list-mods         列出全部候选模组后退出
  -l, --list          列出全部可用「版本 × 服务端」组合后退出
  -h, --help          显示本帮助

示例:
  # Paper 1.21.11，2G 内存
  curl -fsSL <本脚本地址> | bash -s -- --loader paper --version 1.21.11 --mem 2

  # Fabric 1.21.1 模组服，4G
  curl -fsSL <本脚本地址> | bash -s -- --loader fabric --version 1.21.1 --mem 4

  # Forge 1.20.1（老整合包），3G，强制国内镜像
  curl -fsSL <本脚本地址> | bash -s -- --loader forge --version 1.20.1 --mem 3 --mirror always
EOF
}

while [ $# -gt 0 ]; do
  ARGS_GIVEN=1
  case "$1" in
    --loader)        LOADER="${2:-}"; shift 2;;
    --version|--ver) VERSION="${2:-}"; shift 2;;
    --mem|--memory)  MEM="${2:-}"; shift 2;;
    --port)          PORT="${2:-}"; shift 2;;
    --loader-version|--lv) LOADER_VERSION="${2:-}"; shift 2;;
    --motd)          MOTD="${2:-}"; shift 2;;
    --dir)           DIR="${2:-}"; shift 2;;
    --online-mode)   ONLINE_MODE="${2:-}"; shift 2;;
    --view-distance) VIEW_DIST="${2:-}"; shift 2;;
    --max-players)   MAX_PLAYERS="${2:-}"; shift 2;;
    --mirror)        USE_MIRROR="${2:-}"; shift 2;;
    --no-start)      DO_START=0; shift;;
    --no-java)       NO_JAVA=1; shift;;
    --dry-run)       DRY_RUN=1; shift;;
    --ask)           ASK=1; shift;;
    --plugins)       PLUGINS="${2:-}"; shift 2;;
    --mods)          MODS="${2:-}"; shift 2;;
    --pick)          PICK=1; shift;;
    --list-plugins)  LIST_PLUGINS=1; shift;;
    --list-mods)     LIST_MODS=1; shift;;
    -l|--list)       LIST_ONLY=1; shift;;
    -h|--help)       usage; exit 0;;
    *) die "未知参数: $1（用 --help 查看用法）";;
  esac
done

# 交互式读取必须走 /dev/tty：用 curl|bash 运行时 stdin 是脚本本身
ask(){
  # 用 curl|bash 运行时 stdin 是脚本本身，交互必须走 /dev/tty。
  # 但 /dev/tty 可能不存在或不可打开（非交互场景），所以要容错且不刷错误信息。
  local prompt="$1" def="$2" ans=""
  if [ "${HAS_TTY:-0}" = 1 ]; then
    printf '%s' "${C_BOLD}${prompt}${C_0} ${C_D}[${def}]${C_0} " > /dev/tty 2>/dev/null || true
    ans="$( { read -r _a < /dev/tty && printf '%s' "$_a"; } 2>/dev/null )" || ans=""
  fi
  printf '%s' "${ans:-$def}"
}

# ------------------------------- 环境探测 -----------------------------------
detect_env(){
  # Termux 原生：$PREFIX 指向 com.termux 下的 usr
  if [ -n "${PREFIX:-}" ] && printf '%s' "$PREFIX" | grep -q 'com\.termux'; then
    echo termux; return
  fi
  # proot 容器：内核版本串或进程状态里带 PRoot，或存在 PROOT_TMP_DIR
  # （注意不能用 A || B && C 的写法，运算符优先级会让判断失效）
  if [ -n "${PROOT_TMP_DIR:-}" ] \
     || printf '%s' "$(uname -r 2>/dev/null)" | grep -qi 'proot' \
     || grep -qai 'proot' /proc/self/status 2>/dev/null; then
    echo proot; return
  fi
  case "$(uname -s)" in
    Darwin) echo macos;;
    *) echo linux;;
  esac
}
ENVK="$(detect_env)"

# ------------------------------- Java 版本 ----------------------------------
# 与 Minecraft 官方要求一致：26.x→25，1.20.5~1.21.x→21，1.18~1.20.4→17，1.17→17，≤1.16.5→8
java_for(){
  local v="$1" a b c
  a="$(printf '%s' "$v" | cut -d. -f1)"
  b="$(printf '%s' "$v" | cut -d. -f2)"
  c="$(printf '%s' "$v" | cut -d. -f3)"; [ -z "$c" ] && c=0
  if [ "$a" -ge 26 ] 2>/dev/null; then echo 25; return; fi
  if [ "$a" -eq 1 ] && [ "$b" -ge 21 ] 2>/dev/null; then echo 21; return; fi
  if [ "$a" -eq 1 ] && [ "$b" -eq 20 ] && [ "$c" -ge 5 ] 2>/dev/null; then echo 21; return; fi
  if [ "$a" -eq 1 ] && [ "$b" -ge 18 ] 2>/dev/null; then echo 17; return; fi
  if [ "$a" -eq 1 ] && [ "$b" -eq 17 ] 2>/dev/null; then echo 17; return; fi
  echo 8
}
NEED_JAVA="$(java_for "$VERSION")"

current_java(){
  command -v java >/dev/null 2>&1 || { echo 0; return; }
  java -version 2>&1 | head -1 | sed -n 's/.*version "\([0-9]*\).*/\1/p'
}

# ------------------------------- 工具函数 -----------------------------------
have(){ command -v "$1" >/dev/null 2>&1; }

fetch(){
  # fetch <url> <输出文件> [progress]
  # progress 模式且输出是终端时显示进度条，否则静默（重定向到日志时不会刷屏）
  #
  # 注意：这里必须写「字面量」重定向。bash 不会把变量内容识别成重定向符，
  # 写成 $red（值为 2>/dev/null）会被当成额外参数传给 curl，
  # 结果 curl 报 "URL rejected: Bad hostname" 并返回退出码 3，很难排查。
  local url="$1" out="$2" mode="${3:-quiet}" i
  local show=0
  [ "$mode" = "progress" ] && [ -t 2 ] && show=1

  for i in 1 2 3; do
    if have curl; then
      if [ -s "$out" ]; then
        # 已有半截文件：先试断点续传；失败就删掉重下，避免错误内容越滚越大
        if [ "$show" = 1 ]; then
          curl -fL --progress-bar -C - -m 300 -o "$out" "$url" \
            || { rm -f "$out"; curl -fL --progress-bar -m 300 -o "$out" "$url"; }
        else
          curl -fsSL -C - -m 300 -o "$out" "$url" 2>/dev/null \
            || { rm -f "$out"; curl -fsSL -m 300 -o "$out" "$url" 2>/dev/null; }
        fi
      else
        if [ "$show" = 1 ]; then
          curl -fL --progress-bar -m 300 -o "$out" "$url"
        else
          curl -fsSL -m 300 -o "$out" "$url" 2>/dev/null
        fi
      fi
    elif have wget; then
      wget -q -O "$out" --tries=2 "$url" 2>/dev/null
    else
      die "系统里既没有 curl 也没有 wget，无法下载"
    fi
    [ -s "$out" ] && return 0
    [ "$i" -lt 3 ] && warn "第 ${i} 次下载未成功，稍后重试（共 3 次）"
    sleep 2
  done
  return 1
}

# ============================ 插件与模组 ====================================
# 内容来源：Modrinth 官方 API —— 按「加载器 + MC 版本」实时匹配可用文件，
# 不写死下载地址，避免上游更新后 404。

CATALOG_FILE=""

REPO_BASES="
https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main
https://cdn.jsdelivr.net/gh/zhuzijiang/mc-server-deploy@main
https://ghproxy.net/https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main
https://gh-proxy.com/https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main"

CATALOG_URLS="
https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/catalog.json
https://cdn.jsdelivr.net/gh/zhuzijiang/mc-server-deploy@main/catalog.json
https://ghproxy.net/https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/catalog.json
https://gh-proxy.com/https://raw.githubusercontent.com/zhuzijiang/mc-server-deploy/main/catalog.json"

fetch_catalog(){
  [ -n "$CATALOG_FILE" ] && [ -s "$CATALOG_FILE" ] && return 0
  # 本地目录覆盖（便于离线使用与测试）：MC_CATALOG=/path/to/catalog.json
  if [ -n "${MC_CATALOG:-}" ] && [ -s "$MC_CATALOG" ]; then CATALOG_FILE="$MC_CATALOG"; return 0; fi
  local f="${TMPDIR:-/tmp}/mc-catalog.$$.json" base
  : > "$f"
  for base in $CATALOG_URLS; do
    if fetch "$base" "$f" 2>/dev/null && [ -s "$f" ]; then CATALOG_FILE="$f"; return 0; fi
  done
  return 1
}

# 从 catalog.json 取出某类条目（不依赖 python3 / jq）
catalog_items(){
  local kind="$1" arr
  case "$kind" in
    plugins) arr="$(sed -n 's/.*"plugins":\[//; s/\],"mods":\[.*//p' "$CATALOG_FILE" | head -1)";;
    mods)    arr="$(sed -n 's/.*"mods":\[//;   s/\]}*$//p'       "$CATALOG_FILE" | head -1)";;
    *) return 1;;
  esac
  [ -n "$arr" ] || return 1
  printf '%s\n' "$arr" | sed 's/},{/\n/g' | while IFS= read -r item; do
    local slug title cat side
    slug="$(printf '%s' "$item" | sed -n 's/.*"slug":"\([^"]*\)".*/\1/p')"
    title="$(printf '%s' "$item" | sed -n 's/.*"title":"\([^"]*\)".*/\1/p')"
    cat="$(printf '%s' "$item" | sed -n 's/.*"cat":"\([^"]*\)".*/\1/p')"
    side="$(printf '%s' "$item" | sed -n 's/.*"side":"\([^"]*\)".*/\1/p')"
    [ -n "$slug" ] && printf '%s\t%s\t%s\t%s\n' "$slug" "$title" "$cat" "$side"
  done
}

# 只列出候选，供 --list-plugins / --list-mods 使用
show_catalog(){
  local kind="$1" label="$2" n=0 lastcat="" slug title cat side
  if ! fetch_catalog; then
    warn "无法获取候选目录（需要联网访问仓库）"
    return 1
  fi
  hr
  printf '%s\n' "${C_BOLD}可选${label}（共 $(catalog_items "$kind" | wc -l) 个）${C_0}"
  hr
  while IFS="$(printf '\t')" read -r slug title cat side; do
    [ -z "$slug" ] && continue
    n=$((n+1))
    if [ "$cat" != "$lastcat" ]; then printf '\n  %s\n' "${C_B}【${cat}】${C_0}"; lastcat="$cat"; fi
    local mark=""
    [ "$side" = "both" ]   && mark=" ★需客户端"
    [ "$side" = "client" ] && mark=" ⚠仅客户端"
    printf '  %2d) %-24s %s%s\n' "$n" "$slug" "$title" "$mark"
  done <<EOF
$(catalog_items "$kind")
EOF
  printf '\n%s\n' "${C_D}用法：--${kind} slug1,slug2   多个用逗号隔开${C_0}"
}

# 交互式挑选，输出逗号分隔的 slug
pick_items(){
  local kind="$1" label="$2"
  if ! fetch_catalog; then
    warn "无法获取候选目录（需要联网），请改用 --${kind} slug1,slug2 直接指定"
    printf ''
    return 1
  fi
  if [ "${HAS_TTY:-0}" != 1 ]; then
    warn "当前没有可交互的终端，请用 --${kind} slug1,slug2 指定"
    printf ''
    return 1
  fi
  local lines; lines="$(catalog_items "$kind")"
  [ -n "$lines" ] || { warn "目录内容为空"; printf ''; return 1; }

  hr
  printf '%s\n' "${C_BOLD}挑选${label}${C_0}"
  printf '%s\n' "${C_D}  输入编号，多个用逗号隔开；all 全选，none 不装${C_0}"
  printf '%s\n' "${C_D}  ★ 需要客户端也装模组    ⚠ 仅客户端，装在服务端没用${C_0}"
  local n=0 lastcat="" slug title cat side mark
  while IFS="$(printf '\t')" read -r slug title cat side; do
    [ -z "$slug" ] && continue
    n=$((n+1))
    if [ "$cat" != "$lastcat" ]; then printf '\n  %s\n' "${C_B}【${cat}】${C_0}"; lastcat="$cat"; fi
    mark=""
    [ "$side" = "both" ]   && mark=" ★需客户端"
    [ "$side" = "client" ] && mark=" ⚠仅客户端"
    printf '  %2d) %-24s %s%s\n' "$n" "$slug" "$title" "$mark"
  done <<EOF
$lines
EOF

  printf '%s' "${C_BOLD}> ${C_0}"
  local ans; ans="$( { read -r _a < /dev/tty && printf '%s' "$_a"; } 2>/dev/null )" || ans=""
  case "$ans" in
    ""|none|no|n) printf ''; return 0;;
    all|a) printf '%s' "$lines" | cut -f1 | paste -sd, -; return 0;;
  esac
  local out="" idx=0 want
  for want in $(printf '%s' "$ans" | tr ',' ' '); do
    idx=0
    while IFS="$(printf '\t')" read -r slug title cat side; do
      [ -z "$slug" ] && continue
      idx=$((idx+1))
      [ "$idx" = "$want" ] && { out="${out:+$out,}$slug"; break; }
    done <<EOF
$lines
EOF
  done
  printf '%s' "$out"
}

# 把空格分隔的列表编码成 URL 里的 ["a","b"]
enc_arr(){
  local out="%5B" first=1 x
  for x in $1; do
    [ "$first" = 1 ] || out="$out%2C"; first=0
    out="$out%22$x%22"
  done
  printf '%s' "$out%5D"
}

# 当前加载器对应的 Modrinth 加载器标签
modrinth_loaders(){
  case "$LOADER" in
    paper|folia|purpur) printf '%s' "paper spigot bukkit";;
    fabric)   printf '%s' "fabric";;
    forge)    printf '%s' "forge";;
    neoforge) printf '%s' "neoforge";;
    *)        printf '';;
  esac
}

resolve_modrinth(){
  fetch_text "https://api.modrinth.com/v2/project/$1/version?loaders=$(enc_arr "$2")&game_versions=$(enc_arr "$3")"
}

# 下载并安装一批内容
install_contents(){
  local kind="$1" list="$2" target="$3" label="$4"
  local loaders; loaders="$(modrinth_loaders)"
  local slug json url name env sz ok=0 skip=0

  [ -z "$list" ] && return 0
  if [ -z "$loaders" ]; then
    warn "${LOADER} 不支持${label}，已跳过：${list}"
    return 0
  fi

  mkdir -p "$target"
  sub "目标目录   ${target}/"

  for slug in $(printf '%s' "$list" | tr ',' ' '); do
    [ -z "$slug" ] && continue
    json="$(resolve_modrinth "$slug" "$loaders" "$VERSION")"
    if [ -z "$json" ] || [ "$json" = "[]" ]; then
      warn "${slug}：没有适配 ${LOADER} + MC ${VERSION} 的版本，已跳过"
      skip=$((skip+1)); continue
    fi
    # 注意：jget 的第二个参数才是 JSON 本体，不能写成管道
    url="$(jget url "$json")"
    name="$(jget filename "$json")"
    env="$(jget environment "$json")"
    if [ -z "$url" ] || [ -z "$name" ]; then
      warn "${slug}：解析文件地址失败，已跳过"
      skip=$((skip+1)); continue
    fi
    if [ "$env" = "client_only" ]; then
      warn "${slug}：仅客户端内容，装在服务端没有作用，已跳过"
      skip=$((skip+1)); continue
    fi
    sub "下载 ${slug} → ${name}"
    if fetch "$url" "${target}/${name}" quiet && is_jar "${target}/${name}"; then
      sz="$(file_size "${target}/${name}")"
      ok "  ${name}  (${sz})"
      ok=$((ok+1))
    else
      warn "${slug} 下载失败或文件无效，已跳过"
      rm -f "${target}/${name}"
      skip=$((skip+1))
    fi
  done

  printf '   结果       成功 %d 个，跳过 %d 个\n' "$ok" "$skip"
}

# curl 的可用性是整个流程的前提：解析下载地址、下载服务端全靠它。
# Termux 上 libcurl 与 openssl 版本错配时，curl 会在动态链接阶段直接失败，
# 报 CANNOT LINK EXECUTABLE，此时连"下一步该干嘛"都提示不出来，所以单独预检。
preflight_curl(){
  have curl || die "系统里找不到 curl。请先安装：
     Termux:  pkg install curl
     Ubuntu:  apt-get install -y curl"

  curl --version >/dev/null 2>&1 && return 0

  printf '%s\n' "${C_R}✘ curl 无法运行（动态链接失败）${C_0}" >&2
  if [ "$ENVK" = "termux" ]; then
    cat >&2 <<'EOT'
   典型报错：
     CANNOT LINK EXECUTABLE "curl": cannot locate symbol
     "SSL_set_quic_tls_early_data_enabled" referenced by libcurl.so

   原因：Termux 的 libcurl 升级了，但 openssl 没跟上（多见于单独执行
   pkg install curl，而 Termux 官方要求统一用 pkg upgrade）。

   修复，按顺序试：
     1) 直接重跑本脚本 —— 这常常只是升级过程中的瞬时状态，几秒后就自愈
     2) 仍不行就统一升级：
          pkg upgrade -y
     3) 若 pkg 也报同样的链接错误（apt 同样依赖 libcurl），
        用手机浏览器打开下面这个目录，下载文件名里带 aarch64 的 openssl 包，
        放到手机的 Download 目录，然后执行：
          dpkg -i /sdcard/Download/openssl_*_aarch64.deb
        https://packages.termux.dev/apt/termux-main/pool/main/o/openssl/
EOT
  else
    printf '%s\n' "   请重新安装 curl 后重试。" >&2
  fi
  exit 1
}

# 判断文件是不是真正的 jar：jar 本质是 zip，头两字节固定为 PK。
# 比按体积猜可靠得多 —— Fabric 的启动器 jar 只有约 170 KB，
# 而网络拦截页面虽可能有几十 KB，却不会以 PK 开头。
is_jar(){
  [ "$(head -c 2 "$1" 2>/dev/null)" = "PK" ]
}

fetch_text(){
  # 拉取小体积 JSON。空响应视为失败并重试，避免一次抖动就让整个流程中断
  local url="$1" out="" i
  for i in 1 2 3; do
    if have curl; then out="$(curl -fsSL --retry 2 --retry-delay 1 -m 60 "$url" 2>/dev/null)"
    else out="$(wget -q -O - --tries=1 "$url" 2>/dev/null)"; fi
    if [ -n "$out" ]; then printf '%s' "$out"; return 0; fi
    sleep 1
  done
  return 1
}

# 解析 JSON 里的第一个指定字段值（容忍空格，适配紧凑与缩进两种排版）
jget(){
  printf '%s' "$2" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed 's/.*"\([^"]*\)"$/\1/'
}

# 提取 JSON 里的第一个数字字段（如 "size": 54846016）
jnum(){
  printf '%s' "$2" | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*[0-9]+" | head -1 | grep -oE '[0-9]+$'
}

sha256_of(){
  if have sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif have shasum; then shasum -a 256 "$1" | awk '{print $1}'
  elif have openssl; then openssl dgst -sha256 "$1" | awk '{print $NF}'
  else echo ""; fi
}

sha1_of(){
  if have sha1sum; then sha1sum "$1" | awk '{print $1}'
  elif have shasum; then shasum -a 1 "$1" | awk '{print $1}'
  elif have openssl; then openssl dgst -sha1 "$1" | awk '{print $NF}'
  else echo ""; fi
}

md5_of(){
  if have md5sum; then md5sum "$1" | awk '{print $1}'
  elif have md5; then md5 -q "$1"
  elif have openssl; then openssl dgst -md5 "$1" | awk '{print $NF}'
  else echo ""; fi
}

# 按指定算法计算文件摘要
digest_of(){
  case "${1:-sha256}" in
    sha1) sha1_of "$2";;
    md5)  md5_of "$2";;
    *)    sha256_of "$2";;
  esac
}

want_mirror(){
  case "$USE_MIRROR" in
    always) return 0;;
    never)  return 1;;
    *)  # auto：Termux / proot 环境默认走国内镜像，桌面 Linux 与 macOS 走官方源
        if [ "$ENVK" = "termux" ] || [ "$ENVK" = "proot" ]; then return 0; else return 1; fi;;
  esac
}

# Java 不接受小数堆大小（-Xmx2.5G 会报错），小数一律换算成 MB
mem_flag(){
  case "$1" in
    *.*) awk -v g="$1" 'BEGIN{printf "%dM", g*1024}';;
    *)   printf '%sG' "$1";;
  esac
}

# 只保留数字，避免用户输入带单位或小数导致算术/配置出错
int_only(){ printf '%s' "$1" | tr -cd '0-9'; }

# ------------------------------- 端口探测 -----------------------------------
# 注意：Android 上 /proc/net/tcp 是 Permission denied，不能作为主要依据。
# 按可靠性依次尝试：python3 bind > /dev/tcp 连接 > ss/netstat/lsof > /proc/net/tcp
port_used(){
  local p="$1"
  if have python3; then
    if python3 -c '
import socket, sys
s = socket.socket()
try:
    s.bind(("", int(sys.argv[1])))
except OSError:
    sys.exit(0)
sys.exit(1)
' "$p" 2>/dev/null; then return 0; fi
  fi
  if (exec 3<>/dev/tcp/127.0.0.1/"$p") 2>/dev/null; then exec 3<&- 2>/dev/null; return 0; fi
  if have ss; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$p\$" && return 0
  elif have netstat; then
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$p\$" && return 0
  elif have lsof; then
    lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1 && return 0
  fi
  if [ -r /proc/net/tcp ]; then
    local hex; hex="$(printf '%04X' "$p" 2>/dev/null)"
    awk -v h=":$hex" 'NR>1 && toupper($2) ~ h"$" && $4=="0A"{x=1} END{exit !x}' \
      /proc/net/tcp /proc/net/tcp6 2>/dev/null && return 0
  fi
  return 1
}

# 静默探测可用端口：从 25565 起向后顺延，过程中不打印任何东西
find_free_port(){
  local start="${1:-25565}" p i
  p="$start"
  for i in $(seq 1 200); do
    port_used "$p" || { printf '%s' "$p"; return 0; }
    p=$((p + 1))
  done
  printf '%s' "$p"
}

# ------------------------------- 管理工具 mcctl ------------------------------
# 多通道获取，任一可用即成功；失败不影响开服
install_mcctl(){
  local f="${TMPDIR:-/tmp}/mcctl.$$" base
  rm -f "$f"
  for base in $REPO_BASES; do
    if fetch "$base/mcctl" "$f" 2>/dev/null && [ -s "$f" ] && head -1 "$f" 2>/dev/null | grep -q '^#!'; then
      cp -f "$f" ./mcctl && chmod +x ./mcctl 2>/dev/null && rm -f "$f"
      return 0
    fi
  done
  rm -f "$f"
  return 1
}

# ------------------------------- 安装 Java ----------------------------------
install_java(){
  [ "$NO_JAVA" = 1 ] && { info "按参数跳过 Java 检查"; return; }
  local cur; cur="$(current_java)"

  if [ "$cur" != "0" ] && [ "$cur" -ge "$NEED_JAVA" ] 2>/dev/null; then
    ok "已检测到 Java ${cur}，满足 MC ${VERSION} 的要求（需 ${NEED_JAVA}+）"
    return
  fi
  if [ "$cur" != "0" ]; then
    warn "当前 Java ${cur} 低于 MC ${VERSION} 所需的 ${NEED_JAVA}，将安装新版"
  else
    info "未检测到 Java，开始安装 Java ${NEED_JAVA}"
  fi

  case "$ENVK" in
    termux)
      have pkg || die "找不到 pkg 命令，当前似乎不是 Termux 环境"
      if [ "$NEED_JAVA" = 8 ]; then
        die "Termux 官方仓库不提供 Java 8。MC ${VERSION} 需要 Java 8：
     · 建议改用 proot 发行版(Ubuntu)环境部署，或
     · 把版本换成 1.18 以上（需 Java 17+）"
      fi
      info "安装 openjdk-${NEED_JAVA}（Termux 仓库）"
      pkg update -y >/dev/null 2>&1 || warn "pkg update 有警告，继续"
      # 绝对不要在这里带上 curl！
      # Termux 官方要求用 pkg upgrade 统一升级；单独 pkg install curl 会把 libcurl
      # 升到新版而 openssl 还停在旧版，导致 curl 动态链接失败：
      #   CANNOT LINK EXECUTABLE "curl": cannot locate symbol "SSL_set_quic_tls_early_data_enabled"
      # 一旦 curl 挂了，整个脚本连下载地址都解析不了。
      pkg install -y "openjdk-${NEED_JAVA}" || die "安装 Java 失败。
     Termux 上常见原因是包索引与已装包不一致，先做一次统一升级再重试：
       pkg upgrade -y"
      have termux-wake-lock && { termux-wake-lock 2>/dev/null && ok "已获取唤醒锁（防止息屏挂起）"; }
      ;;
    proot|linux)
      local SUDO=""
      [ "$(id -u)" != "0" ] && have sudo && SUDO="sudo"
      local PKG="openjdk-${NEED_JAVA}-jre-headless"
      if have apt-get; then
        info "apt 安装 ${PKG}"
        $SUDO apt-get update -qq || warn "apt update 有警告，继续"
        $SUDO apt-get install -y "$PKG" curl || die "安装 Java 失败"
      elif have dnf; then
        info "dnf 安装 java-${NEED_JAVA}-openjdk-headless"
        $SUDO dnf install -y "java-${NEED_JAVA}-openjdk-headless" curl || die "安装 Java 失败"
      elif have pacman; then
        $SUDO pacman -Sy --noconfirm "jre${NEED_JAVA}-openjdk" || die "安装 Java 失败"
      else
        die "无法识别的包管理器，请手动安装 Java ${NEED_JAVA} 后加 --no-java 重试"
      fi
      ;;
    macos)
      have brew || die "未安装 Homebrew，请先安装，或手动装 Java ${NEED_JAVA} 后加 --no-java 重试"
      info "brew 安装 openjdk@${NEED_JAVA}"
      brew install "openjdk@${NEED_JAVA}" || die "安装 Java 失败"
      local P="/opt/homebrew/opt/openjdk@${NEED_JAVA}/bin"
      [ -d "$P" ] || P="/usr/local/opt/openjdk@${NEED_JAVA}/bin"
      export PATH="$P:$PATH"
      grep -q "openjdk@${NEED_JAVA}/bin" "$HOME/.zshrc" 2>/dev/null || \
        printf '\nexport PATH="%s:$PATH"\n' "$P" >> "$HOME/.zshrc"
      ok "已把 Java 加入 PATH，并写入 ~/.zshrc"
      ;;
  esac

  cur="$(current_java)"
  [ "$cur" != "0" ] && [ "$cur" -ge "$NEED_JAVA" ] 2>/dev/null \
    && ok "Java ${cur} 就绪" \
    || die "Java 安装后仍检测不到，新终端里重试，或手动检查 java -version"
}

# ------------------------------- 解析下载地址 -------------------------------
SRC_URL=""; SRC_MODE="jar"   # jar=直接可跑的 jar；installer=需要先跑安装器
SRC_SIZE_HINT="未知（视服务端而定）"
SRC_SHA=""; SRC_NAME="server.jar"; IS_INSTALLER=0; SRC_ALGO="sha256"

resolve_urls(){
  info "解析 ${LOADER} ${VERSION} 的下载地址"
  case "$LOADER" in
    paper|folia)
      # Paper 与 Folia 同一个 Fill API，只是项目名不同
      local j; j="$(fetch_text "https://fill.papermc.io/v3/projects/${LOADER}/versions/${VERSION}/builds/latest")"
      SRC_URL="$(jget url "$j")"
      SRC_NAME="$(jget name "$j")"
      SRC_SHA="$(jget sha256 "$j")"
      SRC_ALGO="sha256"
      [ -n "$SRC_URL" ] || die "未能解析 Paper ${VERSION} 的下载地址。
     可能原因：该版本不存在 / 网络不通 / API 变更。
     可换版本，或用 --loader vanilla 部署原版。"
      ok "Paper 构建: ${SRC_NAME}"
      local _b; _b="$(jnum size "$j")"
      [ -n "$_b" ] && SRC_SIZE_HINT="$(awk -v b="$_b" 'BEGIN{printf "约 %.0f MB", b/1048576}')"
      ;;
    purpur)
      # Purpur 有自己的 API，返回最新构建号与 md5
      local j b
      j="$(fetch_text "https://api.purpurmc.org/v2/purpur/${VERSION}/latest")"
      b="$(jget build "$j")"
      [ -n "$b" ] || die "Purpur 没有 MC ${VERSION} 的构建。
     Purpur 从 1.14.1 开始支持，可用 --dry-run 前先确认版本。"
      SRC_URL="https://api.purpurmc.org/v2/purpur/${VERSION}/${b}/download"
      SRC_NAME="purpur-${VERSION}-${b}.jar"
      SRC_SHA="$(jget md5 "$j")"; SRC_ALGO="md5"
      SRC_SIZE_HINT="$(jnum size "$j" | awk '{printf "约 %.0f MB", $1/1048576}')"
      ok "Purpur 构建 ${b}"
      ;;

    vanilla)
      if want_mirror; then
        SRC_URL="https://bmclapi2.bangbang93.com/version/${VERSION}/server"
        SRC_SHA=""; SRC_ALGO=""
        info "使用 BMCLAPI 国内镜像"
      else
        local man vl vj
        man="$(fetch_text "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")"
        vl=""
        if have python3; then
          vl="$(printf '%s' "$man" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(next((x['url'] for x in d['versions'] if x['id']=='${VERSION}'),''))" 2>/dev/null)"
        fi
        if [ -z "$vl" ]; then
          vl="$(printf '%s' "$man" | tr ',' '\n' | grep -F "\"id\":\"${VERSION}\"" -A2 \
                 | grep -oE 'https://[^"]+\.json' | head -1)"
        fi
        [ -n "$vl" ] || die "在官方清单里找不到版本 ${VERSION}"

        vj="$(fetch_text "$vl")"
        SRC_URL=""; SRC_SHA=""
        if have python3; then
          SRC_URL="$(printf '%s' "$vj" | python3 -c "
import json,sys
print(json.load(sys.stdin)['downloads']['server']['url'])" 2>/dev/null)"
          SRC_SHA="$(printf '%s' "$vj" | python3 -c "
import json,sys
print(json.load(sys.stdin)['downloads']['server']['sha1'])" 2>/dev/null)"
        fi
        if [ -z "$SRC_URL" ]; then
          # 无 python3（如纯净 Termux）时的退化解析：
          # 版本 JSON 里第一个 "url" 属于 assetIndex，必须定位到 downloads.server 对象内部
          local flat; flat="$(printf '%s' "$vj" | tr -d '\n\r')"
          SRC_URL="$(printf '%s' "$flat" | sed -n 's/.*"server":[[:space:]]*{[^}]*"url":[[:space:]]*"\([^"]*\)".*/\1/p')"
          SRC_SHA="$(printf '%s' "$flat" | sed -n 's/.*"server":[[:space:]]*{[^}]*"sha1":[[:space:]]*"\([^"]*\)".*/\1/p')"
        fi
        SRC_ALGO="sha1"
        case "$SRC_URL" in
          https://*) ;;
          *)
            # 官方源偶发失败时不直接退出，自动退回国内镜像，避免卡住新手
            warn "官方源解析失败（可能是网络问题），自动改用 BMCLAPI 国内镜像"
            SRC_URL="https://bmclapi2.bangbang93.com/version/${VERSION}/server"
            SRC_SHA=""; SRC_ALGO=""
            ;;
        esac
      fi
      ;;
    fabric)
      local lj ld ins
      lj="$(fetch_text "https://meta.fabricmc.net/v2/versions/loader/${VERSION}")"
      ld="$(jget version "$lj")"
      [ -n "$ld" ] || die "Fabric 不支持 MC ${VERSION}（或接口异常）。Fabric 官方支持 1.14 及以上。"
      if [ -n "${LOADER_VERSION:-}" ] && [ "$LOADER_VERSION" != "latest" ]; then
        if printf '%s' "$lj" | grep -q "\"version\"[[:space:]]*:[[:space:]]*\"${LOADER_VERSION}\""; then
          ld="$LOADER_VERSION"; ok "使用指定的 loader 版本 ${ld}"
        else
          warn "该 MC 版本没有 loader ${LOADER_VERSION}，改用最新的 ${ld}"
        fi
      fi
      ins="$(jget version "$(fetch_text "https://meta.fabricmc.net/v2/versions/installer")")"
      SRC_URL="https://meta.fabricmc.net/v2/versions/loader/${VERSION}/${ld}/${ins}/server/jar"
      SRC_NAME="fabric-server-mc.${VERSION}-loader.${ld}-launcher.${ins}.jar"
      ok "Fabric loader ${ld} / installer ${ins}"
      ;;
    neoforge|forge)
      IS_INSTALLER=1; SRC_NAME="installer.jar"
      if [ "$LOADER" = neoforge ]; then
        local nj n
        nj="$(fetch_text "https://bmclapi2.bangbang93.com/neoforge/list/${VERSION}")"
        n="$(printf '%s' "$nj" | grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' | grep -v beta | tail -1)"
        [ -z "$n" ] && n="$(printf '%s' "$nj" | grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' | tail -1)"
        if [ -n "${LOADER_VERSION:-}" ] && [ "$LOADER_VERSION" != "latest" ]; then
          if printf '%s' "$nj" | grep -q "\"version\"[[:space:]]*:[[:space:]]*\"${LOADER_VERSION}\""; then
            n="$LOADER_VERSION"; ok "使用指定的 NeoForge 版本 ${n}"
          else
            warn "该 MC 版本没有 NeoForge ${LOADER_VERSION}，改用 ${n}"
          fi
        fi
        [ -n "$n" ] || die "NeoForge 不支持 MC ${VERSION}。NeoForge 仅支持 1.20.2 及以上。"
        SRC_URL="https://maven.neoforged.net/releases/net/neoforged/neoforge/${n}/neoforge-${n}-installer.jar"
        if want_mirror; then SRC_URL="https://bmclapi2.bangbang93.com/maven/net/neoforged/neoforge/${n}/neoforge-${n}-installer.jar"; fi
        ok "NeoForge ${n}"
      else
        local pj n
        pj="$(fetch_text "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json")"
        n="$(jget "${VERSION}-recommended" "$pj")"
        [ -z "$n" ] && n="$(jget "${VERSION}-latest" "$pj")"
        if [ -n "${LOADER_VERSION:-}" ] && [ "$LOADER_VERSION" != "latest" ]; then
          n="$LOADER_VERSION"; ok "使用指定的 Forge 版本 ${n}"
        fi
        [ -n "$n" ] || die "Forge 没有为 MC ${VERSION} 发布版本。
     可查 https://files.minecraftforge.net/ 确认支持的版本。"
        SRC_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/${VERSION}-${n}/forge-${VERSION}-${n}-installer.jar"
        if want_mirror; then SRC_URL="https://bmclapi2.bangbang93.com/maven/net/minecraftforge/forge/${VERSION}-${n}/forge-${VERSION}-${n}-installer.jar"; fi
        ok "Forge ${n}（推荐版）"
      fi
      ;;
    *) die "未知服务端类型: ${LOADER}";;
  esac
}

# ------------------------------- 自动参数 -----------------------------------
auto_params(){
  local total_kb total_gb
  total_kb="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 8388608)"
  total_gb=$(( total_kb / 1024 / 1024 ))

  if [ -z "$MEM" ]; then
    MEM=$(( total_gb / 4 ))
    [ "$MEM" -lt 1 ] && MEM=1
    [ "$MEM" -gt 8 ] && MEM=8
    info "未指定内存，按系统总内存 ${total_gb}G 自动取 ${MEM}G"
  fi
  if [ -z "$VIEW_DIST" ]; then
    if   [ "${MEM%.*}" -le 1 ] 2>/dev/null; then VIEW_DIST=5
    elif [ "${MEM%.*}" -le 3 ] 2>/dev/null; then VIEW_DIST=6
    else VIEW_DIST=8; fi
  fi
  if [ -z "$MAX_PLAYERS" ]; then
    if   [ "${MEM%.*}" -le 1 ] 2>/dev/null; then MAX_PLAYERS=5
    elif [ "${MEM%.*}" -le 3 ] 2>/dev/null; then MAX_PLAYERS=10
    else MAX_PLAYERS=20; fi
  fi
  [ -z "$DIR" ] && DIR="$HOME/mc"
  [ -z "$MOTD" ] && MOTD="Minecraft Server ${VERSION}"

  # 端口：auto = 静默探测一个空闲端口（不打印探测过程）
  if [ -z "$PORT" ] || [ "$PORT" = "auto" ]; then
    PORT="$(find_free_port 25565)"
  else
    PORT="$(int_only "$PORT")"; [ -z "$PORT" ] && PORT=25565
    port_used "$PORT" && warn "端口 ${PORT} 当前被占用，仍按你的指定使用（可能启动失败）"
  fi

  # 归一化：视距/人数必须是纯整数
  VIEW_DIST="$(int_only "$VIEW_DIST")";  [ -z "$VIEW_DIST" ] && VIEW_DIST=6
  MAX_PLAYERS="$(int_only "$MAX_PLAYERS")"; [ -z "$MAX_PLAYERS" ] && MAX_PLAYERS=10
  SIM_DIST=$(( VIEW_DIST > 4 ? VIEW_DIST - 1 : 4 ))
}

# ------------------------------- 安装流程 -----------------------------------
do_install(){
  print_plan

  if [ "${DRY_RUN:-0}" = 1 ]; then
    step "预演模式：只解析地址，不做任何改动"
    printf '%s\n' "   Java 需求 : ${NEED_JAVA}（当前检测到: $(current_java)）"
    resolve_urls
    printf '%s\n' "   服务端文件: ${SRC_NAME}"
    printf '%s\n' "   下载地址  : ${SRC_URL}"
    [ -n "$SRC_SHA" ] && printf '%s\n' "   校验值(${SRC_ALGO:-sha256}) : ${SRC_SHA}"
    printf '%s\n' "   内存参数  : -Xms$(mem_flag "$MEM") -Xmx$(mem_flag "$MEM")"
    printf '%s\n' "   安装目录  : ${DIR}"
    printf '%s\n' "   端口/视距 : ${PORT} / ${VIEW_DIST}（模拟距离 ${SIM_DIST}）"
    printf '%s\n' "   插件       : ${PLUGINS:-（无）}"
    printf '%s\n' "   模组       : ${MODS:-（无）}"
    printf '\n%s\n' "${C_D}以上地址均可直接复制到下载工具里手动下载。去掉 --dry-run 即真正开始部署。${C_0}"
    exit 0
  fi

  # ---------------------------------------------------------------- 1
  step "检查运行环境"
  sub "运行环境   ${ENVK}$(env_desc "$ENVK")"
  sub "Java 需求  ${NEED_JAVA}（当前: $(current_java_human)）"
  sub "安装目录   ${DIR}"
  sub "监听端口   ${PORT}   内存 ${MEM}G"

  preflight_curl
  check_disk_space
  check_memory_sanity
  [ "$ENVK" = "termux" ] && hint "开服期间请勿清理 Termux 通知栏的常驻通知，否则系统可能回收进程"
  [ "$ENVK" = "proot" ]  && hint "建议先在 Termux 外层执行 termux-wake-lock，防止息屏后被挂起"

  # ---------------------------------------------------------------- 2
  step "准备 Java ${NEED_JAVA}"
  install_java
  sub "java 位置  $(command -v java 2>/dev/null || echo '未找到')"

  # ---------------------------------------------------------------- 3
  step "解析服务端下载地址"
  resolve_urls
  sub "服务端     ${SRC_NAME}"
  if [ "$IS_INSTALLER" = 1 ]; then
    hint "该服务端需要先运行安装器，会额外下载依赖库，耗时较长"
  else
    # Paper 已从 API 拿到准确大小；其它来源尽力探测一次
    case "$SRC_SIZE_HINT" in
      *未知*) ps="$(probe_size "$SRC_URL" 2>/dev/null)" && [ -n "$ps" ] && SRC_SIZE_HINT="$ps";;
    esac
    sub "文件大小   ${SRC_SIZE_HINT:-未知}"
  fi

  # ---------------------------------------------------------------- 4
  step "下载服务端文件"
  mkdir -p "$DIR" || die "无法创建目录 $DIR"
  cd "$DIR" || die "无法进入目录 $DIR"
  sub "保存到     ${DIR}/"

  local T0 T1
  T0=$(date +%s)

  if [ "$IS_INSTALLER" = 1 ]; then
    sub "正在下载安装器..."
    fetch "$SRC_URL" "installer.jar" progress || die "下载失败。
     地址: ${SRC_URL}
     排查: 1) 网络是否可用  2) 加 --mirror always 走国内镜像  3) 用 --dry-run 拿到地址后手动下载"
    sub "安装器大小 $(file_size installer.jar)"
    is_jar installer.jar || die "下载到的安装器不是有效的 jar（开头不是 PK），多半被网络拦截了。
     地址: ${SRC_URL}"
    printf '\n'
    warn_hint "接下来运行安装器，需要下载几十 MB 依赖库，慢是正常的，请勿中断"
    java -jar installer.jar --installServer || die "安装器执行失败，请查看上方输出。
     常见原因: Java 版本不符 / 网络中断 / 磁盘空间不足"
    ok "安装器执行完成"
  else
    sub "正在下载 ${SRC_NAME} ..."
    [ "$(tty_progress)" = "1" ] || hint "当前输出不是终端，不显示进度条属正常"
    fetch "$SRC_URL" "server.jar" progress || die "下载失败。
     地址: ${SRC_URL}
     排查: 1) 网络是否可用  2) 加 --mirror always 走国内镜像  3) 用 --dry-run 拿到地址后手动下载"
    T1=$(( $(date +%s) - T0 ))
    sub "已下载     $(file_size server.jar)   耗时 ${T1} 秒"

    if ! is_jar server.jar; then
      die "下载到的不是有效的 jar 文件（$(file_size server.jar)，开头不是 PK）。
     多半是被网络拦截成了错误页面，或下载被中途截断。
     处理: 加 --mirror always 重试，或手动打开这个地址下载后放进 ${DIR}/
           ${SRC_URL}"
    fi

    if [ -n "$SRC_SHA" ]; then
      sub "校验 ${SRC_ALGO} ..."
      local got; got="$(digest_of "$SRC_ALGO" server.jar)"
      if [ -n "$got" ] && [ "$got" = "$SRC_SHA" ]; then
        ok "${SRC_ALGO} 校验通过"
      elif [ -n "$got" ]; then
        warn "${SRC_ALGO} 与官方值不一致（上游可能已更新构建，通常不影响使用）"
        printf '   期望: %s\n   实际: %s\n' "$SRC_SHA" "$got"
      else
        hint "系统里没有 sha256sum/shasum/openssl，跳过校验"
      fi
    else
      hint "该下载源未提供校验值，跳过校验"
    fi
  fi

  # ---------------------------------------------------------------- 5
  step "安装插件与模组"
  if [ -z "$PLUGINS" ] && [ -z "$MODS" ]; then
    sub "未选择任何插件或模组"
    hint "想要的话用 --pick 交互挑选，或 --plugins essentialsx,luckperms 直接指定"
  else
    case "$LOADER" in
      paper)
        if [ -n "$MODS" ]; then
          warn "Paper 不能加载 Fabric / Forge 模组，--mods 已忽略"
          hint "想要模组请改用 --loader fabric（轻量）或 --loader neoforge"
        fi
        install_contents plugins "$PLUGINS" "${DIR}/plugins" "插件"
        ;;
      vanilla)
        warn "原版服务端既不支持插件也不支持模组，已跳过"
        hint "要插件改用 --loader paper；要模组改用 --loader fabric 或 neoforge"
        ;;
      fabric|forge|neoforge)
        if [ -n "$PLUGINS" ]; then
          warn "Bukkit 插件只能在 Paper 上运行，--plugins 已忽略"
          hint "要插件请改用 --loader paper"
        fi
        install_contents mods "$MODS" "${DIR}/mods" "模组"
        ;;
    esac
    if [ -n "$PLUGINS" ] || [ -n "$MODS" ]; then
      hint "换版本或换加载器后重跑本脚本会重新匹配适配的文件"
    fi
  fi

  # ---------------------------------------------------------------- 6
  step "写入配置"
  printf 'eula=true\n' > eula.txt
  ok "已同意 EULA（eula.txt）"
  hint "Minecraft 服务端必须显式同意许可协议才能启动，这一步是自动完成的"

  if [ -f server.properties ]; then
    ok "server.properties 已存在，保留你的原有配置"
    hint "需要改端口或人数，直接编辑 ${DIR}/server.properties"
  else
    cat > server.properties <<PROP
motd=${MOTD}
server-port=${PORT}
online-mode=${ONLINE_MODE}
max-players=${MAX_PLAYERS}
view-distance=${VIEW_DIST}
simulation-distance=${SIM_DIST}
spawn-protection=0
allow-flight=true
enable-command-block=true
difficulty=easy
white-list=false
PROP
    ok "已写入 server.properties"
    sub "motd=${MOTD}"
    sub "端口=${PORT}  正版验证=${ONLINE_MODE}  人数上限=${MAX_PLAYERS}  视距=${VIEW_DIST}"
    hint "卡顿就调小 view-distance（视野）和 simulation-distance（模拟距离），这两项最吃性能"
  fi

  # ---------------------------------------------------------------- 7
  step "生成启动脚本与管理工具"
  local MF; MF="$(mem_flag "$MEM")"
  # -XX:+UnlockExperimentalVMOptions 必须排在所有 -XX 之前：
  # G1NewSizePercent / G1MaxNewSizePercent 被 JVM 视为实验性选项，
  # 未解锁会直接报 "VM option ... is experimental" 并拒绝启动（Java 8/11/17/21 都是如此）
  local FLAGS="-Xms${MF} -Xmx${MF} -XX:+UnlockExperimentalVMOptions \
-XX:+UseG1GC -XX:+ParallelRefProcEnabled \
-XX:MaxGCPauseMillis=200 -XX:+DisableExplicitGC -XX:+AlwaysPreTouch \
-XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M \
-XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:InitiatingHeapOccupancyPercent=15 \
-XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1 \
-Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"

  sub "校验 JVM 参数是否被当前 Java 接受 ..."
  if java $FLAGS -version >/dev/null 2>&1; then
    ok "调优参数可用（Aikar 方案，能明显减少卡顿）"
  else
    warn "当前 JVM 不接受这套调优参数，自动降级为保守参数"
    FLAGS="-Xms${MF} -Xmx${MF} -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
    if java $FLAGS -version >/dev/null 2>&1; then
      ok "已降级为保守参数"
    else
      FLAGS="-Xms${MF} -Xmx${MF}"
      hint "连保守参数也不支持，将只用内存参数启动"
    fi
  fi
  sub "内存参数   -Xms${MF} -Xmx${MF}"

  if [ "$IS_INSTALLER" = 1 ]; then
    cat > start.sh <<'SH'
#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
exec ./run.sh nogui
SH
  else
    {
      printf '#!/usr/bin/env bash\n'
      printf 'cd "$(dirname "$0")" || exit 1\n'
      printf 'JVM_FLAGS="%s"\n' "$FLAGS"
      printf '# 再自检一次：换 Java 版本后若参数不被支持，退回保守值而不是直接失败\n'
      printf 'if ! java $JVM_FLAGS -version >/dev/null 2>&1; then\n'
      printf '  echo "[提示] 当前 JVM 不支持调优参数，已自动改用保守参数"\n'
      printf '  JVM_FLAGS="-Xms%s -Xmx%s"\n' "$MF" "$MF"
      printf 'fi\n'
      printf 'exec java $JVM_FLAGS -jar server.jar nogui\n'
    } > start.sh
  fi
  chmod +x start.sh 2>/dev/null
  ok "已生成 ${DIR}/start.sh"

  # 记录服务端类型与版本，供 mcctl 的状态面板显示
  printf '%s %s\n' "$LOADER" "$VERSION" > .mcctl.info

  sub "获取管理工具 mcctl ..."
  if install_mcctl; then
    ok "已安装 ./mcctl —— 开服/关服/状态/日志/备份 一个脚本全包"
    sub "常用   ./mcctl status    看状态面板"
    sub "       ./mcctl stop      优雅关服（会存档）"
    sub "       ./mcctl backup    备份世界"
  else
    hint "mcctl 获取失败（不影响开服，仍可用 ./start.sh）"
  fi

  print_summary

  # ---------------------------------------------------------------- 8
  if [ "$DO_START" != 1 ]; then
    step "已按要求跳过启动"
    printf '%s\n' "   需要开服时执行：  cd ${DIR} && ./start.sh"
    printf '\n'
    return 0
  fi

  step "启动服务器"
  warn_hint "首次启动要生成世界，通常 1~3 分钟，日志刷得慢是正常的，请勿中断"
  printf '%s\n' "   ${C_D}成功标志：出现  Done (xx.xxs)! For help, type \"help\"${C_0}"
  printf '%s\n' "   ${C_D}安全关服：在当前窗口输入  stop  回车（直接关窗口可能损坏世界）${C_0}"
  printf '\n'
  exec ./start.sh
}

# ------------------------------- 组合列表 -----------------------------------
list_combos(){
  local f="${TMPDIR:-/tmp}/mc-data.$$.json" base
  : > "$f"
  # 依次尝试各通道，任一成功即停止
  for base in $DATA_MIRRORS; do
    if fetch "$base/data.json" "$f" 2>/dev/null && [ -s "$f" ]; then
      info "数据来源: ${base%%/data.json*}" >&2
      break
    fi
  done
  if [ -s "$f" ]; then
    python3 - "$f" <<'PY' 2>/dev/null || cat "$f"
import json,sys
d=json.load(open(sys.argv[1]))
vs=d.get("versions",{})
print(f"{'版本':<10}{'Java':<6}{'Paper':<7}{'原版':<6}{'Fabric':<8}{'NeoForge':<10}{'Forge':<7}")
print("-"*54)
order=["paper","vanilla","fabric","neoforge","forge"]
tot=0
for v,info in vs.items():
    ld=info.get("loaders",{})
    tot+=len(ld)
    row="".join(("✓" if k in ld else "·").ljust(w) for k,w in zip(order,[7,6,8,10,7]))
    print(f"{v:<10}{info.get('java',''):<6}{row}")
print(f"\n可用组合总数: {tot}")
PY
    rm -f "$f"
  else
    warn "无法获取组合列表（需要联网访问仓库）。以下是内置的常用版本："
    printf '%s\n' "  26.3 26.2 26.1.2 1.21.11 1.21.8 1.21.4 1.21.1 1.20.6 1.20.4 1.20.1 1.19.4 1.18.2 1.16.5 1.12.2"
  fi
}

# ------------------------------- 主流程 -------------------------------------
if [ "${LIST_ONLY:-0}" = 1 ]; then list_combos; exit 0; fi
if [ "${LIST_PLUGINS:-0}" = 1 ]; then show_catalog plugins 插件; exit 0; fi
if [ "${LIST_MODS:-0}" = 1 ]; then show_catalog mods 模组; exit 0; fi
# 判断 /dev/tty 是否真能打开（仅 -r 判断不够，会通过却读不了）
HAS_TTY=0
if [ -r /dev/tty ] && ( : < /dev/tty ) 2>/dev/null; then HAS_TTY=1; fi

# 只有「一个参数都没给」或显式 --ask，并且终端可用时才进向导
if [ "$ASK" = 1 ] || { [ "${ARGS_GIVEN:-0}" = 0 ] && [ "$HAS_TTY" = 1 ]; }; then
  hr
  printf '%s\n' "${C_BOLD}Minecraft 服务器部署向导${C_0}（直接回车使用方括号里的默认值）"
  hr
  LOADER="$(ask '服务端类型 (paper/vanilla/fabric/neoforge/forge):' "$LOADER")"
  VERSION="$(ask 'Minecraft 版本 (如 1.21.11 / 1.20.1):' "$VERSION")"
  NEED_JAVA="$(java_for "$VERSION")"
  printf '%s\n' "${C_D}该版本需要 Java ${NEED_JAVA}${C_0}"
  MEM="$(ask '分配内存 GB (如 2):' "${MEM:-2}")"
  PORT="$(ask '端口:' "$PORT")"
  MOTD="$(ask '服务器名称(motd):' "Minecraft Server ${VERSION}")"
  if [ "$(ask '要交互式挑选插件/模组吗? (y/N):' 'N')" = "y" ]; then PICK=1; fi
  hr
fi

# 校验参数
case "$LOADER" in
  paper|folia|purpur|vanilla|fabric|neoforge|forge) ;;
  *) die "--loader 只能是 paper / folia / purpur / vanilla / fabric / neoforge / forge";;
esac
[ -n "$VERSION" ] || die "--version 不能为空"
auto_params
NEED_JAVA="$(java_for "$VERSION")"

# 交互式挑选插件与模组
if [ "${PICK:-0}" = 1 ]; then
  [ -z "$PLUGINS" ] && PLUGINS="$(pick_items plugins 插件)"
  case "$LOADER" in
    fabric|forge|neoforge) [ -z "$MODS" ] && MODS="$(pick_items mods 模组)";;
  esac
fi

do_install
