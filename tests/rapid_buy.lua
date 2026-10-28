-- Run independently with Lua 5.1. No game APIs or purchases are invoked.
PointBlankSniper = {Events = {OpenBuyView = "open", SnipeSearchStart = "start"}, Config = {Options = {FLIPPING_MAX_SPEND = "budget"}, Get = function() return 100 end}, PriceCheck = {Flipping = {Enabled = function() return true end, Evaluate = function(_, price) return price and price <= 100 end}}}
Auctionator = {EventBus = {}, Utilities = {ItemKeyString = function(key) return tostring(key.itemID) end}}
StaticPopupDialogs = {}
GetMoney = function() return 100000 end
POINT_BLANK_SNIPER_L_BUYING = "Buying"
POINT_BLANK_SNIPER_L_RAPID_ERROR = "Error"
DynamicResizeButton_Resize = function() end
local calls, advanced = 0, 0
C_AuctionHouse = {PlaceBid = function() calls = calls + 1 end}
dofile("Source/Buy/Main.lua")
local button = {enabled = true, IsEnabled = function(self) return self.enabled end, Disable = function(self) self.enabled = false end, SetEnabled = function(self, value) self.enabled = not not value end, SetText = function() end}
local parent = {AdvancePurchased = function(_, itemKey) assert(itemKey.itemID == 42); advanced = advanced + 1 end}
local buy = setmetatable({BuyButton = button, info = {isCommodity = false}, resultInfo = {auctionID = 100, buyoutAmount = 300, quantity = 3}, expectedPrice = 100, expectedItemKey = {itemID = 42}, IsShown = function() return true end, GetParent = function() return parent end}, {__index = PointBlankSniperBuyFrameMixin})
buy:BuyNow()
buy:BuyNow()
buy:SkipResult()
assert(calls == 1 and buy.pendingAuctionID == 100)
buy:OnEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 999)
assert(advanced == 0 and buy.pendingAuctionID == 100)
buy:OnEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 100)
assert(advanced == 1 and buy.pendingAuctionID == nil)
buy:OnEvent("AUCTION_HOUSE_PURCHASE_COMPLETED", 100)
assert(advanced == 1)
local fired
Auctionator.EventBus.Fire = function(_, _, event, details) fired = {event = event, details = details} end
AuctionatorKeyBindingConfigMixin = {
  SetShortcut = function(self, key) self.shortcut = key end,
  StartListening = function(self) self.isListening = true end,
  StopListening = function(self) self.isListening = false end,
}
CreateFromMixins = function(mixin)
  local copy = {}
  for k, v in pairs(mixin) do copy[k] = v end
  return copy
end
dofile("Source/Tab/Main.lua")
local keySaved, cleared, applied
PointBlankSniper.Config.Options.RAPID_BUY_KEY = "key"
PointBlankSniper.Config.Options.RAPID_SKIP_KEY = "skip"
local keys = {key = "", skip = ""}
PointBlankSniper.Config.Get = function(name) return keys[name] end
PointBlankSniper.Config.Set = function(name, value) keys[name] = value; keySaved = value end
local conflict = false
PointBlankSniper.Utilities = {Message = function() conflict = true end}
POINT_BLANK_SNIPER_L_RAPID_KEY_CONFLICT = "Conflict"
InCombatLockdown = function() return false end
ClearOverrideBindings = function() cleared = true end
local captureBuy = {IsShown = function() return true end, ApplyRapidBinding = function() applied = true end}
local capture = setmetatable({bindingOption = "RAPID_BUY_KEY", GetParent = function() return {Buy = captureBuy} end}, {__index = PointBlankSniperRapidKeyMixin})
capture:StartListening()
assert(capture.isListening and cleared)
capture:SetShortcut("CTRL-MOUSEWHEELUP")
capture:StopListening()
assert(keySaved == "CTRL-MOUSEWHEELUP" and applied and not capture.isListening)
local skip = setmetatable({bindingOption = "RAPID_SKIP_KEY", GetParent = function() return {Buy = captureBuy} end}, {__index = PointBlankSniperRapidKeyMixin})
skip:StartListening()
skip:SetShortcut("CTRL-MOUSEWHEELUP")
assert(conflict and keys.skip == "")
skip:SetShortcut("CTRL-MOUSEWHEELDOWN")
skip:StopListening()
assert(keys.skip == "CTRL-MOUSEWHEELDOWN")
local bound = {}
SetOverrideBindingClick = function(_, _, key, target) bound[key] = target end
buy:ApplyRapidBinding()
assert(bound["CTRL-MOUSEWHEELUP"] == "PointBlankSniperRapidBuyButton")
assert(bound["CTRL-MOUSEWHEELDOWN"] == "PointBlankSniperRapidSkipButton")
captureBuy.pendingAuctionID = 1
capture:StartListening()
assert(not capture.isListening)
local entries = {
  {itemKey = {itemID = 10}, minPrice = 50},
  {itemKey = {itemID = 42}, minPrice = 75},
  {itemKey = {itemID = 90}, minPrice = 90},
}
local tab = setmetatable({DataProvider = {results = entries, SetDirty = function() end}}, {__index = PointBlankSniperTabFrameMixin})
tab:AdvancePurchased({itemID = 42})
assert(#entries == 2 and fired.event == "open" and fired.details.itemKey.itemID == 90)
local debugMessages = {}
PointBlankSniper.Config.Options.DEBUG_FAKE_BUY = "fake"
PointBlankSniper.Config.Get = function(name) return name == "fake" end
PointBlankSniper.Utilities.Message = function(message) table.insert(debugMessages, message) end
POINT_BLANK_SNIPER_L_DEBUG_BUY_MESSAGE = "[DEBUG] BUY %s %d"
POINT_BLANK_SNIPER_L_DEBUG_SKIP_MESSAGE = "[DEBUG] SKIP %s %d"
POINT_BLANK_SNIPER_L_DEBUG_BUY_BUTTON = "Simulate Buy"
buy.pendingAuctionID = nil
buy.info = {isCommodity = false, itemName = "Example"}
buy.resultInfo = {auctionID = 101, buyoutAmount = 300, quantity = 3}
button.enabled = true
buy:BuyNow()
assert(calls == 1 and advanced == 2 and #debugMessages == 1)
buy.info = {isCommodity = true, itemName = "Example"}
buy.resultInfo = nil
buy.commodityPlan = {quantity = 3, maxUnitPrice = 100, total = 300}
buy.gotResult = true
buy:UpdateBuyState()
assert(button.enabled)
buy:BuyNow()
assert(calls == 1 and advanced == 3 and #debugMessages == 2)
buy:SkipResult()
assert(advanced == 4 and #debugMessages == 3 and debugMessages[3]:find("SKIP"))
local cancelled, confirmed = 0, 0
C_AuctionHouse.CancelCommoditiesPurchase = function() cancelled = cancelled + 1 end
C_AuctionHouse.ConfirmCommoditiesPurchase = function() confirmed = confirmed + 1 end
buy.buyCommodity = true
buy.resultInfo = {unitPrice = 100, quantity = 3}
buy:OnEvent("COMMODITY_PRICE_UPDATED", 100, 300)
assert(cancelled == 1 and confirmed == 0)
print("rapid buy state: OK")
