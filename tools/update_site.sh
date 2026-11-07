#!/usr/bin/env bash
# Обновляет site/release.json под новый APK: версия, размер, SHA-256, ссылка.
# Предыдущий релиз переходит в "previous" — на сайте остаётся версия для отката.
# Использование: tools/update_site.sh dist/LuCI-Mobile-X.Y.Z.apk <mega-url>
set -euo pipefail
apk="$1"
url="${2:?нужна ссылка на MEGA}"
name="$(basename "$apk")"
version="$(sed -nE 's/.*-([0-9]+\.[0-9]+\.[0-9]+)\.apk$/\1/p' <<<"$name")"
out="$(dirname "$0")/../site/release.json"
python3 -I - "$out" "${version:?не удалось извлечь версию из $name}" "$name" "$(stat -c %s "$apk")" \
  "$(sha256sum "$apk" | cut -d' ' -f1)" "$url" "$(date +%F)" <<'PY'
import json, sys
out, version, name, size, sha, url, date = sys.argv[1:]
try:
    old = json.load(open(out))
except (OSError, ValueError):
    old = {}
prev = old.pop("previous", None)
rel = {"version": version, "date": date, "file": name, "size": int(size), "sha256": sha, "url": url, "minAndroid": "7.0"}
# Повторный запуск для той же версии (новая ссылка) не должен вытеснить настоящую предыдущую.
if old.get("version") and old["version"] != version:
    prev = old
if prev:
    rel["previous"] = prev
json.dump(rel, open(out, "w"), ensure_ascii=False, indent=2)
open(out, "a").write("\n")
PY
cat "$out"
