--[[
	【2.5D 萬花筒光折射引爆引擎】PVPExplosionEngine (Server)
	功能：
	1. 提供 2.5D 高性能網格爆炸演算法，支援 4x4 studs 的 XZ 平面單元。
	2. 利用 CollectionService 自動感知 45度反光鏡面 (Mirror_ForwardSlash, Mirror_BackSlash) 
	   與半透明分光稜鏡 (PrismSplitter)，計算火焰的反射與分光路徑。
	3. 使用遞迴光線追蹤 (TraceFlamePath) 搭配防死循環深度守衛 (Depth Limit: 50)，確保極致性能。
	4. 支援對玩家人物 (Humanoid) 進行精確空間傷害判定，並為擊殺進行主權歸屬 (creator ObjectValue)。
	5. 提供外置調用介面：BindableFunction 與 _G.TriggerGridExplosion。
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- ==================== 網格配置常數 ====================
local CELL = 4 -- 4x4 studs
local MAP_MIN_X = -15
local MAP_MAX_X = 15
local MAP_MIN_Y = -15
local MAP_MAX_Y = 15

-- ==================== 1. 方向向量定義 ====================
local UP = Vector2.new(0, 1)
local DOWN = Vector2.new(0, -1)
local LEFT = Vector2.new(-1, 0)
local RIGHT = Vector2.new(1, 0)

-- ==================== 坐標與邊界檢測輔助 ====================
local function gridToWorld(gx: number, gy: number): Vector3
	return Vector3.new(gx * CELL, 1.5, gy * CELL)
end

local function isOutOfBounds(gx: number, gy: number): boolean
	return gx < MAP_MIN_X or gx > MAP_MAX_X or gy < MAP_MIN_Y or gy > MAP_MAX_Y
end

-- ==================== 2. 反光鏡面與分光稜鏡方向變換 = [[
local function getForwardSlashDirection(dir: Vector2): Vector2
	-- '/' 鏡面反射對照
	if dir == RIGHT then return UP
	elseif dir == LEFT then return DOWN
	elseif dir == UP then return RIGHT
	elseif dir == DOWN then return LEFT
	end
	return dir
end

local function getBackSlashDirection(dir: Vector2): Vector2
	-- '\' 鏡面反射對照
	if dir == RIGHT then return DOWN
	elseif dir == LEFT then return UP
	elseif dir == UP then return LEFT
	elseif dir == DOWN then return RIGHT
	end
	return dir
end

-- ==================== 空間網格物體屬性偵測 ====================
local function GetGridCellState(gx: number, gy: number): (string, Instance?)
	local center = gridToWorld(gx, gy)
	local size = Vector3.new(CELL - 0.2, 4.0, CELL - 0.2)
	
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {}
	
	local parts = workspace:GetPartBoundsInBox(CFrame.new(center), size, overlapParams)
	for _, part in ipairs(parts) do
		if CollectionService:HasTag(part, "IndestructibleWall") then
			return "IndestructibleWall", part
		elseif CollectionService:HasTag(part, "DestructibleBlock") then
			return "DestructibleBlock", part
		elseif CollectionService:HasTag(part, "Mirror_ForwardSlash") then
			return "Mirror_ForwardSlash", part
		elseif CollectionService:HasTag(part, "Mirror_BackSlash") then
			return "Mirror_BackSlash", part
		elseif CollectionService:HasTag(part, "PrismSplitter") then
			return "PrismSplitter", part
		end
	end
	
	return "Empty", nil
end

-- ==================== 3. 遞迴光線火焰傳導演算法 ====================
local function TraceFlamePath(
	currentGridX: number, 
	currentGridY: number, 
	directionVector: Vector2, 
	currentPower: number, 
	depth: number, 
	resultsTable: { [string]: Vector2 }
)
	-- 終止條件守衛
	if currentPower <= 0 then return end
	if depth > 50 then return end -- 防無限鏡面死循環守衛
	if isOutOfBounds(currentGridX, currentGridY) then return end

	-- 記錄目前格子
	local key = currentGridX .. "_" .. currentGridY
	if not resultsTable[key] then
		resultsTable[key] = Vector2.new(currentGridX, currentGridY)
	end

	-- 偵測網格遮擋與道具狀態
	local cellState, part = GetGridCellState(currentGridX, currentGridY)

	if cellState == "IndestructibleWall" then
		-- 鋼鐵硬牆：直接終止此分歧傳導
		return
		
	elseif cellState == "DestructibleBlock" then
		-- 破壞木箱：排入銷毀隊列，並終止此分歧傳導
		if part then
			task.spawn(function()
				part:Destroy()
			end)
		end
		return
		
	elseif cellState == "Mirror_ForwardSlash" then
		-- '/' 45度反光鏡：消耗 1 能量，偏轉方向並遞迴
		local newDir = getForwardSlashDirection(directionVector)
		TraceFlamePath(
			currentGridX + newDir.X, 
			currentGridY + newDir.Y, 
			newDir, 
			currentPower - 1, 
			depth + 1, 
			resultsTable
		)
		
	elseif cellState == "Mirror_BackSlash" then
		-- '\' 45度反光鏡：消耗 1 能量，偏轉方向並遞迴
		local newDir = getBackSlashDirection(directionVector)
		TraceFlamePath(
			currentGridX + newDir.X, 
			currentGridY + newDir.Y, 
			newDir, 
			currentPower - 1, 
			depth + 1, 
			resultsTable
		)
		
	elseif cellState == "PrismSplitter" then
		-- 分光稜鏡：火焰直接穿透，並向垂直兩側分流 (1分為3)
		-- Branch 1: 直行穿透
		TraceFlamePath(
			currentGridX + directionVector.X, 
			currentGridY + directionVector.Y, 
			directionVector, 
			currentPower - 1, 
			depth + 1, 
			resultsTable
		)
		-- Branch 2 & 3: 垂直左右分流
		if directionVector.X ~= 0 then
			-- 水平射入 -> 往垂直上下分流
			local upDir = UP
			local downDir = DOWN
			TraceFlamePath(currentGridX + upDir.X, currentGridY + upDir.Y, upDir, currentPower - 1, depth + 1, resultsTable)
			TraceFlamePath(currentGridX + downDir.X, currentGridY + downDir.Y, downDir, currentPower - 1, depth + 1, resultsTable)
		else
			-- 垂直射入 -> 往水平左右分流
			local rightDir = RIGHT
			local leftDir = LEFT
			TraceFlamePath(currentGridX + rightDir.X, currentGridY + rightDir.Y, rightDir, currentPower - 1, depth + 1, resultsTable)
			TraceFlamePath(currentGridX + leftDir.X, currentGridY + leftDir.Y, leftDir, currentPower - 1, depth + 1, resultsTable)
		end
		
	else
		-- 空格：傳導至下一個單元
		TraceFlamePath(
			currentGridX + directionVector.X, 
			currentGridY + directionVector.Y, 
			directionVector, 
			currentPower - 1, 
			depth + 1, 
			resultsTable
		)
	end
end

-- ==================== 4. 核心引爆控制器與傷害判定 ====================
local function TriggerGridExplosion(originGridX: number, originGridY: number, maxPower: number, owner: Player?)
	local resultsTable = {} -- 保存所有爆炸覆蓋格子 (Key: "X_Y", Value: Vector2)
	
	-- 核心格子永久覆蓋
	local coreKey = originGridX .. "_" .. originGridY
	resultsTable[coreKey] = Vector2.new(originGridX, originGridY)

	-- 往 4 個初始方向進行光線追蹤
	local directions = { UP, DOWN, LEFT, RIGHT }
	for _, dir in ipairs(directions) do
		TraceFlamePath(originGridX + dir.X, originGridY + dir.Y, dir, maxPower, 1, resultsTable)
	end

	-- 遍歷所有爆炸格，進行視覺特效渲染與玩家致死檢測
	for _, cellVec in pairs(resultsTable) do
		local gx, gy = cellVec.X, cellVec.Y
		local center = gridToWorld(gx, gy)

		-- 地圖 5/10 虛空塌陷判定
		local level = workspace:GetAttribute("CurrentLevel") or 1
		local isPVP = (level == 4)
		local currentMapStyle = 1
		if isPVP then
			currentMapStyle = workspace:GetAttribute("PVP_MapIndex") or 1
		else
			currentMapStyle = ((level - 1) % 10) + 1
		end
		if currentMapStyle == 5 or currentMapStyle == 10 then
			if _G.TriggerTileCollapse then
				_G.TriggerTileCollapse(gx, gy)
			end
		end

		-- VFX Spawning: 建立炫麗發光爆炸體與粒子
		local vfx = Instance.new("Part")
		vfx.Name = "PVP_ExplosionFlame"
		vfx.Size = Vector3.new(CELL, 4.5, CELL)
		vfx.Position = center
		vfx.Color = Color3.fromRGB(255, 100, 30) -- 萬花筒霓虹橙
		vfx.Material = Enum.Material.Neon
		vfx.Anchored = true
		vfx.CanCollide = false
		vfx.Transparency = 0.4
		vfx.Parent = workspace

		-- 火焰粒子效果
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 120
		emitter.Lifetime = NumberRange.new(0.25, 0.45)
		emitter.Speed = NumberRange.new(3, 8)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 3.2),
			NumberSequenceKeypoint.new(1, 0)
		})
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 160, 40), Color3.fromRGB(80, 20, 0))
		emitter.Parent = vfx

		-- 震撼爆炸聲效
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://580125756"
		sound.Volume = 0.55
		sound.Parent = vfx
		sound:Play()

		Debris:AddItem(vfx, 0.6)

		-- Spatial Damage Check: 空間致死傷害檢測
		task.spawn(function()
			local characterList = {}
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Character then
					table.insert(characterList, p.Character)
				end
			end

			local overlapParams = OverlapParams.new()
			overlapParams.FilterType = Enum.RaycastFilterType.Include
			overlapParams.FilterDescendantsInstances = characterList

			-- 偵測格子內部的玩家
			local hitParts = workspace:GetPartBoundsInBox(CFrame.new(center), Vector3.new(CELL - 0.2, 5.0, CELL - 0.2), overlapParams)
			local processedHumans = {}

			for _, hitPart in ipairs(hitParts) do
				local char = hitPart.Parent
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 and not processedHumans[hum] then
					processedHumans[hum] = true
					
					-- 標記擊殺主權（CreatorTag）
					if owner then
						local oldTag = hum:FindFirstChild("creator")
						if oldTag then oldTag:Destroy() end
						
						local tag = Instance.new("ObjectValue")
						tag.Name = "creator"
						tag.Value = owner
						tag.Parent = hum
						Debris:AddItem(tag, 2)
					end

					-- 施加致命一擊傷害
					hum:TakeDamage(hum.MaxHealth)
					print(("[PVPExplosionEngine] 💀 玩家 %s 被萬花筒烈焰擊殺！擊殺歸屬者: %s"):format(
						char.Name, owner and owner.Name or "環境物"
					))
				end
			end
		end)
	end
end

-- ==================== 5. 對外通訊與服務註冊 ====================
_G.TriggerGridExplosion = TriggerGridExplosion

-- 註冊 ReplicatedStorage Remotes 的綁定調用
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if Remotes then
	local pvpTrigger = Remotes:FindFirstChild("TriggerPVPExplosion")
	if not pvpTrigger then
		pvpTrigger = Instance.new("BindableFunction")
		pvpTrigger.Name = "TriggerPVPExplosion"
		pvpTrigger.Parent = Remotes
	end
	(pvpTrigger :: BindableFunction).OnInvoke = function(originGridX: number, originGridY: number, maxPower: number, owner: Player?)
		TriggerGridExplosion(originGridX, originGridY, maxPower, owner)
		return true
	end
end

print("[PVPExplosionEngine] 2.5D 萬花筒光折射引爆引擎完美加載成功！")
