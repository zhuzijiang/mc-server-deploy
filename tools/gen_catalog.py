#!/usr/bin/env python3
"""生成 catalog.json：常用插件与模组的目录数据。

- 条目 slug 与元数据（下载量、前后端支持、图标）取自 Modrinth 官方 API，保证真实
- 中文说明与分类为本项目人工整理
用法：python3 tools/gen_catalog.py
"""
import json, os, subprocess, urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = 'mc-server-deploy/1.0 (github.com/zhuzijiang/mc-server-deploy)'

# slug: (分类, 中文说明, 前后端提示)
PLUGINS = {
    # ---- 基础管理 ----
    "essentialsx":       ("基础管理", "指令套装：家、传送、经济、 kits、封禁等一站式基础功能", "server"),
    "luckperms":         ("基础管理", "权限管理事实标准，支持继承、前缀后缀、网页编辑器", "server"),
    "placeholderapi":    ("基础管理", "给其它插件提供变量占位符（大量插件的必备前置）", "server"),
    "tab-was-taken":     ("基础管理", "自定义 TAB 列表、计分板与头顶显示", "server"),
    "lmd":               ("基础管理", "Let Me Despawn：让怪物按配置自然消失，减轻服务器压力", "server"),
    # ---- 世界与保护 ----
    "worldedit":         ("世界与保护", "建筑编辑神器，刷子、复制、生成地形（管理必备）", "server"),
    "fastasyncworldedit":("世界与保护", "WorldEdit 的异步高性能分支，大范围操作不卡服", "server"),
    "worldguard":        ("世界与保护", "区域保护：划定领地、禁 PVP、禁破坏，配合 WorldEdit 使用", "server"),
    "coreprotect":       ("世界与保护", "方块操作日志与回滚，被熊孩子破坏后能一键还原（强烈推荐）", "server"),
    "multiverse-core":   ("世界与保护", "多世界管理，创建/传送/隔离不同玩法世界", "server"),
    # ---- 性能与维护 ----
    "chunky":            ("性能与维护", "预先加载生成地图区块，避免玩家探索时卡顿", "server"),
    "spark":             ("性能与维护", "性能分析器，定位卡顿元凶（看 TPS、找热点）", "server"),
    # ---- 兼容与联机 ----
    "viaversion":        ("兼容与联机", "让高版本客户端连进低版本服务器", "server"),
    "viabackwards":      ("兼容与联机", "让低版本客户端连进高版本服务器（配合 ViaVersion）", "server"),
    "geyser":            ("兼容与联机", "让基岩版（手机/主机）玩家连进 Java 服务器", "server"),
    "floodgate":         ("兼容与联机", "Geyser 配套，让基岩版玩家免正版验证登录", "server"),
    "skinsrestorer":     ("兼容与联机", "修复离线/代理模式下玩家看不到皮肤的问题", "server"),
    # ---- 玩法与社交 ----
    "simple-voice-chat": ("玩法与社交", "近距离语音聊天，按距离衰减音量（需客户端装模组）", "both"),
    "dynmap":            ("玩法与社交", "在浏览器里实时查看服务器地图与玩家位置", "server"),
    "discordsrv":        ("玩法与社交", "打通 Discord：聊天互通、状态显示、身份组同步", "server"),
    "grimac":            ("玩法与社交", "Grim 反作弊，专治飞行/加速/瞬移等作弊", "server"),
    "packetevents":      ("玩法与社交", "数据包事件库，很多现代插件的前置依赖", "server"),
}

MODS = {
    # ---- 性能优化 ----
    "lithium":             ("性能优化", "通用服务端优化，不改玩法地提升 TPS（首选必装）", "both"),
    "ferrite-core":        ("性能优化", "大幅降低内存占用，尤其适合内存紧张的设备", "both"),
    "modernfix":           ("性能优化", "加快启动、降低内存、修复若干原版性能问题", "both"),
    "c2me-fabric":         ("性能优化", "区块生成并行化，世界生成速度显著提升", "server"),
    "krypton":             ("性能优化", "网络栈优化，降低延迟与带宽占用", "both"),
    "servercore":          ("性能优化", "服务端专项优化：实体、区块、随机刻等的综合调优", "server"),
    "noisium":             ("性能优化", "世界生成噪声优化，开新图时省 CPU", "server"),
    # ---- 前置库 ----
    "fabric-api":          ("前置库", "Fabric 生态的地基，绝大多数 Fabric 模组的前置", "both"),
    "architectury-api":    ("前置库", "跨加载器抽象层，很多模组同时依赖它", "both"),
    "cloth-config":        ("前置库", "配置界面库，给模组提供图形化设置页", "both"),
    "fabric-language-kotlin":("前置库", "用 Kotlin 写的模组的前置运行时", "both"),
    # ---- 玩法内容 ----
    "create":              ("玩法内容", "机械动力：齿轮、传送带、自动化，最有名的科技向模组", "both"),
    "farmers-delight":     ("玩法内容", "农夫乐事：新增大量农作物与料理", "both"),
    "waystones":           ("玩法内容", "传送石碑：探索后可在石碑间快速传送", "both"),
    "comforts":            ("玩法内容", "睡袋与吊床，随时睡觉但不重置出生点", "both"),
    "veinminer":           ("玩法内容", "连锁挖矿，一次挖掉整条矿脉（可通过附魔限制）", "server"),
    "terralith":           ("玩法内容", "重写世界生成，地形更壮观（会改变新生成区域）", "server"),
    "rightclickharvest":   ("玩法内容", "右键收割与自动补种，省去反复点击", "server"),
    # ---- 信息显示 ----
    "jei":                 ("信息显示", "Just Enough Items：查看物品配方与用途", "both"),
    "jade":                ("信息显示", "准星指向方块/生物时显示详细信息", "both"),
    "appleskin":           ("信息显示", "显示饥饿值与饱和度细节", "both"),
    "xaeros-minimap":      ("信息显示", "小地图与路径点（服务端装了可共享路径点）", "both"),
    # ---- 仅客户端 ----
    "sodium":              ("仅客户端", "渲染优化，大幅提升帧率 —— 装在服务端没有作用", "client"),
    "iris":                ("仅客户端", "光影支持 —— 只对客户端渲染有意义", "client"),
}


def fetch_projects(slugs):
    q = urllib.parse.quote(json.dumps(slugs))
    out = subprocess.run(
        ['curl', '-s', '-m', '60', '-A', UA,
         f'https://api.modrinth.com/v2/projects?ids={q}'],
        capture_output=True, text=True).stdout
    try:
        return {p['slug']: p for p in json.loads(out)}
    except Exception as e:
        print('  ! 拉取失败:', e)
        return {}


def build(table, kind):
    meta = fetch_projects(list(table))
    items, missing = [], []
    for slug, (cat, desc, side) in table.items():
        p = meta.get(slug)
        if not p:
            missing.append(slug)
            continue
        items.append({
            "slug": slug,
            "title": p.get('title', slug),
            "desc": desc,
            "cat": cat,
            "side": side,
            "downloads": p.get('downloads', 0),
            "icon": p.get('icon_url') or "",
            "api_client": p.get('client_side', ''),
            "api_server": p.get('server_side', ''),
        })
    # 分类内按下载量降序
    order = []
    for c, _, _ in table.values():
        if c not in order:
            order.append(c)
    items.sort(key=lambda x: (order.index(x['cat']), -x['downloads']))
    if missing:
        print(f"  ! {kind} 未找到: {', '.join(missing)}")
    return items


plugins = build(PLUGINS, '插件')
mods = build(MODS, '模组')

catalog = {
    "source": "Modrinth API",
    "plugins": plugins,
    "mods": mods,
}

out = os.path.join(ROOT, 'catalog.json')
json.dump(catalog, open(out, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))

print(f"catalog.json 已生成")
print(f"  插件 {len(plugins)} 个，模组 {len(mods)} 个")
print(f"  大小 {os.path.getsize(out)} 字节")
cats = {}
for i in plugins:
    cats.setdefault('插件·' + i['cat'], 0)
    cats['插件·' + i['cat']] += 1
for i in mods:
    cats.setdefault('模组·' + i['cat'], 0)
    cats['模组·' + i['cat']] += 1
for k, v in cats.items():
    print(f"    {k}: {v}")
