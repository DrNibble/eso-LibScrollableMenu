-- Run with Lua 5.1 from the repository root.
local UI = dofile("tests/order_list_box_mock.lua")
local checks = 0
local function equal(expected, actual)
	checks = checks + 1
	assert(expected == actual, ("check %d: expected %s, got %s"):format(checks, tostring(expected), tostring(actual)))
end

local parent = UI.control("CategoryWindow")
parent:SetHidden(true)
local leftHost = UI.add(parent, "Available")
local rightHost = UI.add(parent, "Present")
local clicked, removed, changes
local left = LibScrollableMenu.CreateOrderListBox(leftHost, { enableFilter = true, visibleRows = 15 })
local right = LibScrollableMenu.CreateOrderListBox(rightHost, { enableManualOrder = true,
	onOrderChanged = function(widget, entries, item, fromIndex, toIndex)
		equal(rightHost, widget.control.parent)
		equal(item, entries[toIndex])
		changes = { fromIndex, toIndex }
	end,
})
local inputs = {}
for i = 1, 18 do inputs[i] = { key = i, name = "Name " .. i, label = "Label " .. i } end
inputs[2].tooltip = "Name 2\ntrue"
inputs[2].callback = function(_, name) clicked = name end
inputs[17].label = "Left (50%)"
inputs[3].rightClickCallback = function(_, _, item) removed = item.name end
left:SetItems(inputs)
right:SetItems(inputs)
equal(nil, left.scroll.commits)
equal(nil, right.scroll.commits)
parent:SetHidden(false)
left:Show()
right:Show()
equal(leftHost, left.control.parent)
equal(rightHost, right.control.parent)
equal(426, left.control.height)
equal(385, right.control.height)
equal(375, left.scroll.height)
equal(375, right.scroll.height)
equal(18, #left.scroll.data)
equal(18, #right.scroll.data)
equal(15, #left.scroll.rows)
equal(15, #right.scroll.rows)
equal("ZO_ThinListHighlight", right.scroll.highlight)
equal(true, right.scroll.useScrollbar)
equal("Label 1", left.scroll.rows[1]:GetText())
equal("Label 15", right.scroll.rows[15]:GetText())
equal(nil, inputs[1].dataEntry)
left.scroll.rows[2]:Fire("OnMouseEnter")
equal("Name 2\ntrue", UI.tooltip)
left.scroll.rows[2]:Fire("OnMouseExit")
equal(nil, UI.tooltip)
left.scroll.rows[2]:Fire("OnMouseUp", MOUSE_BUTTON_INDEX_LEFT, true)
equal("Name 2", clicked)
left.edit:SetText("  LEFT (50%)  ")
equal(1, #left.scroll.rows)
equal("Left (50%)", left.scroll.rows[1]:GetText())
equal(18, #right.scroll.data)
left.edit:SetText("[missing]")
equal(0, #left.scroll.data)
equal(false, left.empty:IsHidden())
left.control:GetNamedChild("Filter"):GetNamedChild("Reset"):Fire("OnClicked")
equal(18, #left.scroll.data)
equal(true, left.empty:IsHidden())

right.scroll.rows[3]:Fire("OnMouseUp", MOUSE_BUTTON_INDEX_RIGHT, true)
equal("Name 3", removed)
right.scroll.rows[3]:Fire("OnMouseUp", MOUSE_BUTTON_INDEX_LEFT, true)
equal(true, right.buttons[1].enabled)
right.buttons[1]:Fire("OnClicked")
equal(3, changes[1])
equal(1, changes[2])
equal("Label 3", right.scroll.rows[1]:GetText())
equal(3, ZO_ScrollList_GetSelectedData(right.scroll).key)
equal(false, right.buttons[2].enabled)
equal(1, inputs[1].key)

-- Refresh using new rows and labels, as AutoCategory does after priority changes.
local rebuilt = {}
for i, dataEntry in ipairs(right.scroll.data) do
	local key = dataEntry.data.key
	rebuilt[i] = { key = key, name = "Name " .. key, label = "Updated " .. key }
end
right:SetItems(rebuilt)
equal(3, ZO_ScrollList_GetSelectedData(right.scroll).key)
equal("Updated 3", right.scroll.rows[1]:GetText())
right.buttons[4]:Fire("OnClicked")
equal(18, changes[2])
equal("Updated 3", right.scroll.rows[18]:GetText())
right.buttons[2]:Fire("OnClicked")
equal(17, changes[2])
right.buttons[3]:Fire("OnClicked")
equal(18, changes[2])
UI.shift = true
right.buttons[2]:Fire("OnClicked")
equal(1, changes[2])
UI.shift = false
equal("Updated 3", right.scroll.rows[1]:GetText())

right.scroll.rows[1]:Fire("OnDragStart", MOUSE_BUTTON_INDEX_LEFT)
equal(false, LSM_OrderListBox_DragPreview:IsHidden())
equal("Updated 3", LSM_OrderListBox_DragPreview:GetNamedChild("Label"):GetText())
UI.overScroll, UI.cursorY = true, 374
UI:Tick()
equal(2, right.scroll.first)
UI.mouseOver = right.scroll.rows[4]
UI:Release(MOUSE_BUTTON_INDEX_LEFT)
equal(4, changes[2])
equal(true, LSM_OrderListBox_DragPreview:IsHidden())
equal(nil, next(UI.updates))

-- Closing the host behaves differently from losing focus/clicking elsewhere.
right.scroll.rows[4]:Fire("OnDragStart", MOUSE_BUTTON_INDEX_LEFT)
UI.mouseOver = left.scroll.rows[1]
local previous = changes
UI:Release(MOUSE_BUTTON_INDEX_LEFT)
equal(previous, changes)
equal(false, right.control:IsHidden())
left.edit:SetText("name")
left.edit:LoseFocus()
equal("name", left.query)
right.scroll.rows[4]:Fire("OnDragStart", MOUSE_BUTTON_INDEX_LEFT)
parent:SetHidden(true)
equal("", left.query)
equal("", left.edit:GetText())
equal(nil, next(UI.updates))
equal(true, LSM_OrderListBox_DragPreview:IsHidden())
parent:SetHidden(false)
left:Show()
right:Show()
equal(18, #left.scroll.data)
equal(1, right.scroll.first)
equal(nil, ZO_ScrollList_GetSelectedData(right.scroll))
right:Hide()
equal(true, right.control:IsHidden())
print("PASS: " .. checks .. " assertions (OrderListBox)")
