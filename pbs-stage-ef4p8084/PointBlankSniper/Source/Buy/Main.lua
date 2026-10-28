local PURCHASE_ITEM_EVENTS = {
  "ITEM_SEARCH_RESULTS_UPDATED",
  "COMMODITY_SEARCH_RESULTS_UPDATED",
  "COMMODITY_SEARCH_RESULTS_ADDED",
  "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
  "COMMODITY_PRICE_UPDATED",
  "COMMODITY_PRICE_UNAVAILABLE",
  "AUCTION_HOUSE_PURCHASE_COMPLETED",
  "AUCTION_HOUSE_SHOW_ERROR",
}

PointBlankSniperBuyFrameMixin = {}

function PointBlankSniperBuyFrameMixin:OnLoad()
  Auctionator.EventBus:Register(self, {
    PointBlankSniper.Events.SnipeSearchStart,
    PointBlankSniper.Events.OpenBuyView
  })
  Auctionator.EventBus:RegisterSource(self, "PointBlankSniperBuyFrameMixin")
end

function PointBlankSniperBuyFrameMixin:ApplyRapidBinding()
  if InCombatLockdown() then return end
  ClearOverrideBindings(self)
  local key = PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.RAPID_BUY_KEY)
  if self:IsShown() and key and key ~= "" then
    SetOverrideBindingClick(self, false, key, "PointBlankSniperRapidBuyButton", "LeftButton")
  end
end

function PointBlankSniperBuyFrameMixin:OnShow()
  self:ApplyRapidBinding()
end

function PointBlankSniperBuyFrameMixin:OnHide()
  self.generation = (self.generation or 0) + 1
  if not InCombatLockdown() then ClearOverrideBindings(self) end
  FrameUtil.UnregisterFrameForEvents(self, PURCHASE_ITEM_EVENTS)

  if self.buyCommodity then
    C_AuctionHouse.CancelCommoditiesPurchase()
    self.buyCommodity = false
  end
  self:Hide()
end

function PointBlankSniperBuyFrameMixin:Reset()
  self.info = nil
  self.expectedPrice = 0
  self.expectedItemKey = nil
  self.gotResult = false
  self.resultInfo = nil
  self.ghostCount = nil
  self.buyCommodity = false
  self.pendingAuctionID = nil
  self.commodityPlan = nil
  self.commodityPagePending = false
  self.waitingForCommodityPage = false
  self:UpdateBuyState()
end

function PointBlankSniperBuyFrameMixin:RequestCommodityPage()
  if self.waitingForCommodityPage and not self.commodityPagePending and self.expectedItemKey and C_AuctionHouse.IsThrottledMessageSystemReady() then
    self.commodityPagePending = true
    C_AuctionHouse.RequestMoreCommoditySearchResults(self.expectedItemKey.itemID)
  end
end

function PointBlankSniperBuyFrameMixin:PrepareFlippingCommodities(itemID)
  self.commodityPlan = nil
  self.gotResult = false
  if not C_AuctionHouse.HasFullCommoditySearchResults(itemID) then
    self.waitingForCommodityPage = true
    self.Price:SetText(POINT_BLANK_SNIPER_L_FLIPPING_INCOMPLETE)
    self:UpdateBuyState()
    self:RequestCommodityPage()
    return
  end
  self.waitingForCommodityPage = false
  local ok, _, maximum = PointBlankSniper.PriceCheck.Flipping.Evaluate(self.expectedItemKey, nil, self.flippingManualMax, true)
  local tiers = {}
  if ok then
    for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
      local tier = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
      if not tier then ok = false break end
      table.insert(tiers, tier)
    end
  end
  if ok then
    self.commodityPlan = PointBlankSniper.PriceCheck.Flipping.PlanCommodities(tiers, maximum, PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.FLIPPING_MAX_SPEND))
  end
  self.gotResult = true
  local plan = self.commodityPlan
  self.Price:SetText(plan and POINT_BLANK_SNIPER_L_FLIPPING_PREPARED:format(plan.quantity, GetMoneyString(plan.total, true)) or POINT_BLANK_SNIPER_L_FLIPPING_COMMODITY_UNTESTED)
  self:UpdateBuyState()
end

function PointBlankSniperBuyFrameMixin:OnEvent(eventName, ...)
  if eventName == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    local auctionID = ...
    if self.pendingAuctionID and self.pendingAuctionID == auctionID then
      self.pendingAuctionID = nil
      self:GetParent():AdvancePurchased(self.expectedItemKey)
    end
  elseif eventName == "AUCTION_HOUSE_SHOW_ERROR" and self.pendingAuctionID then
    self.pendingAuctionID = nil
    self.gotResult = false
    self.BuyButton:Disable()
    self.BuyButton:SetText(POINT_BLANK_SNIPER_L_RAPID_ERROR)
    DynamicResizeButton_Resize(self.BuyButton)
  elseif eventName == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    self:RequestCommodityPage()
  elseif eventName == "COMMODITY_SEARCH_RESULTS_UPDATED" or eventName == "COMMODITY_SEARCH_RESULTS_ADDED" then
    local itemID = ...
    if not self.expectedItemKey or itemID ~= self.expectedItemKey.itemID then
      return
    end
    if PointBlankSniper.PriceCheck.Flipping.Enabled() then
      self.commodityPagePending = false
      self:PrepareFlippingCommodities(itemID)
      return
    elseif eventName == "COMMODITY_SEARCH_RESULTS_ADDED" then
      return
    end
    self.gotResult = true
    self.resultInfo = nil

    self.buyResultsCount = C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID)
    local displayedQuantity = 0
    if C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID) > 0 then
      self.resultInfo = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)

      local displayPrice = self.resultInfo.unitPrice
      self.Price:SetText(POINT_BLANK_SNIPER_L_PRICE_COLON_X:format(
        GetMoneyString(displayPrice, true) ..
        Auctionator.Utilities.CreateCountString(self.resultInfo.quantity)
      ))
      displayedQuantity = self.resultInfo.quantity
    end

    local quantityRequired = Auctionator.Search.SplitAdvancedSearch(self.rawSearchTermInfo.searchTerm).quantity
    if quantityRequired and self.resultInfo and quantityRequired > displayedQuantity then
      C_Timer.After(0, function()
        Auctionator.EventBus:Fire(self, PointBlankSniper.Events.QuickStart)
      end)
    end
    self:UpdateBuyState()

  elseif eventName == "ITEM_SEARCH_RESULTS_UPDATED" then
    local itemKey = ...
    if self.pendingAuctionID or not self.expectedItemKey then return end
    if Auctionator.Utilities.ItemKeyString(itemKey) ~=
        Auctionator.Utilities.ItemKeyString(self.expectedItemKey) then
      return
    end
    self.gotResult = true
    self.resultInfo = nil

    if C_AuctionHouse.GetItemSearchResultsQuantity(itemKey) > 0 then
      self.resultInfo = C_AuctionHouse.GetItemSearchResultInfo(itemKey, 1)

      local displayPrice = self.resultInfo.buyoutAmount or 0
      self.Price:SetText(POINT_BLANK_SNIPER_L_PRICE_COLON_X:format(GetMoneyString(displayPrice, true)))
    end
    self:UpdateBuyState()

  elseif eventName == "COMMODITY_PRICE_UPDATED" and self.buyCommodity then
    local unitPrice, totalPrice = ...
    local valid = self.resultInfo and type(unitPrice) == "number" and type(totalPrice) == "number" and totalPrice > 0 and totalPrice <= GetMoney()
    if valid and PointBlankSniper.PriceCheck.Flipping.Enabled() then
      valid = PointBlankSniper.PriceCheck.Flipping.Evaluate(self.expectedItemKey, unitPrice, self.flippingManualMax, true)
    end
    if valid and (self.ghostCount or (unitPrice <= self.resultInfo.unitPrice and self.resultInfo.unitPrice <= self.expectedPrice)) then
      C_AuctionHouse.ConfirmCommoditiesPurchase(self.expectedItemKey.itemID, self.ghostCount or self.resultInfo.quantity)
    else
      C_AuctionHouse.CancelCommoditiesPurchase()
    end

    self.buyCommodity = false
    self.resultInfo = nil
    self.ghostCount = nil
    self:UpdateBuyState()

  elseif eventName == "COMMODITY_PRICE_UNAVAILABLE" and self.buyCommodity then
    C_AuctionHouse.CancelCommoditiesPurchase()

    self.buyCommodity = false
    self.resultInfo = nil
    self:UpdateBuyState()
  end
end

function PointBlankSniperBuyFrameMixin:UpdateBuyState()
  if self.pendingAuctionID then
    self.BuyButton:Disable()
    self.BuyButton:SetText(POINT_BLANK_SNIPER_L_BUYING)
    return
  end
  if self.gotResult and self.info and self.info.isCommodity and PointBlankSniper.PriceCheck.Flipping.Enabled() then
    self.BuyButton:Disable()
    self.BuyButton:SetText(POINT_BLANK_SNIPER_L_FLIPPING_COMMODITY_UNTESTED)
    DynamicResizeButton_Resize(self.BuyButton)
    return
  end
  if not self.gotResult then
    self.BuyButton:Disable()
    self.BuyButton:SetText(POINT_BLANK_SNIPER_L_WAITING)

  else
    if self.info.isCommodity then
      self.BuyButton:SetEnabled(self.ghostCount or (self.resultInfo and self.resultInfo.quantity > 0 and self.resultInfo.unitPrice <= self.expectedPrice))
    else
      self.BuyButton:SetEnabled(self.resultInfo and self.resultInfo.buyoutAmount ~= nil and self.resultInfo.buyoutAmount <= self.expectedPrice)
    end

    if self.BuyButton:IsEnabled() and PointBlankSniper.PriceCheck.Flipping.Enabled() then
      local price = self.info.isCommodity and self.resultInfo.unitPrice or self.resultInfo.buyoutAmount
      local ok = PointBlankSniper.PriceCheck.Flipping.Evaluate(self.expectedItemKey, price, self.flippingManualMax, true)
      self.BuyButton:SetEnabled(ok)
    end

    if self.BuyButton:IsEnabled() then
      self.BuyButton:SetText(POINT_BLANK_SNIPER_L_BUY_NOW)
    elseif not self.info.isCommodity and self.resultInfo and self.resultInfo.bidAmount ~= nil and self.resultInfo.buyoutAmount == nil then
      self.BuyButton:SetText(POINT_BLANK_SNIPER_L_BID_ONLY)
    else
      self.BuyButton:SetText(POINT_BLANK_SNIPER_L_SOLD)
    end
  end
  DynamicResizeButton_Resize(self.BuyButton)
end

function PointBlankSniperBuyFrameMixin:BuyNow()
  if self.pendingAuctionID or self.buyCommodity or not self:IsShown() or not self.BuyButton:IsEnabled() or not self.info or not self.resultInfo then return end
  if PointBlankSniper.PriceCheck.Flipping.Enabled() then
    local price = self.info.isCommodity and self.resultInfo.unitPrice or self.resultInfo.buyoutAmount
    local budget = PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.FLIPPING_MAX_SPEND)
    if (budget > 0 and price > budget) or price > GetMoney() or not PointBlankSniper.PriceCheck.Flipping.Evaluate(self.expectedItemKey, price, self.flippingManualMax, true) then
      self.BuyButton:Disable()
      return
    end
  end
  self.BuyButton:Disable()
  self.BuyButton:SetText(POINT_BLANK_SNIPER_L_BUYING)
  if self.info.isCommodity then
    self.buyCommodity = true
    C_AuctionHouse.StartCommoditiesPurchase(self.expectedItemKey.itemID, self.ghostCount or self.resultInfo.quantity)
  else
    if not self.resultInfo.auctionID then return end
    self.pendingAuctionID = self.resultInfo.auctionID
    C_AuctionHouse.PlaceBid(self.resultInfo.auctionID, self.resultInfo.buyoutAmount)
  end
end

function PointBlankSniperBuyFrameMixin:SkipResult()
  if self.pendingAuctionID or self.buyCommodity or not self.expectedItemKey then return end
  self:GetParent():AdvancePurchased(self.expectedItemKey)
end

function PointBlankSniperBuyFrameMixin:ViewAll()
  AuctionHouseFrame:SelectBrowseResult({
    itemKey = self.expectedItemKey,
    minPrice = self.expectedPrice,
  })
  AuctionHouseFrame.displayMode = nil
end

function PointBlankSniperBuyFrameMixin:NameSearch()
  if self.expectedItemKey.battlePetSpeciesID ~= 0 then
    Auctionator.API.v1.MultiSearch(POINT_BLANK_SNIPER_L_POINT_BLANK_SNIPER, {
      self.info.itemName
    })
  else
    local item = Item:CreateFromItemID(self.expectedItemKey.itemID)
    item:ContinueOnItemLoad(function()
      Auctionator.API.v1.MultiSearch(POINT_BLANK_SNIPER_L_POINT_BLANK_SNIPER, {
        item:GetItemName()
      })
    end)
  end
end

local deleteSearchTermDialog= "point_blank_sniper_delete_search_term_dialog"
StaticPopupDialogs[deleteSearchTermDialog] = {
  text = "",
  button1 = ACCEPT,
  button2 = CANCEL,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1,
  OnAccept = function(self)
    local list = Auctionator.Shopping.ListManager:GetByName(self.data.listName)
    local index = list:GetIndexForItem(self.data.searchTerm)
    if index ~= nil then
      list:DeleteItem(index)
      PointBlankSniper.Utilities.Message(POINT_BLANK_SNIPER_L_SEARCH_TERM_REMOVED)
    else
      PointBlankSniper.Utilities.Message(POINT_BLANK_SNIPER_L_SEARCH_TERM_ALREADY_REMOVED)
    end
    self.data.callback()
  end
}

function PointBlankSniperBuyFrameMixin:RemoveSearchTerm()
  StaticPopupDialogs[deleteSearchTermDialog].text = POINT_BLANK_SNIPER_L_DELETE_SEARCH_TERM_X:format(Auctionator.Search.PrettifySearchString(self.rawSearchTermInfo.searchTerm)):gsub("%%", "%%%%")
  local data = CopyTable(self.rawSearchTermInfo)
  data.callback = function()
    self:UpdateSearchTermButtons()
  end
  StaticPopup_Show(deleteSearchTermDialog, nil, nil, data)
end

function PointBlankSniperBuyFrameMixin:UpdateSearchTermButtons()
  local list = Auctionator.Shopping.ListManager:GetByName(self.rawSearchTermInfo.listName)
  local index = list:GetIndexForItem(self.rawSearchTermInfo.searchTerm)
  self.RemoveSearchTermButton:SetEnabled(index ~= nil)
end

function PointBlankSniperBuyFrameMixin:ReceiveEvent(eventName, ...)
  if eventName == PointBlankSniper.Events.OpenBuyView then
    if self.pendingAuctionID or self.buyCommodity then return end
    local details = ...

    self:Show()

    if self.buyCommodity then
      C_AuctionHouse.CancelCommoditiesPurchase()
      self.buyCommodity = false
    end
    self:Reset()
    self.generation = (self.generation or 0) + 1
    local generation = self.generation

    self.expectedPrice = details.price
    self.flippingManualMax = details.flippingManualMax
    self.expectedItemKey = details.itemKey
    self.summaryResultsCount = details.quantity
    self.SearchTerm:SetText(details.rawSearchTermInfo and Auctionator.Search.PrettifySearchString(details.rawSearchTermInfo.searchTerm))
    self.rawSearchTermInfo = details.rawSearchTermInfo
    self.Price:SetText(POINT_BLANK_SNIPER_L_PRICE_COLON_X:format(GetMoneyString(details.price, true)))
    self:UpdateBuyState()
    self:UpdateSearchTermButtons()

    Auctionator.AH.GetItemKeyInfo(details.itemKey, function(itemKeyInfo)
      if generation ~= self.generation or not self:IsShown() then return end
      self.info = itemKeyInfo

      self.Icon:Set(details.itemKey, itemKeyInfo.itemName, itemKeyInfo.iconFileID, itemKeyInfo.quality, itemKeyInfo.battlePetLink)

      FrameUtil.RegisterFrameForEvents(self, PURCHASE_ITEM_EVENTS)

      local sortingOrder

      if self.info.isCommodity then
        sortingOrder = {sortOrder = 0, reverseSort = false}
      else
        sortingOrder = {sortOrder = 4, reverseSort = false}
      end
      Auctionator.AH.SendSearchQueryByItemKey(details.itemKey, {sortingOrder}, false)
    end)
  elseif eventName == PointBlankSniper.Events.SnipeSearchStart then
    self:Hide()
  end
end
