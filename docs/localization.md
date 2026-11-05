# 영어 문구 기준 (README·앱 공통)

영어 README(`README.en.md`)와 앱 번역(String Catalog)은 이 문서의 용어와 규칙을 따른다. 새 문구를 넣을 때 한국어와 함께 영어도 여기 기준으로 정한다.

## 말투

- 한국어의 "~해요" 말투처럼, 영어도 짧고 친근하게 쓴다. 사용자를 **you**로 부르고, 설명 글에는 줄임말(can't, you'll, it's)을 써도 된다.
- 명령조보다 무엇이 일어나는지를 쓴다. "Please"는 사과·부탁이 꼭 필요할 때만.
- 느낌표, 과장("Simply", "Just", "Easily")은 쓰지 않는다.
- 기술 용어(sudoers, hook, pmset)는 꼭 필요한 곳에만, 처음 나올 때 무엇인지 함께 쓴다.

## 대소문자 (Apple HIG)

| 종류 | 규칙 | 예 |
|---|---|---|
| 메뉴 항목, 버튼, 탭, 세그먼트, 창 제목 | Title Case | Check for Updates…, Turn Display Off, Set Due Date… |
| 설정의 줄 이름, 스위치 이름 | Sentence case | Open at login, Automatically check for updates |
| 설명 글, 안내, 알림 본문, 알림 질문 | Sentence case | Install now? |

- 누르면 입력이나 창이 더 나오는 항목은 끝에 `…`(말줄임표 한 글자)를 붙인다: Add Note…, Settings…
- 목록은 옥스퍼드 쉼표를 쓴다: to-dos, history, and settings

## 날짜·시간·숫자

- 시각과 날짜는 직접 조립하지 않고 시스템 형식(`Date.formatted`)을 쓴다. 영어 맥이면 "4:30 PM", "Nov 7"처럼 저절로 맞는다. 지금 코드에서 "오후 4:30"을 손으로 만드는 곳(`AwakeText`, `History.clock`)은 번역할 때 바꾼다.
- 남은 시간 표시 "1:42"는 그대로 둔다.
- 개수가 들어간 문구는 String Catalog의 복수형을 쓴다: 1 to-do / 3 to-dos, 1 day left / 3 days left.

## 용어집

### 앱 전체

| 한국어 | 영어 | 메모 |
|---|---|---|
| 랜턴 | Lantern | |
| 깨어 있기 (기능) | Keep Awake | 기능 이름. 탭 이름은 **Awake** |
| 깨어 있는 중 | Awake | 상태: "Awake until 4:30 PM", "Awake · 1:42 left". 에이전트 작업 수는 "Claude Code ×2 · Codex ×1 working" |
| 깨어 있기 꺼짐 | Keep Awake off | |
| 뚜껑 닫아도 유지 / 뚜껑 모드 | Closed-Lid Mode | 하나로 통일. 설명은 "keeps your Mac awake with the lid closed" |
| 지금 뚜껑을 닫으면 | If you close the lid now | 값: **Stays awake** / **Sleeps** |
| 할 일 | to-do (복수 to-dos) | 탭 이름은 **To-dos** |
| 메모 | note | |
| 기한 | due date | |
| 기록 | History | 창 이름 |
| 에이전트 | agent | Claude Code, Codex는 그대로 |
| 평소 창 | summary window | 마우스 클릭이 통과하는 반투명 창 |
| 활성 창 | expanded window | 아이콘·단축키로 연 창 (README에서만 씀) |
| 한 줄 보기 | single-line view | 메뉴 항목은 **Single-Line View** |

### 깨어 있기 탭·메뉴

| 한국어 | 영어 |
|---|---|
| 언제까지 | Until |
| 계속 / 1시간 / 2시간 / 시각 / 에이전트 | Always / 1 Hour / 2 Hours / Time / Agents |
| 끌 때까지 | until you turn it off |
| 에이전트가 끝날 때까지 | until agents finish |
| 연장 › / 30분 더 / 1시간 더 / 2시간 더 | Extend › / +30 Minutes / +1 Hour / +2 Hours |
| 화면 끄기 | Turn Display Off |
| 깨어 있기 끄기 | Turn Off Keep Awake |
| 깨어 있기 시작 · 1시간 | Keep Awake · 1 Hour |
| 창 숨기기 / 창 보이기 | Hide Window / Show Window |
| 기록 보기… | Show History… |
| 업데이트 확인… | Check for Updates… |
| 설정… | Settings… |
| 랜턴 종료 | Quit Lantern |

### 할 일 탭

| 한국어 | 영어 |
|---|---|
| 할 일 추가 (입력 칸) | Add a to-do |
| 완료 3 / 지우기 (완료 묶음) | Done 3 / Clear |
| 지우기 (한 줄, ×) | Remove |
| 끝내기 / 되돌리기 | Mark as Done / Mark as Not Done |
| 메모 추가… / 메모 편집… / 편집 | Add Note… / Edit Note… / Edit |
| 메모를 적어요 (빈 칸 안내) | Write a note |
| 저장 / 취소 | Save / Cancel |
| 기한 정하기… / 기한 바꾸기… / 기한 없애기 | Set Due Date… / Change Due Date… / Remove Due Date |
| 정하기 / 오늘 | Set / Today |
| 오늘 / 내일 / 3일 남음 / 2일 지남 | Today / Tomorrow / 3 days left / 2 days overdue |
| 이름 바꾸기 | Rename |
| 기록 › | History › |

### 업데이트

| 한국어 | 영어 |
|---|---|
| ● 새 버전 0.5.0 | ● Version 0.5.0 available |
| 0.5.0 업데이트 (알약) | Update to 0.5.0 |
| 끝나면 0.5.0 설치 (알약 / 평소 창) | 0.5.0 Pending / Will update to 0.5.0 when done |
| 지금 설치할까요? | Install now? |
| 끝난 뒤 설치 / 지금 설치 / 그대로 두기 | Install Later / Install Now / Keep Waiting |

### 설정

| 한국어 | 영어 |
|---|---|
| 일반 / 에이전트 / 전원 | General / Agents / Power |
| 로그인할 때 열기 | Open at login |
| 평소 창을 한 줄로 보기 | Show summary window in a single line |
| 언어: 시스템 설정 따르기 | Language: System Language |
| 기한 임박 표시 | Highlight as due soon |
| 당일 / 1일 전 / 2일 전 / 3일 전 / 1주 전 | On the due date / 1 day before / 2 days before / 3 days before / 1 week before |
| 업데이트 자동으로 확인 | Automatically check for updates |
| 단축키 / 창 열기·닫기 / 창 숨기기·보이기 | Shortcuts / Open or close window / Hide or show window |
| 키를 누르세요… | Press a shortcut… |
| 배터리 기준 | Battery threshold |
| 연결 / 해제 | Connect / Disconnect |
| 연결됨 · 마지막 신호 2분 전 / 아직 신호 없음 | Connected · Last signal 2 min ago / No signals yet |
| 권한 · 설치됨 / 설치 안 됨 | Permission · Installed / Not installed |
| 설치… / 제거… | Install… / Remove… |

## 대표 문장

| 한국어 | 영어 |
|---|---|
| 적어 둔 할 일은 평소 창에 위에서 세 개까지 보여요 | The top three to-dos show in the summary window |
| 지금까지 끝낸 일 · 지운 일 · 깨어 있기를 날짜별로 봐요 | See completed and removed to-dos and Keep Awake sessions by date |
| 끌어서 다른 모서리나 화면으로 옮길 수 있어요 | Drag to move to another corner or display |
| 새 버전에서 바뀐 내용을 보고 설치해요 | See what's new and install |
| 깨어 있는 동안만 켤 수 있어요 | Available only while Keep Awake is on |
| 맥이 뜨거워서 지금은 켤 수 없어요 | Your Mac is too hot to turn this on right now |
| 배터리가 18% 이하라 켤 수 없어요 | Can't turn on while the battery is at 18% or below |
| 허락을 기다리는 에이전트가 있어요 | An agent is waiting for your approval |
| 1분 안에 다시 일하면 이어져요 | Keeps going if an agent starts again within 1 minute |
| 하루 한 번 새 버전이 있는지 확인해요. 설치는 직접 눌러야 해요. | Checks for a new version once a day. Nothing is installed until you click Install. |
| 설치하면 랜턴이 다시 켜지면서 깨어 있기가 끝나요. | Installing restarts Lantern and ends your Keep Awake session. |
| 배터리가 18%라 깨어 있기를 껐어요. | Battery is at 18%, so Keep Awake was turned off. |
| 맥이 많이 뜨거워서 뚜껑 닫아도 유지를 껐어요. | Your Mac got too hot, so Closed-Lid Mode was turned off. |
| 뚜껑 닫아도 유지를 끄지 못했어요. 맥이 잠들지 않을 수 있어요. 설정 → 전원에서 권한을 확인해 주세요. | Couldn't turn off Closed-Lid Mode, so your Mac may not sleep. Check the permission in Settings → Power. |
| 할 일 저장 파일을 열 수 없어요. 이번에 적는 할 일은 랜턴을 끄면 사라져요. | Couldn't open your to-do file. To-dos you add now will be lost when you quit Lantern. |
| 기한이 이만큼 남았거나 지난 할 일은 주황색으로 표시하고 목록 맨 위로 올려요. | To-dos due within this range, or overdue, turn orange and move to the top of the list. |
| ⌃ 또는 ⌥와 함께 눌러 주세요. | Include ⌃ or ⌥ in the shortcut. |

## 구현 방식 (0.5.0)

- **String Catalog**: 앱은 `Lantern/Localizable.xcstrings`, LanternKit은 `LanternKit/Sources/LanternKit/Localizable.xcstrings`(패키지 `defaultLocalization: "ko"`). 원본 언어는 한국어이고, 열쇠는 한국어 문장 그대로다
- 코드에서는 `Text(String(localized: "할 일 추가"))`, `String(localized: "깨어 있는 중 · \(label)")`처럼 쓴다. 보간은 열쇠에서 `%@`·`%lld`가 된다. 개수가 들어간 문구("%lld일 남음")는 카탈로그의 영어 복수형(one/other)으로 처리한다
- 같은 한국어가 자리마다 다른 영어가 돼야 하면 따로 열쇠를 둔다: `String(localized: "tab.awake", defaultValue: "깨어 있기", comment: …)` (지금: `tab.awake`, `history.metric.awake`, `history.section.completed`, `history.section.removed`, `update.pill.pending`, `todo.clearDone`, LanternKit `time.range`). 보간만 다르고 한국어가 같은 문구("끝낸 일 \(a)"와 "끝낸 일 \(b)")도 열쇠가 같아지니 주의
- LanternKit에서 언어를 직접 정해야 하는 곳(Markdown, 남은 날, 기간 — 테스트용)은 `localized(_:_:)`가 그 언어의 `.lproj` 묶음에서 가져온다. 그래서 카탈로그에 한국어 값도 적어 둔다(`scripts/l10n-fill-source.py`)
- 시각·날짜·기간·요일·달 이름은 문장으로 번역하지 않고 시스템 형식(`Date.FormatStyle`, `Duration` 형식, `Calendar.shortWeekdaySymbols`)을 쓴다. 영어 시각은 "4:30 PM"의 공백이 좁은 공백(U+202F)이다
- 화면 언어(`Localization.language`)는 앱이 실제로 고른 번역(`Bundle.main.preferredLocalizations`)이다. 설정 → 일반 → 언어(시스템 설정 따르기 / 한국어 / English, UserDefaults `app.language`)를 바꾸면 앱 선호 언어(`AppleLanguages`)를 바꾸고 "다시 켜기"로 재시작한다
- Info.plist `CFBundleLocalizations`에 ko·en (Sparkle 창도 영어로 나오게), 영어 앱 이름은 `Lantern/en.lproj/InfoPlist.strings`
- 앱 타깃 빌드 설정 `DEVELOPMENT_LANGUAGE = en`: 맥 언어가 한국어도 영어도 아니면(일본어 등) 영어로 보이게 한다. 프로젝트 개발 지역(ko)을 따르면 한국어로 보이고, "시스템 설정 따르기"의 판단(영어)과도 어긋났다. Info.plist에 `CFBundleDevelopmentRegion`을 직접 적으면 빌드 때 덮인다
- 확인한 언어 고르기: 맥 언어 일본어 → 영어, 독일어·한국어 → 한국어, 한국어 → 한국어, 영어 → 영어 (`-AppleLanguages`로 띄워 확인)
- 기록에 남은 깨어 있기 옵션 이름은 그때 언어로 저장돼 있어서 `History.optionLabel`이 지금 언어로 바꿔 보여 준다
- 줄 끝에 `// 번역 안 함: 이유`를 단 곳만 한글을 그대로 쓴다 (언어 이름 "한국어", 감시 작업 파일 이름 등)

## 누락 점검

- `scripts/check-localization.sh`: 빌드해서 코드의 문구를 카탈로그에 모으고(`xcstringstool sync`), 영어가 빠진 문구, 영어에 한글이 남은 문구, 쓰지 않게 된 문구, 번역을 거치지 않는 코드 속 한글을 찾는다. 하나라도 있으면 실패. 새 문구를 넣으면 이걸 돌리고, 알려 준 열쇠에 Xcode에서 영어를 채운다
- `scripts/render-screens.sh [폴더]`: 주요 화면을 한국어·영어 PNG로 저장(기본 `~/Downloads/랜턴-화면`)하고, 영어 화면에서 글자를 인식해 한글이 남았는지 확인한다. 디버그 빌드의 `LANTERN_RENDER` 모드를 언어마다 따로 실행한다. 창을 화면 밖에 그려 마우스·키보드·포커스를 쓰지 않고 시연 데이터를 쓴다. 유리 효과는 그림에 잡히지 않아 이때만 단색 바탕이고, 입력 칸 테두리도 일부만 그려진다(실제 앱은 정상). 메뉴바 메뉴와 알림은 그림으로 확인할 수 없다

## 번역할 때 따로 정할 것

- (0.5.0에서 함) 기록 창의 Markdown 복사 제목도 화면 언어를 따른다 (`History.markdown`)
- 뚜껑 모드 감시 스크립트 이름 "랜턴 뚜껑 모드 감시"는 시스템 설정 "앱 백그라운드 활동"에 그대로 보인다. 영어 맥에서도 보이므로 이름을 바꿀지, 바꾼다면 예전 이름 파일 정리를 어떻게 할지 정해야 한다.
- (0.5.0에서 함) 시연 데이터(`DemoData`)의 예시 할 일도 영어판을 둔다
- 뚜껑 모드 감시 스크립트 이름은 일단 그대로 둔다(영어 README에 뜻을 함께 적음)
