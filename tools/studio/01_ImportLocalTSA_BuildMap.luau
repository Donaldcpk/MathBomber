--[[
  【推薦】一次取得 160 個「檔名 + rbxassetid」
  用法：Roblox Studio → View → Command Bar → 貼上整段 → Enter

  步驟：
  1. 執行後選 初中題庫/TSA/2024TSA 資料夾內全部 PNG → 開啟
  2. 再執行一次，選 2025TSA 資料夾內全部 PNG → 開啟
  3. 從 Output 複製全部行，存成 data/tsa-image-ids-paste.txt
  4. 在 Mac 終端機執行：
     node tools/parse-tsa-output.mjs data/tsa-image-ids-paste.txt
     node tools/patch-question-database-tsa.mjs

  注意：會上傳新資產（可能與 Asset Manager 舊 ID 不同）。
  若要用昨晚 Bulk Import 的 ID，請改用 02_ExportDecalIdsOnly.luau + 手動對照。
]]

print("=== TSA 本地匯入：建立名稱↔ID 對照表 ===")

local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")

local function extractId(tex)
	if typeof(tex) ~= "string" then return nil end
	return tex:match("rbxassetid://(%d+)") or tex:match("^(%d+)$")
end

local function getIdFromImportItem(item)
	if type(item) ~= "table" then return nil, nil end

	local name = item.Name or item.name or item.FileName or item.fileName
	if typeof(name) == "string" then
		name = name:gsub("%.png$", ""):gsub("%.PNG$", "")
	end

	local id = item.AssetId or item.assetId or item.Id or item.id
	if id then
		return name, tostring(id)
	end

	local inst = item.CreatedInstance
	if inst then
		name = name or inst.Name
		if inst:IsA("Decal") or inst:IsA("Texture") then
			id = extractId(inst.Texture)
		elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			id = extractId(inst.Image)
		end
		return name, id
	end

	return name, nil
end

local ok, results = pcall(function()
	return AssetService:PromptImportFilesAsync()
end)

if not ok or not results or #results == 0 then
	warn("已取消或未選取檔案")
	return
end

local map = {}
local folder = game.ServerStorage:FindFirstChild("TSAImageMap")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "TSAImageMap"
	folder.Parent = game.ServerStorage
end

-- 合併既有 ModuleScript 內容（若已跑過 2024，再跑 2025 會累加）
local mod = folder:FindFirstChild("TSAImageIds")
if not mod then
	mod = Instance.new("ModuleScript")
	mod.Name = "TSAImageIds"
	mod.Parent = folder
end

local existing = {}
if mod.Source and mod.Source ~= "" then
	local fn = loadstring(mod.Source)
	if fn then
		local tab = fn()
		if type(tab) == "table" then
			for k, v in pairs(tab) do
				existing[k] = v
			end
		end
	end
end

print(string.rep("-", 40))

for _, item in ipairs(results) do
	local name, id = getIdFromImportItem(item)
	if name and id then
		existing[name] = id
		map[name] = id
		print(("%s:rbxassetid://%s"):format(name, id))
	else
		warn("略過無法解析的項目：", item)
	end
end

-- 寫入 ModuleScript（遊戲內可直接 require）
local lines = { "return {" }
local names = {}
for n in pairs(existing) do
	table.insert(names, n)
end
table.sort(names, function(a, b)
	local y1, q1 = a:match("TSA(%d+)Q(%d+)")
	local y2, q2 = b:match("TSA(%d+)Q(%d+)")
	y1, q1 = tonumber(y1) or 9999, tonumber(q1) or 9999
	y2, q2 = tonumber(y2) or 9999, tonumber(q2) or 9999
	if y1 ~= y2 then return y1 < y2 end
	return q1 < q2
end)

for _, n in ipairs(names) do
	table.insert(lines, ('\t["%s"] = "%s",'):format(n, existing[n]))
end
table.insert(lines, "}")
mod.Source = table.concat(lines, "\n")

print(string.rep("-", 40))
print(("本次新增 %d 筆，ModuleScript 累計 %d 筆"):format(
	#results,
	#names
))
print("已寫入 ServerStorage/TSAImageMap/TSAImageIds")
print("請將 Output 全部複製到：data/tsa-image-ids-paste.txt")
print("然後在 Mac 執行：node tools/parse-tsa-output.mjs data/tsa-image-ids-paste.txt")
print("=== 完成 ===")
