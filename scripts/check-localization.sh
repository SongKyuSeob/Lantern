#!/bin/zsh
# 번역 점검: 빌드해서 코드의 문구를 카탈로그에 모으고(sync), 영어가 빠진 문구나 쓰지 않는 문구가 있으면 실패한다.
# 사용법: scripts/check-localization.sh
# 새 문구를 넣었다면 이 스크립트가 알려 주는 열쇠에 Xcode에서 영어를 채운다.
set -euo pipefail
cd "$(dirname "$0")/.."

# 평소 디버그 빌드 폴더(DerivedData)를 그대로 쓴다. 새 빌드 폴더를 만들지 않는다
xcodebuild -project Lantern.xcodeproj -scheme Lantern -configuration Debug build -quiet 2>/dev/null >/dev/null
INT=$(xcodebuild -project Lantern.xcodeproj -scheme Lantern -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ OBJROOT = /{print $2; exit}')
xcrun xcstringstool sync Lantern/Localizable.xcstrings --stringsdata $(find "$INT/Lantern.build" -name '*.stringsdata')
xcrun xcstringstool sync LanternKit/Sources/LanternKit/Localizable.xcstrings --stringsdata $(find "$INT/LanternKit.build" -name '*.stringsdata')
python3 scripts/l10n-fill-source.py Lantern/Localizable.xcstrings LanternKit/Sources/LanternKit/Localizable.xcstrings

python3 - <<'PY'
import json, re, sys
problems = []
for path in ['Lantern/Localizable.xcstrings', 'LanternKit/Sources/LanternKit/Localizable.xcstrings']:
    catalog = json.load(open(path))
    for key, entry in catalog['strings'].items():
        if entry.get('extractionState') == 'stale':
            problems.append(f'{path}: 코드에서 쓰지 않는 문구 {key!r}')
            continue
        if entry.get('shouldTranslate') is False:
            continue
        source = entry.get('localizations', {}).get('ko', {}).get('stringUnit', {}).get('value', key)
        en = entry.get('localizations', {}).get('en')
        # 한글이 없는 문구(" · %@" 같은 기호)는 번역 안 함으로 두거나, 언어마다 다르게 쓰면(시각 사이 "~"/"–") 영어를 채운다
        if not re.search('[가-힣]', source) and not en:
            problems.append(f'{path}: 한글이 없는 문구는 번역 안 함으로 표시하거나 영어를 채우기 {key!r}')
            continue
        units = [en['stringUnit']] if en and 'stringUnit' in en else \
            [v['stringUnit'] for v in en.get('variations', {}).get('plural', {}).values()] if en else []
        if not units or any(u.get('state') != 'translated' or not u.get('value') for u in units):
            problems.append(f'{path}: 영어 없음 {key!r}')
        elif any(re.search('[가-힣]', u['value']) for u in units):
            problems.append(f'{path}: 영어에 한글이 남음 {key!r}')
# 코드에 한글을 그대로 쓴 곳 (번역을 거치지 않음). 일부러 둔 곳은 줄 끝에 "// 번역 안 함: 이유"를 단다
import glob
for path in sorted(glob.glob('Lantern/*.swift') + glob.glob('LanternKit/Sources/LanternKit/*.swift')):
    for number, line in enumerate(open(path, encoding='utf-8'), 1):
        stripped = line.strip()
        # 번역 담당자에게 남기는 설명(comment:)은 한국어로 써도 된다
        if stripped.startswith('//') or '번역 안 함' in line or 'localized' in line or 'comment:' in line:
            continue
        if re.search(r'"[^"\n]*[가-힣]', line.split(' //')[0]):
            problems.append(f'{path}:{number}: 번역을 거치지 않는 한글 {stripped[:80]!r}')

if problems:
    print('\n'.join(problems)); sys.exit(1)
print('번역 점검 통과')
PY
