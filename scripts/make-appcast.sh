#!/bin/sh
# 자동 업데이트(Sparkle)용 appcast.xml을 만든다. GitHub 릴리스에 dmg와 함께 올린다.
#
# 사용법: scripts/make-appcast.sh <버전> <빌드 번호> <dmg 경로> <바뀐 내용 HTML 파일> [내려받기 주소 앞부분]
#   예: scripts/make-appcast.sh 0.3.0 4 release/Lantern-0.3.0.dmg build/release-notes-0.3.0.html
#   결과: dmg와 같은 폴더의 appcast.xml
#
# dmg 서명에는 이 맥 키체인의 Sparkle 비밀 키를 쓴다 (generate_keys로 만든 것, 저장소에는 없음).
# 서명 도구는 Xcode가 내려받은 Sparkle 패키지 안에 있다. 다른 곳에 있으면 SPARKLE_BIN에 폴더를 지정한다.
set -eu

if [ $# -lt 4 ]; then
  sed -n 4,6p "$0"
  exit 1
fi
VERSION=$1
BUILD=$2
DMG=$3
NOTES=$4
BASE_URL=${5:-https://github.com/SongKyuSeob/Lantern/releases/download/v$VERSION}

if [ -z "${SPARKLE_BIN:-}" ]; then
  SPARKLE_BIN=$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/Lantern-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1)
fi
if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
  echo "sign_update를 찾지 못했어요. Xcode로 한 번 빌드하거나 SPARKLE_BIN을 지정하세요." >&2
  exit 1
fi

# sparkle:edSignature="..." length="..."
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG")
case "$SIGNATURE" in
  sparkle:edSignature=*) ;;
  *) echo "서명하지 못했어요: $SIGNATURE" >&2; exit 1 ;;
esac

OUT=$(dirname "$DMG")/appcast.xml
DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>랜턴</title>
    <item>
      <title>$VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
$(cat "$NOTES")
      ]]></description>
      <enclosure url="$BASE_URL/$(basename "$DMG")" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
# 만든 파일의 서명이 공개 키와 맞는지 한 번 더 확인한다
"$SPARKLE_BIN/sign_update" --verify "$DMG" "$(echo "$SIGNATURE" | sed 's/.*edSignature="\([^"]*\)".*/\1/')" >/dev/null
echo "$OUT"
