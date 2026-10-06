#!/usr/bin/env python3
"""
穷举版本 × 加载器 组合矩阵。
对每个 Minecraft 版本，逐个探测 Paper / Vanilla / Fabric / NeoForge / Forge 是否真的可用，
并把官方直链 + 国内镜像 + 校验值全部采集下来。
输出: 仓库根目录的 data.json
"""
import json, os, subprocess, urllib.request, concurrent.futures as cf, re, sys

UA = {"User-Agent": "Mozilla/5.0 (mc-deploy-matrix)"}

def get(url, t=30):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=t) as r:
        return json.loads(r.read().decode("utf-8", "replace"))

def curl_json(url, t=30, tries=3):
    """PaperMC / Cloudflare 对 urllib 的 TLS 不友好，用 curl 并重试。"""
    for i in range(tries):
        p = subprocess.run(["curl", "-sL", "-m", str(t), "-A", "Mozilla/5.0", url],
                           capture_output=True, text=True)
        if p.stdout.strip():
            try: return json.loads(p.stdout)
            except Exception: pass
    return None

# ---------------------------------------------------------------- 版本总表
# 覆盖 1.7.10 ~ 26.3，按世代排列，不留大跳空
VERSIONS = [
    "26.3","26.2","26.1.2",
    "1.21.11","1.21.10","1.21.8","1.21.7","1.21.6","1.21.5","1.21.4","1.21.3","1.21.1","1.21",
    "1.20.6","1.20.5","1.20.4","1.20.3","1.20.2","1.20.1","1.20",
    "1.19.4","1.19.3","1.19.2","1.19.1","1.19",
    "1.18.2","1.18.1","1.18",
    "1.17.1","1.17",
    "1.16.5","1.16.4","1.16.3","1.16.2","1.16.1",
    "1.15.2","1.15.1","1.15",
    "1.14.4","1.14.3","1.14.2",
    "1.13.2","1.13.1",
    "1.12.2","1.12.1","1.12",
    "1.11.2","1.11",
    "1.10.2","1.10",
    "1.9.4","1.9",
    "1.8.9","1.8.8",
    "1.7.10",
]

def vkey(v):
    m = re.match(r"^(\d+)\.(\d+)(?:\.(\d+))?$", v)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3) or 0)) if m else (0,0,0)

def java_for(v):
    """Minecraft 官方 Java 需求（按世代）。"""
    k = vkey(v)
    if k[0] >= 26: return 25
    if k >= (1,20,5): return 21
    if k >= (1,18,0): return 17
    if k >= (1,17,0): return 17   # 1.17 官方要求 16+，实践用 17
    return 8                      # 1.16.5 及更早

# ---------------------------------------------------------------- 一次性索引
print("拉取索引...", file=sys.stderr)

paper_supported = set()
pj = curl_json("https://fill.papermc.io/v3/projects/paper")
if pj:
    for grp, lst in (pj.get("versions") or {}).items():
        for x in lst:
            if "-" not in x:            # 排除 rc / pre
                paper_supported.add(x)
print(f"  Paper 支持 {len(paper_supported)} 个版本", file=sys.stderr)

fabric_supported = set()
try:
    for x in get("https://meta.fabricmc.net/v2/versions/game"):
        if x.get("stable"): fabric_supported.add(x["version"])
except Exception as e:
    print("  fabric game 列表失败:", e, file=sys.stderr)
print(f"  Fabric 支持 {len(fabric_supported)} 个版本", file=sys.stderr)

forge_promo = {}
try:
    forge_promo = get("https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json").get("promos", {})
except Exception as e:
    print("  forge promotions 失败:", e, file=sys.stderr)
print(f"  Forge promotions {len(forge_promo)} 条", file=sys.stderr)

vanilla_index = {}
try:
    man = get("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
    vanilla_index = {x["id"]: x["url"] for x in man["versions"]}
except Exception as e:
    print("  mojang manifest 失败:", e, file=sys.stderr)
print(f"  原版清单 {len(vanilla_index)} 个版本", file=sys.stderr)

# ---------------------------------------------------------------- 各加载器采集
def p_paper(v):
    if v not in paper_supported: return None
    b = curl_json(f"https://fill.papermc.io/v3/projects/paper/versions/{v}/builds/latest")
    if not b: return None
    d = b["downloads"]["server:default"]
    return {"file": d["name"], "url": d["url"], "sha256": d["checksums"]["sha256"],
            "mb": round(d["size"]/1048576, 1), "build": b["id"], "channel": b["channel"]}

def p_vanilla(v):
    if v not in vanilla_index: return None
    o = get(vanilla_index[v])["downloads"]["server"]
    return {"official": o["url"], "sha1": o["sha1"], "mb": round(o["size"]/1048576, 1),
            "mirror": f"https://bmclapi2.bangbang93.com/version/{v}/server"}

def p_fabric(v):
    if v not in fabric_supported: return None
    lst = get(f"https://meta.fabricmc.net/v2/versions/loader/{v}")
    if not lst: return None
    ld = lst[0]["loader"]["version"]
    ins = get("https://meta.fabricmc.net/v2/versions/installer")[0]["version"]
    return {"loader": ld, "installer": ins,
            "file": f"fabric-server-mc.{v}-loader.{ld}-launcher.{ins}.jar",
            "url": f"https://meta.fabricmc.net/v2/versions/loader/{v}/{ld}/{ins}/server/jar",
            "mirror": None}

def p_neoforge(v):
    try:
        lst = get(f"https://bmclapi2.bangbang93.com/neoforge/list/{v}")
    except Exception:
        return None
    if not lst: return None
    stable = [x["version"] for x in lst if "beta" not in x["version"].lower()]
    n = stable[-1] if stable else lst[-1]["version"]
    return {"version": n, "beta": not stable, "channel": "stable" if stable else "beta",
            "official": f"https://maven.neoforged.net/releases/net/neoforged/neoforge/{n}/neoforge-{n}-installer.jar",
            "mirror": f"https://bmclapi2.bangbang93.com/maven/net/neoforged/neoforge/{n}/neoforge-{n}-installer.jar"}

def p_forge(v):
    rec, lat = forge_promo.get(f"{v}-recommended"), forge_promo.get(f"{v}-latest")
    if not (rec or lat): return None
    mk = lambda n: {"official": f"https://maven.minecraftforge.net/net/minecraftforge/forge/{v}-{n}/forge-{v}-{n}-installer.jar",
                    "mirror":   f"https://bmclapi2.bangbang93.com/maven/net/minecraftforge/forge/{v}-{n}/forge-{v}-{n}-installer.jar"}
    return {"recommended": rec, "latest": lat,
            "rec": mk(rec) if rec else None, "lato": mk(lat) if lat else None}

PROBES = [("paper",p_paper),("vanilla",p_vanilla),("fabric",p_fabric),
          ("neoforge",p_neoforge),("forge",p_forge)]

tasks = [(v, name, fn) for v in VERSIONS for name, fn in PROBES]
result = {v: {"java": java_for(v), "loaders": {}} for v in VERSIONS}

with cf.ThreadPoolExecutor(max_workers=10) as ex:
    futs = {ex.submit(fn, v): (v, name) for v, name, fn in tasks}
    done = 0
    for f in cf.as_completed(futs):
        v, name = futs[f]
        done += 1
        try:
            r = f.result()
        except Exception as e:
            r = None
            print(f"  ! {v}/{name}: {e}", file=sys.stderr)
        if r: result[v]["loaders"][name] = r
        if done % 40 == 0: print(f"  ...{done}/{len(tasks)}", file=sys.stderr)

out = {"generated": None, "versions": result}
json.dump(out, open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data.json"), "w"), ensure_ascii=False, separators=(",",":"))

# ---------------------------------------------------------------- 报告
print("\n=== 组合矩阵 ===", file=sys.stderr)
print(f"{'版本':<9}{'Java':<5}{'Paper':<7}{'原版':<5}{'Fabric':<8}{'NeoForge':<10}{'Forge':<6}", file=sys.stderr)
names = {"paper":"Paper","vanilla":"原版","fabric":"Fabric","neoforge":"NeoForge","forge":"Forge"}
for v in VERSIONS:
    r = result[v]["loaders"]
    row = "".join(("✓" if k in r else "·").ljust(w) for k, w in
                  [("paper",7),("vanilla",5),("fabric",8),("neoforge",10),("forge",6)])
    print(f"{v:<9}{result[v]['java']:<5}{row}", file=sys.stderr)

total = sum(len(result[v]["loaders"]) for v in VERSIONS)
print(f"\n可用组合总数: {total}", file=sys.stderr)
