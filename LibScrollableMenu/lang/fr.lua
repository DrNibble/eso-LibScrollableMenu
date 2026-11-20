local stringsFR = {
	SI_LSM_SEARCH_FILTER_TOOLTIP = "Saisissez un terme de recherche pour filtrer les menus et les entrées de sous-menu (imbriqués).\nLa recherche avec le préfixe \'/\' affiche également les sous-menus qui ne correspondent pas.",
	SI_LSM_MANUAL_ORDER_DRAG = "Faire glisser pour réordonner",
	SI_LSM_MANUAL_ORDER_UP = "Monter (Maj : déplacer en tête de ce groupe)",
	SI_LSM_MANUAL_ORDER_DOWN = "Descendre (Maj : déplacer en fin de ce groupe)",
	SI_LSM_MANUAL_ORDER_FIRST = "Déplacer en tête de liste",
	SI_LSM_MANUAL_ORDER_LAST = "Déplacer en fin de liste"
}

for stringId, stringValue in pairs(stringsFR) do
   SafeAddString(_G[stringId], stringValue, 1)
end
