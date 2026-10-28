-- Run from the repository root with Lua 5.1 or a compatible interpreter.
PointBlankSniper = {PriceCheck = {}, Config = {Options = {
  FLIPPING = "enabled", FLIPPING_PERCENT = "percent", FLIPPING_DAILY_SOLD = "sold", FLIPPING_MAX_SPEND = "budget"
}}}
local config = {enabled = true, percent = 40, sold = 0.02, budget = 0}
PointBlankSniper.Config.Get = function(key) return config[key] end
SlashCmdList = {}
local values = {dbregionsaleavg = 10000000, dbregionsoldperday = 0.03}
local lastIdentity
TSM_API = {GetCustomPriceValue = function(source, identity)
  lastIdentity = identity
  if source == "dbregionsoldperday * 1000000" then
    return values.dbregionsoldperday and math.floor(values.dbregionsoldperday * 1000000 + 0.5)
  end
  return values[source]
end}
dofile("Source/PriceCheck/Flipping.lua")
local F = PointBlankSniper.PriceCheck.Flipping
local item = {itemID = 42, battlePetSpeciesID = 0}
local function check(price, manual) return F.Evaluate(item, price, manual, true) end
assert(check(3900000))
assert(check(4000000))
assert(not check(4000001))
assert(not check(3500000, 3000000))
config.budget = 800000
assert(check(800000))
assert(not check(800001))
assert(not check(3910000))
config.budget = 0
values.dbregionsoldperday = 0.02
assert(not check(100))
values.dbregionsoldperday = 0.021
assert(check(100))
values.dbregionsoldperday = nil
assert(not check(100))
values.dbregionsoldperday = 5.328
assert(check(100))
values.dbregionsaleavg = 0
assert(not check(100))
values.dbregionsaleavg = 10000000
assert(not check(0))
local pet = {itemID = 82800, battlePetSpeciesID = 123}
assert(F.Evaluate(pet, 100, nil, true))
assert(lastIdentity == "p:123")
TSM_API = nil
assert(not check(100))
-- The resolver must keep one key and the strictest manual limit when terms overlap.
PointBlankSniper.Scan = {}
PointBlankSniper.ItemKeyCache = {State = {orderedKeys = {
  names = {"recipe"}, itemKeyStrings = {{"42 0 0 0"}}
}}}
PointBlankSniper.Utilities = {
  GetStartingIndex = function() return 1 end,
  IsBlacklistedID = function() return false end,
  ItemKeyStringToItemKey = function() return item end,
}
dofile("Source/Scan/GetItemKeys.lua")
local keys, limits = PointBlankSniper.Scan.GetItemKeys({
  {searchString = "recipe", price = 500, rawSearchTerm = "broad"},
  {searchString = "recipe", price = 300, rawSearchTerm = "strict"},
  {searchString = "recipe", rawSearchTerm = "no limit"},
})
assert(#keys == 1 and limits["42 0 0 0"] == 300)
local tiers = {{unitPrice = 100, quantity = 3}, {unitPrice = 200, quantity = 4}, {unitPrice = 401, quantity = 5}}
local plan = F.PlanCommodities(tiers, 400)
assert(plan.quantity == 7 and plan.total == 1100 and plan.maxUnitPrice == 200)
plan = F.PlanCommodities(tiers, 150)
assert(plan.quantity == 3 and plan.total == 300)
assert(F.PlanCommodities({{unitPrice = 200, quantity = 1}, {unitPrice = 100, quantity = 1}}, 400) == nil)
assert(F.PlanCommodities({{unitPrice = 100, quantity = -1}}, 400) == nil)
local quotePlan = {quantity = 2, total = 600}
assert(not F.ValidateCommodityQuote(quotePlan, 400, 1000, 300, 600)) -- average can hide a 500-copper unit
assert(F.ValidateCommodityQuote({quantity = 1, total = 400}, 400, 1000, 400, 400))
assert(not F.ValidateCommodityQuote({quantity = 1, total = 500}, 400, 1000, 401, 401))
assert(not F.ValidateCommodityQuote({quantity = 1, total = 400}, 400, 100, 350, 350))
assert(not F.ValidateCommodityQuote({quantity = 1, total = 300}, 400, 1000, 301, 301))
assert(not F.ValidateCommodityQuote({quantity = 0, total = 300}, 400, 1000, 300, 300))
print("flipping evaluator: OK")
