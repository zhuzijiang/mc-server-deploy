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
TOTAL_STEPS=7
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
  printf '%s\n' "  5 写入配置        6 生成启动脚本   7 启动服务器"
  printf '%s\n' "${C_D}  视网速约 1~5 分钟。中途 Ctrl+C 可安全中断，不会留下坏文件${C_0}"
}

print_summary(){
  hr
  ok "${C_BOLD}部署完成${C_0}  目录: ${C_BOLD}${DIR}${C_0}"
  hr
  printf '%s\n' "${C_BOLD}接下来你可以：${C_0}"
  printf '%s\n' "  开服        cd ${DIR} && ./start.sh"
  printf '%s\n' "  安全关服    在服务器窗口输入 ${C_BOLD}stop${C_0} 回车"
  printf '%s\n' "  改配置      nano ${DIR}/server.properties"
  printf '%s\n' "  备份世界    tar czf ~/mc-backup-\$(date +%F).tar.gz world world_nether world_the_end"
  printf '%s\n' "  自己先进    Minecraft 里「多人游戏 → 添加服务器」填 localhost:${PORT}"
  printf '%s\n' "  给别人进    同一 WiFi 下用 本机IP:${PORT}（ip addr 或 ifconfig 查）"
  hr
}


# ------------------------------- 默认参数 -----------------------------------
LOADER="paper"
VERSION="1.21.11"
MEM=""
PORT="25565"
MOTD=""
DIR=""
ONLINE_MODE="true"
VIEW_DIST=""
MAX_PLAYERS=""
DO_START=1
ASK=0
USE_MIRROR="auto"      # auto | always | never
NO_JAVA=0

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

# 按指定算法计算文件摘要
digest_of(){
  case "${1:-sha256}" in
    sha1) sha1_of "$2";;
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
      pkg install -y "openjdk-${NEED_JAVA}" curl || die "安装 Java 失败"
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
    paper)
      local j; j="$(fetch_text "https://fill.papermc.io/v3/projects/paper/versions/${VERSION}/builds/latest")"
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
        [ -n "$n" ] || die "NeoForge 不支持 MC ${VERSION}。NeoForge 仅支持 1.20.2 及以上。"
        SRC_URL="https://maven.neoforged.net/releases/net/neoforged/neoforge/${n}/neoforge-${n}-installer.jar"
        if want_mirror; then SRC_URL="https://bmclapi2.bangbang93.com/maven/net/neoforged/neoforge/${n}/neoforge-${n}-installer.jar"; fi
        ok "NeoForge ${n}"
      else
        local pj n
        pj="$(fetch_text "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json")"
        n="$(jget "${VERSION}-recommended" "$pj")"
        [ -z "$n" ] && n="$(jget "${VERSION}-latest" "$pj")"
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

  # 归一化：端口/视距/人数必须是纯整数
  PORT="$(int_only "$PORT")";            [ -z "$PORT" ] && PORT=25565
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
    printf '\n%s\n' "${C_D}以上地址均可直接复制到下载工具里手动下载。去掉 --dry-run 即真正开始部署。${C_0}"
    exit 0
  fi

  # ---------------------------------------------------------------- 1
  step "检查运行环境"
  sub "运行环境   ${ENVK}$(env_desc "$ENVK")"
  sub "Java 需求  ${NEED_JAVA}（当前: $(current_java_human)）"
  sub "安装目录   ${DIR}"
  sub "监听端口   ${PORT}   内存 ${MEM}G"

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

  # ---------------------------------------------------------------- 6
  step "生成启动脚本"
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
  hint "以后开服只需执行  cd ${DIR} && ./start.sh"

  print_summary

  # ---------------------------------------------------------------- 7
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
  hr
fi

# 校验参数
case "$LOADER" in paper|vanilla|fabric|neoforge|forge) ;; *) die "--loader 只能是 paper/vanilla/fabric/neoforge/forge";; esac
[ -n "$VERSION" ] || die "--version 不能为空"
auto_params
NEED_JAVA="$(java_for "$VERSION")"

do_install
