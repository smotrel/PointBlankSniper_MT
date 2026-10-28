function PointBlankSniper.Scan.GetItemKeys(searchTerms)
  local strFind = string.find
  local nameCache = PointBlankSniper.ItemKeyCache.State.orderedKeys.names
  local keyCache = PointBlankSniper.ItemKeyCache.State.orderedKeys.itemKeyStrings
  local GetStartingIndex = PointBlankSniper.Utilities.GetStartingIndex
  local IsBlacklistedID = PointBlankSniper.Utilities.IsBlacklistedID

  local keysToSearchFor = {}
  local keysToPrice = {}
  local keysToRaw = {}
  local seen = {}
  local flipping = PointBlankSniper.PriceCheck.Flipping.Enabled()

  for _, search in ipairs(searchTerms) do
    local searchString = search.searchString
    local index = GetStartingIndex(1, #nameCache, nameCache, searchString)
    while index <= #nameCache and strFind(nameCache[index], searchString, 1, true) ~= nil do
      for _, keyString in ipairs(keyCache[index]) do
        local check = true
        local itemKey = PointBlankSniper.Utilities.ItemKeyStringToItemKey(keyString)

        if itemKey.battlePetSpeciesID == 0 then
          if search.minItemLevel ~= nil then
            check = check and itemKey.itemLevel >= search.minItemLevel
          end
          if search.maxItemLevel ~= nil then
            check = check and itemKey.itemLevel <= search.maxItemLevel
          end
        end

        if search.tier ~= nil then
          check = check and C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemKey.itemID) == search.tier
        end

        check = check and (not search.isExact or searchString == nameCache[index])

        check = check and not IsBlacklistedID(itemKey.itemID)

        if check then
          if flipping then
            if not seen[keyString] then
              seen[keyString] = true
              table.insert(keysToSearchFor, itemKey)
              keysToRaw[keyString] = search.rawSearchTerm
            end
            if search.price ~= nil and (keysToPrice[keyString] == nil or search.price < keysToPrice[keyString]) then
              keysToPrice[keyString] = search.price
              keysToRaw[keyString] = search.rawSearchTerm
            end
          elseif keysToPrice[keyString] ~= nil then
            keysToPrice[keyString] = math.max(keysToPrice[keyString], search.price or 0)
          else
            table.insert(keysToSearchFor, itemKey)
            keysToPrice[keyString] = search.price
          end
          if not flipping then keysToRaw[keyString] = search.rawSearchTerm end
        end
      end
      index = index + 1
    end
  end

  return keysToSearchFor, keysToPrice, keysToRaw
end
