--[[
  從 ServerStorage/TSAImages 匯出「僅 ID」（不含正確檔名）
  用於：保留昨晚 Bulk Import 的 Asset ID，但無法自動對名稱時

  輸出兩種格式：
  1. rbxassetid 清單（160 行）
  2. JSON 陣列（貼到 data/tsa-raw-ids.json 手動對照）

  若要名稱+ID 一次到位，請用 01_ImportLocalTSA_BuildMap.luau
]]

print("=== 匯出 TSAImages 內所有 Decal ID ===")

local HttpService = game:GetService("HttpService")
local folder = game.ServerStorage:FindFirstChild("TSAImages")

if not folder then
	warn("找不到 ServerStorage/TSAImages")
	return
end

local ids = {}

for _, inst in ipairs(folder:GetChildren()) do
	if inst:IsA("Decal") or inst:IsA("Texture") then
		local tex = inst.Texture
		local id = tex and (tex:match("rbxassetid://(%d+)") or tex:match("^(%d+)$"))
		if id then
			table.insert(ids, {
				explorerIndex = #ids + 1,
				instanceName = inst.Name,
				assetId = id,
				fullName = inst:GetFullName(),
			})
		end
	end
end

table.sort(ids, function(a, b)
	return a.assetId < b.assetId
end)

print(("共 %d 個 ID"):format(#ids))
print(string.rep("-", 40))
print("-- 格式 1：僅 ID（可搜尋 Asset Manager 對照）--")
for _, row in ipairs(ids) do
	print("rbxassetid://" .. row.assetId)
end

print(string.rep("-", 40))
print("-- 格式 2：JSON（存成 data/tsa-raw-ids.json）--")
local json = HttpService:JSONEncode(ids)
print(json)
print(string.rep("-", 40))
print("=== 完成 ===")
