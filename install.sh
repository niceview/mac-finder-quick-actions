#!/bin/bash
# mac-finder-quick-actions 설치 스크립트
#
# Finder 빠른 동작 2개와 드롭릿 앱 2개를 이 맥에 만든다.
# 필요한 앱이 없으면 그 항목만 건너뛰고 나머지는 계속 설치한다.
#
# 커스터마이즈 (환경변수로 덮어쓰기):
#   VSCODE_MENU_LABEL="Open in VS Code" ./install.sh
#   TERM_APP=iTerm ./install.sh
#
# 저장소를 clone 해서 실행해도 되고, 파이프로 실행해도 된다:
#   curl -fsSL https://raw.githubusercontent.com/niceview/mac-finder-quick-actions/main/install.sh | bash

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/niceview/mac-finder-quick-actions}"
REPO_BRANCH="${REPO_BRANCH:-main}"

# 임시 작업 공간. 트랩은 여기 한 곳에만 건다 (여러 번 걸면 앞의 것이 지워진다).
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 파이프로 실행되면 BASH_SOURCE 가 스크립트 경로를 가리키지 않으므로 src/ 를 찾을 수 없다.
# 그럴 때는 저장소 tarball 을 받아서 쓴다 (git 없이도 동작).
SRC=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]:-}" ]; then
	candidate="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src"
	[ -d "$candidate" ] && SRC="$candidate"
fi
if [ -z "$SRC" ]; then
	printf '\n▸ 저장소 내려받기\n  %s (%s)\n' "$REPO_URL" "$REPO_BRANCH"
	curl -fsSL "$REPO_URL/archive/refs/heads/$REPO_BRANCH.tar.gz" | tar xz -C "$WORK"
	SRC="$(find "$WORK" -maxdepth 2 -type d -name src | head -1)"
	[ -n "$SRC" ] || { printf '  ⚠ 내려받은 아카이브에서 src/ 를 찾지 못했습니다\n' >&2; exit 1; }
fi

VSCODE_MENU_LABEL="${VSCODE_MENU_LABEL:-Visual Studio Code 로 열기}"
HERDR_MENU_LABEL="${HERDR_MENU_LABEL:-Herdr 로 열기}"
TERM_APP="${TERM_APP:-Ghostty}"
DROPLET_NAME="${DROPLET_NAME:-Herdr}"
VSCODE_DROPLET_NAME="${VSCODE_DROPLET_NAME:-Open in VS Code}"

SERVICES_DIR="$HOME/Library/Services"
APPS_DIR="$HOME/Applications"
VSCODE_BUNDLE="$SERVICES_DIR/Open in VS Code.workflow"
HERDR_BUNDLE="$SERVICES_DIR/Open in Herdr.workflow"
DROPLET="$APPS_DIR/$DROPLET_NAME.app"
VSCODE_DROPLET="$APPS_DIR/$VSCODE_DROPLET_NAME.app"

installed=()
skipped=()
removed=()

# 의존 앱이 사라졌는데 예전 설치본이 남아 있으면, 눌러도 아무 일도 일어나지 않는
# 죽은 메뉴가 된다. 그럴 바엔 지우는 편이 낫다 (다시 설치하면 되살아난다).
drop_stale() {
	local path="$1" what="$2"
	if [ -e "$path" ]; then
		rm -rf "$path"
		removed+=("$what")
	fi
}

info()  { printf '  %s\n' "$*"; }
step()  { printf '\n▸ %s\n' "$*"; }
warn()  { printf '  ⚠ %s\n' "$*" >&2; }

# 앱 번들 경로를 찾는다. Spotlight(mdfind)가 꺼져 있어도 동작하도록
# 표준 위치를 먼저 확인한다.
find_app() {
	local name="$1" bundle_id="$2" p
	for p in "/Applications/$name.app" "$HOME/Applications/$name.app"; do
		[ -d "$p" ] && { printf '%s\n' "$p"; return 0; }
	done
	if [ -n "$bundle_id" ] && command -v mdfind >/dev/null 2>&1; then
		p="$(mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" 2>/dev/null | head -1)"
		[ -n "$p" ] && { printf '%s\n' "$p"; return 0; }
	fi
	return 1
}

# 템플릿 토큰을 실제 값으로 치환한다. "__TOKEN__=값" 쌍을 개수 제한 없이 받는다.
# 값에 / 가 들어가고 라벨이 비ASCII 라서 sed 를 쓰지 않는다.
substitute() {
	local file="$1"; shift
	python3 - "$file" "$@" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
for pair in sys.argv[2:]:
    token, _, value = pair.partition("=")
    text = text.replace(token, value)
p.write_text(text, encoding="utf-8")
PY
}

# .workflow 번들 하나를 설치하고 plist 유효성을 확인한다.
install_workflow() {
	local src="$1" dest="$2" label="$3" herdr="${4:-}"
	rm -rf "$dest"
	mkdir -p "$SERVICES_DIR"
	cp -R "$src" "$dest"
	substitute "$dest/Contents/Info.plist"     "__HERDR__=$herdr" "__TERM_APP__=$TERM_APP" "__MENU_LABEL__=$label"
	substitute "$dest/Contents/document.wflow" "__HERDR__=$herdr" "__TERM_APP__=$TERM_APP" "__MENU_LABEL__=$label"
	if ! plutil -lint "$dest/Contents/Info.plist" "$dest/Contents/document.wflow" >/dev/null; then
		rm -rf "$dest"
		warn "plist 검증 실패 — $(basename "$dest") 설치를 취소했습니다"
		return 1
	fi
}

# 드롭릿 .app 하나를 빌드해 설치한다: osacompile → 아이콘 교체 → ad-hoc 재서명.
# $1: 치환이 끝난 applescript  $2: 설치할 .app 경로  $3: 아이콘을 빌려올 앱 (빈 값이면 기본 아이콘)
build_droplet() {
	local script="$1" dest="$2" icon_app="${3:-}" icns="" name=""
	mkdir -p "$APPS_DIR"
	rm -rf "$dest"
	# osacompile 은 성공해도 "replacing existing signature" 를 찍는다.
	# 조용히 두되, 실패하면 그때 출력을 보여준다.
	if ! osacompile -o "$dest" "$script" >"$script.log" 2>&1; then
		cat "$script.log" >&2
		return 1
	fi

	if [ -n "$icon_app" ]; then
		# Info.plist 가 지정한 아이콘을 우선한다. VS Code 처럼 Resources 에
		# 파일 형식 아이콘이 수십 개 있는 앱에서 엉뚱한 것을 집지 않기 위해서다.
		name="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$icon_app/Contents/Info.plist" 2>/dev/null || true)"
		[ -n "$name" ] && icns="$icon_app/Contents/Resources/${name%.icns}.icns"
		if [ ! -f "$icns" ]; then
			icns="$(find "$icon_app/Contents/Resources" -maxdepth 1 -name '*.icns' 2>/dev/null | head -1)"
		fi
	fi
	if [ -n "$icns" ] && [ -f "$icns" ]; then
		cp "$icns" "$dest/Contents/Resources/droplet.icns"
		# Assets.car 와 CFBundleIconName 이 남아 있으면 .icns 보다 우선한다.
		rm -f "$dest/Contents/Resources/Assets.car"
		/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$dest/Contents/Info.plist" >/dev/null 2>&1 || true
	fi

	# 로컬 빌드라 quarantine 은 없지만, 리소스를 바꿨으니 서명을 다시 맞춘다.
	codesign --force --deep -s - "$dest" >/dev/null 2>&1 || warn "ad-hoc 코드사인 실패 (동작에는 지장 없음)"
	touch "$dest"
}

step "사전 점검"

HERDR_BIN=""
if command -v herdr >/dev/null 2>&1; then
	HERDR_BIN="$(command -v herdr)"
elif command -v brew >/dev/null 2>&1 && [ -x "$(brew --prefix)/bin/herdr" ]; then
	HERDR_BIN="$(brew --prefix)/bin/herdr"
fi
[ -n "$HERDR_BIN" ] && info "herdr: $HERDR_BIN" || warn "herdr 를 찾을 수 없습니다 — herdr 관련 항목을 건너뜁니다"

VSCODE_APP="$(find_app "Visual Studio Code" "com.microsoft.VSCode" || true)"
[ -n "$VSCODE_APP" ] && info "VS Code: $VSCODE_APP" || warn "VS Code 를 찾을 수 없습니다 — 해당 빠른 동작을 건너뜁니다"

TERM_APP_PATH="$(find_app "$TERM_APP" "" || true)"
[ -n "$TERM_APP_PATH" ] && info "터미널: $TERM_APP_PATH" || warn "$TERM_APP 을 표준 위치에서 찾지 못했습니다 (open -a 가 이름으로 찾을 수 있으면 동작합니다)"

step "이전 버전 정리"
# 초기 수동 설치본은 번들 이름이 한글이었다. 중복 메뉴가 뜨지 않도록 지운다.
for legacy in "$SERVICES_DIR/Visual Studio Code 로 열기.workflow" "$SERVICES_DIR/Herdr 로 열기.workflow"; do
	if [ -d "$legacy" ]; then
		rm -rf "$legacy"
		info "제거: $(basename "$legacy")"
	fi
done

step "빠른 동작 설치"

if [ -n "$VSCODE_APP" ]; then
	install_workflow "$SRC/vscode.workflow" "$VSCODE_BUNDLE" "$VSCODE_MENU_LABEL"
	installed+=("빠른 동작  「${VSCODE_MENU_LABEL}」")
	info "$VSCODE_BUNDLE"
else
	skipped+=("VS Code 빠른 동작 (VS Code 미설치)")
	drop_stale "$VSCODE_BUNDLE" "이전 VS Code 빠른 동작 (VS Code 가 없어짐)"
fi

if [ -n "$HERDR_BIN" ]; then
	install_workflow "$SRC/herdr.workflow" "$HERDR_BUNDLE" "$HERDR_MENU_LABEL" "$HERDR_BIN"
	installed+=("빠른 동작  「${HERDR_MENU_LABEL}」")
	info "$HERDR_BUNDLE"
else
	skipped+=("herdr 빠른 동작 (herdr 미설치)")
	drop_stale "$HERDR_BUNDLE" "이전 herdr 빠른 동작 (herdr 가 없어짐)"
fi

step "드롭릿 앱 빌드"

tmp="$WORK/droplet"
mkdir -p "$tmp"

if [ -n "$HERDR_BIN" ]; then
	cp "$SRC/herdr-droplet.applescript" "$tmp/herdr-droplet.applescript"
	substitute "$tmp/herdr-droplet.applescript" "__HERDR__=$HERDR_BIN" "__TERM_APP__=$TERM_APP"
	build_droplet "$tmp/herdr-droplet.applescript" "$DROPLET" "$TERM_APP_PATH"
	installed+=("드롭릿 앱   $DROPLET")
	info "$DROPLET"
else
	skipped+=("herdr 드롭릿 앱 (herdr 미설치)")
	drop_stale "$DROPLET" "이전 herdr 드롭릿 앱 (herdr 가 없어짐)"
fi

if [ -n "$VSCODE_APP" ]; then
	cp "$SRC/vscode-droplet.applescript" "$tmp/vscode-droplet.applescript"
	substitute "$tmp/vscode-droplet.applescript" "__VSCODE_APP__=$VSCODE_APP"
	build_droplet "$tmp/vscode-droplet.applescript" "$VSCODE_DROPLET" "$VSCODE_APP"
	installed+=("드롭릿 앱   $VSCODE_DROPLET")
	info "$VSCODE_DROPLET"
else
	skipped+=("VS Code 드롭릿 앱 (VS Code 미설치)")
	drop_stale "$VSCODE_DROPLET" "이전 VS Code 드롭릿 앱 (VS Code 가 없어짐)"
fi

# 설치도 제거도 없었다면 Finder 를 건드릴 이유가 없다.
if [ $((${#installed[@]} + ${#removed[@]})) -gt 0 ]; then
	step "Finder 서비스 등록"
	/System/Library/CoreServices/pbs -flush || true
	killall Finder 2>/dev/null || true
	info "서비스 캐시를 비우고 Finder 를 재시작했습니다"
fi

printf '\n─────────────────────────────────────────\n'
if [ ${#installed[@]} -gt 0 ]; then
	printf '설치됨\n'
	for i in "${installed[@]}"; do printf '  ✓ %s\n' "$i"; done
fi
if [ ${#removed[@]} -gt 0 ]; then
	printf '제거됨\n'
	for r in "${removed[@]}"; do printf '  ✗ %s\n' "$r"; done
fi
if [ ${#skipped[@]} -gt 0 ]; then
	printf '건너뜀\n'
	for s in "${skipped[@]}"; do printf '  – %s\n' "$s"; done
fi

# 설치된 게 하나도 없으면 사용법을 안내해봐야 존재하지 않는 메뉴를 가리킬 뿐이다.
# 호출한 쪽이 실패를 알아챌 수 있도록 0 이 아닌 값으로 끝낸다.
if [ ${#installed[@]} -eq 0 ]; then
	cat >&2 <<'EOF'

설치된 항목이 없습니다. 최소 하나는 있어야 합니다:

  · Visual Studio Code  — https://code.visualstudio.com
  · herdr               — 설치 후 `command -v herdr` 로 잡히는지 확인하세요

설치한 뒤 이 스크립트를 다시 실행하면 됩니다.
EOF
	exit 1
fi

cat <<EOF

사용법
  · Finder 에서 파일/폴더 우클릭 → 빠른 동작
  · 드롭릿을 Finder 툴바에 올리려면 ⌘ 를 누른 채 앱을 툴바로 드래그
    (Finder → 이동 → 응용 프로그램 폴더가 아니라 ~/Applications 입니다)
  · 사이드바 폴더는 그 툴바 아이콘 위로 드래그하면 열립니다
  · 툴바 아이콘을 클릭하면 현재 창의 폴더가 열립니다
    (「${VSCODE_DROPLET_NAME}」 은 VS Code 새 창, 「${DROPLET_NAME}」 은 새 herdr 워크스페이스)
  · 각 드롭릿의 첫 클릭 때 "Finder 제어" 권한 팝업이 한 번 뜹니다 — 허용을 누르세요

메뉴가 안 보이면
  시스템 설정 → 일반 → 로그인 항목 및 확장 프로그램 → Finder 확장 프로그램
EOF
