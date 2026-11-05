# 카탈로그의 모든 문구에 원본(한국어) 값을 적어 둔다.
# 그래야 빌드 때 ko.lproj가 만들어져, 언어를 직접 정해 번역을 가져오는 곳(LanternKit의 localized(_:_:))에서도 한국어를 찾을 수 있다.
# scripts/check-localization.sh가 sync 뒤에 부른다
import json, sys
for path in sys.argv[1:]:
    catalog = json.load(open(path))
    for key, entry in catalog['strings'].items():
        if entry.get('shouldTranslate') is False:
            continue
        localizations = entry.setdefault('localizations', {})
        if 'ko' not in localizations:
            # defaultValue가 따로 있는 문구는 sync가 넣어 둔 값을 쓴다
            localizations['ko'] = {'stringUnit': {'state': 'translated', 'value': key}}
    json.dump(catalog, open(path, 'w'), ensure_ascii=False, indent=2, sort_keys=True)
