--[[
	【金幣商店與數據自癒系統】玩家存檔與屬性商店 (PlayerDataStore)
	功能：
	1. 支援 DataStoreService 進行玩家存檔保存（金幣、最高通關關卡、商城屬性級別）。
	2. 提供金幣商店 Server 驗證端 (RemoteFunction "BuyShopItem")。
	3. 初始化與套用玩家屬性（PVE套用升級、PVP重置公平屬性）。
	4. 提供 `GetPlayerProgression` 遠端函數，返回已解鎖的 10 個 PVE 關卡。
	5. 提供 `RequestPVEMatch` 遠端事件，安全接收客戶端進入 PVE 關卡請求。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestRetry = Remotes:WaitForChild("RequestRetry")
local ShowLoseUI = Remotes:WaitForChild("ShowLoseUI")

-- 確保商城購買遠端函式存在
local BuyShopItem = Remotes:FindFirstChild("BuyShopItem")
if not BuyShopItem then
	BuyShopItem = Instance.new("RemoteFunction")
	BuyShopItem.Name = "BuyShopItem"
	BuyShopItem.Parent = Remotes
end

-- 確保選關與進度遠端存在
local GetPlayerProgression = Remotes:FindFirstChild("GetPlayerProgression")
if not GetPlayerProgression then
	GetPlayerProgression = Instance.new("RemoteFunction")
	GetPlayerProgression.Name = "GetPlayerProgression"
	GetPlayerProgression.Parent = Remotes
end

local RequestPVEMatch = Remotes:FindFirstChild("RequestPVEMatch")
if not RequestPVEMatch then
	RequestPVEMatch = Instance.new("RemoteEvent")
	RequestPVEMatch.Name = "RequestPVEMatch"
	RequestPVEMatch.Parent = Remotes
end

local ReturnToLobby = Remotes:FindFirstChild("ReturnToLobby")
if not ReturnToLobby then
	ReturnToLobby = Instance.new("RemoteEvent")
	ReturnToLobby.Name = "ReturnToLobby"
	ReturnToLobby.Parent = Remotes
end

local ServerRebuildArena = Remotes:FindFirstChild("ServerRebuildArena")
if not ServerRebuildArena then
	ServerRebuildArena = Instance.new("BindableEvent")
	ServerRebuildArena.Name = "ServerRebuildArena"
	ServerRebuildArena.Parent = Remotes
end

-- DataStore 資料庫名稱
local MathBomberDataStore = nil
pcall(function()
	MathBomberDataStore = DataStoreService:GetDataStore("MathBomberStore_v2")
end)

-- 伺服器本地快照，防斷線與頻繁呼叫
local playerSnapshots = {}

-- 預設屬性模版
local DEFAULT_DATA = {
	MaxHP = 50,             -- 預設生命值 50 HP (5顆心)
	BombRange = 3,          -- 預設炸彈範圍 3 格
	Speed = 16,             -- 預設走路速度 16
	MaxBombs = 1,           -- 預設最多放置 1 顆炸彈
	HighestClearedLevel = 0,-- 預設最高通關關卡為 0 (第一關未打過)
	Gold = 0,               -- 預設金幣為 0
}

-- ==================== 屬性載入與套用 ====================
local function applyPlayerAttributes(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then return end
	local userId = player.UserId
	
	-- 判斷是否在大廳
	local inLobby = player:GetAttribute("InLobby")
	if inLobby == nil then
		player:SetAttribute("InLobby", true)
		inLobby = true
	end

	if inLobby then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
		
		-- 賦予大廳安全護盾
		local ff = char:FindFirstChild("LobbyForceField")
		if not ff then
			ff = Instance.new("ForceField")
			ff.Name = "LobbyForceField"
			ff.Parent = char
		end
		print(("[PlayerDataStore] %s 目前在大廳中，WalkSpeed 鎖定為 0，已賦予無敵護盾"):format(player.Name))
		return
	else
		-- 離開大廳，移除無敵護盾
		local ff = char:FindFirstChild("LobbyForceField")
		if ff then ff:Destroy() end
	end

	-- 讀取當前關卡
	local lvl = workspace:GetAttribute("CurrentLevel") or 1
	if lvl == 4 then
		-- PVP 競技場：所有人初始屬性完全重置，確保絕對公平競爭！
		hum.MaxHealth = 50
		hum.Health = 50
		hum.WalkSpeed = 16
		char:SetAttribute("BombRange", 3)
		char:SetAttribute("MaxBombs", 1)
		player:SetAttribute("HighestClearedLevel", playerSnapshots[userId] and playerSnapshots[userId].HighestClearedLevel or 0)
		print(("[PlayerDataStore] ⚔️ PVP 模式公平重置：%s 的初始屬性已歸一。生命: 50, 範圍: 3, 速度: 16, 炸彈上限: 1"):format(player.Name))
		return
	end

	local data = playerSnapshots[userId] or DEFAULT_DATA
	playerSnapshots[userId] = data

	-- 1. 生命上限與當前生命
	hum.MaxHealth = data.MaxHP
	hum.Health = data.MaxHP
	
	-- 2. 走路速度 (原預設 16)
	hum.WalkSpeed = data.Speed
	
	-- 3. 屬性載入
	char:SetAttribute("BombRange", data.BombRange)
	char:SetAttribute("MaxBombs", data.MaxBombs or 1)
	player:SetAttribute("HighestClearedLevel", data.HighestClearedLevel or 0)

	print(("[PlayerDataStore] 成功套用屬性給玩家 %s。生命上限: %d, 炸彈範圍: %d, 速度: %d, 炸彈上限: %d"):format(
		player.Name, data.MaxHP, data.BombRange, data.Speed, data.MaxBombs or 1
	))
end

-- ==================== 讀取存檔 ====================
local function loadData(player: Player)
	local userId = player.UserId
	local key = "Player_" .. userId
	local data = nil

	if MathBomberDataStore then
		local success, result = pcall(function()
			return MathBomberDataStore:GetAsync(key)
		end)
		if success and typeof(result) == "table" then
			data = result
			print("[PlayerDataStore] 💾 成功自雲端載入玩家存檔:", player.Name)
		else
			warn("[PlayerDataStore] 雲端讀取存檔失敗或無存檔，使用預設值。錯誤:", tostring(result))
		end
	else
		print("[PlayerDataStore] ⚠️ DataStore 未啟用/不支援，使用本地記憶體暫存數據。")
	end

	-- 填補缺少欄位
	if not data then
		data = {}
	end
	for k, v in pairs(DEFAULT_DATA) do
		if data[k] == nil then
			data[k] = v
		end
	end

	playerSnapshots[userId] = data
	player:SetAttribute("HighestClearedLevel", data.HighestClearedLevel)

	-- 設置 Leaderstats 金幣（立即初始化以徹底消除同步與競態 Bug）
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local gold = stats:FindFirstChild("Gold") :: IntValue?
	if not gold then
		gold = Instance.new("IntValue")
		gold.Name = "Gold"
		gold.Value = data.Gold or 0
		gold.Parent = stats
	else
		gold.Value = data.Gold or 0
	end

	-- 監聽金幣改變以同步
	gold.Changed:Connect(function(newVal)
		if playerSnapshots[userId] then
			playerSnapshots[userId].Gold = newVal
		end
	end)
end

-- ==================== 儲存存檔 ====================
local function saveData(player: Player)
	local userId = player.UserId
	local key = "Player_" .. userId
	local data = playerSnapshots[userId]

	if not data then return end

	-- 更新最新金幣數
	local stats = player:FindFirstChild("leaderstats")
	local gold = stats and stats:FindFirstChild("Gold") :: IntValue?
	if gold then
		data.Gold = gold.Value
	end

	if MathBomberDataStore then
		local success, result = pcall(function()
			MathBomberDataStore:SetAsync(key, data)
		end)
		if success then
			print("[PlayerDataStore] 💾 成功將玩家存檔同步儲存至雲端:", player.Name)
		else
			warn("[PlayerDataStore] 雲端存檔失敗！錯誤:", tostring(result))
		end
	end
end

-- ==================== 商店購買服務 ====================
BuyShopItem.OnServerInvoke = function(player: Player, itemType: string): (boolean, string)
	local char = player.Character
	if not char then return false, "找不到角色" end
	
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return false, "找不到 Humanoid" end

	local stats = player:FindFirstChild("leaderstats")
	local gold = stats and stats:FindFirstChild("Gold") :: IntValue?
	if not gold then return false, "金幣系統加載錯誤" end

	local userId = player.UserId
	local data = playerSnapshots[userId] or DEFAULT_DATA
	playerSnapshots[userId] = data

	if itemType == "MaxHP" then
		local cost = 150
		if gold.Value < cost then return false, "金幣不足 150 Gold！" end
		if data.MaxHP >= 150 then return false, "生命上限已達最大極限 (150 HP / 15 顆心)！" end
		
		gold.Value -= cost
		data.MaxHP += 10
		playerSnapshots[userId] = data
		applyPlayerAttributes(player, char)
		return true, "成功升級生命上限！已提升至 " .. data.MaxHP .. " HP"
		
	elseif itemType == "BombRange" then
		local cost = 100
		if gold.Value < cost then return false, "金幣不足 100 Gold！" end
		if data.BombRange >= 8 then return false, "炸彈爆炸範圍已達最遠極限 (8格)！" end

		gold.Value -= cost
		data.BombRange += 1
		playerSnapshots[userId] = data
		applyPlayerAttributes(player, char)
		return true, "成功升級炸彈爆炸範圍！已擴大至 " .. data.BombRange .. " 格"

	elseif itemType == "WalkSpeed" then
		local cost = 80
		if gold.Value < cost then return false, "金幣不足 80 Gold！" end
		if data.Speed >= 22 then return false, "玩家走路速度已達最快極限 (22)！" end

		gold.Value -= cost
		data.Speed += 2
		playerSnapshots[userId] = data
		applyPlayerAttributes(player, char)
		return true, "成功升級移動速度！速度提升至 " .. data.Speed

	else
		return false, "商品不存在"
	end
end

-- ==================== 選關與進度查詢服務 ====================
GetPlayerProgression.OnServerInvoke = function(player: Player): any
	local userId = player.UserId
	local data = playerSnapshots[userId] or DEFAULT_DATA
	local highest = data.HighestClearedLevel or 0

	local unlocked = {}
	-- 第一關默認解鎖
	unlocked["Map1"] = true
	-- 關卡 i 解鎖條件為：最高通關關卡 >= i - 1
	for i = 2, 30 do
		if highest >= i - 1 then
			unlocked["Map" .. i] = true
		else
			unlocked["Map" .. i] = false
		end
	end

	return unlocked
end

RequestPVEMatch.OnServerEvent:Connect(function(player: Player, mapKey: string)
	local userId = player.UserId
	local data = playerSnapshots[userId] or DEFAULT_DATA
	local highest = data.HighestClearedLevel or 0

	-- 驗證關卡名稱
	local mapIndexStr = string.match(mapKey, "Map(%d+)")
	if not mapIndexStr then return end
	local mapIndex = tonumber(mapIndexStr)
	if not mapIndex then return end

	-- 驗證是否解鎖
	local isUnlocked = (mapIndex == 1) or (highest >= mapIndex - 1)
	if isUnlocked then
		print(("[PlayerDataStore] 🟢 驗證成功！玩家 %s 解鎖了關卡: %s，正在為其建置..."):format(player.Name, mapKey))
		workspace:SetAttribute("CurrentLevel", mapIndex)
		
		-- 離開大廳狀態
		player:SetAttribute("InLobby", false)
		if player.Character then
			applyPlayerAttributes(player, player.Character)
		end
		
		-- 重新整理地圖 (使用 Server-side BindableEvent 重新建置地圖)
		if ServerRebuildArena then
			ServerRebuildArena:Fire(player)
		end
	else
		warn(("[PlayerDataStore] 🚨 玩家 %s 企圖越級訪問未解鎖關卡 %s！最高通關關卡: %d"):format(player.Name, mapKey, highest))
	end
end)

ReturnToLobby.OnServerEvent:Connect(function(player: Player)
	print(("[PlayerDataStore] 🚪 玩家 %s 請求返回大廳，重置其大廳鎖定狀態。"):format(player.Name))
	player:SetAttribute("InLobby", true)
	if _G.StopPVESuddenDeath then
		_G.StopPVESuddenDeath()
	end
	if player.Character then
		applyPlayerAttributes(player, player.Character)
		-- 隱藏並傳送玩家到大廳隱藏點
		local LOBBY_HIDE_CFRAME = CFrame.new(0, -250, 0)
		player.Character:PivotTo(LOBBY_HIDE_CFRAME)
	end
end)

-- ==================== 重生與登入初始化 ====================
local function onCharacterAdded(character: Model)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		applyPlayerAttributes(player, character)

		local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.Died:Connect(function()
				local lvl = workspace:GetAttribute("CurrentLevel") or 1
				local inLobby = player:GetAttribute("InLobby")
				if lvl ~= 4 and not inLobby then
					print(("[PlayerDataStore] 💀 玩家 %s 在 PVE 關卡 %d 中死亡！正在觸發 ShowLoseUI"):format(player.Name, lvl))
					task.delay(1, function()
						if ShowLoseUI then
							ShowLoseUI:FireClient(player)
						end
					end)
				end
			end)
		end
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute("InLobby", true)
	-- 先載入數據，再連接 CharacterAdded 避免屬性快照為空
	loadData(player)

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayerAdded(p)
end

-- 監聽地圖重建事件，確保屬性即時更新/重置為公平 PVP
local MapRebuilt = Remotes:WaitForChild("MapRebuilt", 10) :: BindableEvent?
if MapRebuilt then
	MapRebuilt.Event:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				applyPlayerAttributes(player, player.Character)
			end
		end
	end)
end

-- 暴露全域函數供 BossGameManager 調用
_G.SetHighestClearedLevel = function(player: Player, lvl: number)
	local userId = player.UserId
	local data = playerSnapshots[userId] or DEFAULT_DATA
	data.HighestClearedLevel = math.max(data.HighestClearedLevel or 0, lvl)
	playerSnapshots[userId] = data
	player:SetAttribute("HighestClearedLevel", data.HighestClearedLevel)
	print(("[PlayerDataStore] 🏆 玩家 %s 更新最高通關關卡為 %d"):format(player.Name, data.HighestClearedLevel))
	
	-- 自動保存數據，避免進度遺失
	saveData(player)
end

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	playerSnapshots[player.UserId] = nil
end)

-- 當伺服器關閉時保存所有在線玩家數據
game:BindToClose(function()
	print("[PlayerDataStore] 🚧 伺服器關閉中，正在強制備份保存所有玩家存檔...")
	for _, player in ipairs(Players:GetPlayers()) do
		saveData(player)
	end
end)

print("[PlayerDataStore] 金幣商城、DataStore 雲端存檔與選關安全服務已完美啟動。")
