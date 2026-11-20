local lib = LibScrollableMenu
if not lib then return end

-- Independent LSM implementation of the OrderListBox presentation:
-- selectable rows, an external four-button rail and a cursor preview.
-- No LibAddonMenu widget, panel or settings callbacks are used here.
local manual = lib.ManualOrder
local matches = lib.Util.matchesFilterText
local listBox = {}
listBox.__index = listBox
lib.OrderListBox = listBox

local function itemKey(item)
	return item.key or item
end

local function movable(item)
	return item ~= nil and item.enabled ~= false
end

local function tooltip(control, stringId)
	ZO_Tooltips_ShowTextTooltip(control, LEFT, GetString(stringId))
end

function listBox:CanReorder()
	return self.shown and self.options.enableManualOrder == true and self.query == ""
end

function listBox:UpdateButtons()
	local selected = ZO_ScrollList_GetSelectedData(self.scroll)
	local item = selected and selected.item
	local canMove = self:CanReorder() and item ~= nil
	for _, button in ipairs(self.buttons) do
		local available = canMove and manual.FindMove(self.items, item, nil, button.direction, button.toEnd, movable) ~= nil
		button:SetEnabled(available)
	end
end

function listBox:Render(reveal)
	ZO_ScrollList_Clear(self.scroll)
	local rows = ZO_ScrollList_GetDataList(self.scroll)
	local selected, selectedIndex
	for _, item in ipairs(self.items) do
		if self.query == "" or matches(item.label or item.name, self.query) then
			-- ESO attaches dataEntry to these temporary wrappers, not to caller entries.
			local row = { item = item, key = itemKey(item) }
			rows[#rows + 1] = ZO_ScrollList_CreateDataEntry(1, row)
			if self.selectedKey == row.key then
				selected, selectedIndex = row, #rows
			end
		end
	end
	ZO_ScrollList_Commit(self.scroll)
	self.empty:SetHidden(#rows > 0)
	if selected then
		ZO_ScrollList_SelectData(self.scroll, selected, nil, true, true)
		if reveal then ZO_ScrollList_ScrollDataIntoView(self.scroll, selectedIndex, nil, true) end
	else
		self.selectedKey = nil
	end
	self:UpdateButtons()
end

function listBox:SetItems(entries)
	manual.CancelDrag(self)
	self.items = {}
	for i, item in ipairs(entries) do self.items[i] = item end
	if self.shown then self:Render() end
end

function listBox:Show()
	self.control:SetHidden(false)
	self.shown = true
	self:Render()
	if #self.items > 0 then ZO_ScrollList_ScrollDataIntoView(self.scroll, 1, nil, true) end
end

function listBox:Reset()
	self.shown, self.selectedKey, self.query = false, nil, ""
	manual.CancelDrag(self)
	if self.edit then
		self.edit:LoseFocus()
		self.edit:SetText("")
	end
end

function listBox:Hide()
	self:Reset()
	self.control:SetHidden(true)
end

function listBox:Move(item, target, direction, toEnd)
	if not self:CanReorder() then return end
	local fromIndex, toIndex = manual.FindMove(self.items, item, target, direction, toEnd, movable)
	if not fromIndex then return end
	manual.MoveAt(self.items, fromIndex, toIndex)
	local callback = self.options.onOrderChanged
	self.selectedKey = itemKey(item)
	ZO_Tooltips_HideTextTooltip()
	self:Render(true)
	if callback then callback(self, ZO_ShallowTableCopy(self.items), item, fromIndex, toIndex) end
	return true
end

local function getDropTarget(self)
	local row = WINDOW_MANAGER:GetMouseOverControl()
	if row and row.lsmOrderList == self and not row:IsHidden() then
		local data = ZO_ScrollList_GetData(row)
		return data and data.item
	end
end

function listBox:StartDrag(row, item, button)
	if button ~= MOUSE_BUTTON_INDEX_LEFT or not self:CanReorder() then return end
	local index, first, last = manual.GetBounds(self.items, item, movable)
	if not index or first == last then return end
	local preview = LSM_OrderListBox_DragPreview
	manual.BeginDrag(self, self.scroll, self.rowHeight,
		function() return self:CanReorder() end,
		function() return getDropTarget(self) end,
		function(target) self:Move(item, target) end,
		function() preview:SetHidden(true) end)
	ZO_Tooltips_HideTextTooltip()
	preview:SetDimensions(math.max(1, math.min(600, row:GetTextWidth() + 12)), self.rowHeight)
	preview:GetNamedChild("Label"):SetText(row:GetText())
	preview:ClearAnchors()
	preview:SetAnchor(LEFT, GuiMouse, RIGHT, 8, 0)
	preview:SetHidden(false)
	preview:BringWindowToTop()
end

function listBox:SetupRow(row, data)
	local item = data.item
	row.lsmOrderList = self
	row:SetText(item.label or item.name)
	row:SetHandler("OnMouseEnter", function(control)
		ZO_SelectableLabel_OnMouseEnter(control)
		if item.tooltip and not manual.IsDragging() then
			ZO_Tooltips_ShowTextTooltip(control, LEFT, item.tooltip)
		end
	end)
	row:SetHandler("OnMouseExit", function(control)
		ZO_SelectableLabel_OnMouseExit(control)
		ZO_Tooltips_HideTextTooltip()
	end)
	row:SetHandler("OnMouseUp", function(control, button, upInside)
		if not upInside or not self.shown or manual.IsDragging() or not movable(item) then return end
		if button == MOUSE_BUTTON_INDEX_LEFT then
			self.selectedKey = data.key
			ZO_ScrollList_SelectData(self.scroll, data, control)
			self:UpdateButtons()
			if item.callback then item.callback(self, item.name, item, control) end
		elseif button == MOUSE_BUTTON_INDEX_RIGHT and item.rightClickCallback then
			item.rightClickCallback(self, control, item)
		end
	end)
	row:SetHandler("OnDragStart", function(control, button) self:StartDrag(control, item, button) end)
	row:SetHidden(false)
end

local function addMoveButton(self, suffix, direction, toEnd, offsetY, stringId)
	local button = WINDOW_MANAGER:CreateControl(self.control:GetName() .. suffix, self.control, CT_BUTTON)
	local texture = toEnd and "EsoUI/Art/ChatWindow/chat_scrollbar_endarrow_%s.dds"
		or (direction < 0 and "EsoUI/Art/Buttons/scrollbox_uparrow_%s.dds" or "EsoUI/Art/Buttons/scrollbox_downarrow_%s.dds")
	button:SetNormalTexture(texture:format("up"))
	button:SetMouseOverTexture(texture:format("over"))
	button:SetPressedTexture(texture:format("down"))
	button:SetPressedMouseOverTexture(texture:format("down"))
	button:SetDisabledTexture(texture:format(toEnd and "disabled" or "up_disabled"))
	button:SetPressedOffset(2, 2)
	button:SetClickSound("Click")
	if toEnd and direction < 0 then button:SetTextureCoords(1, 0, 1, 0) end
	button:SetDimensions(16, 16)
	button:SetAnchor(RIGHT, self.scroll, RIGHT, 22, offsetY)
	button:SetMouseEnabled(true)
	button:SetEnabled(false)
	button.direction, button.toEnd = direction, toEnd
	button:SetHandler("OnMouseEnter", function(control) tooltip(control, stringId) end)
	button:SetHandler("OnMouseExit", ZO_Tooltips_HideTextTooltip)
	button:SetHandler("OnClicked", function()
		local selected = ZO_ScrollList_GetSelectedData(self.scroll)
		if selected then self:Move(selected.item, nil, direction, toEnd or IsShiftKeyDown()) end
	end)
	self.buttons[#self.buttons + 1] = button
end

function listBox.Create(host, options)
	options = options or {}
	local control = WINDOW_MANAGER:CreateControlFromVirtual(host:GetName() .. "OrderListBox", host, "LSM_OrderListBox_Widget")
	local self = setmetatable({
		control = control, options = options, scroll = control:GetNamedChild("List"),
		empty = control:GetNamedChild("Empty"), items = {}, buttons = {}, query = "",
		rowHeight = options.rowHeight or 25,
	}, listBox)
	local filterOffset = options.enableFilter and 41 or 0
	local viewport = self.rowHeight * (options.visibleRows or 15)
	control:SetAnchor(TOPLEFT, host, TOPLEFT)
	control:SetAnchor(TOPRIGHT, host, TOPRIGHT)
	control:SetHeight(viewport + filterOffset + 10)
	self.scroll:SetAnchor(TOPLEFT, control, TOPLEFT, 5, 5 + filterOffset)
	self.scroll:SetAnchor(TOPRIGHT, control, TOPRIGHT, options.enableManualOrder and -27 or -5, 5 + filterOffset)
	self.scroll:SetHeight(viewport)
	ZO_ScrollList_AddDataType(self.scroll, 1, "LSM_OrderListBox_Row", self.rowHeight,
		function(row, data) self:SetupRow(row, data) end)
	ZO_ScrollList_EnableSelection(self.scroll, "ZO_ThinListHighlight")
	ZO_ScrollList_SetUseScrollbar(self.scroll, true)

	if options.enableManualOrder then
		addMoveButton(self, "First", -1, true, -30, SI_LSM_MANUAL_ORDER_FIRST)
		addMoveButton(self, "Up", -1, false, -10, SI_LSM_MANUAL_ORDER_UP)
		addMoveButton(self, "Down", 1, false, 10, SI_LSM_MANUAL_ORDER_DOWN)
		addMoveButton(self, "Last", 1, true, 30, SI_LSM_MANUAL_ORDER_LAST)
	end
	if options.enableFilter then
		local filter = control:GetNamedChild("Filter")
		filter:SetHidden(false)
		self.edit = filter:GetNamedChild("Input"):GetNamedChild("Edit")
		self.edit:SetHandler("OnTextChanged", function(edit)
			local query = zo_strlower(edit:GetText():match("^%s*(.-)%s*$"))
			if query == self.query then return end
			self.query = query
			manual.CancelDrag(self)
			if self.shown then self:Render() end
		end)
		local reset = filter:GetNamedChild("Reset")
		reset:SetHandler("OnClicked", function() self.edit:SetText("") end)
		reset:SetHandler("OnMouseEnter", function(button) tooltip(button, SI_HOOK_POINT_STORE_RESET) end)
		reset:SetHandler("OnMouseExit", ZO_Tooltips_HideTextTooltip)
	end
	control:SetHandler("OnEffectivelyHidden", function()
		if self.shown then self:Reset() end
	end)
	return self
end
