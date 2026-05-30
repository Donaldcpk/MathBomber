--[[
	【遊戲打磨與機制優化版】炸彈放置、十字引爆、地面十字預警投影、特殊方塊與史萊姆小怪系統
	功能：
	1. 支援地面十字高亮預警投影 (Task 5)：放置炸彈時，於地面生成十字發光軌跡，直觀呈現爆炸範圍，完全消除 75 度視角錯覺。
	2. 特殊方塊 (Task 3)：
	   - 普通木箱：1次炸毀，25%機率掉金幣。
	   - 鐵礦箱：需炸 2 次。第一次會變為鐵鏽裂紋色。
	   - 炸藥桶：被爆炸波及立刻連鎖引爆，引燃周圍一格。
	3. 小怪巡邏系統 (Task 3)：隨關卡難度遞增小怪數量（Level 1: 0, Level 2: 2, Level 3: 4），接觸扣血。
	4. 答題無敵狀態 (Task 2)：玩家在 AnsweringQuiz 屬性為 true 時，100% 免疫爆炸自傷與小怪碰撞傷害。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

-- ==================== 輔助函式：確保資料夾存在 ====================
local function ensureFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f :: Folder
end

-- 確保 PVE_Arena 存在（自癒與健壯性優化，使用 WaitForChild 避免 startup race condition）
local arena = workspace:WaitForChild("PVE_Arena", 10)
if not arena then
	warn("[BomberGameManager] 未在 Workspace 找到 PVE_Arena，正在啟動自癒機制建立...")
	arena = Instance.new("Folder")
	arena.Name = "PVE_Arena"
	arena.Parent = workspace
end

local gridFolder = arena:WaitForChild("Grid", 5)
if not gridFolder then
	gridFolder = ensureFolder(arena, "Grid")
end

local bombsFolder = arena:WaitForChild("Bombs", 5)
if not bombsFolder then
	bombsFolder = ensureFolder(arena, "Bombs")
end

local coinsFolder = arena:FindFirstChild("Coins")
if not coinsFolder then
	coinsFolder = ensureFolder(arena, "Coins")
end

local bossModel = arena:WaitForChild("TSABoss", 5)
if not bossModel then
	warn("[BomberGameManager] 未在 PVE_Arena 中找到 TSABoss，啟動自癒建立預設 Boss...")
	bossModel = Instance.new("Model")
	bossModel.Name = "TSABoss"
	bossModel.Parent = arena

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(4, 6, 4)
	root.Position = Vector3.new(0, 3, -12)
	root.Color = Color3.fromRGB(180, 40, 40)
	root.Anchored = false
	root.CanCollide = true
	root.Parent = bossModel

	local hum = Instance.new("Humanoid")
	hum.Name = "Humanoid"
	hum.MaxHealth = 150
	hum.Health = 150
	hum.WalkSpeed = 4
	hum.Parent = bossModel

	bossModel.PrimaryPart = root
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local function ensureRemoteEvent(name: string): RemoteEvent
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r :: RemoteEvent
end

local PlaceBomb = ensureRemoteEvent("PlaceBomb")
local RequestNextLevel = ensureRemoteEvent("RequestNextLevel")
local RequestRetry = ensureRemoteEvent("RequestRetry")

local BossBombHit = Remotes:FindFirstChild("BossBombHit") :: BindableEvent?
if not BossBombHit then
	BossBombHit = Instance.new("BindableEvent")
	BossBombHit.Name = "BossBombHit"
	BossBombHit.Parent = Remotes
end

local MapRebuilt = Remotes:FindFirstChild("MapRebuilt") :: BindableEvent?
if not MapRebuilt then
	MapRebuilt = Instance.new("BindableEvent")
	MapRebuilt.Name = "MapRebuilt"
	MapRebuilt.Parent = Remotes
end

local ServerRebuildArena = Remotes:FindFirstChild("ServerRebuildArena") :: BindableEvent?
if not ServerRebuildArena then
	ServerRebuildArena = Instance.new("BindableEvent")
	ServerRebuildArena.Name = "ServerRebuildArena"
	ServerRebuildArena.Parent = Remotes
end

local function getLobbyHighestClearedLevel()
	local maxLvl = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local lvl = player:GetAttribute("HighestClearedLevel") or 0
		if lvl > maxLvl then
			maxLvl = lvl
		end
	end
	return maxLvl
end

local CELL = 4
local MAP_MIN_X = -37
local MAP_MAX_X = 37
local MAP_MIN_Z = -25
local MAP_MAX_Z = 24

-- 炸彈設定
local BOMB_TIMER = 2.6
local EXPLOSION_LIFETIME = 0.8

-- ==================== 網格坐標轉換 ====================

local function gridToWorld(gx: number, gz: number): Vector3
	return Vector3.new(gx * CELL, 1.5, gz * CELL)
end

local function worldToGrid(pos: Vector3): (number, number)
	local gx = math.round(pos.X / CELL)
	local gz = math.round(pos.Z / CELL)
	return gx, gz
end

-- ==================== 地面十字高亮預警投影 (Task 5) ====================

local function createBombProjections(bomb: Part, bgx: number, bgz: number, range: number)
	-- 生成中心指示
	local centerProj = Instance.new("Part")
	centerProj.Name = "BombRangeProjection"
	centerProj.Size = Vector3.new(CELL - 0.4, 0.05, CELL - 0.4)
	centerProj.Position = gridToWorld(bgx, bgz) + Vector3.new(0, -1.45, 0) -- 貼在平地上
	centerProj.Anchored = true
	centerProj.CanCollide = false
	centerProj.Color = Color3.fromRGB(255, 70, 70)
	centerProj.Material = Enum.Material.Neon
	centerProj.Transparency = 0.75
	centerProj.Parent = bomb

	local directions = {
		Vector3.new(1, 0, 0),   -- 東
		Vector3.new(-1, 0, 0),  -- 西
		Vector3.new(0, 0, 1),   -- 南
		Vector3.new(0, 0, -1)   -- 北
	}

	for _, dir in ipairs(directions) do
		for step = 1, range do
			local tx = bgx + dir.X * step
			local tz = bgz + dir.Z * step

			-- 邊界檢測
			if tx < MAP_MIN_X or tx > MAP_MAX_X or tz < MAP_MIN_Z or tz > MAP_MAX_Z then break end

			-- 偵測碰撞
			local checkPos = gridToWorld(tx, tz)
			local blocked = false
			local hitPart = nil :: Instance?

			for _, child in ipairs(gridFolder:GetChildren()) do
				if child:IsA("BasePart") then
					local cx, cz = worldToGrid(child.Position)
					if cx == tx and cz == tz then
						blocked = true
						hitPart = child
						break
					end
				end
			end

			-- 硬牆阻擋：直接停止投影
			if hitPart and hitPart.Name == "HardWall" then
				break
			end

			-- 建立單格預警投影
			local proj = Instance.new("Part")
			proj.Name = "BombRangeProjection"
			proj.Size = Vector3.new(CELL - 0.4, 0.05, CELL - 0.4)
			proj.Position = checkPos + Vector3.new(0, -1.45, 0)
			proj.Anchored = true
			proj.CanCollide = false
			proj.Color = Color3.fromRGB(255, 100, 30)
			proj.Material = Enum.Material.Neon
			proj.Transparency = 0.78
			proj.Parent = bomb

			-- 如果碰到了木箱、鐵箱、TNT，投影只畫在箱子格上，並阻擋後續投影
			if blocked then
				break
			end
		end
	end
end

-- ==================== 網格地圖生成與特殊方塊 (Task 3) ====================

local COIN_REWARD = 50

local function getPlayerFromHit(hit: Instance): (Player?, Model?)
	local current = hit
	while current and current ~= workspace do
		if current:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(current)
			if player then
				return player, current
			end
		end
		current = current.Parent
	end
	return nil, nil
end

local function spawnGoldCoin(position: Vector3)
	local coin = Instance.new("Part")
	coin.Name = "GoldCoin"
	coin.Size = Vector3.new(1.5, 1.5, 1.5)
	coin.Shape = Enum.PartType.Ball
	coin.Color = Color3.fromRGB(255, 215, 0)
	coin.Material = Enum.Material.Glass
	coin.Position = position + Vector3.new(0, 0.5, 0)
	coin.CanCollide = false
	coin.CanTouch = true
	coin.Anchored = true
	coin.Parent = coinsFolder

	local touchedConn: RBXScriptConnection?
	touchedConn = coin.Touched:Connect(function(hit)
		local touchPlayer, character = getPlayerFromHit(hit)
		if not touchPlayer or not character then
			return
		end

		if touchedConn then
			touchedConn:Disconnect()
			touchedConn = nil
		end
		coin:Destroy()

		local leaderstats = touchPlayer:FindFirstChild("leaderstats")
		local gold = leaderstats and leaderstats:FindFirstChild("Gold")
		if gold and gold:IsA("IntValue") then
			gold.Value += COIN_REWARD
		end

		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			local pickSound = Instance.new("Sound")
			pickSound.SoundId = "rbxassetid://9114223161"
			pickSound.Volume = 0.6
			pickSound.Parent = root
			pickSound:Play()
			Debris:AddItem(pickSound, 1)
		end
	end)

	Debris:AddItem(coin, 15)
end

local function spawnPowerup(pos: Vector3)
	local currentLvl = workspace:GetAttribute("CurrentLevel") or 1
	local maxCleared = getLobbyHighestClearedLevel()
	
	local allowedTypes = {}
	if currentLvl ~= 4 then
		-- PVE 模式：默認解鎖所有道具
		table.insert(allowedTypes, "BombRange")
		table.insert(allowedTypes, "MaxBombs")
		table.insert(allowedTypes, "Heart")
	else
		-- PVP 模式：依據玩家最高通關關卡解鎖
		if maxCleared >= 5 then
			table.insert(allowedTypes, "Heart")
		end
		if maxCleared >= 9 then
			table.insert(allowedTypes, "BombRange")
		end
		if maxCleared >= 13 then
			table.insert(allowedTypes, "MaxBombs")
		end
	end
	
	-- 如果沒有任何道具被解鎖，則在 PVP 模式中退而求其次掉落金幣，避免道具落空
	if #allowedTypes == 0 then
		spawnGoldCoin(pos)
		return
	end
	
	-- 隨機選擇已解鎖的道具
	local pType = allowedTypes[math.random(1, #allowedTypes)]
	local color = Color3.new(1, 1, 1)
	local labelText = ""
	
	if pType == "BombRange" then
		color = Color3.fromRGB(255, 100, 30) -- 橘紅色
		labelText = "🔥"
	elseif pType == "MaxBombs" then
		color = Color3.fromRGB(50, 150, 255) -- 藍色
		labelText = "💣"
	elseif pType == "Heart" then
		color = Color3.fromRGB(255, 80, 100) -- 紅色
		labelText = "❤️"
	end
	
	local item = Instance.new("Part")
	item.Name = "Powerup_" .. pType
	item.Size = Vector3.new(2, 2, 2)
	item.Position = pos + Vector3.new(0, 0.5, 0)
	item.Color = color
	item.Material = Enum.Material.Neon
	item.CanCollide = false
	item.CanTouch = true
	item.Anchored = true
	item.Parent = coinsFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(40, 40)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = item

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = labelText
	lbl.TextSize = 22
	lbl.Parent = billboard

	task.spawn(function()
		while item.Parent do
			item.CFrame = item.CFrame * CFrame.Angles(0, math.rad(4), 0)
			task.wait(0.02)
		end
	end)

	local touchedConn: RBXScriptConnection?
	touchedConn = item.Touched:Connect(function(hit)
		local touchPlayer, character = getPlayerFromHit(hit)
		if not touchPlayer or not character then return end

		if touchedConn then touchedConn:Disconnect() touchedConn = nil end
		item:Destroy()

		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			local pickSound = Instance.new("Sound")
			pickSound.SoundId = "rbxassetid://9114223161"
			pickSound.Volume = 0.7
			pickSound.Parent = root
			pickSound:Play()
			Debris:AddItem(pickSound, 1)
		end

		local hum = character:FindFirstChildOfClass("Humanoid")
		if pType == "BombRange" then
			local range = character:GetAttribute("BombRange") or 3
			character:SetAttribute("BombRange", math.min(8, range + 1))
			print("[Powerup] 玩家範圍增加:", character:GetAttribute("BombRange"))
		elseif pType == "MaxBombs" then
			local maxB = character:GetAttribute("MaxBombs") or 1
			character:SetAttribute("MaxBombs", maxB + 1)
			print("[Powerup] 玩家炸彈上限增加:", character:GetAttribute("MaxBombs"))
		elseif pType == "Heart" then
			if hum then
				hum.Health = math.min(hum.MaxHealth, hum.Health + 10)
				print("[Powerup] 玩家恢復生命:", hum.Health)
			end
		end
	end)

	Debris:AddItem(item, 25)
end

local activeEnvironmentalThreads = {}

local function stopAllEnvironmentalThreads()
	for _, t in ipairs(activeEnvironmentalThreads) do
		pcall(function() task.cancel(t) end)
	end
	activeEnvironmentalThreads = {}
end

local function buildArena()
	stopAllEnvironmentalThreads()
	gridFolder:ClearAllChildren()
	bombsFolder:ClearAllChildren()
	coinsFolder:ClearAllChildren()

	local level = workspace:GetAttribute("CurrentLevel") or 1
	local isPVP = (level == 4)
	local mapStyle = 1
	if isPVP then
		mapStyle = workspace:GetAttribute("PVP_MapIndex") or 1
	else
		mapStyle = ((level - 1) % 10) + 1
	end

	print(("[BomberGameManager] 🧱 正在建置 75x50 網格地圖... 模式: %s, 樣式索引: %d"):format(isPVP and "PVP" or "PVE", mapStyle))

	local playerSafeG_X = -30
	local playerSafeG_Z = 20 -- PVE起跑安全點

	local pvpSpawns = {
		Vector3.new(-120, 3, -72),
		Vector3.new(120, 3, 72),
		Vector3.new(-120, 3, 72),
		Vector3.new(120, 3, -72),
	}

	-- 1. 遍歷網格生成牆體與特殊道具
	for gx = MAP_MIN_X, MAP_MAX_X do
		for gz = MAP_MIN_Z, MAP_MAX_Z do
			local isOuter = (gx == MAP_MIN_X) or (gx == MAP_MAX_X) or (gz == MAP_MIN_Z) or (gz == MAP_MAX_Z)
			local isInnerHardWall = (gx % 2 == 0) and (gz % 2 == 0)

			-- PVE & PVP 安全區防護 (不生成石塊、障礙或小怪)
			local isSafeZone = false
			if not isPVP then
				-- PVE 起跑點安全區
				if math.abs(gx - playerSafeG_X) <= 2 and math.abs(gz - playerSafeG_Z) <= 2 then
					isSafeZone = true
				end
				-- PVE Boss 戰中央安全白名單 (0,0) 周圍 2 格
				if math.abs(gx) <= 2 and math.abs(gz) <= 2 then
					isSafeZone = true
				end
			else
				-- PVP 4 個角落玩家出生點安全區
				for _, spawnPos in ipairs(pvpSpawns) do
					local sgx, sgz = math.round(spawnPos.X / CELL), math.round(spawnPos.Z / CELL)
					if math.abs(gx - sgx) <= 2 and math.abs(gz - sgz) <= 2 then
						isSafeZone = true
					end
				end
			end

			if isOuter then
				-- 生成外圍硬牆
				local wall = Instance.new("Part")
				wall.Name = "HardWall"
				wall.Size = Vector3.new(CELL, 5, CELL)
				wall.Position = gridToWorld(gx, gz)
				wall.Anchored = true
				wall.Color = Color3.fromRGB(80, 80, 90)
				wall.Material = Enum.Material.Concrete
				wall.Parent = gridFolder
				CollectionService:AddTag(wall, "IndestructibleWall")
			elseif isInnerHardWall then
				-- 生成內部間隔水泥硬牆
				local wall = Instance.new("Part")
				wall.Name = "HardWall"
				wall.Size = Vector3.new(CELL, 5, CELL)
				wall.Position = gridToWorld(gx, gz)
				wall.Anchored = true
				wall.Color = Color3.fromRGB(100, 100, 110)
				wall.Material = Enum.Material.Concrete
				wall.Parent = gridFolder
				CollectionService:AddTag(wall, "IndestructibleWall")
			elseif not isSafeZone then
				-- 2. 依據地圖風格生成特色障礙與機關
				local spawnedEnv = false

				-- Map 2 Conveyor (傳送帶工廠)
				if mapStyle == 2 or mapStyle == 10 then
					if (gz == -10 or gz == 10 or gx == -15 or gx == 15) and math.random() < 0.25 then
						local conveyor = Instance.new("Part")
						conveyor.Name = "Conveyor"
						conveyor.Size = Vector3.new(CELL - 0.1, 1.0, CELL - 0.1)
						conveyor.Position = gridToWorld(gx, gz) + Vector3.new(0, -0.45, 0)
						conveyor.Color = Color3.fromRGB(255, 170, 0)
						conveyor.Material = Enum.Material.Metal
						conveyor.Anchored = true
						conveyor.AssemblyLinearVelocity = Vector3.new(gz == 10 and 12 or -12, 0, gx == 15 and 12 or -12)
						conveyor.Parent = gridFolder
						CollectionService:AddTag(conveyor, "Conveyor")
						spawnedEnv = true
					end
				end

				-- Map 3 Kaleidoscope (萬花筒折射)
				if (mapStyle == 3 or mapStyle == 10) and not spawnedEnv then
					-- 在特定點生成折射鏡或分光稜鏡
					if (gx == 10 and gz == 10) or (gx == -10 and gz == -10) or (gx == 20 and gz == -12) then
						local mirror = Instance.new("Part")
						mirror.Name = "Mirror_ForwardSlash"
						mirror.Size = Vector3.new(CELL - 0.5, 4.5, CELL - 0.5)
						mirror.Position = gridToWorld(gx, gz)
						mirror.Color = Color3.fromRGB(220, 220, 255)
						mirror.Material = Enum.Material.Glass
						mirror.Transparency = 0.2
						mirror.Anchored = true
						mirror.CFrame = CFrame.new(mirror.Position) * CFrame.Angles(0, math.rad(45), 0)
						mirror.Parent = gridFolder
						CollectionService:AddTag(mirror, "Mirror_ForwardSlash")
						spawnedEnv = true
					elseif (gx == -10 and gz == 10) or (gx == 10 and gz == -10) or (gx == -20 and gz == -12) then
						local mirror = Instance.new("Part")
						mirror.Name = "Mirror_BackSlash"
						mirror.Size = Vector3.new(CELL - 0.5, 4.5, CELL - 0.5)
						mirror.Position = gridToWorld(gx, gz)
						mirror.Color = Color3.fromRGB(220, 220, 255)
						mirror.Material = Enum.Material.Glass
						mirror.Transparency = 0.2
						mirror.Anchored = true
						mirror.CFrame = CFrame.new(mirror.Position) * CFrame.Angles(0, math.rad(-45), 0)
						mirror.Parent = gridFolder
						CollectionService:AddTag(mirror, "Mirror_BackSlash")
						spawnedEnv = true
					elseif (gx == 0 and math.abs(gz) == 8) or (gz == 0 and math.abs(gx) == 8) then
						local splitter = Instance.new("Part")
						splitter.Name = "PrismSplitter"
						splitter.Size = Vector3.new(CELL - 0.5, 4.5, CELL - 0.5)
						splitter.Position = gridToWorld(gx, gz)
						splitter.Color = Color3.fromRGB(0, 200, 255)
						splitter.Material = Enum.Material.Neon
						splitter.Transparency = 0.5
						splitter.Anchored = true
						splitter.Parent = gridFolder
						CollectionService:AddTag(splitter, "PrismSplitter")
						spawnedEnv = true
					end
				end

				-- 隨機產生可破壞箱子 (普通木箱、鐵礦箱、TNT炸藥桶)
				if not spawnedEnv then
					if math.random() < 0.55 then
						local rand = math.random()
						
						-- PVE 等級或 PVP 中玩家解鎖進度
						local levelUnlockTNT = (not isPVP and level >= 3) or (isPVP and getLobbyHighestClearedLevel() >= 11)
						local levelUnlockIron = (not isPVP and level >= 2) or (isPVP and getLobbyHighestClearedLevel() >= 7)

						if levelUnlockTNT and rand < 0.15 then
							-- 1. TNT 炸藥桶
							local tnt = Instance.new("Part")
							tnt.Name = "TNT"
							tnt.Size = Vector3.new(CELL - 0.5, 4.5, CELL - 0.5)
							tnt.Position = gridToWorld(gx, gz)
							tnt.Anchored = true
							tnt.Color = Color3.fromRGB(180, 50, 50)
							tnt.Material = Enum.Material.Wood
							tnt.Parent = gridFolder
							tnt:SetAttribute("Destructible", true)
							tnt:SetAttribute("IsTNT", true)
							CollectionService:AddTag(tnt, "DestructibleBlock")

							local dec = Instance.new("Decal")
							dec.Texture = "rbxassetid://10850239"
							dec.Face = Enum.NormalId.Front
							dec.Parent = tnt
						elseif levelUnlockIron and rand < 0.35 then
							-- 2. 鐵礦箱
							local iron = Instance.new("Part")
							iron.Name = "IronBrick"
							iron.Size = Vector3.new(CELL - 0.5, 4.5, CELL - 0.5)
							iron.Position = gridToWorld(gx, gz)
							iron.Anchored = true
							iron.Color = Color3.fromRGB(150, 150, 160)
							iron.Material = Enum.Material.Metal
							iron.Parent = gridFolder
							iron:SetAttribute("Destructible", true)
							iron:SetAttribute("Hits", 2)
							CollectionService:AddTag(iron, "DestructibleBlock")
						else
							-- 3. 普通木箱
							local box = Instance.new("Part")
							box.Name = "Brick"
							box.Size = Vector3.new(CELL - 0.5, 4.5, CELL - 0.5)
							box.Position = gridToWorld(gx, gz)
							box.Anchored = true
							box.Color = Color3.fromRGB(160, 110, 60)
							box.Material = Enum.Material.Wood
							box.Parent = gridFolder
							box:SetAttribute("Destructible", true)
							CollectionService:AddTag(box, "DestructibleBlock")
						end
					end
				end
			end
		end
	end

	-- 3. 處理玩家起始位置傳送
	if isPVP then
		-- PVP 傳送至 4 角落
		for i, plr in ipairs(Players:GetPlayers()) do
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local pos = pvpSpawns[((i - 1) % #pvpSpawns) + 1]
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				plr.Character:PivotTo(CFrame.new(pos))
			end
		end
	else
		-- PVE 傳送至 (-120, 3, 80)
		local spawnPos = Vector3.new(-120, 3, 80)
		for _, plr in ipairs(Players:GetPlayers()) do
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				plr.Character:PivotTo(CFrame.new(spawnPos))
			end
		end
	end

	-- 4. 啟動特色地圖之環境定時任務 (利用 activeEnvironmentalThreads)
	
	-- Map 4: Patrol Matrix (巡邏矩陣哨兵 Part)
	if mapStyle == 4 or mapStyle == 10 then
		local p1 = Instance.new("Part")
		p1.Name = "SentinelHazard"
		p1.Size = Vector3.new(12, 4.5, 12)
		p1.Color = Color3.fromRGB(220, 40, 40)
		p1.Material = Enum.Material.Neon
		p1.Anchored = true
		p1.CanCollide = false
		p1.Parent = gridFolder

		local thread = task.spawn(function()
			local t = 0
			while p1.Parent do
				task.wait(0.03)
				t += 0.02
				local targetX = math.sin(t) * 100
				p1.Position = Vector3.new(targetX, 2.5, 0)
				
				-- 接觸傷害檢測
				for _, plr in ipairs(Players:GetPlayers()) do
					local char = plr.Character
					local root = char and char:FindFirstChild("HumanoidRootPart")
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if root and hum and hum.Health > 0 then
						if (root.Position - p1.Position).Magnitude < 8 then
							local inLobby = plr:GetAttribute("InLobby")
							local isInvincible = char:GetAttribute("AnsweringQuiz")
							if not inLobby and not isInvincible then
								hum:TakeDamage(20) -- 碰觸扣20滴血
							end
						end
					end
				end
			end
		end)
		table.insert(activeEnvironmentalThreads, thread)
	end

	-- Map 6: Coordinate Blitz Temple (坐報雷擊)
	if mapStyle == 6 or mapStyle == 10 then
		local thread = task.spawn(function()
			task.wait(15) -- 15秒後啟動雷擊
			while true do
				task.wait(10)
				-- 廣播隨機 4 個坐標
				local targets = {}
				for i = 1, 4 do
					local tx = math.random(MAP_MIN_X + 5, MAP_MAX_X - 5)
					local tz = math.random(MAP_MIN_Z + 5, MAP_MAX_Z - 5)
					table.insert(targets, {x = tx, z = tz})
				end
				
				-- 預警效果 (在地面生成紅色預警投影)
				local indicators = {}
				for _, t in ipairs(targets) do
					local ind = Instance.new("Part")
					ind.Size = Vector3.new(12, 0.1, 12)
					ind.Color = Color3.fromRGB(255, 0, 0)
					ind.Material = Enum.Material.Neon
					ind.Transparency = 0.5
					ind.Position = gridToWorld(t.x, t.z) + Vector3.new(0, -1.4, 0)
					ind.Anchored = true
					ind.CanCollide = false
					ind.Parent = gridFolder
					table.insert(indicators, ind)
				end

				task.wait(2) -- 預警2秒

				-- 降落重磅轟炸！
				for _, ind in ipairs(indicators) do
					ind:Destroy()
				end

				for _, t in ipairs(targets) do
					local worldPos = gridToWorld(t.x, t.z)
					-- 播放爆炸特效與雷擊音效
					local exp = Instance.new("Explosion")
					exp.Position = worldPos
					exp.BlastRadius = 12
					exp.BlastPressure = 0 -- 不用物理推力
					exp.Parent = workspace

					-- 傷害判定 (半徑 3 格內 lethal)
					for _, plr in ipairs(Players:GetPlayers()) do
						local char = plr.Character
						local hum = char and char:FindFirstChildOfClass("Humanoid")
						local root = char and char:FindFirstChild("HumanoidRootPart")
						if root and hum and hum.Health > 0 then
							if (root.Position - worldPos).Magnitude < 12 then
								local inLobby = plr:GetAttribute("InLobby")
								local isInvincible = char:GetAttribute("AnsweringQuiz")
								if not inLobby and not isInvincible then
									hum:TakeDamage(50) -- 致命雷擊扣50 HP (滿血秒殺一半)
								end
							end
						end
					end
				end
			end
		end)
		table.insert(activeEnvironmentalThreads, thread)
	end

	print(("[BomberGameManager] 地圖建置完成。樣式: %d"):format(mapStyle))
	if MapRebuilt then
		MapRebuilt:Fire()
	end
end
	if MapRebuilt then
		MapRebuilt:Fire()
	end
end

-- ==================== 史萊姆小怪巡邏 NPC 系統 (Task 3) ====================

local minionsFolder = ensureFolder(arena, "Minions")

local function spawnMinion()
	local minion = Instance.new("Model")
	minion.Name = "SlimeMinion"
	minion.Parent = minionsFolder

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.new(3, 3, 3)
	root.Position = gridToWorld(math.random(-5, 5), math.random(-5, 5))
	root.Color = Color3.fromRGB(100, 220, 100)
	root.Material = Enum.Material.Neon
	root.Transparency = 0.3
	root.Anchored = false
	root.CanCollide = true
	root.Parent = minion

	local hum = Instance.new("Humanoid")
	hum.Name = "Humanoid"
	hum.MaxHealth = 10
	hum.Health = 10
	hum.WalkSpeed = 6
	hum.Parent = minion

	minion.PrimaryPart = root

	-- 智慧隨機漫步 AI
	task.spawn(function()
		while minion.Parent do
			task.wait(math.random(3, 6))
			if not root or not root.Parent then break end
			
			local directions = {
				Vector3.new(CELL, 0, 0),
				Vector3.new(-CELL, 0, 0),
				Vector3.new(0, 0, CELL),
				Vector3.new(0, 0, -CELL)
			}
			local targetDir = directions[math.random(1, #directions)]
			local targetPos = root.Position + targetDir

			-- Raycast 檢測硬牆與木箱，避免卡牆
			local rayDir = targetPos - root.Position
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { gridFolder }
			local hit = workspace:Raycast(root.Position + Vector3.new(0, 0.5, 0), rayDir, params)

			if not hit then
				hum:MoveTo(targetPos)
			end
		end
	end)

	-- 接觸傷害判定 + 答題無敵免疫
	task.spawn(function()
		while minion.Parent do
			task.wait(0.3)
			if not root or not root.Parent then break end

			for _, player in ipairs(Players:GetPlayers()) do
				local char = player.Character
				local playerRoot = char and char:FindFirstChild("HumanoidRootPart")
				local playerHum = char and char:FindFirstChildOfClass("Humanoid")

				if playerRoot and playerHum and playerHum.Health > 0 then
					local dist = (playerRoot.Position - root.Position).Magnitude
					if dist < 3.5 then
						-- 【核心優化】：玩家答題期間，完全免疫小怪碰撞與接觸傷！
						if char:GetAttribute("AnsweringQuiz") then
							continue
						end

						-- 接觸扣 10 血 (1顆心)
						playerHum:TakeDamage(10)
						print("[BomberGameManager] 綠史萊姆咬了玩家 ", player.Name, "！扣除 10 HP")

						-- 彈開
						local dir = (playerRoot.Position - root.Position).Unit * 12
						local vel = Instance.new("LinearVelocity")
						local att = Instance.new("Attachment")
						att.Parent = playerRoot
						vel.Attachment0 = att
						vel.MaxForce = 60000
						vel.VectorVelocity = Vector3.new(dir.X, 4, dir.Z)
						vel.Parent = playerRoot
						Debris:AddItem(vel, 0.2)
						Debris:AddItem(att, 0.2)
					end
				end
			end
		end
	end)
end

local function initMinionsForLevel()
	minionsFolder:ClearAllChildren()
	local level = workspace:GetAttribute("CurrentLevel") or 1
	local mCount = 0
	if level == 4 then
		mCount = 0 -- PVP 模式不孵化任何小怪，純對決！
	elseif level == 2 then
		mCount = 2
	elseif level >= 3 then
		mCount = 4
	end

	print("[BomberGameManager] 👾 正在孵化小怪數量:", mCount)
	for i = 1, mCount do
		spawnMinion()
	end
end


-- ==================== 爆炸與傷害判定系統 ====================

local function blastHitsBossCell(tx: number, tz: number): boolean
	local bossRootPart = bossModel:FindFirstChild("HumanoidRootPart")
	if not bossRootPart then
		return false
	end
	local bx, bz = worldToGrid(bossRootPart.Position)
	return bx == tx and bz == tz
end

local function tryNotifyBossBombHit(owner: Player, tx: number, tz: number, bossHitFlag: { hit: boolean })
	if bossHitFlag.hit or bossModel:GetAttribute("Stunned") == true then
		return
	end

	local center = gridToWorld(tx, tz)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { bossModel }

	local hitBoss = false
	local parts = workspace:GetPartBoundsInBox(
		CFrame.new(center.X, center.Y + 1, center.Z),
		Vector3.new(CELL - 0.5, 5, CELL - 0.5),
		overlapParams
	)
	for _, part in parts do
		if part:IsDescendantOf(bossModel) then
			hitBoss = true
			break
		end
	end

	if not hitBoss then
		hitBoss = blastHitsBossCell(tx, tz)
	end

	if hitBoss and owner then
		bossHitFlag.hit = true
		print("[BomberGameManager] 💥 爆炸命中 Boss！觸發 BossBombHit，玩家:", owner.Name)
		BossBombHit:Fire(owner, bossModel)
	end
end

local function runSingleFlame(owner: Player, tx: number, tz: number, bossHitFlag: { hit: boolean })
	local pos = gridToWorld(tx, tz)

	-- 建立 3D 立體火焰 Part (霓虹十字火焰效果)
	local flame = Instance.new("Part")
	flame.Name = "ExplosionFlame"
	flame.Size = Vector3.new(CELL, 4.5, CELL)
	flame.Position = pos
	flame.Anchored = true
	flame.CanCollide = false
	flame.Color = Color3.fromRGB(255, 110, 0)
	flame.Material = Enum.Material.Neon
	flame.Parent = workspace

	-- 火焰發光煙霧粒子
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 120
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(2, 6)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3.5),
		NumberSequenceKeypoint.new(1, 0)
	})
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 140, 0), Color3.fromRGB(50, 50, 50))
	emitter.Parent = flame

	Debris:AddItem(flame, EXPLOSION_LIFETIME)

	-- 傷害檢測與判定：玩家、小怪、Boss、箱子

	-- 1. 玩家自傷與無敵判定 (Task 2)
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			local px, pz = worldToGrid(root.Position)
			if px == tx and pz == tz then
				-- 【核心優化】：玩家處於答題眩暈期間，免疫爆炸受傷
				if char:GetAttribute("AnsweringQuiz") then
					print("[BomberGameManager] 玩家正在答題，免疫爆炸波及")
				else
					hum:TakeDamage(10) -- 扣除 1 顆心
					print(("[BomberGameManager] 💥 爆炸波及玩家 %s！扣除 HP 10"):format(player.Name))
				end
			end
		end
	end

	-- 1.5. PVP 機器人傷害與受擊判定
	local botsFolder = workspace:FindFirstChild("PVP_Bots")
	if botsFolder then
		for _, bot in ipairs(botsFolder:GetChildren()) do
			local root = bot:FindFirstChild("HumanoidRootPart")
			local hum = bot:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				local bx, bz = worldToGrid(root.Position)
				if bx == tx and bz == tz then
					hum:TakeDamage(10) -- 扣除 10 HP
					print(("[BomberGameManager] 💥 爆炸波及 PVP 機器人 %s！扣除 HP 10"):format(bot.Name))
				end
			end
		end
	end

	-- 2. 史萊姆小怪擊殺（核心優化：使用 3D Overlap 盒偵測，保障 100% 精確受擊與炸死，不受漫步物理位移偏差影響！）
	local slimeList = {}
	for _, m in ipairs(minionsFolder:GetChildren()) do
		table.insert(slimeList, m)
	end
	if #slimeList > 0 then
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Include
		overlapParams.FilterDescendantsInstances = slimeList
		
		local center = gridToWorld(tx, tz)
		local parts = workspace:GetPartBoundsInBox(
			CFrame.new(center.X, center.Y + 1, center.Z),
			Vector3.new(CELL - 0.5, 5, CELL - 0.5),
			overlapParams
		)
		
		local processedMinions = {}
		for _, part in ipairs(parts) do
			local minion = part:FindFirstAncestor("SlimeMinion")
			if minion then
				local mHum = minion:FindFirstChild("Humanoid") :: Humanoid?
				if mHum and mHum.Health > 0 and not processedMinions[minion] then
					processedMinions[minion] = true
					mHum:TakeDamage(100) -- 秒殺
					print("[BomberGameManager] 💥 3D Overlap 炸死史萊姆！發放金幣給:", owner.Name)
					
					-- 給予放炸彈的人 15 Gold
					local stats = owner:FindFirstChild("leaderstats")
					local gold = stats and stats:FindFirstChild("Gold")
					if gold and gold:IsA("IntValue") then
						gold.Value += 15
					end
				end
			end
		end
	end

	-- 3. Boss 眩暈破防（Overlap + 格子雙重判定）
	tryNotifyBossBombHit(owner, tx, tz, bossHitFlag)
end

local detonateExplosion -- 前向宣告以支援遞迴與 PVP 鏈式引爆

-- 十字鏈式爆裂
local function runExplosion(owner: Player, bgx: number, bgz: number, range: number)
	local bossHitFlag = { hit = false }
	local directions = {
		Vector3.new(0, 0, 0),    -- 中心點
		Vector3.new(1, 0, 0),   -- 東
		Vector3.new(-1, 0, 0),  -- 西
		Vector3.new(0, 0, 1),   -- 南
		Vector3.new(0, 0, -1)   -- 北
	}

	-- 播放重低音爆炸聲
	local soundPart = Instance.new("Part")
	soundPart.Position = gridToWorld(bgx, bgz)
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.Transparency = 1
	soundPart.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://580125756" -- 震撼爆炸聲效
	sound.Volume = 0.85
	sound.PlayOnRemove = true
	sound.Parent = soundPart
	soundPart:Destroy()

	for _, dir in ipairs(directions) do
		local steps = (dir == Vector3.new(0, 0, 0)) and 0 or range
		for step = (dir == Vector3.new(0, 0, 0)) and 0 or 1, steps do
			local tx = bgx + dir.X * step
			local tz = bgz + dir.Z * step

			if tx < MAP_MIN_X or tx > MAP_MAX_X or tz < MAP_MIN_Z or tz > MAP_MAX_Z then break end

			-- 0. 偵測是否有其他炸彈，觸發即時連鎖同步引爆
			for _, b in ipairs(bombsFolder:GetChildren()) do
				if b:IsA("BasePart") and b.Parent then
					local bx, bz = worldToGrid(b.Position)
					if bx == tx and bz == tz then
						print("[BomberGameManager] 💥 炸彈連鎖同步引爆！位置:", bx, bz)
						local placerName = b:GetAttribute("Placer")
						local placerPlayer = (typeof(placerName) == "string" and Players:FindFirstChild(placerName)) or owner
						b:Destroy() -- 這會銷毀實體並觸發計時爆炸的 Parent 檢查阻斷
						task.spawn(function()
							task.wait(0.08) -- 0.08秒極微延遲，獲得最震撼的同秒連鎖引爆感
							detonateExplosion(placerPlayer, bx, bz, range)
						end)
					end
				end
			end

			-- 偵測這格是否被硬牆、箱子阻擋
			local blocked = false
			local hitPart = nil :: Instance?

			for _, child in ipairs(gridFolder:GetChildren()) do
				if child:IsA("BasePart") then
					local cx, cz = worldToGrid(child.Position)
					if cx == tx and cz == tz then
						blocked = true
						hitPart = child
						break
					end
				end
			end

			-- 硬牆阻擋：直接阻斷，不放火
			if hitPart and hitPart.Name == "HardWall" then
				break
			end

			-- 生成火焰
			runSingleFlame(owner, tx, tz, bossHitFlag)

			-- 如果碰到的是可破壞箱子
			if blocked and hitPart then
				local destructible = hitPart:GetAttribute("Destructible")
				if destructible then
					local hits = hitPart:GetAttribute("Hits")
					local isTnt = hitPart:GetAttribute("IsTNT")

					if isTnt then
						-- 1. 【TNT 連鎖引爆機制】：
						print("[BomberGameManager] 💥 炸藥桶被引爆！")
						hitPart:Destroy()
						task.spawn(function()
							task.wait(0.15) -- 0.15秒微延遲，極佳的連鎖爆裂視覺感
							detonateExplosion(owner, tx, tz, range)
						end)
					elseif hits and hits > 1 then
						-- 2. 【鐵礦箱減血機制】：
						hitPart:SetAttribute("Hits", hits - 1)
						hitPart.Color = Color3.fromRGB(110, 100, 100) -- 變為暗鐵碎裂裂痕色
						hitPart.Material = Enum.Material.CorrodedMetal
						print("[BomberGameManager] 鐵礦箱血量 -1，剩餘:", hits - 1)
					else
						-- 3. 【普通箱子炸毀機制】：
						hitPart:Destroy()
						
						-- 25% 機率掉金幣，15% 機率掉威力/上限/愛心道具（伺服器 Touched）
						local dropRand = math.random()
						if dropRand < 0.25 then
							spawnGoldCoin(gridToWorld(tx, tz))
						elseif dropRand < 0.40 then
							spawnPowerup(gridToWorld(tx, tz))
						end
					end
				end

				-- 火焰被任何箱子撞上後，該方向的爆波就此被阻斷
				break
			end
		end
	end
end

detonateExplosion = function(owner: Player, gx: number, gz: number, range: number)
	local currentLvl = workspace:GetAttribute("CurrentLevel") or 1
	if currentLvl == 4 then
		local pvpTrigger = Remotes:FindFirstChild("TriggerPVPExplosion") :: BindableFunction?
		if pvpTrigger then
			pvpTrigger:Invoke(gx, gz, range, owner)
		else
			runExplosion(owner, gx, gz, range)
		end
	else
		runExplosion(owner, gx, gz, range)
	end
end

-- ==================== 放置炸彈核心服務 ====================

local function placeBomb(player: Player, gx: number, gz: number)
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	-- 1. 限制座標在網格地圖範圍內
	if gx < MAP_MIN_X or gx > MAP_MAX_X or gz < MAP_MIN_Z or gz > MAP_MAX_Z then
		return
	end

	-- 2. 確保此格目前沒有放置炸彈（防重複堆疊）
	for _, b in ipairs(bombsFolder:GetChildren()) do
		local bx, bz = worldToGrid(b.Position)
		if bx == gx and bz == gz then
			return
		end
	end

	-- 2.5 限制最大放置炸彈數量（預設 1，吃道具增加）
	local maxBombs = char:GetAttribute("MaxBombs") or 1
	local activeCount = 0
	for _, b in ipairs(bombsFolder:GetChildren()) do
		if b:GetAttribute("Placer") == player.Name then
			activeCount += 1
		end
	end
	if activeCount >= maxBombs then
		print("[BomberGameManager] 已達到最大炸彈放置限制:", maxBombs)
		return
	end

	-- 3. 讀取玩家炸彈範圍 (Range)
	local range = char:GetAttribute("BombRange") or 3

	-- 4. 建立炸彈實體（方塊、與牆等高，避免矮台階讓玩家擠上層）
	local bomb = Instance.new("Part")
	bomb.Name = "Bomb"
	bomb.Shape = Enum.PartType.Block
	bomb.Size = Vector3.new(3.8, 4.0, 3.8)
	local bombPos = gridToWorld(gx, gz)
	bomb.Position = Vector3.new(bombPos.X, 2.0, bombPos.Z)
	bomb.Anchored = true
	bomb.CanCollide = false -- 【極致優化：Ghost Bomb機制】初始不可碰撞，防擠上牆與卡位
	bomb.Color = Color3.fromRGB(40, 40, 45)
	bomb.Material = Enum.Material.SmoothPlastic
	bomb:SetAttribute("Placer", player.Name)
	bomb.CustomPhysicalProperties = PhysicalProperties.new(100, 0, 0, 100, 1)
	bomb.Parent = bombsFolder

	-- 當所有重疊的玩家皆踏出炸彈格子（水平距離 > 4.5 studs）後，解鎖實體碰撞
	task.spawn(function()
		while bomb and bomb.Parent do
			local overlapping = false
			for _, p in ipairs(Players:GetPlayers()) do
				local pChar = p.Character
				local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart")
				if pRoot then
					local distXZ = (Vector3.new(pRoot.Position.X, 0, pRoot.Position.Z) - Vector3.new(bomb.Position.X, 0, bomb.Position.Z)).Magnitude
					if distXZ < 4.5 then
						overlapping = true
						break
					end
				end
			end
			if not overlapping then
				bomb.CanCollide = true
				break
			end
			task.wait(0.1)
		end
	end)

	-- 5. 【預警投影優化】：生成地表的十字發光軌跡
	createBombProjections(bomb, gx, gz, range)

	-- 放置嗶嗶聲
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://130113322" -- 放炸彈嗶一聲
	sound.Volume = 0.5
	sound.Parent = bomb
	sound:Play()

	-- 6. 計時爆裂
	task.delay(BOMB_TIMER, function()
		if not bomb.Parent then
			return
		end
		local placerName = bomb:GetAttribute("Placer")
		local placerPlayer = (typeof(placerName) == "string" and Players:FindFirstChild(placerName)) or player
		bomb:Destroy()
		
		local currentLvl = workspace:GetAttribute("CurrentLevel") or 1
		if currentLvl == 4 then
			-- 使用 2.5D 萬花筒 PVP 引爆引擎！
			local pvpTrigger = Remotes:FindFirstChild("TriggerPVPExplosion") :: BindableFunction?
			if pvpTrigger then
				pvpTrigger:Invoke(gx, gz, range, placerPlayer)
			else
				runExplosion(placerPlayer :: Player, gx, gz, range)
			end
		else
			runExplosion(placerPlayer :: Player, gx, gz, range)
		end
	end)
end

-- ==================== 註冊伺服端監聽 ====================

print("[BomberGameManager] PlaceBomb 遠端已綁定，可按 E / 空白鍵放炸彈")

PlaceBomb.OnServerEvent:Connect(function(player: Player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		local gx, gz = worldToGrid(root.Position)
		placeBomb(player, gx, gz)
	end
end)

-- ==================== PVP 多人匹配佇列與地圖交集 ====================

local JoinPVPQueue = ensureRemoteEvent("JoinPVPQueue")
local LeavePVPQueue = ensureRemoteEvent("LeavePVPQueue")
local PVELobbyUpdate = ensureRemoteEvent("PVELobbyUpdate")
local PVPStartMatch = ensureRemoteEvent("PVPStartMatch")

local pvpQueue = {}
local REQUIRED_PLAYERS = 2 -- 最低 2 人開戰
local isMatchStarting = false

local botsFolder = workspace:FindFirstChild("PVP_Bots")
if not botsFolder then
	botsFolder = Instance.new("Folder")
	botsFolder.Name = "PVP_Bots"
	botsFolder.Parent = workspace
end

local queueTimeoutThread = nil

-- 宣告 AI 運作與輔助函式
local function checkCellBlocked(gx: number, gz: number): boolean
	if gx < MAP_MIN_X or gx > MAP_MAX_X or gz < MAP_MIN_Z or gz > MAP_MAX_Z then
		return true
	end
	for _, child in ipairs(gridFolder:GetChildren()) do
		if child:IsA("BasePart") then
			local cx, cz = worldToGrid(child.Position)
			if cx == gx and cz == gz then
				return true
			end
		end
	end
	return false
end

-- 宣告 AI 邏輯與爆縮避讓行為
local function spawnBotAI(botModel: Model, spawnCornerIndex: number)
	local hum = botModel:FindFirstChildOfClass("Humanoid")
	local root = botModel:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end

	local botThread = task.spawn(function()
		local rng = Random.new()
		local bombCooldown = 0

		while botModel.Parent and hum.Health > 0 do
			task.wait(0.2) -- AI 思考間隔 (0.2 秒/次)
			if bombCooldown > 0 then
				bombCooldown -= 0.2
			end

			local bgx, bgz = worldToGrid(root.Position)

			-- 1. 檢測自己是否處於爆炸危害範圍內 (避爆邏輯)
			local endangered = false
			local dangerBombs = {}
			for _, b in ipairs(bombsFolder:GetChildren()) do
				if b:IsA("BasePart") then
					local bx, bz = worldToGrid(b.Position)
					local range = b:GetAttribute("Range") or 3
					-- 如果與炸彈在同一直線上且在爆炸半徑內
					if (bx == bgx and math.abs(bz - bgz) <= range) or (bz == bgz and math.abs(bx - bgx) <= range) then
						endangered = true
						table.insert(dangerBombs, {x = bx, z = bz, r = range})
					end
				end
			end

			if endangered then
				-- 計算逃跑安全網格
				local directions = {
					{x = 1, z = 0}, {x = -1, z = 0}, {x = 0, z = 1}, {x = 0, z = -1}
				}
				local safestNeighbor = nil

				for _, d in ipairs(directions) do
					local nx, nz = bgx + d.x, bgz + d.z
					if not checkCellBlocked(nx, nz) then
						-- 檢查移動到此格是否仍然有危險
						local neighborSafe = true
						for _, db in ipairs(dangerBombs) do
							if (db.x == nx and math.abs(db.z - nz) <= db.r) or (db.z == nz and math.abs(db.x - nx) <= db.r) then
								neighborSafe = false
								break
							end
						end
						if neighborSafe then
							safestNeighbor = {x = nx, z = nz}
							break
						end
					end
				end

				if safestNeighbor then
					-- 朝向安全格子移動
					hum:MoveTo(gridToWorld(safestNeighbor.x, safestNeighbor.z))
				else
					-- 找不到完全安全的鄰格，隨機找無障礙格子
					local escapeDir = directions[rng:NextInteger(1, 4)]
					local nx, nz = bgx + escapeDir.x, bgz + escapeDir.z
					if not checkCellBlocked(nx, nz) then
						hum:MoveTo(gridToWorld(nx, nz))
					end
				end
			else
				-- 2. 安全狀態：決策是否移動或放置炸彈
				local nearbyDestructible = false
				local directions = {
					{x = 1, z = 0}, {x = -1, z = 0}, {x = 0, z = 1}, {x = 0, z = -1}
				}
				for _, d in ipairs(directions) do
					local nx, nz = bgx + d.x, bgz + d.z
					for _, child in ipairs(gridFolder:GetChildren()) do
						if child:IsA("BasePart") and child:GetAttribute("Destructible") == true then
							local cx, cz = worldToGrid(child.Position)
							if cx == nx and cz == nz then
								nearbyDestructible = true
								break
							end
						end
					end
					if nearbyDestructible then break end
				end

				-- 周圍有箱子且炸彈冷卻結束，立即放置炸彈！
				if nearbyDestructible and bombCooldown <= 0 then
					bombCooldown = 5.0 -- 5 秒放置冷卻

					-- 放置伺服器炸彈
					local bPart = Instance.new("Part")
					bPart.Name = "Bomb"
					bPart.Shape = Enum.PartType.Ball
					bPart.Size = Vector3.new(CELL - 0.5, CELL - 0.5, CELL - 0.5)
					bPart.Position = gridToWorld(bgx, bgz)
					bPart.Anchored = true
					bPart.Color = Color3.fromRGB(40, 40, 40)
					bPart.Material = Enum.Material.Metal
					bPart.Parent = bombsFolder

					bPart:SetAttribute("Placer", botModel.Name)
					bPart:SetAttribute("Range", 3)

					-- 建立範圍投影預警
					createBombProjections(bPart, bgx, bgz, 3)

					-- 計時引爆
					task.delay(2.6, function()
						if bPart.Parent then
							bPart:Destroy()
							runExplosion(nil, bgx, bgz, 3)
						end
					end)
				else
					-- 隨機漫步尋找目標
					local moveDirs = {
						{x = 1, z = 0}, {x = -1, z = 0}, {x = 0, z = 1}, {x = 0, z = -1}
					}
					for idx = 1, 4 do
						local rIdx = rng:NextInteger(1, 4)
						moveDirs[idx], moveDirs[rIdx] = moveDirs[rIdx], moveDirs[idx]
					end

					for _, d in ipairs(moveDirs) do
						local nx, nz = bgx + d.x, bgz + d.z
						if not checkCellBlocked(nx, nz) then
							hum:MoveTo(gridToWorld(nx, nz))
							break
						end
					end
				end
			end
		end
	end)
	table.insert(activeEnvironmentalThreads, botThread)
end

-- 時間到自動補齊 PVP Bots 展開對決！
local function startPVPWithBots()
	isMatchStarting = true
	botsFolder:ClearAllChildren()

	local hostPlayer = pvpQueue[1]
	local selectedMapIndex = hostPlayer and hostPlayer:GetAttribute("SelectedPVPMap") or 1
	local mapNames = {
		"經典交叉網格", "傳送帶工廠", "萬花筒折射迷宮", "巡邏哨兵矩陣",
		"算術虛空塌陷", "坐標天雷神殿", "因數诅咒之室", "終端收縮孤島",
		"混沌變數 X 核心", "歐幾里得終極大亂鬥"
	}
	local selectedMapName = "⚔️ PVP [" .. (mapNames[selectedMapIndex] or "經典交叉網格") .. "] ⚔️"

	print(("[PVP Matchmaker] 🤖 時間到！自動補齊 Bots 開始對戰。地圖: %d (%s)"):format(selectedMapIndex, selectedMapName))

	-- 廣播匹配成功
	for _, p in ipairs(pvpQueue) do
		PVPStartMatch:FireClient(p, selectedMapName)
	end

	task.delay(5, function()
		workspace:SetAttribute("PVP_MapIndex", selectedMapIndex)
		workspace:SetAttribute("CurrentLevel", 4)

		for _, p in ipairs(pvpQueue) do
			p:SetAttribute("InLobby", false)
		end

		buildArena()
		initMinionsForLevel()

		local spawnCorners = {
			Vector3.new(-120, 3, -72),
			Vector3.new(120, 3, 72),
			Vector3.new(-120, 3, 72),
			Vector3.new(120, 3, -72),
		}

		-- 傳送玩家
		for i, p in ipairs(pvpQueue) do
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				local cornerPos = spawnCorners[i]
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				char:PivotTo(CFrame.new(cornerPos))
			end
		end

		-- 用 PVP Bots 填補空位置 (最多至 4 位玩家)
		local botIndex = 1
		for i = #pvpQueue + 1, 4 do
			local spawnPos = spawnCorners[i]
			
			local bot = Instance.new("Model")
			bot.Name = "🤖 機器人 " .. botIndex
			bot.Parent = botsFolder

			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Size = Vector3.new(2.5, 4.5, 2.5)
			root.Color = Color3.fromRGB(150, 100, 255)
			root.Material = Enum.Material.Metal
			root.Position = spawnPos
			root.Anchored = false
			root.CanCollide = true
			root.Parent = bot

			local hum = Instance.new("Humanoid")
			hum.Name = "Humanoid"
			hum.MaxHealth = 50
			hum.Health = 50
			hum.WalkSpeed = 14
			hum.Parent = bot

			bot.PrimaryPart = root

			-- 啟動 Bot AI
			spawnBotAI(bot, i)
			botIndex += 1
		end

		pvpQueue = {}
		isMatchStarting = false

		if MapRebuilt then
			MapRebuilt:Fire()
		end
	end)
end

-- 啟動 20 秒匹配倒數
local function startQueueTimeout()
	if queueTimeoutThread then return end

	queueTimeoutThread = task.spawn(function()
		local countdown = 20
		while countdown > 0 do
			task.wait(1)
			if #pvpQueue == 0 or isMatchStarting then
				queueTimeoutThread = nil
				return
			end
			countdown -= 1
			for _, p in ipairs(pvpQueue) do
				PVELobbyUpdate:FireClient(p, #pvpQueue, REQUIRED_PLAYERS, countdown)
			end
		end

		if #pvpQueue >= 1 and not isMatchStarting then
			startPVPWithBots()
		end
		queueTimeoutThread = nil
	end)
end

local function updateLobbyStatus()
	for _, player in ipairs(pvpQueue) do
		PVELobbyUpdate:FireClient(player, #pvpQueue, REQUIRED_PLAYERS)
	end
end

local function removePlayerFromQueue(player: Player)
	for i = #pvpQueue, 1, -1 do
		if pvpQueue[i] == player then
			table.remove(pvpQueue, i)
			break
		end
	end
	updateLobbyStatus()
end

JoinPVPQueue.OnServerEvent:Connect(function(player: Player, mapIndex: number)
	if isMatchStarting then return end

	mapIndex = tonumber(mapIndex) or 1
	if mapIndex < 1 or mapIndex > 10 then mapIndex = 1 end
	player:SetAttribute("SelectedPVPMap", mapIndex)
	
	-- 檢查是否已在佇列中
	local found = false
	for _, p in ipairs(pvpQueue) do
		if p == player then
			found = true
			break
		end
	end
	
	if not found then
		table.insert(pvpQueue, player)
		print(("[PVP Matchmaker] ➕ 玩家 %s 加入了 PVP 佇列。選擇地圖: %d。當前人數: %d"):format(player.Name, mapIndex, #pvpQueue))
		updateLobbyStatus()
		
		-- 啟動 20 秒匹配倒數 (逾時將以 Bots 補齊開戰)
		startQueueTimeout()
	end
	
	-- 達到匹配人數，啟動對戰
	if #pvpQueue >= REQUIRED_PLAYERS then
		isMatchStarting = true
		print("[PVP Matchmaker] 🎮 佇列滿載！正在計算所有在場玩家共同解鎖的地圖...")
		
		-- 1. 取得隊首玩家選擇的地圖索引與地圖名稱
		local selectedMapIndex = pvpQueue[1] and pvpQueue[1]:GetAttribute("SelectedPVPMap") or 1
		local mapNames = {
			"經典交叉網格", "傳送帶工廠", "萬花筒折射迷宮", "巡邏哨兵矩陣",
			"算術虛空塌陷", "坐標天雷神殿", "因數诅咒之室", "終端收縮孤島",
			"混沌變數 X 核心", "歐幾里得終極大亂鬥"
		}
		local selectedMapName = "⚔️ PVP [" .. (mapNames[selectedMapIndex] or "經典交叉網格") .. "] ⚔️"
		
		print(("[PVP Matchmaker] 🗺️ 隊首玩家選擇地圖: %d (%s)"):format(selectedMapIndex, selectedMapName))
		
		-- 2. 廣播匹配成功事件，通知客戶端進入 5 秒倒數
		for _, p in ipairs(pvpQueue) do
			PVPStartMatch:FireClient(p, selectedMapName)
		end
		
		-- 3. 倒數 5 秒後進行傳送、重置屬性與載入地圖
		task.delay(5, function()
			workspace:SetAttribute("PVP_MapIndex", selectedMapIndex)
			workspace:SetAttribute("CurrentLevel", 4) -- 設定為關卡 4 (PVP 競技場)
			
			-- 3.5 PVP 玩家離開大廳狀態
			for _, p in ipairs(pvpQueue) do
				p:SetAttribute("InLobby", false)
			end
			
			buildArena()
			initMinionsForLevel() -- 會孵化 0 隻小怪，因為 PVP 不生成怪物
			
			-- 4. 傳送玩家至競技場 4 個角落 (適配 75x50 網格)
			local spawnCorners = {
				Vector3.new(-120, 3, -72),
				Vector3.new(120, 3, 72),
				Vector3.new(-120, 3, 72),
				Vector3.new(120, 3, -72),
			}
			
			for i, p in ipairs(pvpQueue) do
				local char = p.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root then
					local cornerPos = spawnCorners[((i - 1) % #spawnCorners) + 1]
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					char:PivotTo(CFrame.new(cornerPos))
				end
			end
			
			-- 5. 重置佇列，解除匹配鎖定
			pvpQueue = {}
			isMatchStarting = false
			
			-- 6. 強制套用公平 PVP 屬性 (生命 50，威力 3，移速 16)
			if MapRebuilt then
				MapRebuilt:Fire()
			end
			
			print("[PVP Matchmaker] ⚔️ PVP 對戰正式開始！")
		end)
	end
end)

LeavePVPQueue.OnServerEvent:Connect(function(player: Player)
	if isMatchStarting then return end
	print(("[PVP Matchmaker] ➖ 玩家 %s 離開了 PVP 佇列。"):format(player.Name))
	removePlayerFromQueue(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	removePlayerFromQueue(player)
end)

-- 關卡晉級與重挑戰重新建置地圖
RequestNextLevel.OnServerEvent:Connect(function(player: Player)
	player:SetAttribute("InLobby", false)
	task.wait(0.2) -- 稍微延遲等 Boss 重置
	buildArena()
	initMinionsForLevel()
end)

RequestRetry.OnServerEvent:Connect(function(player: Player)
	player:SetAttribute("InLobby", false)
	task.wait(0.2)
	buildArena()
	initMinionsForLevel()
end)

-- 處理 PVE 關卡選關後的地圖重整
if ServerRebuildArena then
	ServerRebuildArena.Event:Connect(function(player: Player)
		print(("[BomberGameManager] 收到 ServerRebuildArena，開始為 %s 建置 PVE 地圖關卡"):format(player.Name))
		player:SetAttribute("InLobby", false)
		task.wait(0.2)
		buildArena()
		initMinionsForLevel()
	end)
end

-- ==================== PVE 倒數塌陷天降方塊縮圈系統 ====================
local suddenDeathActive = false
local suddenDeathThread = nil

_G.StopPVESuddenDeath = function()
	print("[BomberGameManager] 🛑 呼叫 _G.StopPVESuddenDeath()")
	suddenDeathActive = false
	if suddenDeathThread then
		pcall(function() task.cancel(suddenDeathThread) end)
		suddenDeathThread = nil
	end
	-- 清理殘留的預警指示器
	for _, child in ipairs(gridFolder:GetChildren()) do
		if child.Name == "SuddenDeathIndicator" then
			child:Destroy()
		end
	end
end

_G.StartPVESuddenDeath = function()
	_G.StopPVESuddenDeath() -- 先停止舊的
	suddenDeathActive = true
	print("[BomberGameManager] ⏱️ 啟動 PVE 坍塌（天降方塊縮圈機制）！")

	suddenDeathThread = task.spawn(function()
		local minX = MAP_MIN_X
		local maxX = MAP_MAX_X
		local minZ = MAP_MIN_Z
		local maxZ = MAP_MAX_Z

		while suddenDeathActive and (minX <= maxX) and (minZ <= maxZ) do
			-- 收集這一圈的所有網格座標
			local ringCells = {}
			for gx = minX, maxX do
				table.insert(ringCells, {x = gx, z = minZ})
				if minZ ~= maxZ then
					table.insert(ringCells, {x = gx, z = maxZ})
				end
			end
			for gz = minZ + 1, maxZ - 1 do
				table.insert(ringCells, {x = minX, z = gz})
				if minX ~= maxX then
					table.insert(ringCells, {x = maxX, z = gz})
				end
			end

			if #ringCells == 0 then break end

			print(("[BomberGameManager] 🚨 縮圈中！最外圈 X: [%d, %d], Z: [%d, %d] 共有 %d 格塌陷"):format(minX, maxX, minZ, maxZ, #ringCells))

			-- 1. 生成地面預警
			local indicators = {}
			for _, cell in ipairs(ringCells) do
				-- 避開已經放置有 HardWall 的格，避免重疊
				local alreadyHasWall = false
				for _, child in ipairs(gridFolder:GetChildren()) do
					if child:IsA("BasePart") then
						local cx, cz = worldToGrid(child.Position)
						if cx == cell.x and cz == cell.z and child.Name == "HardWall" then
							alreadyHasWall = true
							break
						end
					end
				end

				if not alreadyHasWall then
					local ind = Instance.new("Part")
					ind.Name = "SuddenDeathIndicator"
					ind.Size = Vector3.new(CELL - 0.2, 0.1, CELL - 0.2)
					ind.Position = gridToWorld(cell.x, cell.z) + Vector3.new(0, -1.4, 0)
					ind.Color = Color3.fromRGB(255, 0, 0)
					ind.Material = Enum.Material.Neon
					ind.Transparency = 0.4
					ind.Anchored = true
					ind.CanCollide = false
					ind.Parent = gridFolder
					table.insert(indicators, {cell = cell, part = ind})
				end
			end

			-- 預警 1.2 秒
			task.wait(1.2)
			if not suddenDeathActive then break end

			-- 2. 天降暗紅方塊
			for _, item in ipairs(indicators) do
				local cell = item.cell
				if item.part and item.part.Parent then
					item.part:Destroy()
				end

				-- 建立暗紅坍塌方塊 (HardWall)
				local wall = Instance.new("Part")
				wall.Name = "HardWall"
				wall.Size = Vector3.new(CELL, 5, CELL)
				wall.Position = gridToWorld(cell.x, cell.z) + Vector3.new(0, 40, 0)
				wall.Color = Color3.fromRGB(130, 20, 20)
				wall.Material = Enum.Material.Concrete
				wall.Parent = gridFolder
				CollectionService:AddTag(wall, "IndestructibleWall")

				local targetPos = gridToWorld(cell.x, cell.z)
				wall.Anchored = true
				wall.CanCollide = false

				local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Bounce, Enum.EasingDirection.In)
				local tween = TweenService:Create(wall, tweenInfo, {Position = targetPos})
				tween:Play()

				tween.Completed:Connect(function()
					if not wall.Parent then return end
					wall.CanCollide = true

					-- 砸地音效
					local thud = Instance.new("Sound")
					thud.SoundId = "rbxassetid://580125756" -- 重音落地聲
					thud.Volume = 0.4
					thud.Parent = wall
					thud:Play()
					Debris:AddItem(thud, 2)
				end)
			end

			-- 3. 砸地後傷害判定 (0.35s 補間完成後立即檢測)
			task.spawn(function()
				task.wait(0.35)
				if not suddenDeathActive then return end

				for _, item in ipairs(indicators) do
					local cell = item.cell
					local worldPos = gridToWorld(cell.x, cell.z)

					-- 建立震盪塵土
					local exp = Instance.new("Explosion")
					exp.Position = worldPos
					exp.BlastRadius = 3
					exp.BlastPressure = 0
					exp.Visible = false
					exp.Parent = workspace

					-- 傷害判定：
					-- A. 真人玩家
					for _, p in ipairs(Players:GetPlayers()) do
						local char = p.Character
						local hum = char and char:FindFirstChildOfClass("Humanoid")
						local rootPart = char and char:FindFirstChild("HumanoidRootPart")
						if hum and rootPart and hum.Health > 0 then
							local px, pz = worldToGrid(rootPart.Position)
							if px == cell.x and pz == cell.z then
								hum:TakeDamage(50) -- 直接造成超大傷害
								print(("[BomberGameManager] 💀 塌陷方塊砸中玩家 %s！"):format(p.Name))
							end
						end
					end

					-- B. PVP 機器人
					local botsFolder = workspace:FindFirstChild("PVP_Bots")
					if botsFolder then
						for _, bot in ipairs(botsFolder:GetChildren()) do
							local hum = bot:FindFirstChildOfClass("Humanoid")
							local rootPart = bot:FindFirstChild("HumanoidRootPart")
							if hum and rootPart and hum.Health > 0 then
								local bx, bz = worldToGrid(rootPart.Position)
								if bx == cell.x and bz == cell.z then
									hum:TakeDamage(50)
								end
							end
						end
					end

					-- C. PVE Boss
					local bossRootPart = bossModel:FindFirstChild("HumanoidRootPart")
					local bossHum = bossModel:FindFirstChildOfClass("Humanoid")
					if bossRootPart and bossHum and bossHum.Health > 0 then
						local bx, bz = worldToGrid(bossRootPart.Position)
						if bx == cell.x and bz == cell.z then
							bossHum:TakeDamage(100) -- 方塊也會砸傷 Boss
							print("[BomberGameManager] 💥 塌陷方塊砸中 PVE Boss！")
						end
					end

					-- D. PVE 小怪
					for _, minion in ipairs(minionsFolder:GetChildren()) do
						local mHum = minion:FindFirstChildOfClass("Humanoid")
						local mRoot = minion:FindFirstChild("HumanoidRootPart")
						if mHum and mRoot and mHum.Health > 0 then
							local mx, mz = worldToGrid(mRoot.Position)
							if mx == cell.x and mz == cell.z then
								mHum:TakeDamage(100)
							end
						end
					end
				end
			end)

			-- 收縮邊界
			minX += 1
			maxX -= 1
			minZ += 1
			maxZ -= 1

			-- 每圈塌陷間隔 1.5 秒
			task.wait(1.5)
		end
	end)
end

-- 伺服器啟動初始化地圖與小怪
buildArena()
initMinionsForLevel()

print("[BomberGameManager] 網格與史萊姆小怪 NPC 系統已極致優化啟動！")
