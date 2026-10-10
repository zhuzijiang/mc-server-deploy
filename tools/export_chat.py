#!/usr/bin/env python3
"""把 DSH 会话记录导出成可读的 Markdown。

用法：
    python3 tools/export_chat.py <session.v4.jsonl.zstd> <输出目录>

产出：
    chat-dialogue.md    只含对话正文（人读）
    chat-with-tools.md  含工具调用与结果（重建上下文用）

安全：所有 GitHub 凭据在写出前一律替换成 <已脱敏>。
"""
import json, os, re, subprocess, sys

# 本次导出中实际出现过的凭据：连「主体」一起点名脱敏。
# 只按「前缀+主体」匹配是不够的 —— 会话里可能把 token 拆开讨论
# （例如「ghp_ 加 36 位，逐段数一下：a4Rx…」），那样前缀规则就漏了。
# 需要脱敏的凭据不写死在代码里 —— 这个文件本身要提交到公开仓库。
# 通过环境变量传入（逗号或空白分隔），或从一个不进版本库的文件读取：
#   REDACT_SECRETS="ghp_xxx,token2" python3 tools/export_chat.py <会话> <输出目录>
#   REDACT_SECRETS_FILE=~/.dsh-export-secrets python3 tools/export_chat.py ...
def load_secrets():
    out = []
    env = os.environ.get("REDACT_SECRETS", "")
    if env:
        out += [x for x in re.split(r"[,\s]+", env) if x]
    f = os.environ.get("REDACT_SECRETS_FILE", "")
    if f and os.path.exists(f):
        out += [l.strip() for l in open(f, encoding="utf-8") if l.strip()]
    return out


KNOWN_SECRETS = load_secrets()

SECRET_PATTERNS = [
    (re.compile(r'github_pat_[A-Za-z0-9_]{20,}'), 'github_pat_<已脱敏>'),
    (re.compile(r'ghp_[A-Za-z0-9]{20,}'),          'ghp_<已脱敏>'),
    (re.compile(r'gho_[A-Za-z0-9]{20,}'),          'gho_<已脱敏>'),
    (re.compile(r'ghs_[A-Za-z0-9]{20,}'),          'ghs_<已脱敏>'),
]


# 从已知凭据生成全部 >=6 位的子串，长的优先替换。
# 之所以这么做：会话里为了数长度，把 token 按 8 位一组拆开写过，
# 单靠「前缀+主体」或固定长度阈值都会漏掉这些碎片。
MIN_FRAG = 6
FRAGMENTS = set()
for _sec in KNOWN_SECRETS:
    _n = len(_sec)
    for _i in range(_n):
        for _j in range(_i + MIN_FRAG, _n + 1):
            FRAGMENTS.add(_sec[_i:_j])
FRAGMENTS = sorted(FRAGMENTS, key=len, reverse=True)


def redact(text: str) -> str:
    for frag in FRAGMENTS:
        if frag in text:
            text = text.replace(frag, '<已脱敏>')
    for pat, rep in SECRET_PATTERNS:
        text = pat.sub(rep, text)
    return text


def read_events(path):
    if path.endswith('.zstd'):
        raw = subprocess.run(['zstd', '-d', '-c', path],
                             capture_output=True).stdout.decode('utf-8', 'replace')
    else:
        raw = open(path, encoding='utf-8', errors='replace').read()
    for line in raw.split('\n'):
        line = line.strip()
        if not line:
            continue
        try:
            yield json.loads(line)
        except Exception:
            continue


def text_of(content):
    """把 message.content 数组拼成文本，reasoning 单独返回"""
    body, think = [], []
    if isinstance(content, str):
        return content, ''
    for part in content or []:
        if not isinstance(part, dict):
            continue
        t = part.get('type')
        if t == 'text':
            body.append(part.get('text', ''))
        elif t == 'reasoning':
            think.append(part.get('text', ''))
    return '\n'.join(body).strip(), '\n'.join(think).strip()


def fmt_args(raw, limit=1200):
    try:
        d = json.loads(raw) if isinstance(raw, str) else raw
    except Exception:
        return str(raw)[:limit]
    if isinstance(d, dict):
        cmd = d.get('command')
        if cmd:
            return str(cmd)[:limit]
        return json.dumps(d, ensure_ascii=False)[:limit]
    return str(d)[:limit]


def export(src, outdir):
    os.makedirs(outdir, exist_ok=True)
    dial, full = [], []
    turn = 0
    n_user = n_asst = n_call = n_res = 0

    dial.append('# 对话记录（仅正文）\n\n> 由 DSH 会话记录导出，凭据已脱敏。\n')
    full.append('# 完整对话记录（含工具调用与结果）\n\n> 由 DSH 会话记录导出，凭据已脱敏。\n')

    for ev in read_events(src):
        t = ev.get('type')
        d = ev.get('data') or {}

        if t == 'turn/start':
            turn += 1
            dial.append(f'\n---\n\n## 第 {turn} 轮\n')
            full.append(f'\n---\n\n## 第 {turn} 轮\n')

        elif t == 'user/message':
            body, _ = text_of(d.get('content'))
            if not body:
                continue
            n_user += 1
            dial.append(f'\n### 👤 用户\n\n{redact(body)}\n')
            full.append(f'\n### 👤 用户\n\n{redact(body)}\n')

        elif t == 'assistant/message':
            msg = d.get('message') or {}
            body, think = text_of(msg.get('content'))
            if not (body or think):
                continue
            n_asst += 1
            if body:
                dial.append(f'\n### 🤖 助手\n\n{redact(body)}\n')
            if think:
                dial.append(f'\n<details><summary>💭 思考过程</summary>\n\n{redact(think)}\n\n</details>\n')
            full.append(f'\n### 🤖 助手\n\n{redact(body)}\n')
            if think:
                full.append(f'\n<details><summary>💭 思考过程</summary>\n\n{redact(think)}\n\n</details>\n')

        elif t == 'tool/call':
            n_call += 1
            name = d.get('name', '?')
            args = fmt_args(d.get('arguments'))
            full.append(f'\n<details><summary>🔧 调用 <code>{name}</code></summary>\n\n'
                        f'```\n{redact(args)}\n```\n\n</details>\n')

        elif t == 'tool/result':
            n_res += 1
            res = d.get('result') or d.get('content') or d.get('output') or ''
            if isinstance(res, (dict, list)):
                res = json.dumps(res, ensure_ascii=False)
            res = str(res)
            if len(res) > 4000:
                res = res[:4000] + f'\n…（已截断，原文 {len(res)} 字符）'
            full.append(f'\n<details><summary>📤 结果</summary>\n\n```\n{redact(res)}\n```\n\n</details>\n')

    for fn, buf in (('chat-dialogue.md', dial), ('chat-with-tools.md', full)):
        p = os.path.join(outdir, fn)
        open(p, 'w', encoding='utf-8').write('\n'.join(buf))
        print(f'  ✓ {fn:<22} {os.path.getsize(p)/1024:8.1f} KB')

    print(f'  轮次 {turn} · 用户 {n_user} · 助手 {n_asst} · 工具调用 {n_call} · 结果 {n_res}')
    return turn, n_user, n_asst


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    export(sys.argv[1], sys.argv[2])
