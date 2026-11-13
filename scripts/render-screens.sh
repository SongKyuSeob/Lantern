#!/bin/zsh
# 주요 화면을 한국어·영어, 다크·라이트로 그림(PNG) 저장하고, 영어 화면에 한글이 남았는지 글자 인식으로 확인한다.
# 창을 화면 밖에 그려서 마우스·키보드·포커스를 쓰지 않고, 실제 할 일 대신 시연 데이터를 쓴다.
# 사용법: scripts/render-screens.sh [저장 폴더]   (기본 ~/Downloads/랜턴-화면)
#         LANTERN_RENDER_SIZE=small|standard|large|larger 를 주면 그 크기 단계로 그린다
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-$HOME/Downloads/랜턴-화면}
xcodebuild -project Lantern.xcodeproj -scheme Lantern -configuration Debug build -quiet 2>/dev/null >/dev/null
APP="$(xcodebuild -project Lantern.xcodeproj -scheme Lantern -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')/Lantern.app"
rm -rf "$OUT"; mkdir -p "$OUT"
for appearance in dark light; do
    for lang in ko en; do
        open -g -n --env LANTERN_DEMO=1 --env LANTERN_RENDER="$OUT" --env LANTERN_RENDER_APPEARANCE=$appearance --env LANTERN_RENDER_SIZE=${LANTERN_RENDER_SIZE:-standard} "$APP" --args -AppleLanguages "($lang)"
        sleep 3
        for _ in {1..60}; do pgrep -f "$APP/Contents/MacOS" >/dev/null || break; sleep 1; done
    done
done
echo "저장: $OUT (ko·en은 다크, ko-light·en-light는 라이트)"
xcrun swift scripts/find-hangul.swift "$OUT"/en/*.png "$OUT"/en-light/*.png
