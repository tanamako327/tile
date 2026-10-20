-- Arrange Terminal windows running Claude Code / Codex evenly: up to 6 per external monitor in one full-height row
-- (overflow goes to the next monitor on the right; without external monitors, the display of the front window is used).
-- With 2+ external monitors and at least one Codex window, Claude Code goes to the leftmost monitor and Codex to the rightmost.
-- Usage: tile             … font size is chosen from the display size
--        tile 14          … use 14pt
--        tile row         … one full-height row with equal widths
--        tile grid        … floor(√n) rows (default without external monitors: one row up to 8 windows, two rows from 9)
--        tile --no-close  … do not close windows that are not running Claude Code / Codex
-- Helper scripts are loaded from $TILE_HOME/libexec/ (default ~/.local/share/tile).

-- Reference for the automatic font size (12pt on the usable area of a 14" MacBook at default resolution)
property baseWidth : 1512
property baseHeight : 908
property baseFont : 12
property floorFontSize : 12
property maxFont : 18
-- Max windows per external monitor in a single row; the rest go to the next monitor on the right
property perMonitor : 6

on run argv
	set libDir to my libexecDir()
	-- 0a. Close every Terminal window that is not running Claude Code / Codex
	set noClose to argv contains "--no-close"
	set closeMsg to "Kept all windows open (--no-close)"
	if not noClose then
		set closeMsg to do shell script "/usr/bin/python3 " & quoted form of (libDir & "close-idle-windows.py")
	end if
	-- 0. Target displays = all external monitors (left to right), or the display of the front Terminal window if none
	tell application "Terminal" to activate
	delay 0.3
	set {screens, isExternal} to my screenList()
	set k to count of screens
	-- Collect targets before changing the font size (resized windows can grow off screen and be missed)
	-- With external monitors, windows on any display are gathered onto them
	set {fx, fy, fw, fh} to items 1 thru 4 of (item 1 of screens)
	set targetIds to my targetWindowIds(fx, fy, fw, fh, isExternal)
	if targetIds is {} then return closeMsg & linefeed & "No Claude Code / Codex windows on the current desktop"
	-- Arguments: a number sets the font size, row (or tall) forces one row, grid forces a grid
	set fontArg to 0
	set modeArg to ""
	repeat with a in argv
		set a to a as text
		if a is "--no-close" then
			-- handled above
		else if {"row", "tall"} contains a then
			set modeArg to "row"
		else if a is "grid" then
			set modeArg to "grid"
		else
			set fontArg to a as number
		end if
	end repeat
	-- Place higher-priority themes first and keep windows with the same working directory adjacent (left to right, then next row)
	-- The order comes from terminal-agent-dirs.py (owner_rank in priorities.json → optional rank_command ranking → directory)
	-- It also writes the working directory name into each tab title (--label)
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
			-- A window whose session title matches pin_title_keys becomes the full-height column on the far left
			if targetIds contains wid then
				if isPin and pinId = 0 then
					set pinId to wid
				else if isPrio then
					-- Theme windows keep the output order (highest priority first) and go left of the others
					set end of prioIds to wid
				else
					set end of sortedIds to wid
				end if
			else if isPin then
				-- Windows on another desktop or minimized cannot be moved; report that the pinned window was skipped
				set pinAway to true
			end if
		end if
	end repeat
	repeat with wid in targetIds
		if sortedIds does not contain (contents of wid) and prioIds does not contain (contents of wid) and (contents of wid) ≠ pinId then set end of sortedIds to (contents of wid)
	end repeat
	set targetIds to prioIds & sortedIds
	set n to count of targetIds
	-- Without external monitors: one row for up to 8 windows (including the pinned one), two rows from 9
	-- row always uses one row; grid always uses a grid
	set builtinCount to n
	if pinId ≠ 0 then set builtinCount to n + 1
	set builtinRow to (not isExternal) and (modeArg is "row" or (modeArg is not "grid" and builtinCount ≤ 8))
	-- The pinned window, if any, becomes a full-height column at the far left of the leftmost monitor
	set monId to 0
	if pinId ≠ 0 then set monId to pinId
	set slots to n
	if monId ≠ 0 then set slots to n + 1
	-- Each external monitor takes up to perMonitor windows in one row; the rest go right (e.g. 6 → 6 / 9 → 6 + 3)
	-- Only when windows exceed monitors × perMonitor are they split evenly into grids
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

	-- With 2+ external monitors, Claude Code windows (including the pinned one) go to the leftmost monitor and Codex windows to the rightmost
	-- Each uses one row up to perMonitor, then a grid. Without Codex windows, monitors are filled from the left as above
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

	-- In grid mode, windows are split evenly across monitors (e.g. 16 on 2 → 8, 8 / 15 → 8, 7)
	-- Plan per display: {usable x, top y, width, height, window ids, has pinned window, single row}
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
			-- The pinned window takes one slot on the first (leftmost) display
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

	-- 1. Choose the font size and set it on the profile (scaled by the smaller of the width/height ratios, clamped to floorFontSize..maxFont)
	-- The profile is shared, so with several displays the smallest one decides
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
	-- Tabs keep their previous size even after ⌘0, so set the size on each target tab as well
	set fontIds to targetIds
	if monId ≠ 0 then set fontIds to fontIds & {monId}
	repeat with wid in fontIds
		tell application "Terminal"
			repeat with t in tabs of window id (contents of wid)
				if font size of t ≠ fontSize then set font size of t to fontSize
			end repeat
		end tell
	end repeat

	-- 2. Reset windows zoomed with ⌘+ / ⌘- back to the profile font size (same as ⌘0)
	-- Bringing a window to the front can lag, so retry only the windows still zoomed, up to 3 passes
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
				-- Wait until the window is actually in front (max 2s), otherwise the menu click hits another window
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

	-- 3. Lay out each display's usable area (excluding menu bar and Dock). Address windows by id (indexes change as windows come to the front)
	set summary to {}
	set placed to {}
	repeat with pl in plans
		set {leftX, topY, sw, vh, ids, withMon, oneRow} to contents of pl
		set m to count of ids
		-- Short windows are hard to read, so use floor(√cells) rows (12 → 3 rows, 19 → 4 rows) to keep them tall
		set cells to m
		if withMon then set cells to m + 1
		set rows to 1
		if not oneRow then
			repeat while (rows + 1) * (rows + 1) ≤ cells
				set rows to rows + 1
			end repeat
		end if
		-- Without external monitors, use at most 2 rows with equal widths per row (grid keeps the √ rows)
		if (not isExternal) and modeArg is not "grid" and rows > 2 then set rows to 2
		if rows > m and m > 0 then set rows to m
		set h to vh / rows
		-- The pinned window is a full-height column on the left, one column wide; the others share the remaining width
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
		-- Spread windows evenly over rows (e.g. 14 → 5, 5, 4) and split each row's full width equally
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
			set end of summary to "pinned + " & (m as text) & " in " & rows & " row(s)"
		else
			set end of summary to (m as text) & " in " & rows & " row(s)"
		end if
	end repeat
	-- Later placements can push earlier windows; re-place only those that moved (up to 2 passes)
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
	if pinAway and pinId = 0 then set awayMsg to linefeed & "The pinned window is on another desktop or minimized, so it was not placed (move it to this desktop and run again)"
	return closeMsg & linefeed & (count of plans) & " display(s): " & summaryText & " / " & fontSize & "pt" & awayMsg
end run

-- Return the plan for placing ids (and the pinned window on the left when monId ≠ 0) on display scr
-- An external monitor's menu bar is not always excluded from visibleFrame, so probe the real top edge with one window
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

-- Return {{{frame x, y, width, height, usable x, y, width, height}, ...}, true if external}
-- All external (non-built-in) displays left to right if any, otherwise only the display of the front window
-- Coordinates match Terminal bounds (origin at the main display's top-left, y grows downward)
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

-- Return ids of windows on the current desktop (Space), on the target display (any display if allScreens), running Claude Code / Codex
-- (windows on other desktops cannot be moved and would leave gaps if counted)
on targetWindowIds(fx, fy, fw, fh, allScreens)
	-- System Events lists only windows on the current desktop. Claude Code keeps changing titles, so match by position and size
	set shownRects to {}
	tell application "System Events" to tell process "Terminal"
		repeat with aw in windows
			set {px, py} to position of aw
			set {qw, qh} to size of aw
			set end of shownRects to {px, py, px + qw, py + qh}
		end repeat
	end tell
	-- Tabs merged into one window look like separate windows to Terminal but share one frame, which System Events lists once
	-- Count each System Events window once so tabs do not get stacked on top of each other
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

-- Treat a window as zoomed if any tab's pixels per column are far from the usual ~0.6 × font size
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

-- Move window wid to bounds b. On external monitors Terminal may push the window back to the top edge,
-- so fall back to Accessibility (find the window by its current position and size) when it lands elsewhere
on placeWindow(wid, b)
	-- Titles can be duplicated or rewritten by Claude Code at any time, so match by position and size. Retry up to 5 times
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

-- Location of the helper scripts ($TILE_HOME/libexec/, default ~/.local/share/tile)
on libexecDir()
	set h to system attribute "TILE_HOME"
	if h is "" then set h to POSIX path of (path to home folder) & ".local/share/tile"
	if h does not end with "/" then set h to h & "/"
	return h & "libexec/"
end libexecDir

-- Undo ⌘+ / ⌘- on the front window (View → Default Font Size). Tries the Japanese, then English menu names, then sends ⌘0
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

-- Whether bounds b matches any of shownRects within ±2px (rounding can shift windows by 1px)
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
