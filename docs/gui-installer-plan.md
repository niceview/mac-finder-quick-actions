# 차기 계획 — DMG 배포용 GUI 설치 앱

> 상태: **미구현.** 2026-08-30 설계만 마친 문서다. 착수 전에 「선행 과제」를 먼저 읽을 것.

## 배경

지금 이 저장소를 쓰려면 터미널에서 `install.sh` 를 실행해야 한다 (클론 후 실행, 또는 `curl | bash`).
터미널을 쓰지 않는 사람에게는 진입 장벽이고, 재설치·제거를 하려면 저장소나 명령어를 기억하고 있어야 한다.

목표는 **DMG 하나를 받아 앱을 더블클릭하면 설치가 끝나는** 경로를 *추가*하는 것이다.
기존 터미널 경로는 그대로 둔다 — 커스터마이즈용이자, GUI 앱이 내부적으로 재사용하는 실체이기도 하다.

### 결정 사항

| 항목 | 결정 | 이유 |
|---|---|---|
| 배포 형식 | 설치 앱(.app) + DMG | `install.sh` 로직을 그대로 재사용할 수 있어 가장 단순하다. `.pkg` 는 옵션 화면을 못 만든다 |
| GUI 범위 | 기본값 설치, 화면 2개 (환영 → 결과) | 세부 커스터마이즈는 지금처럼 환경변수로 |
| 코드 서명 | 안 함 (ad-hoc 만) | Apple Developer 계정이 없다. Gatekeeper 우회 절차를 문서로 안내 |
| 릴리스 | `build.sh` 로컬 빌드 | GitHub Actions 는 지금 규모에 과하다 |

## 선행 과제 — 히스토리 분기 (해결됨)

2026-08-30 시점에 `main` 과 `origin/main` 이 **공통 조상 없이** 갈라져 있었다.
원격을 기준으로 잡고 로컬에만 있던 작업(VS Code 드롭릿, herdr 드롭릿의 `frontFinderFolder()`,
이 문서)을 그 위에 재적용해 정리했다. 아래 설계는 정리된 트리를 기준으로 한다.

## 설계 개요

```
build.sh
  └─ osacompile src/installer.applescript
       → dist/stage/Finder 빠른 동작.app
            Contents/Info.plist            ← 번들 ID·버전 주입
            Contents/Resources/payload/    ← src/ + install.sh + uninstall.sh 통째로 복사
  └─ codesign --force --deep -s -
  └─ hdiutil create → dist/FinderQuickActions-<VERSION>.dmg
                         ├─ Finder 빠른 동작.app
                         └─ 먼저 읽어주세요.txt   ← Gatekeeper 안내
```

설치 앱은 새 설치 로직을 만들지 않는다. 번들 안의 `payload/install.sh` 를 `do shell script` 로 실행하고
결과만 다이얼로그로 보여준다. **설치 로직은 계속 `install.sh` 하나**이고, GUI 는 얇은 껍데기다.

## 작업 1 — `install.sh` 손보기

앱에서 호출하면 두 곳이 깨진다. 아래 넷을 고친다. **모두 하위 호환** — 터미널 실행과 `curl | bash` 가 그대로 동작해야 한다.

### 1-1. `python3` 의존성 제거 (필수)

`substitute()` 는 `python3` 힙독으로 토큰을 치환한다. 순정 macOS 에는 `python3` 가 없다
(Command Line Tools 를 깔아야 생긴다). 더블클릭 사용자에게 가장 잘 깨질 지점이다.

순수 bash 로 교체한다 (bash 3.2 에서 동작 확인):

```bash
substitute() {
	local file="$1" text pair token value
	text="$(cat "$file")"
	shift
	for pair in "$@"; do
		token="${pair%%=*}"; value="${pair#*=}"
		text="${text//$token/$value}"
	done
	printf '%s\n' "$text" > "$file"
}
```

CLAUDE.md 가 `sed` 대신 Python 을 쓴 이유로 "값에 `/` 가 들어가고 라벨이 비ASCII" 를 든다 —
bash 파라미터 확장은 두 문제 모두 없다. 치환 대상은 plist/applescript 텍스트뿐이고,
뒤에 `plutil -lint` 검증이 이미 있어 회귀도 잡힌다.

### 1-2. PATH 비의존 `herdr` 탐색 (필수)

Finder 에서 실행된 앱의 `do shell script` 는 PATH 가 `/usr/bin:/bin:/usr/sbin:/sbin` 뿐이다.
지금의 `command -v herdr` 와 `brew --prefix` 가 **무조건 실패**해서 herdr 관련 항목이 통째로 건너뛰어진다.

`find_herdr()` 를 만들어 순서대로 시도:

1. `command -v herdr`
2. `/bin/zsh -lc 'command -v herdr'` — 사용자 로그인 셸의 PATH 를 빌려온다
3. 고정 후보: `/opt/homebrew/bin`, `/usr/local/bin`, `$HOME/.local/bin`, `$HOME/.cargo/bin`

터미널 경로에도 이득이다 (herdr 를 흔치 않은 곳에 깐 경우도 잡힌다).

### 1-3. `--check` 모드 (필수)

환영 화면에서 "무엇이 설치되고 무엇이 건너뛰어지는지" 를 보여주려면,
아무것도 바꾸지 않고 감지 결과만 뱉는 모드가 필요하다.

```
$ ./install.sh --check
HERDR=/opt/homebrew/bin/herdr
VSCODE=/Applications/Visual Studio Code.app
TERM_APP=/Applications/Ghostty.app
```

없으면 값이 빈 문자열. 사전 점검 블록을 함수로 빼서 재사용한다.

### 1-4. `SUMMARY_FILE` 환경변수 (필수)

결과 화면에 목록을 그리기 위해, 지정되면 기존 `installed[]` / `skipped[]` / `removed[]` 배열을
기계가 읽을 형태로 파일에 쓴다:

```
INSTALLED|빠른 동작 「Visual Studio Code 로 열기」
SKIPPED|herdr 드롭릿 앱 (herdr 미설치)
REMOVED|Herdr.app (herdr 가 사라짐)
```

사람용 터미널 출력은 지금 그대로 둔다. `uninstall.sh` 에도 같은 방식으로 추가한다.

## 작업 2 — `src/installer.applescript` (신규)

기존 두 드롭릿과 같은 스타일(한국어 주석, 최소 의존)로 작성한다.

1. **payload 경로 확인** — `path to me` → `Contents/Resources/payload`. 없으면 오류 다이얼로그
2. **사전 점검** — `bash payload/install.sh --check` 실행, 결과 파싱
3. **환영 다이얼로그** — 설치될 항목·건너뛸 항목과 설치 위치(`~/Library/Services`, `~/Applications`)를 명시.
   버튼 `취소` / `제거` / `설치`. 감지된 게 하나도 없으면 설치 버튼 대신 안내만
4. **설치 실행** — `do shell script "SUMMARY_FILE=… bash <payload>/install.sh"`.
   관리자 권한 불필요 ($HOME 에만 쓴다). stdout·stderr 는 임시 로그로 받아 둔다
5. **결과 다이얼로그** — 요약 파일을 읽어 ✓/– 목록 + "툴바에 올리는 법" 3줄.
   버튼 `완료` / `앱 폴더 열기`(→ `~/Applications`)
6. **오류 처리** — 종료코드가 0이 아니면 로그 마지막 15줄을 `display alert` 로
7. **제거 경로** — 3번에서 `제거` 를 누르면 `payload/uninstall.sh` 를 같은 방식으로 실행

> **설계 판단:** 제거 앱을 따로 만들지 않고 설치 앱 하나에 `제거` 버튼을 넣는다.
> 화면 수도 DMG 안 항목 수도 늘지 않는다. 대신 DMG 를 지우면 GUI 제거 수단이 사라지므로,
> README 에 "제거하려면 DMG 를 다시 열거나 `uninstall.sh`" 라고 적는다.

**구현 시 반드시 지킬 것**

- 앱을 DMG 에서 바로 실행하면 App Translocation 으로 임의의 읽기전용 경로에서 돌아간다.
  `path to me` 는 그래도 올바르게 풀리고 `install.sh` 는 `mktemp -d` 만 쓰므로 문제없다 —
  **payload 에 쓰기를 추가하지 말 것.**
- `install.sh` 는 piped 실행일 때 저장소 tarball 을 내려받는다. 앱에서 호출할 때는
  `BASH_SOURCE[0]` 이 payload 안의 실제 파일이므로 번들 안 `src/` 를 쓴다 (의도한 동작).
  이 분기를 건드릴 때 앱 경로도 같이 확인할 것.
- `install.sh` 는 무언가 실제로 바뀐 경우에만 `killall Finder` 를 한다.
  결과 다이얼로그에 "Finder 가 한 번 재시작됩니다" 를 적어 둔다.

## 작업 3 — `build.sh` (신규, 저장소 루트)

```
./build.sh            → dist/ 에 .app 과 .dmg 생성
./build.sh --app-only → .app 까지만
```

1. `VERSION` 파일(신규, `1.0.0`)에서 버전을 읽는다
2. `dist/` 정리 → `osacompile -o "dist/stage/Finder 빠른 동작.app" src/installer.applescript`
3. `PlistBuddy` 로 `Info.plist` 주입 — `CFBundleIdentifier=com.niceview.finder-quick-actions.installer`,
   `CFBundleName`, `CFBundleShortVersionString`, `CFBundleVersion`, `LSMinimumSystemVersion`
4. `src/`, `install.sh`, `uninstall.sh` 를 `Contents/Resources/payload/` 로 복사, 실행 권한 부여
5. `codesign --force --deep -s -` — ad-hoc. 실패해도 경고만 (`build_droplet` 과 같은 태도)
6. `dist/stage/먼저 읽어주세요.txt` 작성
7. `hdiutil create -volname "Finder 빠른 동작" -srcfolder dist/stage -ov -format UDZO`
8. 산출물 경로와 `shasum -a 256` 출력

`.gitignore` 에 `dist/` 추가. 아이콘은 이번 범위 밖 (기본 애플릿 아이콘 사용).
나중에 `assets/*.icns` 하나를 넣고 build.sh 에서 복사하는 세 줄로 추가할 수 있다.

## 작업 4 — 문서

### `먼저 읽어주세요.txt` (DMG 안)

서명이 없어 macOS 15 부터는 우클릭 → 열기 우회가 통하지 않는다. 정확한 절차를 적는다:

```
1. 「Finder 빠른 동작」 을 더블클릭합니다.
2. "열 수 없습니다" 경고가 뜨면 확인을 누릅니다.
3. 시스템 설정 → 개인정보 보호 및 보안 → 아래로 스크롤 →
   "「Finder 빠른 동작」이(가) 차단되었습니다" 옆의 [그래도 열기] 클릭
4. 다시 [열기] 를 누르면 설치 화면이 뜹니다.
```

### `README.md`

- 설치 섹션을 셋으로: **① DMG 다운로드** / **② 원라인 `curl | bash`** / **③ 클론 후 실행**
- ①에 Gatekeeper 안내와 "왜 경고가 뜨는가 — 서명이 없어서. 소스는 이 저장소에 전부 공개돼 있다" 한 줄
- 제거 섹션에 GUI 제거 추가
- 「동작 원리」에 설치 앱은 껍데기이고 실체는 `install.sh` 라는 점 추가

### `CLAUDE.md`

- "`install.sh` 는 **세 가지** 방식으로 동작해야 한다: 클론 실행, piped 실행, 설치 앱의 payload 실행" 으로 갱신
- Python 힙독 관련 서술을 순수 bash 치환으로 교체
- 최소 PATH 제약(1-2)을 「깨지기 쉬운 제약」에 추가

## 변경/추가 파일

| 파일 | 상태 | 내용 |
|---|---|---|
| `install.sh` | 수정 | python3 제거, `find_herdr()`, `--check`, `SUMMARY_FILE` |
| `uninstall.sh` | 수정 | `SUMMARY_FILE` 지원 |
| `src/installer.applescript` | 신규 | GUI 설치 앱 본체 |
| `build.sh` | 신규 | .app + .dmg 빌드 |
| `VERSION` | 신규 | `1.0.0` |
| `.gitignore` | 수정 | `dist/` 추가 |
| `README.md` / `CLAUDE.md` | 수정 | DMG 경로, Gatekeeper 안내, 제약 갱신 |

## 검증

기존 경로가 깨지지 않는 것이 가장 중요하다. 순서대로:

1. **터미널 하위 호환** — `./install.sh` 후 `~/Library/Services` 에 workflow 2개,
   `~/Applications` 에 앱 2개. Finder 우클릭 → 빠른 동작에 두 항목이 보이는지
2. **piped 하위 호환** — `cat install.sh | bash` 가 여전히 tarball 을 받아 설치하는지
3. **python3 없는 최소 PATH 환경** — `env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin bash install.sh`
   가 성공하고, 특히 **herdr 항목이 건너뛰어지지 않는지** (1-2 의 핵심 회귀 테스트)
4. **`--check`** — 3줄을 출력하고 파일시스템을 건드리지 않는지 (`~/Library/Services` mtime 확인)
5. **빌드** — `./build.sh` → `codesign -dv` 로 ad-hoc 서명, `hdiutil verify` 로 DMG 무결성 확인
6. **로컬 실행** — DMG 마운트 → 더블클릭 → 환영 화면 감지 결과가 4번과 일치 → 설치 →
   결과 목록이 맞는지 → 실제 우클릭 메뉴와 드롭릿 동작
7. **Gatekeeper 실사** — DMG 에 `xattr -w com.apple.quarantine "0083;00000000;Safari;"` 를 붙여
   다운로드 상황을 재현하고, 안내문 절차가 실제 화면과 일치하는지. 다르면 문구를 화면에 맞춘다
8. **제거** — 앱의 `제거` 버튼으로 경로들이 사라지는지. `./uninstall.sh` 도 여전히 동작하는지
9. 마지막으로 `./install.sh` 를 한 번 더 돌려 원래 상태로 복구
