-- Military-Industrial Complex (MIC) - top-level menu (prototype M0b).
--
-- Adds a "Military-Industrial Complex" tab with its own icon (mic_tlt) to the top-level menu bar, after Help,
-- and a menu listing every procurement contract the player qualifies for, galaxy-wide, sectioned by faction.
--
-- Read-only by design (DESIGN.md: all logic lives in MD). Data source: player.entity.$MIC_UI, a UI-ready table
-- that md/mic_core.xml publishes (plain strings and numbers). MD keys arrive without the leading '$'.
-- Opening the menu or pressing Refresh sends AddUITriggeredEvent("MICMenu", ...); MD republishes and raises
-- the lua event "MIC.UIUpdated", which redraws the open menu.
--
-- Modelled on ui/addons/ego_detailmonitor/menu_help.lua (registration, top-level tab, scroll and close handlers).
-- Unsigned Lua: needs Protected UI Mode OFF.

local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
	typedef uint64_t UniverseID;
	UniverseID GetPlayerID(void);
]]

local menu = {
	name = "MICMenu",
}

local config = {
	layer = 4,
	topLevelId = "mic",
	-- sort modes: "payout" = highest premium first; "type" = grouped by contract type, then payout
	sortModes = {
		{ id = "payout", text = "Sort: payout" },
		{ id = "type",   text = "Sort: type" },
	},
	-- every contract type the design plans (DESIGN.md milestones); types with no contracts yet are simply empty
	typeOrder = { ["Trade supply"] = 1, ["Military"] = 2, ["Ship delivery"] = 3, ["Station delivery"] = 4 },
	filters = { "All", "Trade supply", "Military", "Ship delivery", "Station delivery" },
}

menu.sortMode = "payout"
menu.filter = "All"

local function debugLog(text)
	DebugError("[MIC][UI] " .. tostring(text))
end

-- ---------------------------------------------------------------- top-level bar entry
local function addTopLevelEntry()
	if not (Helper and Helper.topLevelMenus) then
		debugLog("Helper.topLevelMenus missing: top-level tab NOT added")
		return
	end
	for _, entry in ipairs(Helper.topLevelMenus) do
		if entry.id == config.topLevelId then
			return -- already added (UI reload)
		end
	end
	table.insert(Helper.topLevelMenus, {
		id = config.topLevelId,
		name = "Military-Industrial Complex",
		icon = "mic_tlt",
		shortcut = "",
		menu = menu.name,
		helpOverlayID = "toplevel_mic",
		helpOverlayText = "Military-Industrial Complex: government procurement contracts you qualify for.",
		param = { 0, 0 },
	})
	debugLog("top-level tab added (" .. #Helper.topLevelMenus .. " entries)")
end

local function init()
	Menus = Menus or { }
	table.insert(Menus, menu)
	if Helper then
		Helper.registerMenu(menu)
	end
	addTopLevelEntry()
	RegisterEvent("MIC.UIUpdated", menu.onDataUpdated)
	debugLog("menu registered")
end

-- ---------------------------------------------------------------- data
local function isTrue(v)
	return (v == true) or (v == 1)
end

function menu.readData()
	menu.data = { factions = {}, hidden = 0, total = 0, updated = nil }
	local playerid = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
	local ui = GetNPCBlackboard(playerid, "$MIC_UI")
	if type(ui) ~= "table" then
		menu.data.missing = true
		return
	end
	menu.data.updated = ui.updated
	menu.data.testmode = isTrue(ui.testmode)
	menu.data.testminrep = ui.testminrep
	local byFaction = {}
	for _, k in ipairs(ui.contracts or {}) do
		menu.data.total = menu.data.total + 1
		if not isTrue(k.eligible) then
			menu.data.hidden = menu.data.hidden + 1
		elseif (menu.filter == "All") or (k.typename == menu.filter) then
			local f = byFaction[k.faction]
			if not f then
				f = { id = k.faction, name = k.factionname or k.faction, rep = k.rep, contracts = {}, best = 0 }
				byFaction[k.faction] = f
				table.insert(menu.data.factions, f)
			end
			table.insert(f.contracts, k)
			f.best = math.max(f.best, tonumber(k.paycr) or 0)
		end
	end

	local function byPay(a, b)
		local pa, pb = tonumber(a.paycr) or 0, tonumber(b.paycr) or 0
		if pa ~= pb then return pa > pb end
		return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
	end
	local function byType(a, b)
		local ta, tb = config.typeOrder[a.typename] or 99, config.typeOrder[b.typename] or 99
		if ta ~= tb then return ta < tb end
		return byPay(a, b)
	end
	for _, f in ipairs(menu.data.factions) do
		table.sort(f.contracts, (menu.sortMode == "type") and byType or byPay)
	end
	-- factions: best payout first in payout mode, alphabetical in type mode
	table.sort(menu.data.factions, function (a, b)
		if menu.sortMode == "payout" and a.best ~= b.best then
			return a.best > b.best
		end
		return tostring(a.name) < tostring(b.name)
	end)
end

function menu.onDataUpdated()
	if menu.shown then
		menu.refresh = getElapsedTime() + 0.1
	end
end

-- ---------------------------------------------------------------- lifecycle (as menu_help.lua)
function menu.cleanup()
	menu.shown = nil
	menu.frame = nil
	menu.table_toplevel = nil
	menu.table_header = nil
	menu.table_list = nil
	menu.topLevelOffsetY = nil
	menu.refresh = nil
	menu.data = nil
end

function menu.onShowMenu()
	Helper.setTabScrollCallback(menu, menu.onTabScroll)
	menu.shown = true
	AddUITriggeredEvent(menu.name, "open")
	menu.readData()
	menu.display()
end

function menu.display()
	Helper.removeAllWidgetScripts(menu, config.layer)

	menu.frame = Helper.createFrameHandle(menu, {
		width = Helper.viewWidth,
		height = Helper.viewHeight,
		x = 0,
		y = 0,
		layer = config.layer,
		standardButtons = { back = true, close = true },
	})
	menu.frame:setBackground("solid", { color = Color["frame_background_semitransparent"] })

	menu.topLevelOffsetY = Helper.createTopLevelTab(menu, config.topLevelId, menu.frame, "", nil, true) or 0

	local width = math.floor(Helper.viewWidth * 0.7)
	local xoffset = math.floor((Helper.viewWidth - width) / 2)
	local yoffset = menu.topLevelOffsetY + Helper.borderSize + 25

	-- header: title, sort and filter buttons, refresh
	local numFilter = #config.filters
	local header = menu.frame:addTable(numFilter + 3, { tabOrder = 2, width = width, x = xoffset, y = yoffset })
	local row = header:addRow(false, { fixed = true })
	row[1]:setColSpan(numFilter + 3):createText("Military-Industrial Complex - Procurement Contracts", Helper.headerRowCenteredProperties)
	if menu.data and menu.data.testmode then
		row = header:addRow(false, { fixed = true })
		row[1]:setColSpan(numFilter + 3):createText("TEST MODE: reputation requirement lowered to " .. tostring(menu.data.testminrep) .. " (contractor rank still required)", { color = Color["text_warning"], halign = "center" })
	end

	row = header:addRow(true, { fixed = true })
	for i, filter in ipairs(config.filters) do
		local selected = (menu.filter == filter)
		row[i]:createButton({ bgColor = selected and Color["row_background_selected"] or nil }):setText(filter, { halign = "center" })
		row[i].handlers.onClick = function () return menu.buttonFilter(filter) end
	end
	local nextSort = (menu.sortMode == "payout") and config.sortModes[2] or config.sortModes[1]
	local currentSort = (menu.sortMode == "payout") and config.sortModes[1] or config.sortModes[2]
	row[numFilter + 1]:setColSpan(2):createButton({ mouseOverText = "Switch to " .. nextSort.text }):setText(currentSort.text, { halign = "center" })
	row[numFilter + 1].handlers.onClick = function () return menu.buttonSort(nextSort.id) end
	row[numFilter + 3]:createButton({}):setText("Refresh", { halign = "center" })
	row[numFilter + 3].handlers.onClick = menu.buttonRefresh

	yoffset = header.properties.y + header:getFullHeight() + Helper.borderSize

	-- contract list: Type | Contract | Destination | Payout | Expires
	local maxheight = Helper.viewHeight - yoffset - Helper.scaleY(Helper.standardButtonHeight) - 2 * Helper.frameBorder
	local list = menu.frame:addTable(5, { tabOrder = 1, width = width, x = xoffset, y = yoffset, maxVisibleHeight = maxheight })
	list:setColWidthPercent(1, 12)
	list:setColWidthPercent(3, 26)
	list:setColWidthPercent(4, 14)
	list:setColWidthPercent(5, 10)
	list.properties.defaultInteractiveObject = true

	local data = menu.data or {}
	if data.missing then
		row = list:addRow(true, {})
		row[1]:setColSpan(5):createText("No MIC data yet. The procurement backend publishes its first contract list about a minute after a game loads.", { wordwrap = true })
	elseif #data.factions == 0 then
		row = list:addRow(true, {})
		local text = (menu.filter == "All") and "No procurement contracts are open to you right now." or ("No " .. menu.filter .. " contracts are open to you right now.")
		if (data.hidden or 0) > 0 then
			text = text .. "\n" .. data.hidden .. " more need a higher reputation or contractor rank with their faction."
		end
		row[1]:setColSpan(5):createText(text, { wordwrap = true })
	else
		row = list:addRow(false, { fixed = true })
		row[1]:createText("Type", Helper.subHeaderTextProperties)
		row[2]:createText("Contract", Helper.subHeaderTextProperties)
		row[3]:createText("Destination", Helper.subHeaderTextProperties)
		row[4]:createText("Payout", Helper.subHeaderTextProperties)
		row[5]:createText("Expires", Helper.subHeaderTextProperties)

		for _, f in ipairs(data.factions) do
			row = list:addRow(false, { bgColor = Color["row_title_background"] })
			row[1]:setColSpan(5):createText(string.format("%s   (your reputation: %s, %d contract%s)", tostring(f.name), tostring(f.rep), #f.contracts, (#f.contracts == 1) and "" or "s"), Helper.headerRow1Properties)
			for _, k in ipairs(f.contracts) do
				row = list:addRow({ id = k.id }, {})
				local active = (k.state == "active")
				row[1]:createText(tostring(k.typename) .. (active and "\n(accepted)" or ""), { color = active and Color["text_positive"] or nil })
				row[2]:createText(string.format("#%s  %s", tostring(k.id), tostring(k.what)), { wordwrap = true })
				local dest = tostring(k.destination or "")
				if (k.sector or "") ~= "" then
					dest = dest .. "\n" .. tostring(k.sector)
				end
				row[3]:createText(dest, { wordwrap = true })
				row[4]:createText(tostring(k.paytext), { halign = "right" })
				local expires = tonumber(k.expiresin) or 0
				row[5]:createText(active and "-" or ((expires > 0) and ConvertTimeString(expires, (expires < 3600) and ReadText(1001, 209) or ReadText(1001, 207)) or "now"), { halign = "right" })
			end
		end
		if (data.hidden or 0) > 0 then
			row = list:addRow(false, {})
			row[1]:setColSpan(5):createText(data.hidden .. " more contract(s) need a higher reputation or contractor rank with their faction.", { color = Color["text_inactive"], wordwrap = true })
		end
	end

	menu.frame:display()
end

function menu.viewCreated(layer, ...)
	if layer == config.layer then
		menu.table_toplevel, menu.table_header, menu.table_list = ...
	end
end

-- ---------------------------------------------------------------- buttons
function menu.buttonFilter(filter)
	menu.filter = filter
	menu.readData()
	menu.refresh = getElapsedTime() + 0.05
end

function menu.buttonSort(mode)
	menu.sortMode = mode
	menu.readData()
	menu.refresh = getElapsedTime() + 0.05
end

function menu.buttonRefresh()
	AddUITriggeredEvent(menu.name, "refresh")
end

-- ---------------------------------------------------------------- top-level tab scrolling (as menu_help.lua)
function menu.onTabScroll(direction)
	if direction == "right" then
		Helper.scrollTopLevel(menu, config.topLevelId, 1)
	elseif direction == "left" then
		Helper.scrollTopLevel(menu, config.topLevelId, -1)
	end
end

menu.updateInterval = 0.1

function menu.onUpdate()
	if menu.refresh and (menu.refresh < getElapsedTime()) then
		menu.refresh = nil
		menu.readData()
		menu.display()
		return
	end
	if menu.frame then
		menu.frame:update()
	end
end

function menu.onRowChanged(row, rowdata, uitable)
end

function menu.onSelectElement(uitable, modified, row, isdblclick, input)
end

function menu.closeMenu(dueToClose)
	Helper.closeMenu(menu, dueToClose)
	menu.cleanup()
end

function menu.onCloseElement(dueToClose)
	menu.closeMenu(dueToClose)
end

init()
