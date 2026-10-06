#!/usr/bin/env python3
"""穷举版本 × 服务端 组合矩阵，并采集加载器版本表。

- 版本范围：Mojang 版本清单里所有 >= 1.7.10 的正式版（自动获取，不写死）
- 服务端：Paper / Folia / Purpur / 原版 / Fabric / NeoForge / Forge
- 额外采集：Fabric / NeoForge / Forge 的可用加载器版本（供 --loader-version 选择）

输出: 仓库根目录的 data.json
用法: python3 tools/gen_matrix.py
"""
import json, os, re, subprocess, sys, urllib.request
import concurrent.futures as cf

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = {"User-Agent": "mc-server-deploy/1.0 (github.com/zhuzijiang/mc-server-deploy)"}
CURL_UA = "mc-server-deploy/1.0"


def get(url, t=30):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=t) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def curl_json(url, t=30, tries=3):
    """PaperMC 等对 urllib 的 TLS 不友好，改走 curl 并重试。"""
    for _ in range(tries):
        p = subprocess.run(["curl", "-sL", "-m", str(t), "-A", CURL_UA, url],
                           capture_output=True, text=True)
        if p.stdout.strip():
            try:
                return json.loads(p.stdout)
            except Exception:
                pass
    return None


def vkey(v):
    m = re.match(r"^(\d+)\.(\d+)(?:\.(\d+))?$", v)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3) or 0)) if m else (0, 0, 0)


def java_for(v):
    """Minecraft 官方 Java 需求（按世代）。"""
    k = vkey(v)
    if k[0] >= 26: return 25
    if k >= (1, 20, 5): return 21
    if k >= (1, 17, 0): return 17
    return 8


# ---------------------------------------------------------------- 版本列表
print("拉取索引...", file=sys.stderr)

man = get("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
VERSIONS = [x["id"] for x in man["versions"]
            if x["type"] == "release" and vkey(x["id"]) >= (1, 7, 10)]
vanilla_index = {x["id"]: x["url"] for x in man["versions"]}
print(f"  正式版（>=1.7.10）: {len(VERSIONS)} 个", file=sys.stderr)

paper_supported, folia_supported = set(), set()
for proj, bucket in (("paper", paper_supported), ("folia", folia_supported)):
    pj = curl_json(f"https://fill.papermc.io/v3/projects/{proj}")
    if pj:
        for _, lst in (pj.get("versions") or {}).items():
            for x in lst:
                if "-" not in x:
                    bucket.add(x)
print(f"  Paper {len(paper_supported)} 个 / Folia {len(folia_supported)} 个", file=sys.stderr)

purpur_supported = set()
try:
    purpur_supported = set(get("https://api.purpurmc.org/v2/purpur").get("versions", []))
except Exception as e:
    print("  purpur 列表失败:", e, file=sys.stderr)
print(f"  Purpur {len(purpur_supported)} 个", file=sys.stderr)

fabric_supported = set()
try:
    for x in get("https://meta.fabricmc.net/v2/versions/game"):
        if x.get("stable"):
            fabric_supported.add(x["version"])
except Exception as e:
    print("  fabric 列表失败:", e, file=sys.stderr)
print(f"  Fabric {len(fabric_supported)} 个", file=sys.stderr)

forge_promo = {}
try:
    forge_promo = get("https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json").get("promos", {})
except Exception as e:
    print("  forge promotions 失败:", e, file=sys.stderr)
print(f"  Forge promotions {len(forge_promo)} 条", file=sys.stderr)

FABRIC_INSTALLER = None
try:
    FABRIC_INSTALLER = get("https://meta.fabricmc.net/v2/versions/installer")[0]["version"]
except Exception:
    pass


# ---------------------------------------------------------------- 采集函数
def _fill(proj, v):
    b = curl_json(f"https://fill.papermc.io/v3/projects/{proj}/versions/{v}/builds/latest")
    if not b:
        return None
    d = b["downloads"]["server:default"]
    return {"file": d["name"], "url": d["url"], "sha256": d["checksums"]["sha256"],
            "mb": round(d["size"] / 1048576, 1), "build": b["id"], "channel": b["channel"]}


def p_paper(v):
    return _fill("paper", v) if v in paper_supported else None


def p_folia(v):
    return _fill("folia", v) if v in folia_supported else None


def p_purpur(v):
    if v not in purpur_supported: return None
    j = get(f"https://api.purpurmc.org/v2/purpur/{v}/latest")
    b = j.get("build")
    if not b: return None
    return {"file": f"purpur-{v}-{b}.jar", "build": b,
            "url": f"https://api.purpurmc.org/v2/purpur/{v}/{b}/download",
            "md5": j.get("md5"), "mb": round(int(j.get("size", 0)) / 1048576, 1)}


def p_vanilla(v):
    if v not in vanilla_index: return None
    o = get(vanilla_index[v])["downloads"]["server"]
    return {"official": o["url"], "sha1": o["sha1"], "mb": round(o["size"] / 1048576, 1),
            "mirror": f"https://bmclapi2.bangbang93.com/version/{v}/server"}


def p_fabric(v):
    if v not in fabric_supported: return None
    lst = get(f"https://meta.fabricmc.net/v2/versions/loader/{v}")
    if not lst: return None
    vers = [x["loader"]["version"] for x in lst]
    ld = vers[0]
    ins = FABRIC_INSTALLER or get("https://meta.fabricmc.net/v2/versions/installer")[0]["version"]
    return {"loader": ld, "installer": ins, "versions": vers[:12],
            "file": f"fabric-server-mc.{v}-loader.{ld}-launcher.{ins}.jar",
            "url": f"https://meta.fabricmc.net/v2/versions/loader/{v}/{ld}/{ins}/server/jar",
            "tpl": f"https://meta.fabricmc.net/v2/versions/loader/{v}/{{loader}}/{ins}/server/jar"}


def p_neoforge(v):
    try:
        lst = get(f"https://bmclapi2.bangbang93.com/neoforge/list/{v}")
    except Exception:
        return None
    if not lst: return None
    allv = [x["version"] for x in lst]
    stable = [x for x in allv if "beta" not in x.lower()]
    n = stable[-1] if stable else allv[-1]
    return {"version": n, "beta": not stable, "channel": "stable" if stable else "beta",
            "versions": (stable[-10:] if stable else allv[-10:])[::-1],
            "official": f"https://maven.neoforged.net/releases/net/neoforged/neoforge/{n}/neoforge-{n}-installer.jar",
            "mirror": f"https://bmclapi2.bangbang93.com/maven/net/neoforged/neoforge/{n}/neoforge-{n}-installer.jar",
            "tpl": "https://maven.neoforged.net/releases/net/neoforged/neoforge/{v}/neoforge-{v}-installer.jar"}


def p_forge(v):
    rec, lat = forge_promo.get(f"{v}-recommended"), forge_promo.get(f"{v}-latest")
    if not (rec or lat): return None

    def mk(n):
        return {"official": f"https://maven.minecraftforge.net/net/minecraftforge/forge/{v}-{n}/forge-{v}-{n}-installer.jar",
                "mirror": f"https://bmclapi2.bangbang93.com/maven/net/minecraftforge/forge/{v}-{n}/forge-{v}-{n}-installer.jar"}

    vers = []
    for x in (rec, lat):
        if x and x not in vers:
            vers.append(x)
    return {"recommended": rec, "latest": lat, "versions": vers,
            "rec": mk(rec) if rec else None, "lato": mk(lat) if lat else None,
            "tpl": f"https://maven.minecraftforge.net/net/minecraftforge/forge/{v}-{{v}}/forge-{v}-{{v}}-installer.jar"}


PROBES = [("paper", p_paper), ("folia", p_folia), ("purpur", p_purpur), ("vanilla", p_vanilla),
          ("fabric", p_fabric), ("neoforge", p_neoforge), ("forge", p_forge)]

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
        if r:
            result[v]["loaders"][name] = r
        if done % 100 == 0:
            print(f"  ...{done}/{len(tasks)}", file=sys.stderr)

with open(os.path.join(ROOT, "data.json"), "w", encoding="utf-8") as fh:
    json.dump({"generated": None, "versions": result}, fh,
              ensure_ascii=False, separators=(",", ":"))

# ---------------------------------------------------------------- 报告
KEYS = [("paper", "Paper"), ("folia", "Folia"), ("purpur", "Purpur"), ("vanilla", "原版"),
        ("fabric", "Fabric"), ("neoforge", "NeoForge"), ("forge", "Forge")]
print("\n=== 组合矩阵 ===", file=sys.stderr)
print(f"{'版本':<10}{'Java':<5}" + "".join(f"{n:<9}" for _, n in KEYS), file=sys.stderr)
tally = {k: 0 for k, _ in KEYS}
for v in VERSIONS:
    ld = result[v]["loaders"]
    for k, _ in KEYS:
        if k in ld:
            tally[k] += 1
    print(f"{v:<10}{result[v]['java']:<5}"
          + "".join(("✓" if k in ld else "·").ljust(9) for k, _ in KEYS), file=sys.stderr)

total = sum(len(result[v]["loaders"]) for v in VERSIONS)
print(f"\n版本数: {len(VERSIONS)}   可用组合总数: {total}", file=sys.stderr)
for k, n in KEYS:
    print(f"  {n:<9} 覆盖 {tally[k]} 个版本", file=sys.stderr)
print(f"  data.json 大小: {os.path.getsize(os.path.join(ROOT,'data.json'))} 字节", file=sys.stderr)
