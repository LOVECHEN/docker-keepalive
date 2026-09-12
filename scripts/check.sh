#!/usr/bin/env bash
# 逐个 pull 校验命名空间内镜像是否可用；pull 后立即删除以释放磁盘。
# 受总时间预算约束，未检查完的下次继续。
#
# 环境变量:
#   IMAGES_FILE   清单文件            (默认 images.txt)
#   TIME_BUDGET   单次时间预算(秒)    (默认 18000)
#   MIN_SLEEP     镜像间最短间隔(秒)  (默认 20)
#   MAX_SLEEP     镜像间最长间隔(秒)  (默认 150)
#   PULL_TIMEOUT  单个 pull 超时(秒)  (默认 900)
#   MAX_IMAGES    单次最多数量(0=不限)(默认 0)
#   PLATFORM      平台                (默认空)
set -uo pipefail

IMAGES_FILE="${IMAGES_FILE:-images.txt}"
TIME_BUDGET="${TIME_BUDGET:-18000}"
MIN_SLEEP="${MIN_SLEEP:-20}"
MAX_SLEEP="${MAX_SLEEP:-150}"
PULL_TIMEOUT="${PULL_TIMEOUT:-900}"
MAX_IMAGES="${MAX_IMAGES:-0}"
PLATFORM="${PLATFORM:-}"

[ -s "$IMAGES_FILE" ] || { echo "empty list: $IMAGES_FILE"; exit 1; }

mapfile -t IMAGES < <(shuf "$IMAGES_FILE")
TOTAL=${#IMAGES[@]}
START=$(date +%s)
DEADLINE=$((START + TIME_BUDGET))

ok=0; fail=0; done=0
echo "total $TOTAL | budget ${TIME_BUDGET}s | interval ${MIN_SLEEP}-${MAX_SLEEP}s | pull timeout ${PULL_TIMEOUT}s"
echo "start $(date -u '+%F %T')Z | platform=${PLATFORM:-default}"
echo "--------------------------------------------------------------------------"

PLAT_ARG=(); [ -n "$PLATFORM" ] && PLAT_ARG=(--platform "$PLATFORM")

# 拉取一个 ref: 先默认平台; 未显式指定平台时再退回 arm64 (适配 arm64-only 镜像)
try_pull() {
  timeout "$PULL_TIMEOUT" docker pull "${PLAT_ARG[@]}" "$1" >/dev/null 2>&1 && return 0
  [ -z "$PLATFORM" ] && timeout "$PULL_TIMEOUT" docker pull --platform linux/arm64 "$1" >/dev/null 2>&1 && return 0
  return 1
}

for img in "${IMAGES[@]}"; do
  remain=$((DEADLINE - $(date +%s)))
  if [ "$remain" -le $((MAX_SLEEP + 60)) ]; then
    echo "budget nearly used (${remain}s left), stop"
    break
  fi
  if [ "$MAX_IMAGES" -gt 0 ] && [ "$done" -ge "$MAX_IMAGES" ]; then
    echo "reached MAX_IMAGES=$MAX_IMAGES, stop"
    break
  fi

  done=$((done + 1))
  echo "[$done/$TOTAL] $img"
  if try_pull "$img:latest"; then
    ok=$((ok + 1)); tag="latest"
  else
    tag=$(python3 scripts/first_tag.py "$img" 2>/dev/null || true)
    if [ -n "$tag" ] && try_pull "$img:$tag"; then
      ok=$((ok + 1))
    else
      echo "     unavailable, skip"
      fail=$((fail + 1))
      continue
    fi
  fi

  slp=$(( RANDOM % (MAX_SLEEP - MIN_SLEEP + 1) + MIN_SLEEP ))
  echo "     ok ($img:$tag), wait ${slp}s"
  sleep "$slp"

  docker rmi -f "$img:$tag" >/dev/null 2>&1 || true
done

docker image prune -af >/dev/null 2>&1 || true

ELAPSED=$(( $(date +%s) - START ))
echo "--------------------------------------------------------------------------"
echo "checked $done | ok $ok | unavailable $fail | ${ELAPSED}s ($((ELAPSED/60))min)"
df -h / | tail -1
[ "$done" -eq 0 ] && { echo "nothing checked this run"; exit 0; }
[ "$ok" -gt 0 ] || { echo "checked $done but 0 ok"; exit 1; }
exit 0
