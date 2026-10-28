-- Verify the same missing-data and strict liquidity rule in both scanners.
PointBlankSniper = {PriceCheck = {}, Scan = {}, Utilities = {}, Config = {Options = {FLIPPING = "enabled", FLIPPING_PERCENT = "percent", FLIPPING_DAILY_SOLD = "sold", FLIPPING_MAX_SPEND = "budget"}}}
local config = {enabled = true, percent = 40, sold = 0.02, budget = 0}
PointBlankSniper.Config.Get = function(key) return config[key] end
SlashCmdList = {}
TSM_API = {GetCustomPriceValue = function(source, item)
  if source == "dbregionsaleavg" then return 1000 end
  if source == "dbregionsoldperday * 1000000" then
    return ({["i:1"] = nil, ["i:2"] = 19000, ["i:3"] = 30000})[item]
  end
end}
Auctionator = {Utilities = {ItemKeyString = function(key) return tostring(key.itemID) end}}
Enum = {AuctionHouseSortOrder = {Price = 0, Name = 1}}
PointBlankSniper.Utilities.CleanItemKey = function(key) return key end
PointBlankSniper.Utilities.GetStartingIndex = function() return 1 end
PointBlankSniper.Utilities.IsBlacklistedID = function() return false end
tIndexOf = function(t, target) for i, v in ipairs(t) do if v == target then return i end end end
dofile("Source/PriceCheck/Flipping.lua")
dofile("Source/Scan/KeyCache.lua")
dofile("Source/Scan/NameCache.lua")
local function result(id) return {itemKey = {itemID = id, battlePetSpeciesID = 0}, minPrice = 300} end
local keyScanner = setmetatable({results = {}, keysToPrice = {}, keysToRaw = {}, listName = "test"}, {__index = PointBlankSniperListScannerKeyCacheMixin})
keyScanner:ScanItemKeyResults({result(1), result(2), result(3)})
assert(#keyScanner.results == 1 and keyScanner.results[1].itemKey.itemID == 3)
local blankScanner = setmetatable({results = {}, listName = "test", searchFor = {{searchString = "recipe", rawSearchTerm = "recipe"}}}, {__index = PointBlankSniperListScannerNameCacheMixin})
blankScanner:DoShoppingListSearch({cache = {result(1), result(2), result(3)}, names = {"recipe", "recipe", "recipe"}})
assert(#blankScanner.results == 1 and blankScanner.results[1].itemKey.itemID == 3)
config.budget = 200
keyScanner.results = {}
keyScanner:ScanItemKeyResults({result(3)})
blankScanner.results = {}
blankScanner:DoShoppingListSearch({cache = {result(3)}, names = {"recipe"}})
assert(#keyScanner.results == 0 and #blankScanner.results == 0)
print("scanner flipping filters: OK")
