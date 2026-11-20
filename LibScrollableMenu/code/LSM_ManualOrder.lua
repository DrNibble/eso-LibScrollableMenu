local lib = LibScrollableMenu
if not lib then return end

local manualOrder = {}
lib.ManualOrder = manualOrder

local getControlData = lib.Util.getControlData
local normalEntry = lib.LSM_ENTRY_TYPE_NORMAL
local normalTemplate = "LibScrollableMenu_ComboBoxEntry"
local dragNamespace = "LibScrollableMenu_ManualOrderDrag"
local controlsWidth = 68
local activeDrag

function manualOrder.IsEnabled(comboBox)
	return not comboBox.isSubmenu and comboBox:GetOptions().enableManualOrder == true
end

local function isMovable(item)
	return item ~= nil and item.entryType == normalEntry and item.enabled ~= false
		and item.customEntryTemplate == normalTemplate
		and not item.isNoEntriesResult and not item.isNoEntriesResultsEntry
end

local function canReorder(comboBox)
	return manualOrder.IsEnabled(comboBox) and (comboBox.filterString or "") == ""
end

function manualOrder.GetWidth(comboBox, item)
	return canReorder(comboBox) and isMovable(item) and controlsWidth or 0
end

-- Header/divider/special/disabled rows delimit contiguous groups. Reject ambiguous item references.
function manualOrder.GetBounds(items, item, movable)
	movable = movable or isMovable
	if not movable(item) then return end
	local index
	for i, candidate in ipairs(items) do
		if candidate == item then
			if index then return end
			index = i
		end
	end
	if not index then return end

	local first, last = index, index
	while first > 1 and movable(items[first - 1]) do first = first - 1 end
	while last < #items and movable(items[last + 1]) do last = last + 1 end
	return index, first, last
end

function manualOrder.MoveAt(items, fromIndex, toIndex)
	table.insert(items, toIndex, table.remove(items, fromIndex))
end

function manualOrder.FindMove(items, item, target, direction, toEnd, movable)
	local fromIndex, first, last = manualOrder.GetBounds(items, item, movable)
	if not fromIndex then return end

	local toIndex
	if target then
		toIndex = manualOrder.GetBounds(items, target, movable)
	elseif direction == -1 then
		toIndex = toEnd and first or fromIndex - 1
	elseif direction == 1 then
		toIndex = toEnd and last or fromIndex + 1
	end
	if not toIndex or toIndex < first or toIndex > last or toIndex == fromIndex then return end
	return fromIndex, toIndex
end

local function move(dropdown, item, target, direction, toEnd)
	local comboBox = dropdown.owner
	if not comboBox:IsDropdownVisible() or not canReorder(comboBox) then return end
	local items = comboBox.m_sortedItems
	local fromIndex, toIndex = manualOrder.FindMove(items, item, target, direction, toEnd)
	if not fromIndex then return end

	-- Context menus are rebuilt from GetEntries(); regular combo boxes keep m_sortedItems.
	if comboBox.isContextMenu then
		local entries = comboBox:GetEntries()
		if #entries ~= #items then return end
		for index, entry in ipairs(entries) do
			if items[index] ~= entry then return end
		end
		if entries ~= items then manualOrder.MoveAt(entries, fromIndex, toIndex) end
	end
	manualOrder.MoveAt(items, fromIndex, toIndex)

	local callback = comboBox:GetOptions().onOrderChanged
	local orderedItems
	if type(callback) == "function" then
		orderedItems = ZO_ShallowTableCopy(items)
	end

	local submenu = comboBox.m_submenu
	if submenu and submenu:IsDropdownVisible() then submenu:HideDropdown() end
	ZO_Tooltips_HideTextTooltip()
	comboBox:Show()
	if direction then
		local list = dropdown.scrollControl
		local rowData = ZO_ScrollList_GetDataList(list)[toIndex]
		if rowData and rowData:GetDataSource() == item then
			ZO_ScrollList_ScrollDataIntoView(list, toIndex, nil, true)
		end
	end

	if orderedItems then callback(comboBox, orderedItems, item, fromIndex, toIndex) end
	return true
end

function manualOrder.MoveWithButton(button, direction)
	local row = button:GetParent():GetParent()
	if row.m_dropdownObject then
		return move(row.m_dropdownObject, getControlData(row), nil, direction, IsShiftKeyDown())
	end
end

function manualOrder.ShowTooltip(control, stringId)
	LibScrollableMenu.XML.OnXMLControlEventHandler("ShowTextTooltip", control, control, BOTTOM, GetString(stringId))
end

local function getDropTarget(dropdown)
	local control = WINDOW_MANAGER:GetMouseOverControl()
	while control and control ~= dropdown.control do
		if control.m_dropdownObject == dropdown and control.m_data then
			return getControlData(control)
		end
		control = control:GetParent()
	end
end

function manualOrder.IsDragging(surface)
	return activeDrag ~= nil and (surface == nil or activeDrag.surface == surface)
end

function manualOrder.CancelDrag(surface)
	if not manualOrder.IsDragging(surface) then return end
	local drag = activeDrag
	activeDrag = nil
	EVENT_MANAGER:UnregisterForEvent(dragNamespace, EVENT_GLOBAL_MOUSE_UP)
	EVENT_MANAGER:UnregisterForUpdate(dragNamespace)
	if drag.onEnd then drag.onEnd() end
end

-- Both popup rows and the OrderListBox use the same drag lifecycle.
function manualOrder.BeginDrag(surface, list, rowHeight, isActive, getTarget, onDrop, onEnd)
	manualOrder.CancelDrag()
	local drag = { surface = surface, onEnd = onEnd }
	activeDrag = drag
	ZO_Tooltips_HideTextTooltip()

	EVENT_MANAGER:RegisterForUpdate(dragNamespace, 75, function()
		if not isActive() then
			manualOrder.CancelDrag(surface)
			return
		end
		if not MouseIsOver(list) then return end
		local _, y = GetUIMousePosition()
		local edge = math.min(20, list:GetHeight() / 3)
		if y < list:GetTop() + edge then
			ZO_ScrollList_ScrollRelative(list, -rowHeight, nil, true)
		elseif y > list:GetBottom() - edge then
			ZO_ScrollList_ScrollRelative(list, rowHeight, nil, true)
		end
	end)

	EVENT_MANAGER:RegisterForEvent(dragNamespace, EVENT_GLOBAL_MOUSE_UP, function(_, button)
		if button ~= MOUSE_BUTTON_INDEX_LEFT then return end
		EVENT_MANAGER:UnregisterForEvent(dragNamespace, EVENT_GLOBAL_MOUSE_UP)
		EVENT_MANAGER:UnregisterForUpdate(dragNamespace)
		local target = getTarget()
		-- Keep the drag guard alive until this mouse-up has finished dispatching to menu rows.
		zo_callLater(function()
			if activeDrag ~= drag then return end
			manualOrder.CancelDrag(surface)
			if target and isActive() then onDrop(target) end
		end, 0)
	end)
end

function manualOrder.StartDrag(grip, mouseButton)
	if mouseButton ~= MOUSE_BUTTON_INDEX_LEFT then return end
	local row = grip:GetParent():GetParent()
	local dropdown = row.m_dropdownObject
	local comboBox = dropdown and dropdown.owner
	if not comboBox or not comboBox:IsDropdownVisible() or not canReorder(comboBox) then return end

	local item = getControlData(row)
	local index, first, last = manualOrder.GetBounds(comboBox.m_sortedItems, item)
	if not index or first == last then return end
	manualOrder.BeginDrag(dropdown, dropdown.scrollControl, ZO_COMBO_BOX_ENTRY_TEMPLATE_HEIGHT,
		function() return comboBox:IsDropdownVisible() and canReorder(comboBox) end,
		function() return getDropTarget(dropdown) end,
		function(target) move(dropdown, item, target) end)
end

function manualOrder.SetupRow(comboBox, row)
	local controls = row.LSMManualOrderControls
	local enabled = canReorder(comboBox)
	if not controls and not enabled then return end
	local item = getControlData(row)
	local width = enabled and isMovable(item) and controlsWidth or 0
	if width == 0 and not controls then return end
	if not controls then
		controls = CreateControlFromVirtual("$(parent)ManualOrder", row, "LibScrollableMenu_ManualOrderControls")
		row.LSMManualOrderControls = controls
	end

	-- This runs only for the stock normal row. Restore its anchors when a pooled row is reused.
	local label = row.m_label
	label:ClearAnchors()
	label:SetAnchor(TOPLEFT, row.m_iconContainer, TOPRIGHT, 1)
	label:SetAnchor(RIGHT, row, RIGHT, ZO_COMBO_BOX_ENTRY_TEMPLATE_LABEL_PADDING - width)
	controls:SetHidden(width == 0)
	if width == 0 then return end

	local index, first, last = manualOrder.GetBounds(comboBox.m_sortedItems, item)
	local up, down = controls:GetNamedChild("Up"), controls:GetNamedChild("Down")
	local grip = controls:GetNamedChild("Grip")
	local canMoveUp, canMoveDown = index ~= nil and index > first, index ~= nil and index < last
	up:SetEnabled(canMoveUp)
	up:SetAlpha(canMoveUp and 1 or 0.4)
	down:SetEnabled(canMoveDown)
	down:SetAlpha(canMoveDown and 1 or 0.4)
	grip:SetMouseEnabled(canMoveUp or canMoveDown)
	grip:SetAlpha((canMoveUp or canMoveDown) and 1 or 0.4)
end
