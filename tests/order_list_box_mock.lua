-- Small ESO UI stand-in. Commit materializes only visible rows and invokes
-- production setup callbacks. No popup, combo box, or LibAddonMenu is provided.
local root = ... or "."
local function noop() end
local C = {}
C.__index = C
local function control(name, parent)
	return setmetatable({ hidden = false, name = name, parent = parent, children = {}, handlers = {}, text = "" }, C)
end
function C:GetName() return self.name end
function C:GetNamedChild(key) return self.children[key] end
function C:SetHandler(event, fn) self.handlers[event] = fn end
function C:Fire(event, ...) if self.handlers[event] then return self.handlers[event](self, ...) end end
function C:SetText(text) self.text = text; self:Fire("OnTextChanged") end
function C:GetText() return self.text end
function C:GetTextWidth() return #self.text * 8 end
function C:IsHidden() return self.hidden end
function C:IsShown() return not self.hidden and (not self.parent or self.parent:IsShown()) end
function C:SetHidden(hidden)
	local wasShown = self:IsShown()
	self.hidden = hidden
	if wasShown and not self:IsShown() then
		local function hide(control)
			control:Fire("OnEffectivelyHidden")
			for _, child in pairs(control.children) do if not child.hidden then hide(child) end end
		end
		hide(self)
	end
end
function C:SetEnabled(enabled) self.enabled = enabled end
function C:SetHeight(height) self.height = height end
function C:GetHeight() return self.height end
function C:GetTop() return 0 end
function C:GetBottom() return self.height end
function C:LoseFocus() self.focused = false end
function C:SetAnchor(...) self.anchor = { ... } end
for _, method in ipairs({ "SetMouseEnabled", "SetDimensions", "SetTextureCoords", "SetNormalTexture",
	"SetMouseOverTexture", "SetPressedTexture", "SetPressedMouseOverTexture", "SetDisabledTexture",
	"SetPressedOffset", "SetClickSound", "BringWindowToTop", "ClearAnchors" }) do C[method] = noop end

local function add(parent, key)
	local child = control(parent.name .. key, parent)
	parent.children[key] = child
	return child
end
local function renderScroll(scroll)
	scroll.rows = {}
	local first = scroll.first or 1
	for i = first, math.min(#scroll.data, first + math.floor(scroll.height / scroll.rowHeight) - 1) do
		local dataEntry = scroll.data[i]
		dataEntry.data.dataEntry = dataEntry
		local row = control(scroll.name .. "Row" .. i, scroll)
		row.dataEntry = dataEntry
		scroll.setup(row, dataEntry.data)
		scroll.rows[i] = row
	end
end

UI = { control = control, add = add, shift = false, events = {}, updates = {}, deferred = {} }
WINDOW_MANAGER = {
	CreateControl = function(_, name, parent, kind) assert(kind == CT_BUTTON); return control(name, parent) end,
	CreateControlFromVirtual = function(_, name, parent, template)
		assert(template == "LSM_OrderListBox_Widget" and parent)
		local widget = add(parent, name:sub(#parent.name + 1))
		widget:SetHidden(true)
		add(widget, "List").data = {}
		add(widget, "Empty")
		local filter = add(widget, "Filter")
		filter:SetHidden(true)
		add(filter, "Reset")
		add(add(filter, "Input"), "Edit")
		return widget
	end,
	GetMouseOverControl = function() return UI.mouseOver end,
}
LSM_OrderListBox_DragPreview = control("DragPreview")
LSM_OrderListBox_DragPreview:SetHidden(true)
add(LSM_OrderListBox_DragPreview, "Label")
TOPLEFT, TOPRIGHT, LEFT, RIGHT, CT_BUTTON = 1, 2, 3, 4, 5
GuiMouse = control("GuiMouse")
MOUSE_BUTTON_INDEX_LEFT, MOUSE_BUTTON_INDEX_RIGHT = 1, 2
EVENT_GLOBAL_MOUSE_UP = 7
ZO_COMBO_BOX_ENTRY_TEMPLATE_HEIGHT = 25
SI_LSM_MANUAL_ORDER_FIRST, SI_LSM_MANUAL_ORDER_UP = "first", "up"
SI_LSM_MANUAL_ORDER_LAST, SI_LSM_MANUAL_ORDER_DOWN = "last", "down"
zo_strlower, GetString = string.lower, function(id) return id end
function ZO_ShallowTableCopy(items) local copy = {}; for i, item in ipairs(items) do copy[i] = item end; return copy end
function IsShiftKeyDown() return UI.shift end
function MouseIsOver() return UI.overScroll end
function GetUIMousePosition() return 0, UI.cursorY or 0 end
ZO_Tooltips_ShowTextTooltip = function(_, _, text) UI.tooltip = text end
ZO_Tooltips_HideTextTooltip = function() UI.tooltip = nil end
ZO_SelectableLabel_OnMouseEnter, ZO_SelectableLabel_OnMouseExit = noop, noop
EVENT_MANAGER = {
	RegisterForEvent = function(_, namespace, event, fn) assert(event == EVENT_GLOBAL_MOUSE_UP); UI.events[namespace] = fn end,
	UnregisterForEvent = function(_, namespace) UI.events[namespace] = nil end,
	RegisterForUpdate = function(_, namespace, _, fn) UI.updates[namespace] = fn end,
	UnregisterForUpdate = function(_, namespace) UI.updates[namespace] = nil end,
}
function UI:Tick() for _, fn in pairs(self.updates) do fn() end end
function zo_callLater(fn) UI.deferred[#UI.deferred + 1] = fn end
function UI:Release(button)
	for _, fn in pairs(self.events) do fn(EVENT_GLOBAL_MOUSE_UP, button) end
	for _, fn in ipairs(self.deferred) do fn() end
	self.deferred = {}
end
function ZO_ScrollList_AddDataType(scroll, kind, name, height, setup)
	assert(kind == 1 and name == "LSM_OrderListBox_Row")
	scroll.setup, scroll.rowHeight = setup, height
end
function ZO_ScrollList_EnableSelection(scroll, highlight) scroll.highlight = highlight end
function ZO_ScrollList_SetUseScrollbar(scroll, enabled) scroll.useScrollbar = enabled end
function ZO_ScrollList_GetSelectedData(scroll) return scroll.selected end
function ZO_ScrollList_SelectData(scroll, data) scroll.selected = data end
function ZO_ScrollList_GetDataList(scroll) return scroll.data end
function ZO_ScrollList_GetData(row) return row.dataEntry and row.dataEntry.data end
function ZO_ScrollList_Clear(scroll) scroll.data, scroll.selected = {}, nil end
function ZO_ScrollList_CreateDataEntry(kind, data) return { typeId = kind, data = data } end
function ZO_ScrollList_Commit(scroll)
	assert(scroll:IsShown() and scroll.height > 0 and scroll.anchor[2] == scroll.parent)
	scroll.commits = (scroll.commits or 0) + 1
	scroll.first = math.min(scroll.first or 1, math.max(1, #scroll.data - scroll.height / scroll.rowHeight + 1))
	renderScroll(scroll)
end
function ZO_ScrollList_ScrollDataIntoView(scroll, index)
	if not scroll.rows[index] then
		local visibleRows = scroll.height / scroll.rowHeight
		scroll.first = index > scroll.first and math.max(1, index - visibleRows + 1) or index
		renderScroll(scroll)
	end
end
function ZO_ScrollList_ScrollRelative(scroll, distance)
	scroll.first = math.max(1, math.min(#scroll.data - scroll.height / scroll.rowHeight + 1,
		scroll.first + math.floor(distance / scroll.rowHeight)))
	renderScroll(scroll)
end

-- Load the three production units without booting the rest of ESO.
LibScrollableMenu = { Util = {} }
local function loadFunction(file, signature, env)
	local input = assert(io.open(root .. "/LibScrollableMenu/" .. file))
	local text = input:read("*a")
	input:close()
	local first = assert(text:find(signature, 1, true))
	local last = assert(text:find("\nend\r?\n", first))
	setfenv(assert(loadstring(text:sub(first, last + 3), "@" .. file)), setmetatable(env, { __index = _G }))()
end
loadFunction("code/LSM_Util.lua", "function libUtil.matchesFilterText(", { libUtil = LibScrollableMenu.Util })
dofile(root .. "/LibScrollableMenu/code/LSM_ManualOrder.lua")
dofile(root .. "/LibScrollableMenu/code/LSM_OrderListBox.lua")
loadFunction("LSM_API.lua", "function lib.CreateOrderListBox(", { lib = LibScrollableMenu })
return UI
