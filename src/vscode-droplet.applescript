-- VS Code 드롭릿
-- Finder 툴바에 두고, 클릭하면 현재 Finder 창의 폴더를 VS Code 새 창으로 연다.
-- 폴더나 파일을 떨어뜨리면 그 경로(파일이면 상위 폴더)를 새 창으로 연다.
--
-- __VSCODE_APP__ 은 install.sh 가 설치 시점에 치환한다.
--
-- 이 저장소의 다른 스크립트와 달리 Finder 에 Apple Events 를 보낸다.
-- "현재 창의 폴더"는 Apple Events 없이는 알아낼 수 없기 때문이다.
-- 첫 클릭 때 "Finder 제어" 권한 팝업이 한 번 뜬다.

property vscodeApp : "__VSCODE_APP__"

-- 현재 Finder 창의 폴더를 POSIX 경로로 돌려준다.
-- 창이 없거나, 최근 항목·AirDrop 처럼 실제 폴더가 아닌 뷰이거나,
-- 자동화 권한이 거부되면 데스크탑으로 폴백한다.
on frontFinderFolder()
	try
		tell application "Finder"
			if (count of Finder windows) > 0 then
				return POSIX path of ((target of front Finder window) as alias)
			end if
		end tell
	end try
	return POSIX path of (path to desktop)
end frontFinderFolder

-- 경로 하나를 VS Code 새 창으로 연다. 파일이면 상위 폴더를 쓴다.
-- 내장 CLI 의 -n 이 새 창을 보장한다. CLI 가 없으면 open -na 로 폴백.
on openInVSCode(posixPath)
	set sh to "APP=" & quoted form of vscodeApp & "; " & ¬
		"t=" & quoted form of posixPath & "; " & ¬
		"[ -d \"$t\" ] || t=\"$(dirname \"$t\")\"; " & ¬
		"cli=\"$APP/Contents/Resources/app/bin/code\"; " & ¬
		"if [ -x \"$cli\" ]; then \"$cli\" -n \"$t\"; " & ¬
		"else open -na \"$APP\" --args -n \"$t\"; fi"
	do shell script sh
end openInVSCode

-- 항목을 드롭했을 때: 항목마다 새 창으로 연다.
on open theItems
	repeat with anItem in theItems
		openInVSCode(POSIX path of anItem)
	end repeat
end open

-- 아이콘을 클릭했을 때: 현재 Finder 창의 폴더를 연다.
on run
	openInVSCode(frontFinderFolder())
end run
