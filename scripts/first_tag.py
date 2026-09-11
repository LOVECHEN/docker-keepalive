#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""给定 <ns>/<repo>，返回一个最近更新的真实 tag（供没有 latest 的仓库使用）。"""
import json, os, ssl, sys, time, urllib.request
img = sys.argv[1]                      # 形如 lovechen/xxx
ns, repo = img.split("/", 1)
ctx = ssl.create_default_context()
if os.environ.get("INSECURE") == "1":
    ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
url = f"https://hub.docker.com/v2/repositories/{ns}/{repo}/tags/?page_size=10&ordering=last_updated"
req = urllib.request.Request(url, headers={"User-Agent": "docker-sync/1.0"})
for i in range(3):
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=20) as r:
            d = json.load(r)
        for t in d.get("results", []):
            if t.get("name"):
                print(t["name"]); sys.exit(0)
        sys.exit(1)
    except Exception:
        time.sleep(2)
sys.exit(1)
