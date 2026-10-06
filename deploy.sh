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
  local prompt="$1" def="$2" ans=""
  if [ -r /dev/tty ]; then
    printf '%s' "${C_BOLD}${prompt}${C_0} ${C_D}[${def}]${C_0} " > /dev/tty
    read -r ans < /dev/tty || ans=""
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
  # fetch <url> <输出文件>：带自建重试，因为 curl 的 --retry 并不覆盖所有瞬时错误
  local url="$1" out="$2" i
  for i in 1 2 3; do
    if have curl; then
      if [ -s "$out" ]; then
        # 已存在半截文件：先试断点续传；失败就删掉重下，避免错误内容越滚越大
        curl -fsSL -C - -m 300 -o "$out" "$url" 2>/dev/null \
          || { rm -f "$out"; curl -fsSL -m 300 -o "$out" "$url" 2>/dev/null; }
      else
        curl -fsSL -m 300 -o "$out" "$url" 2>/dev/null
      fi
    elif have wget; then
      wget -q -O "$out" --tries=2 "$url" 2>/dev/null
    else
      die "系统里既没有 curl 也没有 wget，无法下载"
    fi
    [ -s "$out" ] && return 0
    warn "第 ${i} 次下载未成功，重试..."
    sleep 2
  done
  return 1
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
  hr
  info "${C_BOLD}环境${C_0}  ${ENVK}    ${C_BOLD}服务端${C_0} ${LOADER} ${VERSION}    ${C_BOLD}Java${C_0} ${NEED_JAVA}    ${C_BOLD}内存${C_0} ${MEM}G"
  hr

  if [ "${DRY_RUN:-0}" = 1 ]; then
    info "${C_BOLD}DRY RUN${C_0}：只解析地址并打印计划，不安装、不下载、不修改任何文件"
    printf '%s\n' "   Java 需求 : ${NEED_JAVA}（当前检测到: $(current_java)）"
    resolve_urls
    printf '%s\n' "   服务端文件: ${SRC_NAME}"
    printf '%s\n' "   下载地址  : ${SRC_URL}"
    [ -n "$SRC_SHA" ] && printf '%s\n' "   校验值(${SRC_ALGO:-sha256}) : ${SRC_SHA}"
    printf '%s\n' "   内存参数  : -Xms$(mem_flag "$MEM") -Xmx$(mem_flag "$MEM")"
    printf '%s\n' "   安装目录  : ${DIR}"
    printf '%s\n' "   端口/视距 : ${PORT} / ${VIEW_DIST}（模拟距离 ${SIM_DIST}）"
    exit 0
  fi

  install_java
  resolve_urls

  mkdir -p "$DIR" || die "无法创建目录 $DIR"
  cd "$DIR" || die "无法进入目录 $DIR"

  if [ "$IS_INSTALLER" = 1 ]; then
    info "下载安装器"
    fetch "$SRC_URL" "installer.jar" || die "下载失败：$SRC_URL"
    ls -l installer.jar | awk '{print "   大小:", $5, "字节"}'
    info "运行安装器（首次较慢，需要下载大量依赖库）"
    java -jar installer.jar --installServer || die "安装器执行失败，请查看上方输出"
    ok "安装器执行完成"
  else
    info "下载服务端 ${SRC_NAME}"
    fetch "$SRC_URL" "server.jar" || die "下载失败：$SRC_URL"
    local sz; sz="$(wc -c < server.jar 2>/dev/null || echo 0)"
    if [ "$sz" -lt 1000000 ]; then
      die "下载到的文件只有 ${sz} 字节，明显不是服务端 jar（可能被拦截成了错误页面）。
     请检查网络，或换用国内镜像：--mirror always"
    fi
    ok "下载完成（$(echo "scale=1; $sz/1048576" | bc 2>/dev/null || echo "?") MB）"

    if [ -n "$SRC_SHA" ]; then
      info "校验完整性（${SRC_ALGO}）"
      local got; got="$(digest_of "$SRC_ALGO" server.jar)"
      if [ -n "$got" ] && [ "$got" = "$SRC_SHA" ]; then
        ok "${SRC_ALGO} 校验通过"
      elif [ -n "$got" ] && [ -n "$SRC_SHA" ]; then
        warn "${SRC_ALGO} 不一致（上游可能已更新构建，通常不影响使用）"
        printf '%s\n' "   期望: $SRC_SHA" "   实际: $got" >&2
      fi
    fi
  fi

  # EULA
  printf 'eula=true\n' > eula.txt
  ok "已同意 EULA（eula.txt）"

  # server.properties：已存在则不覆盖，避免冲掉玩家的自定义配置
  if [ -f server.properties ]; then
    info "server.properties 已存在，保留原配置（只确保端口与内存相关项）"
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
  fi

  # 启动脚本
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

  # 部署前本地校验一次，不通过就当场降级，避免交给用户一个起不来的脚本
  if ! java $FLAGS -version >/dev/null 2>&1; then
    warn "当前 JVM 不接受这套调优参数，自动降级为保守参数"
    FLAGS="-Xms${MF} -Xmx${MF} -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
    java $FLAGS -version >/dev/null 2>&1 || FLAGS="-Xms${MF} -Xmx${MF}"
  fi

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
  ok "已生成启动脚本 start.sh"

  hr
  ok "${C_BOLD}部署完成${C_0}  目录: ${C_BOLD}${DIR}${C_0}"
  printf '%s\n' "   启动：  cd ${DIR} && ./start.sh"
  printf '%s\n' "   关闭：  在服务器窗口输入 ${C_BOLD}stop${C_0} 回车（不要直接关窗口）"
  printf '%s\n' "   修改配置：${DIR}/server.properties"
  hr

  if [ "$DO_START" = 1 ]; then
    info "正在启动服务器，首次会生成世界，请耐心等待..."
    info "看到 ${C_BOLD}Done (xx.xxs)! For help, type \"help\"${C_0} 就是启动成功"
    hr
    exec ./start.sh
  else
    info "按参数要求不自动启动。需要时执行：cd ${DIR} && ./start.sh"
  fi
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
if [ "$ASK" = 1 ] || { [ $# -eq 0 ] && [ ! -t 0 ] && [ -r /dev/tty ]; }; then
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
