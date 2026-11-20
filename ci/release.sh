#!/usr/bin/env bash
# Полный прогон релиза:
#   сборка на ноде (ci/remote_build.sh, SHA-256 архива и APK) → копия в ~/Downloads →
#   MEGA (храним 2 версии) → site/release.json → коммит и push → сообщение в Discord.
# Секреты: .mega (mega login/password), DISCORD_WEBHOOK (или из claude.md).
# Использование: ci/release.sh ["что нового"]
set -euo pipefail
cd "$(dirname "$0")/.."
notes="${1:-}"
PY="${MEGA_PY:-$HOME/.venvs/wallet-mega/bin/python}"
GIT=(git -c safe.directory="$PWD")

bash ci/remote_build.sh
version="$(sed -nE 's/^version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml)"
apk="dist/LuCI-Mobile-$version.apk"
sha="$(cut -d' ' -f1 "$apk.sha256")"

dl="$HOME/Downloads"
mkdir -p "$dl"
cp "$apk" "$dl/"
(cd "$dl" && echo "$sha  $(basename "$apk")" | sha256sum -c -)

export MEGA_LOGIN="$(sed -nE 's/^mega login:\s*(.+)$/\1/p' .mega)"
export MEGA_PASSWORD="$(sed -nE 's/^mega password:\s*(.+)$/\1/p' .mega)"
url="$("$PY" ci/mega_upload.py "$apk")"
echo "MEGA: $url"

bash tools/update_site.sh "$apk" "$url" >/dev/null
prev="$(python3 -I -c 'import json;p=json.load(open("site/release.json")).get("previous");print(p["version"] if p else "")')"
prev_url="$(python3 -I -c 'import json;p=json.load(open("site/release.json")).get("previous");print(p["url"] if p else "")')"

# claude.md уже в .gitignore; явное исключение заставляет git add вернуть ошибку
"${GIT[@]}" add -A -- .
"${GIT[@]}" commit -q -m "release $version${prev:+ (previous $prev kept for rollback)}" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" || true
"${GIT[@]}" push -q "${GIT_PUSH_URL:-git@github.com:relkin016/luci-mobile.git}" HEAD:main

webhook="${DISCORD_WEBHOOK:-$(grep -ohE 'https://discord.com/api/webhooks/[^ ]+' claude.md CLAUDE.md 2>/dev/null | head -1)}"
{
  echo "📡 **LuCI Mobile $version** собран и выложен"
  [ -n "$notes" ] && echo "$notes"
  echo "APK: $url"
  echo "SHA-256: \`$sha\`"
  echo "Размер: $(( $(stat -c %s "$apk") / 1024 )) КБ · R8, подпись проверена, x86 нет"
  [ -n "$prev" ] && echo "Откат: $prev — $prev_url"
  echo "Сайт: https://relkin016.github.io/luci-mobile/"
} | DISCORD_WEBHOOK="$webhook" python3 -I ci/discord.py
echo "готово: $version"
