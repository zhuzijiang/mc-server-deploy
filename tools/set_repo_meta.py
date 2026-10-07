#!/usr/bin/env python3
"""把仓库的「介绍信息」（描述 / 主题 / 主页）同步成当前状态。

描述里的版本数、服务端数、插件模组数都从 data.json 与 catalog.json 现算，
这样数据一变就不会再出现「介绍还是老版本」的脱节。

用法：
    GITHUB_TOKEN=xxx python3 tools/set_repo_meta.sh   # 或 .py
    GITHUB_TOKEN=xxx REPO=owner/name python3 tools/set_repo_meta.py --check   # 只看会改成什么
"""
import json, os, subprocess, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.environ.get("REPO", "zhuzijiang/mc-server-deploy")
OWNER, NAME = REPO.split("/", 1)
PAGES_URL = f"https://{OWNER}.github.io/{NAME}/"

TOPICS = ["minecraft", "minecraft-server", "minecraft-java-edition", "termux",
          "paper", "folia", "purpur", "fabric", "neoforge", "forge",
          "android", "bash", "minecraft-plugin", "minecraft-mod", "modrinth",
          "server-management", "one-click-deploy", "mcctl"]

LOADER_LABEL = {
    "paper": "Paper", "folia": "Folia", "purpur": "Purpur", "vanilla": "原版",
    "fabric": "Fabric", "neoforge": "NeoForge", "forge": "Forge",
}


def build_description():
    d = json.load(open(os.path.join(ROOT, "data.json"), encoding="utf-8"))
    cat = json.load(open(os.path.join(ROOT, "catalog.json"), encoding="utf-8"))
    vs = d["versions"]

    loaders, seen = [], set()
    for info in vs.values():
        for k in info["loaders"]:
            if k not in seen:
                seen.add(k)
                loaders.append(k)
    loaders.sort(key=lambda k: list(LOADER_LABEL).index(k) if k in LOADER_LABEL else 99)
    names = "/".join(LOADER_LABEL.get(k, k) for k in loaders)

    total = sum(len(i["loaders"]) for i in vs.values())
    desc = (f"Minecraft Java 版服务器一键部署：{len(vs)} 个游戏版本 × {len(loaders)} 种服务端"
            f"（{names}），内置 {len(cat['plugins'])} 个插件与 {len(cat['mods'])} 个模组目录，"
            f"共 {total} 个可用组合；自动探测空闲端口，自带 mcctl 管理工具与离线网页控制台")
    return desc[:350]


def api(method, path, data=None, token=""):
    cmd = ["curl", "-s", "-X", method, "-m", "60",
           "-H", f"Authorization: Bearer {token}",
           "-H", "Accept: application/vnd.github+json",
           f"https://api.github.com/repos/{REPO}{path}"]
    inp = None
    if data is not None:
        cmd += ["-d", "@-"]
        inp = json.dumps(data)
    p = subprocess.run(cmd, input=inp, capture_output=True, text=True)
    try:
        return json.loads(p.stdout)
    except Exception:
        return {}


def main():
    desc = build_description()
    check = "--check" in sys.argv
    token = os.environ.get("GITHUB_TOKEN", "")

    print(f"仓库      {REPO}")
    print(f"新描述    {desc}")
    print(f"描述字数  {len(desc)} / 350")
    print(f"主题      {len(TOPICS)} 个：{' '.join(TOPICS)}")
    print(f"主页      {PAGES_URL}")

    if check:
        print("\n（--check 模式，未做任何修改）")
        return 0
    if not token:
        print("\n缺少 GITHUB_TOKEN 环境变量，无法写入。", file=sys.stderr)
        return 1

    r = api("PATCH", "", {"description": desc, "homepage": PAGES_URL}, token)
    ok1 = r.get("description") == desc
    print(f"\n{'✓' if ok1 else '✗'} 描述已更新")

    r = api("PUT", "/topics", {"names": TOPICS}, token)
    ok2 = sorted(r.get("names") or []) == sorted(TOPICS)
    print(f"{'✓' if ok2 else '✗'} 主题已更新（{len(r.get('names') or [])} 个）")

    # Pages 未开启时顺手开启
    pg = api("GET", "/pages", token=token)
    if not pg.get("html_url"):
        pg = api("POST", "/pages", {"source": {"branch": "main", "path": "/"}}, token)
    print(f"{'✓' if pg.get('html_url') else '·'} Pages：{pg.get('html_url') or pg.get('message')}")

    return 0 if (ok1 and ok2) else 1


if __name__ == "__main__":
    sys.exit(main())
