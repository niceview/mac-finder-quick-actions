# mac-finder-quick-actions

macOS Finder에서 파일이나 폴더를 우클릭해 **VS Code** 또는 **[herdr](https://github.com/)** 워크스페이스로 바로 여는 빠른 동작(Quick Action)과, 툴바/Dock에 올려두고 드래그 앤 드롭으로 쓰는 드롭릿 앱을 설치합니다.

## 설치되는 것

| 항목 | 설치 위치 | 하는 일 |
|---|---|---|
| 빠른 동작 `Visual Studio Code 로 열기` | `~/Library/Services/Open in VS Code.workflow` | 선택 항목을 VS Code로 연다 |
| 빠른 동작 `Herdr 로 열기` | `~/Library/Services/Open in Herdr.workflow` | 선택 항목 경로로 herdr 워크스페이스를 만든다 |
| 드롭릿 `Herdr.app` | `~/Applications/Herdr.app` | 폴더를 드롭하면 herdr 워크스페이스를 만든다 |

파일을 대상으로 실행하면 herdr 쪽은 **그 파일의 상위 폴더**를 작업 디렉터리로 씁니다. 여러 항목을 선택해도 첫 번째 것만 처리합니다 (워크스페이스 난립 방지).

## 요구사항

macOS(빠른 동작을 지원하는 버전) 외에는 전부 선택 사항입니다. 없는 항목은 건너뛰고 나머지만 설치됩니다.

- [Visual Studio Code](https://code.visualstudio.com/) — VS Code 빠른 동작용
- `herdr` — herdr 빠른 동작 및 드롭릿용. `command -v herdr` 로 찾으므로 Apple Silicon(`/opt/homebrew`)과 Intel(`/usr/local`) 모두 자동 인식됩니다
- [Ghostty](https://ghostty.org/) — herdr를 띄울 터미널. 다른 터미널은 `TERM_APP` 으로 지정

## 설치

한 줄이면 됩니다. 저장소를 clone 하지 않고, 임시 폴더에 받아서 설치한 뒤 지웁니다.

```sh
curl -fsSL https://raw.githubusercontent.com/niceview/mac-finder-quick-actions/main/install.sh | bash
```

무엇을 실행하는지 먼저 보고 싶다면 위 URL을 브라우저로 열어보거나, 저장소를 clone 해서 실행해도 됩니다.

```sh
git clone https://github.com/niceview/mac-finder-quick-actions.git
cd mac-finder-quick-actions
./install.sh
```

여러 번 실행해도 안전합니다 (기존 설치본을 지우고 다시 만듭니다).

설치 스크립트는 마지막에 `killall Finder` 를 실행합니다. Finder가 재시작되지만 열려 있던 창은 유지됩니다.

## 사용법

**우클릭 빠른 동작** — Finder에서 파일/폴더 우클릭 → `빠른 동작` → 원하는 항목

**툴바 드롭 대상** — `~/Applications` 의 `Herdr.app` 을 **⌘ 누른 채** Finder 툴바로 드래그하면 아이콘이 고정됩니다. 사이드바(즐겨찾기)의 폴더를 그 아이콘 위로 드래그하면 워크스페이스가 열립니다.

> 사이드바 항목을 우클릭했을 때는 빠른 동작이 나타나지 않습니다. macOS가 사이드바에 별도의 축약 메뉴를 쓰기 때문이고, 우회할 방법이 없습니다. 드롭릿을 만든 이유가 이것입니다.

**아이콘 클릭** — 이미 떠 있는 herdr 세션을 앞으로 가져옵니다. 꺼져 있으면 새로 띄워 attach 합니다.

## 커스터마이즈

환경변수로 덮어쓸 수 있습니다.

```sh
VSCODE_MENU_LABEL="Open in VS Code" \
HERDR_MENU_LABEL="Open in Herdr" \
TERM_APP=iTerm \
DROPLET_NAME=Workspace \
./install.sh
```

| 변수 | 기본값 | 설명 |
|---|---|---|
| `VSCODE_MENU_LABEL` | `Visual Studio Code 로 열기` | 우클릭 메뉴에 뜰 문구 |
| `HERDR_MENU_LABEL` | `Herdr 로 열기` | 우클릭 메뉴에 뜰 문구 |
| `TERM_APP` | `Ghostty` | herdr를 띄울 터미널 앱 이름 |
| `DROPLET_NAME` | `Herdr` | 드롭릿 앱 이름 |

## 제거

```sh
curl -fsSL https://raw.githubusercontent.com/niceview/mac-finder-quick-actions/main/uninstall.sh | bash
```

저장소를 clone 해두었다면 `./uninstall.sh` 로도 됩니다.

툴바에 올려둔 아이콘은 ⌘ 누른 채 툴바 밖으로 드래그해 빼면 됩니다.

## 메뉴가 안 보일 때

시스템 설정 → 일반 → 로그인 항목 및 확장 프로그램 → **Finder 확장 프로그램** 에서 해당 항목이 켜져 있는지 확인하세요.

## 동작 원리

빠른 동작은 Automator GUI로 만들지만, 실체는 plist 두 개가 든 `.workflow` 번들일 뿐입니다. 이 저장소는 그 번들을 템플릿으로 들고 있다가 설치 시점에 `__HERDR__` / `__TERM_APP__` / `__MENU_LABEL__` 토큰만 치환합니다.

드롭릿은 `.app` 을 그대로 배포하지 않고 대상 맥에서 `osacompile` 로 새로 빌드합니다. 복사된 앱에 붙는 Gatekeeper quarantine을 피하기 위해서입니다.

저장소 안의 번들 디렉터리 이름은 전부 ASCII입니다. macOS는 파일명을 NFD로 저장해서 한글 디렉터리명을 git에 담으면 정규화 문제가 생기기 때문입니다. 한글은 `Info.plist` 안의 문자열 값으로만 존재하고, 우클릭 메뉴 문구는 번들 이름이 아니라 `NSMenuItem.default` 에서 옵니다.

## 참고

이 저장소는 공개 저장소입니다. 개인 경로나 사내 설정을 추가하지 마세요.
