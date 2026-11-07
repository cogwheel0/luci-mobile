#!/usr/bin/env bash
# Собирает подписанный release APK на сборочной ноде: R8 + shrinkResources,
# только arm64-v8a/armeabi-v7a (без x86/x86_64). Перед сборкой — analyze и тесты.
# Результат: dist/LuCI-Mobile-X.Y.Z.apk + .sha256
set -euo pipefail
cd "$(dirname "$0")/.."
TOOLS="${TOOLS:-$HOME/tools}"
export JAVA_HOME="$TOOLS/jdk" ANDROID_HOME="$TOOLS/android-sdk" ANDROID_SDK_ROOT="$TOOLS/android-sdk"
export PATH="$TOOLS/flutter/bin:$JAVA_HOME/bin:$PATH"
echo "sdk.dir=$ANDROID_HOME" > android/local.properties
echo "flutter.sdk=$TOOLS/flutter" >> android/local.properties

[ -f android/key.properties ] || { echo "нет android/key.properties — APK будет неподписанным" >&2; exit 1; }

# Нода: 16 потоков / 32 ГБ — нагружаем полностью.
workers="${GRADLE_WORKERS:-$(nproc)}"
export GRADLE_OPTS="-Dorg.gradle.workers.max=$workers -Dorg.gradle.parallel=true"

flutter config --no-analytics >/dev/null
flutter pub get
flutter analyze --no-fatal-infos
flutter test --concurrency="$workers"
flutter build apk --release --target-platform android-arm,android-arm64

version="$(sed -nE 's/^version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml)"
mkdir -p dist
apk="dist/LuCI-Mobile-$version.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$apk"

apksigner="$(ls -d "$ANDROID_HOME"/build-tools/*/ | sort -V | tail -1)apksigner"
"$apksigner" verify --print-certs "$apk" | grep -m1 'certificate SHA-256'
if "$JAVA_HOME/bin/jar" tf "$apk" | grep -q '^lib/x86'; then
  echo "в $apk попали x86-библиотеки" >&2; exit 1
fi
(cd dist && sha256sum "$(basename "$apk")" > "$(basename "$apk").sha256")
cat "$apk.sha256"
ls -l "$apk"
