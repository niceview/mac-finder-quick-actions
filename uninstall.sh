#!/bin/bash
# mac-finder-quick-actions 제거 스크립트
set -euo pipefail

DROPLET_NAME="${DROPLET_NAME:-Herdr}"
VSCODE_DROPLET_NAME="${VSCODE_DROPLET_NAME:-Open in VS Code}"
SERVICES_DIR="$HOME/Library/Services"

targets=(
	"$SERVICES_DIR/Open in VS Code.workflow"
	"$SERVICES_DIR/Open in Herdr.workflow"
	"$HOME/Applications/$DROPLET_NAME.app"
	"$HOME/Applications/$VSCODE_DROPLET_NAME.app"
	# 초기 수동 설치본 (번들 이름이 한글이던 시절)
	"$SERVICES_DIR/Visual Studio Code 로 열기.workflow"
	"$SERVICES_DIR/Herdr 로 열기.workflow"
)

removed=0
for t in "${targets[@]}"; do
	if [ -e "$t" ]; then
		rm -rf "$t"
		printf '  ✓ 제거: %s\n' "${t/#$HOME/~}"
		removed=$((removed + 1))
	fi
done

if [ "$removed" -eq 0 ]; then
	printf '  설치된 항목이 없습니다.\n'
	exit 0
fi

/System/Library/CoreServices/pbs -flush || true
killall Finder 2>/dev/null || true
printf '\n%d개 항목을 제거하고 Finder 를 재시작했습니다.\n' "$removed"
printf '툴바에 올려둔 아이콘은 ⌘ 를 누른 채 툴바 밖으로 드래그해 빼주세요.\n'
