-- Claude Code が動いている Terminal ウィンドウを、外部モニター1台につき6枚まで縦長1段で（超えたら右のモニターへ。無ければ前面のディスプレイ）等間隔に並べる
-- 外部モニターが2台以上で Codex のウィンドウがあれば、Claude Code は左のモニター・Codex は右のモニターに分けて並べる
-- 使い方: tile             … 文字サイズはディスプレイの大きさから自動で決める
--         tile 14          … 文字サイズを 14pt に指定して並べる
--         tile row         … 縦長1段で横幅を等分する
--         tile grid        … 段数を √枚数 にして並べる（外部モニターが無いときの既定は8枚以下なら縦長1段・9枚以上は上下2段）
--         tile --no-close  … Claude Code / Codex が動いていないウィンドウを閉じずに並べる
-- 補助スクリプトは環境変数 TILE_HOME（既定 ~/.local/share/tile）の libexec/ から呼ぶ

-- 文字サイズの自動決定の基準（MacBook 14インチ標準解像度の使える領域で 12pt）
property baseWidth : 1512
property baseHeight : 908
property baseFont : 12
property floorFontSize : 12
property maxFont : 18
-- 外部モニター1台に縦長1段で並べる上限。超えた分は右のモニターへ
property perMonitor : 6

on run argv
	set libDir to my libexecDir()
	-- 0-a. Claude Code / Codex が動いていない Terminal ウィンドウを全部閉じる
	set noClose to argv contains "--no-close"
	set closeMsg to "既存ウィンドウは閉じずに整列"
	if not noClose then
		set closeMsg to do shell script "/usr/bin/python3 " & quoted form of (libDir & "close-idle-windows.py")
	end if
	-- 0. 対象ディスプレイ = 外部モニター全部（左から順）。つながっていなければ前面のTerminalウィンドウがあるディスプレイ
	tell application "Terminal" to activate
	delay 0.3
	set {screens, isExternal} to my screenList()
	set k to count of screens
	-- 対象は文字サイズ変更の前に確定する（変更でウィンドウが伸びて画面外に出ると取りこぼすため）
	-- 外部モニターがあるときは、どのディスプレイにあるウィンドウも外部モニターへ集める
	set {fx, fy, fw, fh} to items 1 thru 4 of (item 1 of screens)
	set targetIds to my targetWindowIds(fx, fy, fw, fh, isExternal)
	if targetIds is {} then return closeMsg & linefeed & "対象のウィンドウがありません"
	-- 引数: 数字は文字サイズ、row（tall / 縦長）は縦長1段、grid（段組）は段組を強制する
	set fontArg to 0
	set modeArg to ""
	repeat with a in argv
		set a to a as text
		if a is "--no-close" then
			-- ウィンドウを閉じずに整列する
		else if {"row", "tall", "縦長"} contains a then
			set modeArg to "row"
		else if {"grid", "段組"} contains a then
			set modeArg to "grid"
		else
			set fontArg to a as number
		end if
	end repeat
	-- 優先度の高いテーマのウィンドウから左に置き、同じ作業ディレクトリのウィンドウが隣り合うよう並べ替える（左上から右へ、段を下へ詰める）
	-- 順番は terminal-agent-dirs.py が決める（~/.config/tile/priorities.json の owner_rank → タスクDBから作った順位（任意） → ディレクトリ順）
	-- あわせて各タブのタイトル先頭に作業ディレクトリ名を出す（terminal-agent-dirs.py --label）
	set dirOut to do shell script "/usr/bin/python3 " & quoted form of (libDir & "terminal-agent-dirs.py") & " --label"
	set sortedIds to {}
	set prioIds to {}
	set pinId to 0
	set pinAway to false
	repeat with ln in paragraphs of dirOut
		if (ln as text) is not "" then
			set AppleScript's text item delimiters to tab
			set wid to (text item 1 of (ln as text)) as integer
			set isPin to (text item 3 of (ln as text)) is "1"
			set isPrio to (text item 4 of (ln as text)) is "1"
			set AppleScript's text item delimiters to ""
			-- セッションのタイトルが pin_title_keys に当たるウィンドウは左端の縦長に回す
			if targetIds contains wid then
				if isPin and pinId = 0 then
					set pinId to wid
				else if isPrio then
					-- 優先テーマのウィンドウは、出力順（優先度の高い順）のまま他のウィンドウより左に置く
					set end of prioIds to wid
				else
					set end of sortedIds to wid
				end if
			else if isPin then
				-- 別デスクトップ・最小化の窓は動かせないので、縦長に置けなかったことを結果に出す
				set pinAway to true
			end if
		end if
	end repeat
	repeat with wid in targetIds
		if sortedIds does not contain (contents of wid) and prioIds does not contain (contents of wid) and (contents of wid) ≠ pinId then set end of sortedIds to (contents of wid)
	end repeat
	set targetIds to prioIds & sortedIds
	set n to count of targetIds
	-- 外部モニターが無いときは、Claude Code / Codex のウィンドウ（固定する窓を含む）が8枚以下なら縦長1段、9枚以上は上下2段
	-- 引数 row なら枚数に関係なく縦長1段、grid なら段組にする
	set builtinCount to n
	if pinId ≠ 0 then set builtinCount to n + 1
	set builtinRow to (not isExternal) and (modeArg is "row" or (modeArg is not "grid" and builtinCount ≤ 8))
	-- 固定するウィンドウがあれば、それを左のモニターの一番左に縦長で置く
	set monId to 0
	if pinId ≠ 0 then set monId to pinId
	set slots to n
	if monId ≠ 0 then set slots to n + 1
	-- 外部モニターは1台につき perMonitor 枚まで縦長1段で並べ、超えた分は右のモニターへ縦長1段で並べる（例: 6枚 → 左6 / 9枚 → 左6・右3）
	-- 全モニターの枠（台数 × perMonitor）を超えるときだけ、従来どおり均等に分けて段組にする
	set fillRow to false
	if isExternal and modeArg is not "grid" and slots ≤ perMonitor * k then
		set fillRow to true
		set k to (slots + perMonitor - 1) div perMonitor
		if k < 1 then set k to 1
	end if
	set singleRow to fillRow
	if modeArg is "row" or builtinRow then set singleRow to true
	if modeArg is "grid" then set singleRow to false
	if k > slots then set k to slots

	-- 外部モニターが2台以上なら、Claude Code のウィンドウ（固定する窓を含む）を左のモニター、Codex のウィンドウを右のモニターに分ける
	-- 各モニターは perMonitor 枚まで縦長1段、超えたら段組。Codex のウィンドウが無ければ従来どおり左から詰める
	set splitMode to false
	set claudeIds to {}
	set codexIds to {}
	if isExternal and (count of screens) ≥ 2 and modeArg is not "grid" then
		repeat with wid in targetIds
			tell application "Terminal" to set procs to processes of selected tab of window id (contents of wid)
			if procs contains "claude" then
				set end of claudeIds to (contents of wid)
			else
				set end of codexIds to (contents of wid)
			end if
		end repeat
		if codexIds is not {} then set splitMode to true
	end if

	-- 外部モニターが複数なら、1枚のディスプレイに詰め込まないよう枚数を均等に分ける（例: 16枚・2枚 → 8,8 / 15枚 → 8,7）
	-- 各ディスプレイの {使える領域x, 上端y, 幅, 高さ, そのディスプレイに置くウィンドウid一覧, 固定する窓を置くか, 縦長1段か}
	set plans to {}
	if splitMode then
		set claudeCells to count of claudeIds
		if monId ≠ 0 then set claudeCells to claudeCells + 1
		if claudeCells > 0 then set end of plans to my makePlan(item 1 of screens, claudeIds, monId, modeArg is "row" or claudeCells ≤ perMonitor)
		set end of plans to my makePlan(item -1 of screens, codexIds, 0, modeArg is "row" or (count of codexIds) ≤ perMonitor)
	else
		set i to 0
		repeat with si from 1 to k
			set cnt to slots div k
			if si ≤ (slots mod k) then set cnt to cnt + 1
			if fillRow then
				set cnt to slots - (si - 1) * perMonitor
				if cnt > perMonitor then set cnt to perMonitor
			end if
			-- 固定する窓は1枚目（一番左）のディスプレイの枠を1つ使う
			set planMon to 0
			if si = 1 then set planMon to monId
			if planMon ≠ 0 then set cnt to cnt - 1
			if cnt > 0 then
				set ids to items (i + 1) thru (i + cnt) of targetIds
			else
				set ids to {}
			end if
			set i to i + cnt
			set end of plans to my makePlan(item si of screens, ids, planMon, singleRow)
		end repeat
	end if

	-- 1. 文字サイズを決めてプロファイルに設定（大きいディスプレイほど大きく。基準比の小さい方で拡大し、12〜18ptに収める）
	-- 文字サイズはプロファイル共通なので、ディスプレイが複数なら一番小さいディスプレイに合わせる
	if fontArg ≠ 0 then
		set fontSize to fontArg
	else
		set ratio to 999
		repeat with pl in plans
			if (item 3 of pl) / baseWidth < ratio then set ratio to (item 3 of pl) / baseWidth
			if (item 4 of pl) / baseHeight < ratio then set ratio to (item 4 of pl) / baseHeight
		end repeat
		set fontSize to round (baseFont * ratio)
		if fontSize < floorFontSize then set fontSize to floorFontSize
		if fontSize > maxFont then set fontSize to maxFont
	end if
	tell application "Terminal" to set font size of default settings to fontSize
	-- タブが前の文字サイズを持ったままだと ⌘0 でもその大きさに戻るだけなので、対象の各タブにも直接設定する
	set fontIds to targetIds
	if monId ≠ 0 then set fontIds to fontIds & {monId}
	repeat with wid in fontIds
		tell application "Terminal"
			repeat with t in tabs of window id (contents of wid)
				if font size of t ≠ fontSize then set font size of t to fontSize
			end repeat
		end tell
	end repeat

	-- 2. ⌘+ / ⌘- で個別に拡大縮小されたウィンドウを、プロファイルの文字サイズ（⌘0 相当）に戻す
	-- 前面化の反映が遅れて取りこぼすことがあるため、ずれたままのウィンドウだけ最大3周やり直す
	set zoomIds to targetIds
	if monId ≠ 0 then set zoomIds to zoomIds & {monId}
	repeat 3 times
		set pending to {}
		repeat with wid in zoomIds
			if my isZoomed(contents of wid, fontSize) then set end of pending to (contents of wid)
		end repeat
		if pending is {} then exit repeat
		repeat with wid in pending
			tell application "Terminal" to set tabCount to count of tabs of window id wid
			repeat with ti from 1 to tabCount
				tell application "Terminal"
					activate
					set index of window id wid to 1
					set selected of tab ti of window id wid to true
				end tell
				-- 前面化が反映される前にクリックすると別ウィンドウに効いてしまうので、前面になるまで待つ（最大2秒）
				repeat 10 times
					delay 0.2
					tell application "Terminal" to if id of front window = wid then exit repeat
				end repeat
				delay 0.3
				my resetZoom()
			end repeat
			delay 0.3
		end repeat
	end repeat

	-- 3. ディスプレイごとに、使える領域（メニューバーとDockを除く）に並べる。位置指定は window id で行う（index参照だと前面化のたびに順番がずれて重なる）
	set summary to {}
	set placed to {}
	repeat with pl in plans
		set {leftX, topY, sw, vh, ids, withMon, oneRow} to contents of pl
		set m to count of ids
		-- 縦が短いと読みにくいので、段数は √(枠数) の切り捨て（12枚→3段、19枚→4段）にして高さを確保する
		set cells to m
		if withMon then set cells to m + 1
		set rows to 1
		if not oneRow then
			repeat while (rows + 1) * (rows + 1) ≤ cells
				set rows to rows + 1
			end repeat
		end if
		-- 外部モニターが無いときは上下2段までにして、各段の横幅を等分する（引数 grid のときは √ の段数のまま）
		if (not isExternal) and modeArg is not "grid" and rows > 2 then set rows to 2
		if rows > m and m > 0 then set rows to m
		set h to vh / rows
		-- 固定する窓は左端に縦いっぱいの1列（幅は他のウィンドウ1列分）。残りの幅に他のウィンドウを並べる
		if withMon then
			if m = 0 then
				set monW to sw
			else
				set maxInRow to (m + rows - 1) div rows
				set monW to sw / (maxInRow + 1)
			end if
			set mb to {round leftX, round topY, round (leftX + monW), round (topY + vh)}
			my placeWindow(monId, mb)
			set end of placed to {monId, mb}
			set leftX to leftX + monW
			set sw to sw - monW
		end if
		-- 各段に枚数を均等に割り振り（例: 14枚なら 5,5,4）、段ごとに横幅いっぱいまで等分する
		set i to 0
		repeat with r from 0 to rows - 1
			set inRow to m div rows
			if r < (m mod rows) then set inRow to inRow + 1
			set w to sw / inRow
			repeat with c from 0 to inRow - 1
				set i to i + 1
				set b to {round (leftX + c * w), round (topY + r * h), round (leftX + (c + 1) * w), round (topY + (r + 1) * h)}
				my placeWindow(item i of ids, b)
				set end of placed to {item i of ids, b}
			end repeat
		end repeat
		if withMon then
			set end of summary to "固定+" & (m as text) & "枚/" & rows & "段"
		else
			set end of summary to (m as text) & "枚/" & rows & "段"
		end if
	end repeat
	-- 後から置いたウィンドウに押されてずれることがあるので、全部置いた後にずれたものだけ置き直す（最大2周）
	repeat 2 times
		set moved to false
		repeat with pw in placed
			set {wid, b} to contents of pw
			tell application "Terminal" to set got to bounds of window id wid
			if got ≠ b then
				my placeWindow(wid, b)
				set moved to true
			end if
		end repeat
		if not moved then exit repeat
	end repeat
	set AppleScript's text item delimiters to " + "
	set summaryText to summary as text
	set AppleScript's text item delimiters to ""
	set awayMsg to ""
	if pinAway and pinId = 0 then set awayMsg to linefeed & "固定する窓は別デスクトップか最小化中のため縦長に置けません（今のデスクトップへ移してから再実行）"
	return closeMsg & linefeed & (count of plans) & "画面: " & summaryText & " / " & fontSize & "pt" & awayMsg
end run

-- ディスプレイ scr にウィンドウ ids（と、monId ≠ 0 なら左端に固定する窓）を置く計画を返す
-- 外部モニターのメニューバーは visibleFrame に含まれないことがあるので、1枚を上端へ置いて実際に置ける上端を測る
on makePlan(scr, ids, monId, oneRow)
	set {sfx, sfy, sfw, sfh, leftX, topY, sw, vh} to scr
	set withMon to (monId ≠ 0)
	if withMon then
		set probeId to monId
	else
		set probeId to item 1 of ids
	end if
	my placeWindow(probeId, {leftX, topY, leftX + 400, topY + 300})
	tell application "Terminal" to set actualTop to item 2 of (get bounds of window id probeId)
	if actualTop > topY then
		set vh to vh - (actualTop - topY)
		set topY to actualTop
	end if
	return {leftX, topY, sw, vh, ids, withMon, oneRow}
end makePlan

-- 並べる先のディスプレイ一覧と、外部モニターかどうかを {{{全体x, 全体y, 全体幅, 全体高さ, 使える領域x, 使える領域y, 使える幅, 使える高さ}, ...}, 外部なら true} で返す
-- 外部モニター（内蔵でないディスプレイ）が1枚以上あれば全部を左から順に、無ければ前面ウィンドウのあるディスプレイだけ
-- 座標は Terminal の bounds と同じ系（メインディスプレイ左上が原点・下向き正）
on screenList()
	set js to "ObjC.import(\"AppKit\"); ObjC.import(\"CoreGraphics\"); var a=$.NSScreen.screens, H=a.objectAtIndex(0).frame.size.height, r=function(s){var f=s.frame, v=s.visibleFrame; return [f.origin.x, H-f.origin.y-f.size.height, f.size.width, f.size.height, v.origin.x, H-v.origin.y-v.size.height, v.size.width, v.size.height]}, ext=[]; for (var i=0;i<a.count;i++){var x=a.objectAtIndex(i); if (!$.CGDisplayIsBuiltin(ObjC.unwrap(x.deviceDescription.objectForKey(\"NSScreenNumber\")))) ext.push(r(x))} ext.sort(function(p,q){return p[0]-q[0]||p[1]-q[1]}); (ext.length ? \"1\\n\"+ext.map(function(e){return e.join(\",\")}).join(\"\\n\") : \"0\\n\"+r($.NSScreen.mainScreen).join(\",\"))"
	set out to do shell script "osascript -l JavaScript -e " & quoted form of js
	set ls to paragraphs of out
	set isExternal to (item 1 of ls) = "1"
	set screens to {}
	set AppleScript's text item delimiters to ","
	repeat with li from 2 to count of ls
		set nums to {}
		repeat with p in text items of (item li of ls)
			set end of nums to (p as number)
		end repeat
		set end of screens to nums
	end repeat
	set AppleScript's text item delimiters to ""
	return {screens, isExternal}
end screenList

-- 今見えているデスクトップ（Space）にあり、対象ディスプレイ上にあり（allScreens なら全ディスプレイ）、Claude Code が動いているウィンドウのidを返す
-- （別デスクトップのウィンドウは位置を変えられず、数に入れると画面に空きができるため）
on targetWindowIds(fx, fy, fw, fh, allScreens)
	-- 今見えているデスクトップのウィンドウは System Events に出る。タイトルは Claude Code が動かし続けるので名前でなく位置と大きさで照合する
	set shownRects to {}
	tell application "System Events" to tell process "Terminal"
		repeat with aw in windows
			set {px, py} to position of aw
			set {qw, qh} to size of aw
			set end of shownRects to {px, py, px + qw, py + qh}
		end repeat
	end tell
	-- 1つのウィンドウにタブでまとめられたものは Terminal では別ウィンドウに見えるが枠は共通で、System Events には1枚だけ出る
	-- 同じ枠を2枚目以降が使うと重なって並ぶので、System Events の1枚につき1つだけ対象にする
	set claimed to {}
	repeat with r in shownRects
		set end of claimed to false
	end repeat
	set ids to {}
	tell application "Terminal"
		repeat with w in (every window whose visible is true and miniaturized is false)
			set b to bounds of w
			set cx to ((item 1 of b) + (item 3 of b)) / 2
			set cy to ((item 2 of b) + (item 4 of b)) / 2
			set onScreen to allScreens or (cx ≥ fx and cx < fx + fw and cy ≥ fy and cy < fy + fh)
			set procs to processes of selected tab of w
			if onScreen and (procs contains "claude" or procs contains "codex") then
				repeat with si from 1 to count of shownRects
					if not (item si of claimed) and my rectShown(b, {item si of shownRects}) then
						set item si of claimed to true
						set end of ids to (id of w)
						exit repeat
					end if
				end repeat
			end if
		end repeat
	end tell
	return ids
end targetWindowIds

-- 1文字あたりの横幅が、今の文字サイズの標準幅（約0.6倍）から大きく外れるタブがあれば「個別に拡大縮小中」とみなす
on isZoomed(wid, fontSize)
	tell application "Terminal"
		set b to bounds of window id wid
		repeat with t in tabs of window id wid
			set pxPerCol to ((item 3 of b) - (item 1 of b)) / (number of columns of t)
			if pxPerCol > fontSize * 0.75 or pxPerCol < fontSize * 0.5 then return true
		end repeat
	end tell
	return false
end isZoomed

-- ウィンドウを bounds b に置く。外部モニターでは Terminal の bounds 指定が上端へ押し戻されることがあるので、
-- ずれたときはアクセシビリティ経由（今の位置と大きさが一致するウィンドウを探す）で位置と大きさを直す
on placeWindow(wid, b)
	-- タイトルは同じ名前のウィンドウがあったり Claude Code が随時書き換えたりして別のウィンドウを動かしてしまうので、名前でなく位置と大きさで照合する。最大5回やり直す
	repeat 5 times
		tell application "Terminal"
			set bounds of window id wid to b
			set cur to bounds of window id wid
		end tell
		if cur = b then return
		try
			tell application "System Events" to tell process "Terminal"
				repeat with w in windows
					set {px, py} to position of w
					set {qw, qh} to size of w
					if my rectShown(cur, {{px, py, px + qw, py + qh}}) then
						set position of w to {item 1 of b, item 2 of b}
						set size of w to {(item 3 of b) - (item 1 of b), (item 4 of b) - (item 2 of b)}
						exit repeat
					end if
				end repeat
			end tell
		end try
		tell application "Terminal" to if (bounds of window id wid) = b then return
		delay 0.2
	end repeat
end placeWindow

-- 補助スクリプトの置き場（TILE_HOME/libexec/）。TILE_HOME が無ければ ~/.local/share/tile
on libexecDir()
	set h to system attribute "TILE_HOME"
	if h is "" then set h to POSIX path of (path to home folder) & ".local/share/tile"
	if h does not end with "/" then set h to h & "/"
	return h & "libexec/"
end libexecDir

-- 前面のウィンドウの ⌘+ / ⌘- を戻す（表示 → デフォルトのフォントサイズ）。メニュー名は日本語 → 英語の順に試し、どちらも無ければ ⌘0 を送る
on resetZoom()
	tell application "System Events" to tell process "Terminal"
		perform action "AXRaise" of window 1
		try
			click menu item "デフォルトのフォントサイズ" of menu 1 of menu bar item "表示" of menu bar 1
		on error
			try
				click menu item "Default Font Size" of menu 1 of menu bar item "View" of menu bar 1
			on error
				keystroke "0" using command down
			end try
		end try
	end tell
end resetZoom

-- bounds b が、今見えているデスクトップのウィンドウの位置・大きさのどれかと ±2px で一致するか（丸め誤差で1pxずれることがある）
on rectShown(b, shownRects)
	repeat with r in shownRects
		set ok to true
		repeat with j from 1 to 4
			set d to (item j of b) - (item j of r)
			if d > 2 or d < -2 then
				set ok to false
				exit repeat
			end if
		end repeat
		if ok then return true
	end repeat
	return false
end rectShown
