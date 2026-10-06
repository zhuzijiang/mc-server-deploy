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
    "essentialsx":       ("基础管理", "指令套装：家、传送、经济、kits、封禁等一站式基础功能", "server"),
    "luckperms":         ("基础管理", "权限管理事实标准，支持继承、前缀后缀、网页编辑器", "server"),
    "placeholderapi":    ("基础管理", "给其它插件提供变量占位符（大量插件的必备前置）", "server"),
    "tab-was-taken":     ("基础管理", "自定义 TAB 列表、计分板与头顶显示", "server"),
    "lmd":               ("基础管理", "Let Me Despawn：让怪物按配置自然消失，减轻服务器压力", "server"),
    "deluxemenus":       ("基础管理", "用配置文件做各种 GUI 菜单（商店、传送、任务入口）", "server"),
    "chestshop":         ("基础管理", "箱子商店：玩家互相买卖，无需额外经济插件", "server"),
    "towny":             ("基础管理", "城镇与领地系统：建城、宣地、居民管理、战争", "server"),
    # ---- 世界与保护 ----
    "worldedit":         ("世界与保护", "建筑编辑神器，刷子、复制、生成地形（管理必备）", "server"),
    "fastasyncworldedit":("世界与保护", "WorldEdit 的异步高性能分支，大范围操作不卡服", "server"),
    "worldguard":        ("世界与保护", "区域保护：划定领地、禁 PVP、禁破坏，配合 WorldEdit 使用", "server"),
    "coreprotect":       ("世界与保护", "方块操作日志与回滚，被熊孩子破坏后能一键还原（强烈推荐）", "server"),
    "griefprevention":   ("世界与保护", "玩家自助圈地，用金铲子划地防止被破坏", "server"),
    "multiverse-core":   ("世界与保护", "多世界管理，创建/传送/隔离不同玩法世界", "server"),
    "multiverse-portals":("世界与保护", "自定义传送门，把多个世界连起来", "server"),
    "multiverse-inventories":("世界与保护", "按世界隔离背包与经验，做资源世界/创造世界必备", "server"),
    # ---- 性能与维护 ----
    "chunky":            ("性能与维护", "预先加载生成地图区块，避免玩家探索时卡顿", "server"),
    "spark":             ("性能与维护", "性能分析器，定位卡顿元凶（看 TPS、找热点）", "server"),
    "bluemap":           ("性能与维护", "高性能 3D 网页地图，可在浏览器里看服务器全貌", "server"),
    "squaremap":         ("性能与维护", "轻量 2D 网页地图，资源占用比 Dynmap 低", "server"),
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
    "mythicmobs":        ("玩法与社交", "自定义怪物、技能与掉落，做 RPG 玩法的核心插件", "server"),
    "crazycrates":       ("玩法与社交", "抽奖箱系统，配合权限组做奖励发放", "server"),
    "excellentcrates":   ("玩法与社交", "功能更全的抽奖箱，支持动画预览与多种钥匙", "server"),
}

MODS = {
    # ---- 性能优化 ----
    "lithium":             ("性能优化", "通用服务端优化，不改玩法地提升 TPS（首选必装）", "both"),
    "ferrite-core":        ("性能优化", "大幅降低内存占用，尤其适合内存紧张的设备", "both"),
    "modernfix":           ("性能优化", "加快启动、降低内存、修复若干原版性能问题", "both"),
    "c2me-fabric":         ("性能优化", "区块生成并行化，世界生成速度显著提升", "server"),
    "krypton":             ("性能优化", "网络栈优化，降低延迟与带宽占用", "both"),
    "servercore":          ("性能优化", "服务端专项优化：实体、区块、随机刻的综合调优", "server"),
    "noisium":             ("性能优化", "世界生成噪声优化，开新图时省 CPU", "server"),
    "memoryleakfix":       ("性能优化", "修掉原版与部分模组的内存泄漏，长时间开服不掉帧", "both"),
    "clumps":              ("性能优化", "把散落的经验球合并，减少实体数量", "both"),
    "threadtweak":         ("性能优化", "调整服务端线程优先级，改善卡顿尖峰", "both"),
    "async-locator":       ("性能优化", "异步执行结构定位，避免 /locate 卡住主线程", "server"),
    "tt20":                ("性能优化", "TPS 修复：让服务端在低负载时稳定跑满 20 TPS", "server"),
    "fastload":            ("性能优化", "加快区块加载与进入世界的速度", "both"),
    # ---- 前置库 ----
    "fabric-api":          ("前置库", "Fabric 生态的地基，绝大多数 Fabric 模组的前置", "both"),
    "architectury-api":    ("前置库", "跨加载器抽象层，很多模组同时依赖它", "both"),
    "cloth-config":        ("前置库", "配置界面库，给模组提供图形化设置页", "both"),
    "fabric-language-kotlin":("前置库", "用 Kotlin 写的模组的前置运行时", "both"),
    "forge-config-api-port":("前置库", "让 Fabric 模组也能读 Forge 风格配置", "both"),
    "puzzles-lib":         ("前置库", "很多内容模组共用的基础库", "both"),
    "geckolib":            ("前置库", "3D 动画实体/物品的渲染库", "both"),
    "balm":                ("前置库", "跨加载器的通用工具库", "both"),
    "midnightlib":         ("前置库", "轻量配置库，不少现代模组依赖它", "both"),
    "trinkets":            ("前置库", "饰品栏 API（Fabric 版 Curios）", "both"),
    "cardinal-components-api":("前置库", "给实体/方块附加自定义数据的组件系统", "server"),
    # ---- 玩法内容 ----
    "create":              ("玩法内容", "机械动力：齿轮、传送带、自动化，最有名的科技向模组", "both"),
    "farmers-delight":     ("玩法内容", "农夫乐事：新增大量农作物与料理", "both"),
    "waystones":           ("玩法内容", "传送石碑：探索后可在石碑间快速传送", "both"),
    "comforts":            ("玩法内容", "睡袋与吊床，随时睡觉但不重置出生点", "both"),
    "veinminer":           ("玩法内容", "连锁挖矿，一次挖掉整条矿脉（可通过附魔限制）", "server"),
    "terralith":           ("玩法内容", "重写世界生成，地形更壮观（会改变新生成区域）", "server"),
    "rightclickharvest":   ("玩法内容", "右键收割与自动补种，省去反复点击", "server"),
    "supplementaries":     ("玩法内容", "大量装饰与实用小物件，画风与原版一致", "both"),
    "quark":               ("玩法内容", "原版风格扩展：几百个可开关的小功能", "both"),
    "sophisticated-backpacks":("玩法内容", "可升级的背包系统，支持自动拾取与堆叠升级", "both"),
    "iron-chests":         ("玩法内容", "铁箱子等大容量容器，缓解储物压力", "both"),
    "mekanism":            ("玩法内容", "工业科技模组：矿物处理、发电、数字化存储", "both"),
    "immersiveengineering":("玩法内容", "沉浸工程：重型机械与电力网络，画风硬朗", "both"),
    "botania":             ("玩法内容", "植物魔法：用花与魔力做自动化与装备", "both"),
    "ars-nouveau":         ("玩法内容", "自定义法术系统，可自由组合法术效果", "both"),
    "aether":              ("玩法内容", "以太天堂维度，天空岛屿与地牢冒险", "both"),
    # ---- 信息显示 ----
    "jei":                 ("信息显示", "Just Enough Items：查看物品配方与用途", "both"),
    "jade":                ("信息显示", "准星指向方块/生物时显示详细信息", "both"),
    "appleskin":           ("信息显示", "显示饥饿值与饱和度细节", "both"),
    "xaeros-minimap":      ("信息显示", "小地图与路径点（服务端装了可共享路径点）", "both"),
    "wthit":               ("信息显示", "What The Hell Is That：方块/实体信息提示（Forge 系）", "both"),
    "emi":                 ("信息显示", "现代化的配方查看器，界面比 JEI 更清爽", "both"),
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
