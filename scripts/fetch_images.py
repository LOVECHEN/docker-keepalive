#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
列出 DockerHub 命名空间下全部公开镜像名 -> 输出文件。
优先 search-v3，失败退回 v2；任一成功即写文件，全失败退出码 1。
用法: fetch_images.py <namespace> <out_file>
"""
import json, os, ssl, sys, time, urllib.request, urllib.error

NS  = sys.argv[1] if len(sys.argv) > 1 else "lovechen"
OUT = sys.argv[2] if len(sys.argv) > 2 else "images.txt"

ctx = ssl.create_default_context()
if os.environ.get("INSECURE") == "1":            # 可选: 跳过证书校验
    ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE

H = {"User-Agent": ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"),
     "Accept": "application/json, text/plain, */*"}

def get(url):
    last = None
    for i in range(5):
        try:
            req = urllib.request.Request(url, headers=H)
            with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            last = e; time.sleep(min(40, 4 * (2 ** i)))
        except Exception as e:
            last = e; time.sleep(4 * (i + 1))
    raise RuntimeError(str(last))

def via_v3():
    names, frm = set(), 0
    while True:
        d = get(f"https://hub.docker.com/api/search/v3/catalog/search?query={NS}&from={frm}&size=100")
        rs = d.get("results", [])
        for r in rs:
            if r.get("type") == "image" and r.get("publisher", {}).get("name") == NS:
                names.add(r["slug"])                 # ns/repo
        frm += 100
        if frm >= d.get("total", 0) or not rs:
            break
        time.sleep(1)
    return sorted(names)

def via_v2():
    names, page = [], 1
    while True:
        d = get(f"https://hub.docker.com/v2/repositories/{NS}/?page_size=100&page={page}")
        names += [f"{NS}/{r['name']}" for r in d.get("results", []) if not r.get("is_private")]
        if not d.get("next"):
            break
        page += 1; time.sleep(3)
    return sorted(set(names))

names = []
for how, fn in (("search-v3", via_v3), ("v2-repositories", via_v2)):
    try:
        names = fn()
        if names:
            print(f"[fetch] 经 {how} 拿到 {len(names)} 个", file=sys.stderr)
            break
    except Exception as e:
        print(f"[fetch] {how} 失败: {e}", file=sys.stderr)

if not names:
    print("[fetch] 全部方式失败", file=sys.stderr)
    sys.exit(1)

with open(OUT, "w") as f:
    f.write("\n".join(names) + "\n")
print(f"[fetch] {NS}: {len(names)} 个 -> {OUT}")
