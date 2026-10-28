-- One field, with independent values for the upstream and flipping modes.
CreateFromMixins = function(mixin) local result = {}; for k, v in pairs(mixin) do result[k] = v end; return result end
AuctionatorKeyBindingConfigMixin = {}
PointBlankSniper = {Config = {Options = {FLIPPING = "mode", FLIPPING_PERCENT = "flip", PERCENTAGE = "original", FLIPPING_DAILY_SOLD = "sold", FLIPPING_MAX_SPEND = "max"}}, PriceCheck = {Flipping = {NewPass = function() end}}}
local values = {mode = false, flip = 40, original = 0.25, sold = 0.02, max = 800000}
PointBlankSniper.Config.Get = function(key) return values[key] end
PointBlankSniper.Config.Set = function(key, value) values[key] = value end
POINT_BLANK_SNIPER_L_FLIPPING_PERCENT_LABEL = "Region sale avg %:"
POINT_BLANK_SNIPER_L_PERCENTAGE_COLON = "Percentage:"
POINT_BLANK_SNIPER_L_RAPID_FLIPPING_ON = "ON"
POINT_BLANK_SNIPER_L_RAPID_FLIPPING_OFF = "OFF"
dofile("Source/Tab/Main.lua")
local function field(value)
  return {value = value, GetText = function(self) return tostring(self.value) end, SetText = function(self, v) self.value = v end}
end
local toggle = {checked = false, GetChecked = function(self) return self.checked end}
local tab = setmetatable({
  Percentage = field(25), PercentageLabel = field(""), RapidFlipping = toggle,
  RapidFlippingLabel = field(""), RapidSold = field(0.02), RapidSpend = field(80),
  Buy = {Hide = function() end, IsShown = function() return false end},
  DataProvider = {Reset = function() end}, Alert = {Reset = function() end},
  Stop = function() end, IsShown = function() return false end,
}, {__index = PointBlankSniperTabFrameMixin})
tab:RefreshPercentage()
assert(tab.Percentage.value == 25)
toggle.checked = true
tab:SaveFlippingControls()
assert(values.mode and values.flip == 40 and values.original == 0.25 and tab.Percentage.value == 40)
tab.Percentage.value = "35.5"
tab:SavePercentage()
assert(values.flip == 35.5 and values.original == 0.25)
toggle.checked = false
tab:SaveFlippingControls()
assert(not values.mode and values.flip == 35.5 and tab.Percentage.value == 25)
toggle.checked = true
tab:SaveFlippingControls()
assert(values.flip == 35.5 and tab.Percentage.value == 35.5)
print("percentage mode switching: OK")
