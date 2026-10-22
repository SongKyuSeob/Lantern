# 랜턴 (Lantern)

에이전트용 깨어 있기 + 우측 상단 플로팅 할 일 창 macOS 앱 (macOS 26+, SwiftUI + AppKit).

- 작업 전에 `docs/인수인계.md`를 먼저 읽는다. 최신 결정은 이 문서가 `docs/기획.md`보다 우선한다.
- UI와 무관한 로직은 `LanternKit` 로컬 패키지에 두고, AppKit 의존은 앱 타깃(`Lantern/`)에만 둔다.
- 앱 타깃은 폴더 동기화 그룹이라 `Lantern/` 아래에 파일을 넣으면 자동으로 포함된다. `project.pbxproj`는 빌드 설정을 바꿀 때만 건드린다.

## 작업 규칙
- 사용자가 명시적으로 요청하지 않으면 commit, push를 하지 않는다.
- 코드를 수정했다면 가능한 가장 작은 build 또는 test를 실행하고, 실제 결과를 보고한다. 검증하지 못한 항목은 명확히 말한다.
- 커밋 메시지는 `type: 내용` 형식. type은 영어, 내용은 한국어.
  - `feat` 새 기능 · `fix` 버그 수정 · `refactor` 구조 개선 · `design` 디자인 수정 · `docs` 문서 · `setting` 프로젝트 설정 · `add` 에셋 추가 · `del` 안 쓰는 코드 삭제 · `chore` 그 밖의 잡일
- 브랜치 이름은 `type/#이슈번호` (예: `feat/#3`)

## 빌드·테스트
```bash
xcodebuild -project Lantern.xcodeproj -scheme Lantern -configuration Debug build
swift test --package-path LanternKit
```
