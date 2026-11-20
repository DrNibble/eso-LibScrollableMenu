-- Messages settings
local strings = {
	SI_LSM_SEARCH_FILTER_TOOLTIP = "Enter a search term to filter the menus and (nested) submenu entries.\nPrefix search with \'/\' shows non matching submenu-entries too",

    SI_LSM_CNTXT_CHECK_ALL = "Check all",
    SI_LSM_CNTXT_CHECK_NONE = "Check none",
    SI_LSM_CNTXT_CHECK_INVERT = "Invert",

    SI_LSM_SLIDER_CURRENT_MIN_MAX_STEP = "Current: %q (Min.: %s/Max.: %s, step: %s)",
    SI_LSM_MANUAL_ORDER_DRAG = "Drag to reorder",
    SI_LSM_MANUAL_ORDER_UP = "Move up (Shift: move to the top of this group)",
    SI_LSM_MANUAL_ORDER_DOWN = "Move down (Shift: move to the bottom of this group)"
}

for stringId, stringValue in pairs(strings) do
   ZO_CreateStringId(stringId, stringValue)
   SafeAddVersion(stringId, 1)
end