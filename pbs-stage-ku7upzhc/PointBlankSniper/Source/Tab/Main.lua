PointBlankSniperTabFrameMixin = {}

function PointBlankSniperTabFrameMixin:OnLoad()
  Auctionator.Debug.Message("PointBlankSniperTabMixin:OnLoad()")

  self.Alert = CreateAndInitFromMixin(PointBlankSniperAlertMixin)

  Auctionator.EventBus:Register(self, {
    PointBlankSniper.Events.SnipeSearchStart,
    PointBlankSniper.Events.SnipeSearchNewResults,
    PointBlankSniper.Events.SnipeSearchComplete,
    PointBlankSniper.Events.OpenBuyView,
    PointBlankSniper.Events.QuickStart,
  })
  Auctionator.EventBus:RegisterSource(self, "PointBlankSniperTabFrame")

  PointBlankSniper.Config.InitializeData()

  self:SetupMarketData()
  self.FilterKeySelector:Reset()
  self:UpdateShoppingListNames()

  self.ResultsListing:Init(self.DataProvider)
  self.PriceSource:SetValue(PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.PRICE_SOURCE))
  self.Percentage:SetText(PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.PERCENTAGE) * 100)
  self.FilterKeySelector:SetValue(PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.ITEM_CLASS))
  self.ScanMode:SetSelectedValue(PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.SCAN_MODE))

  self.scanTime = -1
  self.currentBatch = 0
  self.scanCount = 0

  self:UpdateStartButton()
  self:UpdateConfigs()
end
function PointBlankSniperTabFrameMixin:SetupMarketData()
  local marketNames = {}
  local marketValues = {}
  for _, m in pairs(PointBlankSniper.Constants.Market) do
    if PointBlankSniper.PriceCheck.IsAvailable(m) then
      table.insert(marketValues, m)
    end
  end

  table.sort(marketValues)
  for _, m in ipairs(marketValues) do
    table.insert(marketNames, PointBlankSniper.Constants.MarketToName[m])
  end

  -- Try to select some market that isn't None if the chosen market is
  -- unavailable or not configured yet. It will select None if there are no
  -- other options.
  if (not PointBlankSniper.PriceCheck.IsAvailable(PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.PRICE_SOURCE))
      and not PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.WAS_PRICE_SOURCE_CHANGED)
    ) then
    PointBlankSniper.Config.Set(PointBlankSniper.Config.Options.PRICE_SOURCE,  marketValues[2] or PointBlankSniper.Constants.Market.None)
  end

  self.PriceSource:InitAgain(marketNames, marketValues)
end

function PointBlankSniperTabFrameMixin:UpdateShoppingListNames()
  local listNames = {}
  for i = 1, Auctionator.Shopping.ListManager:GetCount() do
    table.insert(listNames, Auctionator.Shopping.ListManager:GetByIndex(i):GetName())
  end
  self.ListName:InitAgain(listNames, listNames)

  local currentList = PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.CURRENT_LIST)
  if tIndexOf(listNames, currentList) == nil then
    currentList = listNames[1]
    PointBlankSniper.Config.Set(PointBlankSniper.Config.Options.CURRENT_LIST, currentList)
  end
  self.ListName:SetValue(currentList)
end

function PointBlankSniperTabFrameMixin:UpdateStartButton()
  self.StartButton:SetEnabled(Auctionator.Shopping.ListManager:GetIndexForName(PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.CURRENT_LIST)) ~= nil)
end

local function FormatTime(scanTime)
  return string.format("%.2f", scanTime / 1000)
end

function PointBlankSniperTabFrameMixin:UpdateStatusMessageOngoing()
  if self.scanTime < 0 then
    self.Status:SetText(POINT_BLANK_SNIPER_L_STATUS_MESSAGE_NO_TIME:format(self.scanCount, self.currentBatch))
  else
    self.Status:SetText(POINT_BLANK_SNIPER_L_STATUS_MESSAGE:format(self.scanCount, self.currentBatch, FormatTime(self.scanTime)))
  end
end

function PointBlankSniperTabFrameMixin:UpdateStatusMessageStopped()
  if self.scanTime < 0 then
    self.Status:SetText(POINT_BLANK_SNIPER_L_STATUS_MESSAGE_STOPPED_NO_TIME:format(self.scanCount))
  else
    self.Status:SetText(POINT_BLANK_SNIPER_L_STATUS_MESSAGE_STOPPED:format(self.scanCount, FormatTime(self.scanTime)))
  end
end

local function ChangeCheck(config, newValue)
  local oldValue = PointBlankSniper.Config.Get(config)
  if oldValue ~= newValue then
    PointBlankSniper.Config.Set(config, newValue)
    return true
  end
  return false
end

local function FlippingSignature()
  local options = PointBlankSniper.Config.Options
  return tostring(PointBlankSniper.Config.Get(options.FLIPPING)) .. ":" .. tostring(PointBlankSniper.Config.Get(options.FLIPPING_PERCENT)) .. ":" .. tostring(PointBlankSniper.Config.Get(options.FLIPPING_DAILY_SOLD)) .. ":" .. tostring(PointBlankSniper.Config.Get(options.FLIPPING_MAX_SPEND))
end

function PointBlankSniperTabFrameMixin:UpdateConfigs()
  if ChangeCheck(PointBlankSniper.Config.Options.CURRENT_LIST, self.ListName:GetValue()) then
    self:Stop()
  end

  if ChangeCheck(PointBlankSniper.Config.Options.PRICE_SOURCE, self.PriceSource:GetValue()) then
    PointBlankSniper.Config.Set(PointBlankSniper.Config.Options.WAS_PRICE_SOURCE_CHANGED, true)
    self:Stop()
  end

  local percentage = tonumber(self.Percentage:GetText())
  if percentage ~= nil and percentage >= 0 and ChangeCheck(PointBlankSniper.Config.Options.PERCENTAGE, percentage / 100) then
    self:Stop()
  end

  if ChangeCheck(PointBlankSniper.Config.Options.ITEM_CLASS, self.FilterKeySelector:GetValue()) then
    self:Stop()
  end

  if ChangeCheck(PointBlankSniper.Config.Options.SCAN_MODE, self.ScanMode:GetValue()) then
    self:Stop()
  end
end

function PointBlankSniperTabFrameMixin:OnShow()
  -- Companion versions that dock the listing still use the upstream -110
  -- offset. Restore room for this fork's controls when the tab is shown.
  self.ResultsListing:ClearAllPoints()
  self.ResultsListing:SetPoint("TOPLEFT", self, "TOPLEFT", 20, -185)
  self.ResultsListing:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -320, 27)
  self:RefreshFlippingControls()
  self.flippingSignature = FlippingSignature()
  self:UpdateShoppingListNames()
  if PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.KEYS_SEARCH) then
    Auctionator.EventBus:Fire(self, PointBlankSniper.Events.SetupKeysSearch)
  end
  self:UpdateStartButton()
  if self.StartButton:IsEnabled() then
    self:Start()
  end
end

function PointBlankSniperTabFrameMixin:RefreshFlippingControls()
  local config, options = PointBlankSniper.Config, PointBlankSniper.Config.Options
  self.RapidFlipping:SetChecked(config.Get(options.FLIPPING))
  self.RapidFlippingLabel:SetText(config.Get(options.FLIPPING) and POINT_BLANK_SNIPER_L_RAPID_FLIPPING_ON or POINT_BLANK_SNIPER_L_RAPID_FLIPPING_OFF)
  self.RapidPercent:SetText(config.Get(options.FLIPPING_PERCENT))
  self.RapidSold:SetText(config.Get(options.FLIPPING_DAILY_SOLD))
  self.RapidSpend:SetText(config.Get(options.FLIPPING_MAX_SPEND) / 10000)
  self.RapidKey:SetText(config.Get(options.RAPID_BUY_KEY))
end

function PointBlankSniperTabFrameMixin:SaveFlippingControls()
  if self.Buy.pendingAuctionID or self.Buy.buyCommodity then
    self:RefreshFlippingControls()
    return
  end
  local config, options = PointBlankSniper.Config, PointBlankSniper.Config.Options
  local previousSignature = FlippingSignature()
  local percent, sold, spend = tonumber(self.RapidPercent:GetText()), tonumber(self.RapidSold:GetText()), tonumber(self.RapidSpend:GetText())
  if not percent or percent < 0 or percent >= math.huge or not sold or sold < 0 or sold >= math.huge or not spend or spend < 0 or spend >= 100000000000 then
    self:RefreshFlippingControls()
    return
  end
  config.Set(options.FLIPPING, not not self.RapidFlipping:GetChecked())
  config.Set(options.FLIPPING_PERCENT, percent)
  config.Set(options.FLIPPING_DAILY_SOLD, sold)
  config.Set(options.FLIPPING_MAX_SPEND, math.floor(spend * 10000))
  config.Set(options.RAPID_BUY_KEY, string.upper((self.RapidKey:GetText():gsub("%s+", ""))))
  self.RapidFlippingLabel:SetText(config.Get(options.FLIPPING) and POINT_BLANK_SNIPER_L_RAPID_FLIPPING_ON or POINT_BLANK_SNIPER_L_RAPID_FLIPPING_OFF)
  local signature = FlippingSignature()
  if signature ~= previousSignature then
    self:Stop()
    self.DataProvider:Reset()
    self.Alert:Reset()
    self.Buy:Hide()
    PointBlankSniper.PriceCheck.Flipping.NewPass()
    self.flippingSignature = signature
    if self:IsShown() and self.StartButton:IsEnabled() then self:Start() end
  end
  if self.Buy:IsShown() then self.Buy:ApplyRapidBinding() end
end

function PointBlankSniperTabFrameMixin:AdvancePurchased(itemKey)
  local key = Auctionator.Utilities.ItemKeyString(itemKey)
  local results = self.DataProvider.results or {}
  for index, result in ipairs(results) do
    if Auctionator.Utilities.ItemKeyString(result.itemKey) == key then
      table.remove(results, index)
      self.DataProvider:SetDirty()
      local nextResult = results[index]
      if nextResult then
        Auctionator.EventBus:Fire(self, PointBlankSniper.Events.OpenBuyView, {
          itemKey = nextResult.itemKey, price = nextResult.minPrice,
          quantity = nextResult.totalQuantity, comparisonPrice = nextResult.comparisonPrice,
          flippingManualMax = nextResult.flippingManualMax, rawSearchTermInfo = nextResult.rawSearchTermInfo,
        })
      else
        self.Buy:Hide()
        self.Status:SetText(POINT_BLANK_SNIPER_L_RAPID_COMPLETE)
      end
      return
    end
  end
  self.Buy:Hide()
  self.Status:SetText(POINT_BLANK_SNIPER_L_RAPID_COMPLETE)
end

function PointBlankSniperTabFrameMixin:OnHide()
  Auctionator.EventBus:Fire(self, PointBlankSniper.Events.MergeKeys)
  self:Hide()
end

function PointBlankSniperTabFrameMixin:StartButtonClicked()
  self.DataProvider:Reset()
  self.Alert:Reset()
  self:Start()
end

function PointBlankSniperTabFrameMixin:Start()
  self.ScannerKeyCache:Stop()
  self.ScannerNameCache:Stop()

  if PointBlankSniper.PriceCheck.Flipping.Enabled() then
    if not PointBlankSniper.PriceCheck.Flipping.Available() then
      self.Status:SetText(POINT_BLANK_SNIPER_L_FLIPPING_TSM_MISSING)
      PointBlankSniper.Utilities.Message(POINT_BLANK_SNIPER_L_FLIPPING_TSM_MISSING)
      return
    end
    PointBlankSniper.PriceCheck.Flipping.NewPass()
  end

  if PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.SCAN_MODE) == PointBlankSniper.Constants.ScanModes.Blank then
    self.Scanner = self.ScannerNameCache
    self.Scanner:SetThresholdCheck(nil)
  elseif PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.SCAN_MODE) == PointBlankSniper.Constants.ScanModes.Keys then
    self.Scanner = self.ScannerKeyCache
    self.Scanner:SetKeyFilter(nil)
  elseif PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.SCAN_MODE) == PointBlankSniper.Constants.ScanModes.NoGear then
    self.Scanner = self.ScannerKeyCache
    self.Scanner:SetKeyFilter(function(itemKey)
      return not PointBlankSniper.Utilities.IsGear(itemKey.itemID)
    end)
  elseif PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.SCAN_MODE) == PointBlankSniper.Constants.ScanModes.Threshold then
    self.Scanner = self.ScannerNameCache
    self.Scanner:SetThresholdCheck(function(value)
      return value > 100
    end)
  end

  self.Scanner:SetPriceCheck(PointBlankSniper.PriceCheck.Get())
  self.Scanner:SetCategories(self.FilterKeySelector:GetValue())
  self.Scanner:SetList(PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.CURRENT_LIST))
  if self.Scanner:GotAnyTerms() then
    self.Scanner:Start()
  end
end

function PointBlankSniperTabFrameMixin:OnUpdate()
  local signature = FlippingSignature()
  if self.flippingSignature and self.flippingSignature ~= signature then
    self:Stop()
    self.DataProvider:Reset()
    self.Buy:Hide()
    PointBlankSniper.PriceCheck.Flipping.NewPass()
    self:RefreshFlippingControls()
  end
  self.flippingSignature = signature
  self:UpdateConfigs()
  self:UpdateKeysSearchDialog()
  self:UpdateStartButton()
end

function PointBlankSniperTabFrameMixin:Stop()
  self.ScannerKeyCache:Stop()
  self.ScannerNameCache:Stop()

  self:UpdateStatusMessageStopped()
end

function PointBlankSniperTabFrameMixin:ReceiveEvent(eventName, ...)
  if eventName == PointBlankSniper.Events.SnipeSearchStart then
    self.currentBatch = 1
    self.scanCount = self.scanCount + 1
    self.scanStartTime = debugprofilestop()
    self:UpdateStatusMessageOngoing()
  elseif eventName == PointBlankSniper.Events.SnipeSearchNewResults then
    self.currentBatch = self.currentBatch + 1
    self:UpdateStatusMessageOngoing()
    if not PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.CARRY_ON_AFTER_RESULT) and self.Alert:AnyItemsFound() then
      self.Scanner:Stop()

      local results = ...
      Auctionator.EventBus:Fire(self, PointBlankSniper.Events.OpenBuyView, {
        itemKey = results[1].itemKey,
        price = results[1].minPrice,
        quantity = results[1].totalQuantity,
        comparisonPrice = results[1].comparisonPrice,
        flippingManualMax = results[1].flippingManualMax,
        rawSearchTermInfo = results[1].rawSearchTermInfo
      })
    end
  elseif eventName == PointBlankSniper.Events.SnipeSearchComplete then
    self.scanTime = debugprofilestop() - self.scanStartTime
    self:UpdateStatusMessageOngoing()
    if PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.CARRY_ON_AFTER_RESULT) or not self.Alert:AnyItemsFound() then
      self.Scanner:Start()
    else
      self:Stop()
      if not PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.CARRY_ON_AFTER_RESULT) and self.Alert:AnyItemsFound() then
        local results = ...
        Auctionator.EventBus:Fire(self, PointBlankSniper.Events.OpenBuyView, {
          itemKey = results[1].itemKey,
          price = results[1].minPrice,
          quantity = results[1].totalQuantity,
          comparisonPrice = results[1].comparisonPrice,
          flippingManualMax = results[1].flippingManualMax,
          rawSearchTermInfo = results[1].rawSearchTermInfo
        })
      end
    end
  elseif eventName == PointBlankSniper.Events.QuickStart then
    self:Start()
  elseif eventName == PointBlankSniper.Events.OpenBuyView then
    self:Stop()
  end
end

function PointBlankSniperTabFrameMixin:OpenOptions()
  Settings.OpenToCategory(PointBlankSniper.SettingsCategory:GetID())
end

function PointBlankSniperTabFrameMixin:EnableKeysSearch()
  PointBlankSniper.Config.Set(PointBlankSniper.Config.Options.KEYS_SEARCH, true)
  self.KeysSearchDialog:Hide()
  Auctionator.EventBus:Fire(self, PointBlankSniper.Events.SetupKeysSearch)
end

function PointBlankSniperTabFrameMixin:UpdateKeysSearchDialog()
  self.KeysSearchDialog:SetShown((self.ScanMode:GetValue() == PointBlankSniper.Constants.ScanModes.Keys or self.ScanMode:GetValue() == PointBlankSniper.Constants.ScanModes.NoGear) and PointBlankSniper.ItemKeyCache.State.orderedKeys == nil)
end
