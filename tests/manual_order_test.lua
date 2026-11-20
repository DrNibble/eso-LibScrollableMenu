-- Run with Lua 5.1 from the repository root. ESO controls and events are simulated.
local assertions, shift, mouseOver, mouseY = 0, false, nil, 0
local mouseUp, onUpdate, deferred

local function equals(actual, expected, message)
	assert(actual == expected, (message or "unexpected value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
	assertions = assertions + 1
end

LibScrollableMenu = {
	LSM_ENTRY_TYPE_NORMAL = 1,
	Util = { getControlData = function(control) return control.m_data:GetDataSource() end },
}
MOUSE_BUTTON_INDEX_LEFT, EVENT_GLOBAL_MOUSE_UP = 1, 2
ZO_COMBO_BOX_ENTRY_TEMPLATE_HEIGHT, ZO_COMBO_BOX_ENTRY_TEMPLATE_LABEL_PADDING = 25, -5
TOPLEFT, TOPRIGHT, RIGHT = 1, 2, 3

EVENT_MANAGER = {
	RegisterForEvent = function(_, _, event, callback)
		equals(event, EVENT_GLOBAL_MOUSE_UP)
		mouseUp = callback
	end,
	UnregisterForEvent = function() mouseUp = nil end,
	RegisterForUpdate = function(_, _, _, callback) onUpdate = callback end,
	UnregisterForUpdate = function() onUpdate = nil end,
}
WINDOW_MANAGER = { GetMouseOverControl = function() return mouseOver end }
function IsShiftKeyDown() return shift end
function MouseIsOver(list) return list.mouseInside end
function GetUIMousePosition() return 0, mouseY end
function ZO_Tooltips_HideTextTooltip() end
function zo_callLater(callback) deferred = callback end
function ZO_ScrollList_GetDataList(list) return list.rows end
function ZO_ScrollList_ScrollDataIntoView(list, index) list.revealed = index end
function ZO_ScrollList_ScrollRelative(list, delta) list.delta = delta end
function ZO_ShallowTableCopy(items)
	local copy = {}
	for key, value in pairs(items) do copy[key] = value end
	return copy
end

local function makeControl(parent)
	return {
		GetParent = function() return parent end,
		SetHidden = function(self, hidden) self.hidden = hidden end,
		SetEnabled = function(self, enabled) self.enabled = enabled end,
		SetMouseEnabled = function(self, enabled) self.mouseEnabled = enabled end,
		SetAlpha = function(self, alpha) self.alpha = alpha end,
	}
end

function CreateControlFromVirtual(_, parent, template)
	equals(template, "LibScrollableMenu_ManualOrderControls")
	local controls = makeControl(parent)
	local children = { Up = makeControl(controls), Down = makeControl(controls), Grip = makeControl(controls) }
	controls.GetNamedChild = function(_, name) return children[name] end
	return controls
end

dofile("LibScrollableMenu/code/LSM_ManualOrder.lua")
local manualOrder = LibScrollableMenu.ManualOrder

local function item(name, entryType, enabled, template)
	return {
		name = name, entryType = entryType or 1, enabled = enabled ~= false,
		customEntryTemplate = template or "LibScrollableMenu_ComboBoxEntry",
	}
end

local function wrap(data)
	return { GetDataSource = function() return data end }
end

local function makeMenu(items, isContextMenu)
	local menu = {
		m_sortedItems = ZO_ShallowTableCopy(items), visible = true, options = { enableManualOrder = true },
		shows = 0, isContextMenu = isContextMenu,
	}
	local dropdown = {
		owner = menu,
		control = makeControl(),
		scrollControl = {
			mouseInside = true,
			GetHeight = function() return 100 end,
			GetTop = function() return 50 end,
			GetBottom = function() return 150 end,
		},
	}
	function menu:GetOptions() return self.options end
	function menu:IsDropdownVisible() return self.visible end
	function menu:GetEntries() return items end
	function menu:Show()
		self.shows = self.shows + 1
		dropdown.scrollControl.rows = {}
		for i, row in ipairs(self.m_sortedItems) do dropdown.scrollControl.rows[i] = wrap(row) end
	end
	return menu, dropdown
end

local function rowFor(dropdown, entry)
	local row = makeControl(dropdown.control)
	row.m_dropdownObject, row.m_data, row.m_iconContainer = dropdown, wrap(entry), {}
	row.m_label = {
		ClearAnchors = function() end,
		SetAnchor = function(self, point, _, _, x) if point == RIGHT then self.right = x end end,
	}
	return row
end

local function childFor(dropdown, entry, name)
	local row = rowFor(dropdown, entry)
	manualOrder.SetupRow(dropdown.owner, row)
	return row.LSMManualOrderControls:GetNamedChild(name or "Grip"), row
end

local function runDeferred()
	local callback = deferred
	deferred = nil
	callback()
end

local a, b, c = item("same"), item("same"), item("c")
local header, d, disabled, custom = item("header", 3), item("d"), item("disabled", 1, false), item("custom", 1, true, "custom")
local menu, dropdown = makeMenu({ a, b, c, header, d, disabled, custom })
local callbacks, lastMove = 0
menu.options.onOrderChanged = function(owner, order, movedItem, from, to)
	equals(owner, menu)
	callbacks = callbacks + 1
	lastMove = { movedItem, from, to, order[to] }
	order[1] = nil -- The callback's array cannot modify the menu array.
end

-- Arrows, boundaries and identity, even when labels match.
local up, row = childFor(dropdown, a, "Up")
equals(up.enabled, false)
equals(row.m_label.right, -73)
equals(manualOrder.MoveWithButton(up, -1), nil)
equals(callbacks, 0)
equals(manualOrder.MoveWithButton(row.LSMManualOrderControls:GetNamedChild("Down"), 1), true)
equals(menu.m_sortedItems[1], b)
equals(menu.m_sortedItems[2], a)
equals(dropdown.scrollControl.revealed, 2)
equals(lastMove[1], a)
equals(lastMove[2], 1)
equals(lastMove[3], 2)
equals(lastMove[4], a)
equals(callbacks, 1)

shift = true
equals(manualOrder.MoveWithButton(childFor(dropdown, c, "Up"), -1), true)
equals(menu.m_sortedItems[1], c)
equals(manualOrder.MoveWithButton(childFor(dropdown, c, "Down"), 1), true)
equals(menu.m_sortedItems[3], c)
equals(menu.m_sortedItems[4], header)
equals(menu.m_sortedItems[6], disabled)
equals(manualOrder.MoveWithButton(childFor(dropdown, d, "Down"), 1), nil)
shift = false

-- Drag tracks the item rather than a pooled row, scrolls near edges, and resolves nested controls.
local grip, sourceRow = childFor(dropdown, b)
-- Load the real mouse-up handler to check that normal selection is only suppressed while dragging.
local dropdownFile = assert(io.open("LibScrollableMenu/classes/dropdown_class.lua"))
local clickSource = assert(dropdownFile:read("*a"):match("(function dropdownClass:OnEntryMouseUp%b()%s.-\nend)\n"))
dropdownFile:close()
LibScrollableMenu.preventerVars = {}
local clickClass = assert(loadstring([[
	local dropdownClass = {}
	local lib, libDebug = LibScrollableMenu, {}
	local getControlData = lib.Util.getControlData
	local onEntryMouseUpExcludeEntryTypes, handlerFunctions = {}, {}
	local function checkIfContextMenuOpenedButOtherControlWasClicked() return false end
	local function checkNextOnEntryMouseUpShouldExecute() return false end
	local function runHandler() return true end
]] .. clickSource .. "\nreturn dropdownClass"))()
local selected = 0
function dropdown:OnEntrySelected() selected = selected + 1 end
sourceRow.m_owner = menu
clickClass.OnEntryMouseUp(dropdown, sourceRow, MOUSE_BUTTON_INDEX_LEFT, true)
equals(selected, 1)
manualOrder.StartDrag(grip, MOUSE_BUTTON_INDEX_LEFT)
equals(manualOrder.IsDragging(dropdown), true)
sourceRow.m_data = wrap(d) -- Recycled after scrolling away from the drag source.
mouseY = 54
onUpdate()
equals(dropdown.scrollControl.delta, -25)
mouseY = 146
onUpdate()
equals(dropdown.scrollControl.delta, 25)
mouseOver = makeControl(rowFor(dropdown, c))
mouseUp(nil, MOUSE_BUTTON_INDEX_LEFT)
equals(manualOrder.IsDragging(dropdown), true, "drag guard lasts through mouse-up")
clickClass.OnEntryMouseUp(dropdown, sourceRow, MOUSE_BUTTON_INDEX_LEFT, true)
equals(selected, 1)
runDeferred()
equals(manualOrder.IsDragging(dropdown), false)
equals(menu.m_sortedItems[3], b)
equals(mouseUp, nil)
equals(onUpdate, nil)
equals(callbacks, 4)
equals(menu.shows, 4)
clickClass.OnEntryMouseUp(dropdown, sourceRow, MOUSE_BUTTON_INDEX_LEFT, true)
equals(selected, 2)

-- Fixed rows, outside drops, and hidden or filtered menus cannot be changed.
local before = callbacks
for _, target in ipairs({ rowFor(dropdown, d), makeControl(), rowFor(dropdown, a) }) do
	manualOrder.StartDrag(childFor(dropdown, a), MOUSE_BUTTON_INDEX_LEFT)
	mouseOver = target
	mouseUp(nil, MOUSE_BUTTON_INDEX_LEFT)
	runDeferred()
end
equals(callbacks, before)
manualOrder.StartDrag(childFor(dropdown, a), MOUSE_BUTTON_INDEX_LEFT)
mouseOver = rowFor(dropdown, b)
mouseUp(nil, MOUSE_BUTTON_INDEX_LEFT)
manualOrder.CancelDrag(dropdown)
runDeferred()
equals(callbacks, before)

menu.filterString = "same"
manualOrder.SetupRow(menu, row)
equals(row.LSMManualOrderControls.hidden, true)
equals(row.m_label.right, -5)
equals(manualOrder.MoveWithButton(up, -1), nil)
equals(manualOrder.GetWidth(menu, a), 0)
menu.filterString, menu.options.enableManualOrder = "", false
equals(manualOrder.GetWidth(menu, a), 0)
menu.options.enableManualOrder, menu.isSubmenu = true, true
equals(manualOrder.GetWidth(menu, a), 0)

-- Context menu backing order must survive a rebuild; mismatched data cannot be moved.
local entries = { a, b, c }
local context, contextDrop = makeMenu(entries, true)
equals(manualOrder.MoveWithButton(childFor(contextDrop, a, "Down"), 1), true)
equals(entries[1], b)
equals(entries[2], a)
context.m_sortedItems = ZO_ShallowTableCopy(entries) -- Same source used by RefreshSortedItems.
equals(context.m_sortedItems[2], a)
entries[3] = d
equals(manualOrder.MoveWithButton(childFor(contextDrop, a, "Down"), 1), nil)
equals(context.m_sortedItems[3], c)

-- Exercise the actual combo-box sorting hook without building the full ESOUI.
local sourceFile = assert(io.open("LibScrollableMenu/classes/comboBox_base.lua"))
local source = sourceFile:read("*a")
sourceFile:close()
local updateItems = assert(source:match("(function comboBox_base:UpdateItems%b()%s.-\nend)\n"))
local class = assert(loadstring("local comboBox_base = {}; local lib = LibScrollableMenu\n" .. updateItems .. "\nreturn comboBox_base"))()
local sortMenu = makeMenu({ item("z"), item("a") })
sortMenu.m_sortOrder, sortMenu.m_sortsItems = true, true
function sortMenu:GetSortData() return nil, nil, nil, function(x, y) return x.name < y.name end end
function sortMenu:ShowDropdown() self:Show() end
class.UpdateItems(sortMenu)
equals(sortMenu.m_sortedItems[1].name, "z")
sortMenu.options.enableManualOrder = false
class.UpdateItems(sortMenu)
equals(sortMenu.m_sortedItems[1].name, "a")

print(("Manual ordering: %d assertions passed"):format(assertions))
