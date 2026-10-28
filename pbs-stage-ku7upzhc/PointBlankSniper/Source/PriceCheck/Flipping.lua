-- TSM's regional data describes an item/species, not an individual auction.
PointBlankSniper.PriceCheck.Flipping = {}
local Flipping = PointBlankSniper.PriceCheck.Flipping

local function finite(value)
  return type(value) == "number" and value == value and value < math.huge and value > -math.huge
end

function Flipping.Enabled()
  return PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.FLIPPING)
end

function Flipping.Available()
  return TSM_API and type(TSM_API.GetCustomPriceValue) == "function"
end

function Flipping.NewPass()
  Flipping.cache = {}
  Flipping.reasons = {}
end

function Flipping.Evaluate(itemKey, price, manualMax, fresh)
  if not Flipping.Available() then return false, "tsm_unavailable" end
  if not itemKey or not itemKey.itemID then return false, "invalid_item" end
  local species = itemKey.battlePetSpeciesID or 0
  local identity = species > 0 and ("p:" .. species) or ("i:" .. itemKey.itemID)
  Flipping.cache = Flipping.cache or {}
  local data = not fresh and Flipping.cache[identity]
  if not data then
    local okPrice, reference = pcall(TSM_API.GetCustomPriceValue, "dbregionsaleavg", identity)
    -- TSM rounds custom-string results to integers, including value sources.
    -- Scale before evaluation to retain six decimal places of sold/day.
    local okSold, soldScaled = pcall(TSM_API.GetCustomPriceValue, "dbregionsoldperday * 1000000", identity)
    data = {reference = okPrice and reference or nil, sold = okSold and type(soldScaled) == "number" and soldScaled / 1000000 or nil}
    Flipping.cache[identity] = data
  end
  local percent = PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.FLIPPING_PERCENT)
  local minimum = PointBlankSniper.Config.Get(PointBlankSniper.Config.Options.FLIPPING_DAILY_SOLD)
  if not finite(percent) or percent < 0 or not finite(minimum) or minimum < 0 then return false, "invalid_config" end
  if not finite(data.reference) or data.reference <= 0 then return false, "missing_reference" end
  if not finite(data.sold) or data.sold < 0 then return false, "missing_sold" end
  if data.sold <= minimum then return false, "liquidity" end
  local maximum = data.reference * percent / 100
  if manualMax ~= nil then
    if not finite(manualMax) or manualMax < 0 then return false, "invalid_manual_price" end
    maximum = math.min(maximum, manualMax)
  end
  if price ~= nil and (not finite(price) or price <= 0 or price > maximum) then return false, "price" end
  return true, nil, maximum, data.reference, data.sold, price and price / data.reference
end

function Flipping.Check(itemKey, price, manualMax)
  local ok, reason, maximum, reference, sold, fraction = Flipping.Evaluate(itemKey, price, manualMax)
  if not ok then
    Flipping.reasons = Flipping.reasons or {}
    Flipping.reasons[reason] = (Flipping.reasons[reason] or 0) + 1
  end
  return ok, reason, maximum, reference, sold, fraction
end

-- Results are sorted by unit price. Reject incomplete or malformed input; do
-- not infer a purchasable quantity from a partial page of results.
function Flipping.PlanCommodities(results, maximum, budget)
  if not finite(maximum) or maximum <= 0 or not finite(budget) or budget < 0 then return nil, "invalid_limit" end
  local quantity, total, lastPrice, highestSelected = 0, 0, 0, 0
  for _, result in ipairs(results) do
    local price, count = result.unitPrice, result.quantity
    if not finite(price) or price <= 0 or price < lastPrice or not finite(count) or count <= 0 or count ~= math.floor(count) then
      return nil, "invalid_results"
    end
    lastPrice = price
    if price > maximum then break end
    if budget > 0 then count = math.min(count, math.floor((budget - total) / price)) end
    if count > 0 then highestSelected = price end
    quantity = quantity + count
    total = total + price * count
    if budget > 0 and total + price > budget then break end
  end
  return {quantity = quantity, total = total, maxUnitPrice = highestSelected}
end

-- A quote contains a total and a unit price, not the price of each unit.
-- Treating the quoted unit price as the maximum tranche price is unsafe: it
-- may be an average. All auction prices are positive whole copper, so the
-- smallest possible total containing a unit above floor(maximum) is
-- floor(maximum) + quantity. Only totals below that bound prove every unit is
-- within the limit without making assumptions about other addons or stale
-- search results. This intentionally rejects many otherwise valid quotes.
function Flipping.ValidateCommodityQuote(plan, maximum, budget, money, unitPrice, totalPrice)
  if type(plan) ~= "table" or not finite(plan.quantity) or plan.quantity <= 0 or plan.quantity ~= math.floor(plan.quantity)
      or not finite(plan.total) or plan.total <= 0 or not finite(maximum) or maximum <= 0
      or not finite(budget) or budget < 0 or not finite(money) or money < 0
      or not finite(unitPrice) or unitPrice <= 0 or not finite(totalPrice) or totalPrice <= 0
      or totalPrice ~= math.floor(totalPrice) then
    return false, "invalid_quote"
  end
  if totalPrice > plan.total or totalPrice > money or (budget > 0 and totalPrice > budget) then
    return false, "total_exceeded"
  end
  if totalPrice >= math.floor(maximum) + plan.quantity then
    return false, "unit_limit_unverifiable"
  end
  return true
end

SLASH_POINTBLANKFLIP1 = "/pbsflip"
SlashCmdList.POINTBLANKFLIP = function()
  if not Flipping.reasons or not next(Flipping.reasons) then
    print("Point Blank Sniper: TSM Flipping: no exclusions recorded.")
    return
  end
  for reason, count in pairs(Flipping.reasons) do
    print("Point Blank Sniper: " .. reason .. ": " .. count)
  end
end
