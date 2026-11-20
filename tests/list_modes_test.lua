-- Run with Lua 5.1 from the repository root. Load production functions
-- with stubs for ESO widgets and the parts of LSM unrelated to list modes.
local checks = 0
local function equal(expected, actual)
	checks = checks + 1
	assert(expected == actual, ("expected %s, got %s"):format(tostring(expected), tostring(actual)))
end

local function loadFunctions(file, signatures, env)
	local f = assert(io.open(file))
	local source = f:read("*a")
	f:close()
	for _, signature in ipairs(signatures) do
		local start = assert(source:find(signature, 1, true))
		local finish = assert(source:find("\nend\r?\n", start))
		setfenv(assert(loadstring(source:sub(start, finish + 3), "@" .. file)), env)()
	end
end

local env = setmetatable({
	submenuClass = {}, dropdownClass = {}, lib = {}, libDebug = {},
	libUtil = { refreshDropdownHeader = function(menu, header)
		header.shown = menu:IsFilterEnabled()
		equal(nil, menu.options.titleText)
	end },
	zo_strlower = string.lower,
	ZO_Tooltips_HideTextTooltip = function() end,
	getControlData = function(c) return c.data end,
}, { __index = _G })
local classes = "LibScrollableMenu/classes/"
loadFunctions(classes .. "subMenu_class.lua", {
	"function submenuClass:IsFilterEnabled(", "function submenuClass:SetLocalFilter(",
	"function submenuClass:AddMenuItems(",
}, env)
loadFunctions(classes .. "dropdown_class.lua", {
	"function dropdownClass:IsFilterEnabled(", "function dropdownClass:SetFilterString(",
	"function dropdownClass:ResetFilters(",
}, env)
loadFunctions("LibScrollableMenu/LSM_API.lua", { "function lib.CreateEmbeddedList(" }, env)

local root = { filterString = "root-only", enabled = false }
function root:IsFilterEnabled() return self.enabled end
function root:CheckIfOtherLSMControlsNeedToBeHidden() end
env.closeLSMContextMenuFromFilterHeader = function() end
local submenu = setmetatable({ isSubmenu = true, options = { titleText = "root title" } }, { __index = env.submenuClass })
local dd = setmetatable({ control = {}, m_comboBox = root, owner = submenu }, { __index = env.dropdownClass })
local filter = { text = "" }
function filter:GetText() return self.text end
function filter:SetText(text)
	self.text = text
	dd:SetFilterString(self)
end
function filter:LoseFocus() self.focused = false end
env.ApplyTemplateToControl = function(control, template)
	equal("LibScrollableMenu_Dropdown_Template_WithHeader", template)
	control.header, control.filterBox = {}, filter
end
submenu.m_dropdownObject = dd
submenu.containerMinWidth = 380
function submenu:IsDropdownVisible() return self.visible end
function submenu:RefreshSortedItems(opener) self.entries = opener.data.entries end
function submenu:UpdateWidth(control) equal(dd.control, control) end
function submenu:UpdateHeight(control) equal(dd.control, control) end
function dd:AnchorToControl(opener) equal(submenu.openingControl, opener) end
function dd.control:GetWidth() return 420 end
local redraws = 0
function submenu:Show()
	equal(420, self.containerMinWidth)
	redraws = redraws + 1
end
local move = { data = { entries = { "Z", "A" }, additionalData = { enableSubmenuFilter = true } } }
local level = { data = { entries = { "Increase" } } }
submenu:AddMenuItems(move)
equal(true, dd:IsFilterEnabled())
equal(true, dd.control.header.shown)
equal(move.data.entries, submenu.entries)
equal("root title", submenu.options.titleText)
submenu.visible = true
filter.focused = true
filter:SetText("  [50%] A  ")
equal("[50%] a", submenu.filterString)
equal("root-only", root.filterString)
equal(true, filter.focused)
equal(1, redraws)
equal(380, submenu.containerMinWidth)
dd:ResetFilters(dd.control)
equal("", submenu.filterString)
equal("", filter.text)
equal(2, redraws)
filter:SetText("Z")
submenu.visible = false
submenu:AddMenuItems(level)
equal(false, dd:IsFilterEnabled())
equal(false, dd.control.header.shown)
equal(false, filter.focused)
equal("", filter.text)
equal(level.data.entries, submenu.entries)
equal("root-only", root.filterString)
submenu:AddMenuItems(move)
equal(true, dd:IsFilterEnabled())
equal("", submenu.filterString)
equal(3, redraws)

local combo = { m_sortedItems = {}, m_unsortedItems = {}, visible = false }
local host, container, control = {}, {}, {}
local embedded = { control = control }
function host:GetWidth() return 410 end
function host:GetOwningWindow() return self end
function host:GetDrawTier() return "high" end
function host:SetHandler(event, handler) self[event] = handler end
function container:SetWidth(width) equal(410, width) end
function container:SetHidden(hidden) equal(true, hidden) end
function control:SetDrawTier(tier) equal("high", tier) end
function control:ClearAnchors() end
function control:SetAnchor(_, anchor) equal(host, anchor) end
function embedded:SetHidden(hidden) self.hidden = hidden end
function combo:UpdateDropdownHeader() end
function combo:Show() self.redraws = (self.redraws or 0) + 1 end
function combo:SetVisible(value) self.visible = value end
function combo:IsDropdownVisible() return self.visible end
function combo:AddItem(item, mode)
	equal(env.ZO_COMBOBOX_SUPPRESS_UPDATE, mode)
	table.insert(self.m_sortedItems, item)
	table.insert(self.m_unsortedItems, item)
end
env.WINDOW_MANAGER = { CreateControlFromVirtual = function(_, _, parent, template)
	equal(host, parent)
	equal("ZO_ComboBox", template)
	return container
end }
env.AddCustomScrollableComboBoxDropdownMenu = function() return embedded end
env.ZO_ComboBox_ObjectFromContainer = function() return combo end
env.ZO_COMBOBOX_SUPPRESS_UPDATE = {}
env.ZO_ClearNumericallyIndexedTable = function(list) for i = #list, 1, -1 do list[i] = nil end end
env.lib.ManualOrder = { CancelDrag = function(dropdown) equal(embedded, dropdown) end }
local list = env.lib.CreateEmbeddedList(host, {})
list:SetItems({ "Z", "A" })
equal("Z,A", table.concat(combo.m_sortedItems, ","))
list:Show()
equal(true, combo.embeddedList)
equal(true, combo.visible)
equal(false, embedded.hidden)
list:SetItems({ "B" })
equal(2, combo.redraws)
equal("B", table.concat(combo.m_unsortedItems, ","))
combo.filterString = "B"
host.OnEffectivelyHidden()
equal(false, combo.visible)
equal(true, embedded.hidden)
equal("", combo.filterString)
print("List modes: " .. checks .. " assertions passed")
