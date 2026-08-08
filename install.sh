#!/bin/bash
# mac-finder-quick-actions 설치 스크립트
#
# Finder 빠른 동작 2개와 herdr 드롭릿 앱을 이 맥에 만든다.
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

SERVICES_DIR="$HOME/Library/Services"
APPS_DIR="$HOME/Applications"
VSCODE_BUNDLE="$SERVICES_DIR/Open in VS Code.workflow"
HERDR_BUNDLE="$SERVICES_DIR/Open in Herdr.workflow"
DROPLET="$APPS_DIR/$DROPLET_NAME.app"

installed=()
skipped=()

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

# 템플릿 토큰을 실제 값으로 치환한다. 값에 / 가 들어가므로 구분자로 | 를 쓴다.
substitute() {
	local file="$1" herdr="$2" term="$3" label="$4"
	python3 - "$file" "$herdr" "$term" "$label" <<'PY'
import sys, pathlib
path, herdr, term, label = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
p = pathlib.Path(path)
text = p.read_text(encoding="utf-8")
for token, value in (("__HERDR__", herdr), ("__TERM_APP__", term), ("__MENU_LABEL__", label)):
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
	substitute "$dest/Contents/Info.plist"    "$herdr" "$TERM_APP" "$label"
	substitute "$dest/Contents/document.wflow" "$herdr" "$TERM_APP" "$label"
	if ! plutil -lint "$dest/Contents/Info.plist" "$dest/Contents/document.wflow" >/dev/null; then
		rm -rf "$dest"
		warn "plist 검증 실패 — $(basename "$dest") 설치를 취소했습니다"
		return 1
	fi
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
fi

if [ -n "$HERDR_BIN" ]; then
	install_workflow "$SRC/herdr.workflow" "$HERDR_BUNDLE" "$HERDR_MENU_LABEL" "$HERDR_BIN"
	installed+=("빠른 동작  「${HERDR_MENU_LABEL}」")
	info "$HERDR_BUNDLE"
else
	skipped+=("herdr 빠른 동작 (herdr 미설치)")
fi

step "드롭릿 앱 빌드"

if [ -n "$HERDR_BIN" ]; then
	tmp="$WORK/droplet"
	mkdir -p "$tmp"
	cp "$SRC/herdr-droplet.applescript" "$tmp/droplet.applescript"
	substitute "$tmp/droplet.applescript" "$HERDR_BIN" "$TERM_APP" ""

	mkdir -p "$APPS_DIR"
	rm -rf "$DROPLET"
	# osacompile 은 성공해도 "replacing existing signature" 를 찍는다.
	# 조용히 두되, 실패하면 그때 출력을 보여준다.
	if ! osacompile -o "$DROPLET" "$tmp/droplet.applescript" >"$tmp/osacompile.log" 2>&1; then
		cat "$tmp/osacompile.log" >&2
		exit 1
	fi

	# 터미널 앱 아이콘을 빌려 쓴다. 없으면 기본 드롭릿 아이콘을 그대로 둔다.
	icns=""
	if [ -n "$TERM_APP_PATH" ]; then
		icns="$(find "$TERM_APP_PATH/Contents/Resources" -maxdepth 1 -name '*.icns' 2>/dev/null | head -1)"
	fi
	if [ -n "$icns" ]; then
		cp "$icns" "$DROPLET/Contents/Resources/droplet.icns"
		# Assets.car 와 CFBundleIconName 이 남아 있으면 .icns 보다 우선한다.
		rm -f "$DROPLET/Contents/Resources/Assets.car"
		/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$DROPLET/Contents/Info.plist" >/dev/null 2>&1 || true
	fi

	# 로컬 빌드라 quarantine 은 없지만, 리소스를 바꿨으니 서명을 다시 맞춘다.
	codesign --force --deep -s - "$DROPLET" >/dev/null 2>&1 || warn "ad-hoc 코드사인 실패 (동작에는 지장 없음)"
	touch "$DROPLET"

	installed+=("드롭릿 앱   $DROPLET")
	info "$DROPLET"
else
	skipped+=("herdr 드롭릿 앱 (herdr 미설치)")
fi

step "Finder 서비스 등록"
/System/Library/CoreServices/pbs -flush || true
killall Finder 2>/dev/null || true
info "서비스 캐시를 비우고 Finder 를 재시작했습니다"

printf '\n─────────────────────────────────────────\n'
if [ ${#installed[@]} -gt 0 ]; then
	printf '설치됨\n'
	for i in "${installed[@]}"; do printf '  ✓ %s\n' "$i"; done
fi
if [ ${#skipped[@]} -gt 0 ]; then
	printf '건너뜀\n'
	for s in "${skipped[@]}"; do printf '  – %s\n' "$s"; done
fi
cat <<EOF

사용법
  · Finder 에서 파일/폴더 우클릭 → 빠른 동작
  · 드롭릿을 Finder 툴바에 올리려면 ⌘ 를 누른 채 앱을 툴바로 드래그
    (Finder → 이동 → 응용 프로그램 폴더가 아니라 ~/Applications 입니다)
  · 사이드바 폴더는 그 툴바 아이콘 위로 드래그하면 열립니다

메뉴가 안 보이면
  시스템 설정 → 일반 → 로그인 항목 및 확장 프로그램 → Finder 확장 프로그램
EOF
