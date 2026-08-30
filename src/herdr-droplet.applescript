-- Herdr 드롭릿
-- Finder 툴바 / Dock / 데스크탑에 두고, 클릭하면 현재 Finder 창의 폴더로,
-- 폴더나 파일을 떨어뜨리면 그 경로로 herdr 워크스페이스를 새로 만든다.
--
-- __HERDR__ 와 __TERM_APP__ 는 install.sh 가 설치 시점에 치환한다.
--
-- "현재 창의 폴더"는 Finder 에 Apple Events 를 보내야만 알 수 있어서
-- 첫 클릭 때 "Finder 제어" 권한 팝업이 한 번 뜬다 (vscode-droplet 과 동일).

property herdrPath : "__HERDR__"
property termApp : "__TERM_APP__"

-- 터미널이 이미 떠 있으면 앞으로 가져오고, 아니면 새로 띄워 herdr 에 attach 한다.
on surfaceTerminal()
	do shell script "if pgrep -f " & quoted form of ("/" & termApp & ".app/Contents/MacOS/") & " >/dev/null 2>&1; then " & ¬
		"open -a " & quoted form of termApp & "; " & ¬
		"else open -na " & quoted form of termApp & " --args -e " & quoted form of herdrPath & "; fi"
end surfaceTerminal

on openTarget(posixPath)
	set sh to "HERDR=" & quoted form of herdrPath & "; " & ¬
		"TERM_APP=" & quoted form of termApp & "; " & ¬
		"t=" & quoted form of posixPath & "; " & ¬
		"[ -d \"$t\" ] || t=\"$(dirname \"$t\")\"; " & ¬
		"label=\"$(basename \"$t\")\"; " & ¬
		"if \"$HERDR\" workspace create --cwd \"$t\" --label \"$label\" --focus >/dev/null 2>&1; then " & ¬
		"  if pgrep -f \"/$TERM_APP.app/Contents/MacOS/\" >/dev/null 2>&1; then open -a \"$TERM_APP\"; " & ¬
		"  else open -na \"$TERM_APP\" --args -e \"$HERDR\"; fi; " & ¬
		"else open -na \"$TERM_APP\" --args --working-directory=\"$t\" -e \"$HERDR\"; fi"
	do shell script sh
end openTarget

-- 항목을 드롭했을 때: 첫 번째 항목만 사용한다 (워크스페이스 난립 방지).
-- 파일을 드롭하면 openTarget 안에서 상위 폴더로 바뀐다.
on open theItems
	if (count of theItems) is 0 then return
	openTarget(POSIX path of (item 1 of theItems))
end open

-- 현재 Finder 창의 폴더를 POSIX 경로로 돌려준다.
-- 창이 없거나, 최근 항목·AirDrop 처럼 실제 폴더가 아닌 뷰이거나,
-- 자동화 권한이 거부되면 missing value 를 돌려준다.
on frontFinderFolder()
	try
		tell application "Finder"
			if (count of Finder windows) > 0 then
				return POSIX path of ((target of front Finder window) as alias)
			end if
		end tell
	end try
	return missing value
end frontFinderFolder

-- 아이콘을 클릭했을 때: 현재 Finder 창의 폴더로 워크스페이스를 만든다.
-- 폴더를 알아낼 수 없으면 기존 herdr 세션만 앞으로 가져온다.
on run
	set target to frontFinderFolder()
	if target is missing value then
		surfaceTerminal()
	else
		openTarget(target)
	end if
end run
