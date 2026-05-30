--[[
	【遊戲性與關卡優化版】Boss 答題、智慧巡邏 AI、接觸傷害、受傷眩暈凍結與關卡管理 (LevelManager)
	功能：
	1. 關卡管理器：支援 3 大關卡，HP 遞增，小怪數量與關卡道具（鐵箱、TNT）隨關卡解鎖！
	2. 答題無敵狀態：答題期間玩家掛載 "AnsweringQuiz" 屬性，100% 免疫所有地圖傷害與碰撞。
	3. 智慧巡邏與解凍物理：Boss 會自動避開迷宮牆體巡邏。
	4. 勝利與失敗面板：與客戶端 Remotes 連結，通關顯示勝利煙火，死亡彈出重新挑戰。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
if not Modules then
	Modules = Instance.new("Folder")
	Modules.Name = "Modules"
	Modules.Parent = ReplicatedStorage
end

local tsaDbScript = Modules:WaitForChild("TSADatabase", 10) or ReplicatedStorage:WaitForChild("TSADatabase", 10)
local TSADatabase
if tsaDbScript then
	TSADatabase = require(tsaDbScript)
else
	warn("[BossGameManager] 未能成功載入 TSADatabase，啟用後備內建題庫")
	TSADatabase = {
		["2024TSA"] = {
			["Q1"] = { ImageId = "rbxassetid://86475262339715", Answer = "A" }
		}
	}
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

-- 通訊節點
local ShowMathUI = ensureRemoteEvent("ShowMathUI")
local VerifyAnswer = Remotes:FindFirstChild("VerifyAnswer") :: RemoteFunction?
if not VerifyAnswer then
	VerifyAnswer = Instance.new("RemoteFunction")
	VerifyAnswer.Name = "VerifyAnswer"
	VerifyAnswer.Parent = Remotes
end

local BossBombHit = Remotes:FindFirstChild("BossBombHit") :: BindableEvent?
if not BossBombHit then
	BossBombHit = Instance.new("BindableEvent")
	BossBombHit.Name = "BossBombHit"
	BossBombHit.Parent = Remotes
end

local ShowWinUI = ensureRemoteEvent("ShowWinUI")
local ShowLoseUI = ensureRemoteEvent("ShowLoseUI")
local RequestNextLevel = ensureRemoteEvent("RequestNextLevel")
local RequestRetry = ensureRemoteEvent("RequestRetry")
local SyncPVETimer = ensureRemoteEvent("SyncPVETimer")

local MapRebuilt = Remotes:FindFirstChild("MapRebuilt") :: BindableEvent?
if not MapRebuilt then
	MapRebuilt = Instance.new("BindableEvent")
	MapRebuilt.Name = "MapRebuilt"
	MapRebuilt.Parent = Remotes
end

-- 確保 PVE_Arena 存在（自癒與健壯性優化，使用 WaitForChild 避免 startup race condition）
local arena = workspace:WaitForChild("PVE_Arena", 10)
if not arena then
	warn("[BossGameManager] 未在 Workspace 找到 PVE_Arena，正在啟動自癒機制建立...")
	arena = Instance.new("Folder")
	arena.Name = "PVE_Arena"
	arena.Parent = workspace
end

local gridFolder = arena:WaitForChild("Grid", 5)
if not gridFolder then
	gridFolder = Instance.new("Folder")
	gridFolder.Name = "Grid"
	gridFolder.Parent = arena
end

local bossModel = arena:WaitForChild("TSABoss", 5)
if not bossModel then
	warn("[BossGameManager] 未在 PVE_Arena 中找到 TSABoss，啟動自癒建立預設 Boss...")
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

local bossHumanoid = bossModel:WaitForChild("Humanoid", 10)
local bossRoot = bossModel:WaitForChild("HumanoidRootPart", 10)
if not bossHumanoid or not bossRoot then
	error("[BossGameManager] TSABoss 缺少 Humanoid 或 HumanoidRootPart")
end

-- 初始化 Boss 物理：強制解鎖錨定，設定極限重量 (防止玩家推動) 與伺服器網路所有權
print("[BossGameManager] 正在解凍 Boss 物理，確保 unanchored 並設定極大重量...")
bossRoot.Anchored = false
bossRoot.CanCollide = true
bossRoot.CustomPhysicalProperties = PhysicalProperties.new(100, 0.5, 0.5, 100, 1)

for _, part in ipairs(bossModel:GetDescendants()) do
	if part:IsA("BasePart") then
		part.Anchored = false
		part.CustomPhysicalProperties = PhysicalProperties.new(100, 0.5, 0.5, 100, 1)
	end
end

-- 鎖定 Boss 的物理網路所有權給伺服器，使玩家完全無法隨意推動
pcall(function()
	bossRoot:SetNetworkOwner(nil)
end)

-- 關卡常數配置 (支援 1 到 30 關 PVE 挑戰，難度與獎勵漸進提升，第 4 關為 PVP 佔位符)
local LEVEL_CONFIGS = {
	[1] = { BossHP = 150, Speed = 0.0, GoldReward = 100 }, -- 第 1 關：新手教學（Boss完全靜止）
	[2] = { BossHP = 180, Speed = 4.0, GoldReward = 120 }, -- 第 2 關：初試身手（Boss僅在中央小圈漫步）
	[3] = { BossHP = 220, Speed = 4.5, GoldReward = 140 }, -- 第 3 關：小試牛刀（Boss全地圖巡邏）
	[4] = { BossHP = 1,   Speed = 0.0, GoldReward = 0 },   -- 第 4 關：PVP 專屬佔位符
	[5] = { BossHP = 260, Speed = 5.0, GoldReward = 160 }, -- 第 5 關
	[6] = { BossHP = 280, Speed = 5.2, GoldReward = 180 },
	[7] = { BossHP = 300, Speed = 5.5, GoldReward = 200 },
	[8] = { BossHP = 320, Speed = 5.8, GoldReward = 220 },
	[9] = { BossHP = 340, Speed = 6.0, GoldReward = 240 },
	[10] = { BossHP = 360, Speed = 6.2, GoldReward = 260 },
	[11] = { BossHP = 380, Speed = 6.5, GoldReward = 280 },
	[12] = { BossHP = 400, Speed = 6.8, GoldReward = 300 },
	[13] = { BossHP = 420, Speed = 7.0, GoldReward = 320 },
	[14] = { BossHP = 440, Speed = 7.2, GoldReward = 340 },
	[15] = { BossHP = 460, Speed = 7.5, GoldReward = 360 },
	[16] = { BossHP = 480, Speed = 7.8, GoldReward = 380 },
	[17] = { BossHP = 500, Speed = 8.0, GoldReward = 400 },
	[18] = { BossHP = 520, Speed = 8.2, GoldReward = 420 },
	[19] = { BossHP = 540, Speed = 8.5, GoldReward = 440 },
	[20] = { BossHP = 560, Speed = 8.8, GoldReward = 460 },
	[21] = { BossHP = 580, Speed = 9.0, GoldReward = 480 },
	[22] = { BossHP = 600, Speed = 9.2, GoldReward = 500 },
	[23] = { BossHP = 620, Speed = 9.5, GoldReward = 520 },
	[24] = { BossHP = 640, Speed = 9.8, GoldReward = 540 },
	[25] = { BossHP = 660, Speed = 10.0, GoldReward = 560 },
	[26] = { BossHP = 680, Speed = 10.2, GoldReward = 580 },
	[27] = { BossHP = 700, Speed = 10.5, GoldReward = 600 },
	[28] = { BossHP = 720, Speed = 10.8, GoldReward = 620 },
	[29] = { BossHP = 750, Speed = 11.0, GoldReward = 650 },
	[30] = { BossHP = 800, Speed = 11.5, GoldReward = 700 },
}

local BOSS_DAMAGE = 50       -- 答對一題扣 Boss HP
local PLAYER_PENALTY = 20    -- 答錯一題扣玩家 20 HP (2顆心)
local CONTACT_DAMAGE = 20    -- 碰觸 Boss 扣 20 HP (2顆心)
local CELL = 4               -- 縮放網格：4 studs
local BOSS_SPAWN_GX = 0
local BOSS_SPAWN_GZ = 0
local BOSS_FLOOR_Y = 3.5     -- PivotTo 絕對高度，避免 MoveTo 被石塊頂到箱頂，且貼合地板防止離地
local currentTimerThread = nil

-- 初始化關卡狀態
if not workspace:GetAttribute("CurrentLevel") then
	workspace:SetAttribute("CurrentLevel", 1)
end

local session = {
	stunned = false,
	player = nil :: Player?,
	correctAnswer = nil :: string?,
	imageId = nil :: string?,
}

local function getLevel(): number
	return workspace:GetAttribute("CurrentLevel") or 1
end

-- ==================== 題目抽選邏輯 ====================

local function allQuestionKeys(): { { year: string, q: string } }
	local list = {}
	for year, questions in pairs(TSADatabase) do
		if type(questions) == "table" then
			for q, _ in pairs(questions) do
				table.insert(list, { year = year, q = q })
			end
		end
	end
	return list
end

local function pickRandomQuestion(): (string?, string?)
	local keys = allQuestionKeys()
	if #keys == 0 then
		warn("[BossGameManager] TSADatabase 為空！")
		return nil, nil
	end
	local pick = keys[math.random(1, #keys)]
	local row = TSADatabase[pick.year][pick.q]
	if not row then
		return nil, nil
	end
	return row.ImageId, row.Answer
end

-- ==================== 關卡管理與重置 ====================

local function teleportBossToSafeSpawn()
	local spawnPos = Vector3.new(BOSS_SPAWN_GX * CELL, BOSS_FLOOR_Y, BOSS_SPAWN_GZ * CELL)
	bossRoot.AssemblyLinearVelocity = Vector3.zero
	bossRoot.AssemblyAngularVelocity = Vector3.zero
	-- 使用 PivotTo 強制落點，不要用 MoveTo（會被障礙物往上頂）
	bossModel:PivotTo(CFrame.new(spawnPos))
	bossModel:SetAttribute("Stunned", false)
end

local function playBossHitFeedback()
	local hitSound = Instance.new("Sound")
	hitSound.SoundId = "rbxassetid://12222253"
	hitSound.Volume = 0.9
	hitSound.Parent = bossRoot
	hitSound:Play()
	Debris:AddItem(hitSound, 2)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 40)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = bossRoot

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "💥 被炸到了！"
	label.TextColor3 = Color3.fromRGB(255, 80, 80)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.Parent = billboard

	Debris:AddItem(billboard, 1.2)

	-- 短暫閃紅
	local orig = bossRoot.Color
	bossRoot.Color = Color3.fromRGB(255, 60, 60)
	task.delay(0.2, function()
		if bossRoot.Parent then
			bossRoot.Color = orig
		end
	end)
end

local function initBossForLevel()
	local lvl = getLevel()
	
	-- 停止 PVE 倒數坍塌 (Sudden Death)
	if _G.StopPVESuddenDeath then
		_G.StopPVESuddenDeath()
	end
	
	-- 移除/重置計時器執行緒
	if currentTimerThread then
		task.cancel(currentTimerThread)
		currentTimerThread = nil
	end

	if lvl == 4 then
		-- PVP 競技場：將 PVE Boss 暫時放置於極深地下並凍結 walkspeed，不干擾 PVP 玩法
		bossRoot.AssemblyLinearVelocity = Vector3.zero
		bossRoot.AssemblyAngularVelocity = Vector3.zero
		bossModel:PivotTo(CFrame.new(0, -1000, 0))
		bossHumanoid.WalkSpeed = 0
		bossHumanoid.HipHeight = 0
		session.stunned = false
		session.player = nil
		print("[BossGameManager] ⚔️ PVP 模式啟用：已完美隱藏並凍結 PVE Boss")
		return
	end

	local config = LEVEL_CONFIGS[lvl] or LEVEL_CONFIGS[30]

	bossHumanoid.MaxHealth = config.BossHP
	bossHumanoid.Health = config.BossHP
	bossHumanoid.HipHeight = 0 -- 徹底防止離地浮空
	if lvl == 1 then
		bossHumanoid.WalkSpeed = 0
	else
		bossHumanoid.WalkSpeed = config.Speed
	end

	teleportBossToSafeSpawn()
	session.stunned = false
	session.player = nil
	print(("[BossGameManager] 關卡 %d 初始化成功！Boss HP: %d, 巡邏速度: %.1f"):format(lvl, config.BossHP, bossHumanoid.WalkSpeed))

	-- 啟動 5 分鐘計時器執行緒 (300 秒)
	currentTimerThread = task.spawn(function()
		local timeLeft = 300
		-- 立即同步 300 秒給客戶端
		if SyncPVETimer then
			SyncPVETimer:FireAllClients(timeLeft)
		end
		
		while timeLeft > 0 do
			task.wait(1)
			-- 檢查 Boss 是否已死亡或關卡是否改變
			if getLevel() == 4 or bossHumanoid.Health <= 0 then
				break
			end
			timeLeft -= 1
			-- 同步時間給所有 PVE 玩家
			if SyncPVETimer then
				SyncPVETimer:FireAllClients(timeLeft)
			end
		end

		if timeLeft <= 0 and bossHumanoid.Health > 0 and getLevel() ~= 4 then
			print("[BossGameManager] ⏱️ 5 分鐘計時結束！玩家未能擊敗 Boss，天降方塊縮圈開始！")
			if _G.StartPVESuddenDeath then
				_G.StartPVESuddenDeath()
			end
		end
	end)
end

-- ==================== 答題無敵與 Stun 眩暈控制 ====================

local function beginBossQuiz(player: Player)
	if session.stunned or bossModel:GetAttribute("Stunned") == true then
		return
	end

	local imageId, answer = pickRandomQuestion()
	if not imageId or not answer then
		warn("[BossGameManager] 題庫為空或載入失敗！")
		return
	end

	session.stunned = true
	session.player = player
	session.correctAnswer = answer
	session.imageId = imageId
	bossModel:SetAttribute("Stunned", true)

	-- 鎖死 Boss（勿用 MoveTo，避免防卡牆再次抬高 Y）
	bossHumanoid.WalkSpeed = 0
	
	-- 1. 【核心優化】：開啟玩家「答題無敵狀態」，100% 免疫傷害
	local char = player.Character
	if char then
		char:SetAttribute("AnsweringQuiz", true)
		print("[BossGameManager] 🛡️ 已開啟答題無敵狀態：", player.Name)
	end
	
	playBossHitFeedback()

	-- 受傷紅光發光特效
	local att = Instance.new("Attachment")
	att.Parent = bossRoot
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 50, 50)
	light.Brightness = 12
	light.Range = 15
	light.Parent = att
	Debris:AddItem(att, 1.5)

	print(("[BossGameManager] 📚 送出答題 UI → %s，題圖: %s"):format(player.Name, imageId))
	ShowMathUI:FireClient(player, imageId)
end

local function endStun()
	print("[BossGameManager] 🔄 解除眩暈狀態。")
	
	-- 2. 【核心優化】：解除玩家「答題無敵狀態」
	if session.player and session.player.Character then
		session.player.Character:SetAttribute("AnsweringQuiz", nil)
		print("[BossGameManager] 🛡️ 已關閉答題無敵狀態：", session.player.Name)
	end

	session.stunned = false
	session.player = nil
	session.correctAnswer = nil
	session.imageId = nil
	bossModel:SetAttribute("Stunned", false)

	local lvl = getLevel()
	local config = LEVEL_CONFIGS[lvl] or LEVEL_CONFIGS[10]
	if lvl == 1 then
		bossHumanoid.WalkSpeed = 0
	else
		bossHumanoid.WalkSpeed = config.Speed
	end
end

-- ==================== 煙火勝利特效 ====================

local function spawnFireworks()
	print("[BossGameManager] 🎉 播放通關勝利煙火特效！")
	for i = 1, 8 do
		task.delay((i - 1) * 0.25, function()
			local p = Instance.new("Part")
			p.Size = Vector3.new(1, 1, 1)
			p.Shape = Enum.PartType.Ball
			p.Color = Color3.fromHSV(math.random(), 1, 1)
			p.Material = Enum.Material.Neon
			p.Anchored = true
			p.CanCollide = false
			p.Position = bossRoot.Position + Vector3.new(math.random(-15, 15), math.random(5, 18), math.random(-15, 15))
			p.Parent = workspace
			
			local att = Instance.new("Attachment")
			att.Parent = p
			local pe = Instance.new("ParticleEmitter")
			pe.Color = ColorSequence.new(p.Color, Color3.fromRGB(255, 255, 255))
			pe.Size = NumberSequence.new(0.6, 0)
			pe.Lifetime = NumberRange.new(0.5, 1)
			pe.Speed = NumberRange.new(5, 15)
			pe.Rate = 200
			pe.Parent = att
			
			Debris:AddItem(p, 1.2)
		end)
	end
end

-- ==================== 智慧巡邏 AI ====================

local function isPathFree(startPos: Vector3, endPos: Vector3): boolean
	local dir = endPos - startPos
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { gridFolder }
	
	local result = workspace:Raycast(startPos + Vector3.new(0, 1.5, 0), dir, params)
	return result == nil
end

task.spawn(function()
	while bossModel.Parent do
		task.wait(math.random(3, 5))
		local lvl = getLevel()
		if lvl == 4 then continue end
		if lvl == 1 then
			-- 第一關：新手教學，Boss 完全靜止不動
			bossHumanoid.WalkSpeed = 0
			continue
		end
		if session.stunned or bossHumanoid.Health <= 0 then continue end
		
		local currentPos = bossRoot.Position
		local directions = {
			Vector3.new(CELL, 0, 0),   -- 東
			Vector3.new(-CELL, 0, 0),  -- 西
			Vector3.new(0, 0, CELL),   -- 南
			Vector3.new(0, 0, -CELL),  -- 北
		}
		
		local spawnPos = Vector3.new(BOSS_SPAWN_GX * CELL, bossRoot.Position.Y, BOSS_SPAWN_GZ * CELL)
		local validMoves = {}
		for _, dir in ipairs(directions) do
			local targetPos = currentPos + dir
			if isPathFree(currentPos, targetPos) then
				if lvl == 2 then
					-- 第二關：限制在中央 3.5 格半徑（21 studs）之內漫步
					local distFromSpawn = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(spawnPos.X, 0, spawnPos.Z)).Magnitude
					if distFromSpawn <= 3.5 * CELL then
						table.insert(validMoves, targetPos)
					end
				else
					-- 第三關及以上：全地圖追逐漫步，無限制
					table.insert(validMoves, targetPos)
				end
			end
		end
		
		if #validMoves > 0 and not session.stunned then
			local target = validMoves[math.random(1, #validMoves)]
			bossHumanoid:MoveTo(target)
		end
	end
end)

-- ==================== 接觸傷害與無敵判斷 ====================

task.spawn(function()
	while bossModel.Parent do
		task.wait(0.3)
		if getLevel() == 4 then continue end
		if session.stunned or bossHumanoid.Health <= 0 then continue end
		
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local playerRoot = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if playerRoot and hum and hum.Health > 0 then
				local dist = (playerRoot.Position - bossRoot.Position).Magnitude
				if dist < 4.5 then
					-- 【核心優化】：如果玩家正在答題，免疫傷害！
					if char:GetAttribute("AnsweringQuiz") then
						continue
					end
					
					-- 扣血接觸傷害
					hum:TakeDamage(CONTACT_DAMAGE)
					print(("[BossGameManager] Boss 衝撞了玩家 %s！扣除 HP %d"):format(player.Name, CONTACT_DAMAGE))
					
					-- 輕微推開（避免 LinearVelocity 造成鏡頭抖動）
					local pushDir = (playerRoot.Position - bossRoot.Position).Unit
					playerRoot.AssemblyLinearVelocity = Vector3.new(pushDir.X * 8, 0, pushDir.Z * 8)
				end
			end
		end
	end
end)

-- ==================== 訊號與事件綁定 ====================

BossBombHit.Event:Connect(function(player: Player, targetBoss: Model?)
	if targetBoss and targetBoss ~= bossModel then
		return
	end
	if not player or typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if bossModel:GetAttribute("Stunned") == true then
		return
	end
	print("[BossGameManager] 🎯 收到 BossBombHit，準備為玩家彈出題目:", player.Name)
	beginBossQuiz(player)
end)

VerifyAnswer.OnServerInvoke = function(player: Player, chosen: string): boolean
	if not session.stunned or session.player ~= player then
		return false
	end
	
	local lvl = getLevel()
	local config = LEVEL_CONFIGS[lvl] or LEVEL_CONFIGS[10]

	if chosen ~= session.correctAnswer then
		-- 答錯扣玩家血
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			-- 答錯時：暫時取消 AnsweringQuiz 以便正常扣血，扣完立刻補上
			char:SetAttribute("AnsweringQuiz", nil)
			hum:TakeDamage(PLAYER_PENALTY)
			char:SetAttribute("AnsweringQuiz", true)
			print("[BossGameManager] ❌ 答錯！扣除玩家生命:", PLAYER_PENALTY)
			
			-- 檢查玩家是否死亡，死亡觸發失敗 UI
			if hum.Health <= 0 then
				print("[BossGameManager] 💀 玩家生命值歸零，挑戰失敗！")
				char:SetAttribute("AnsweringQuiz", nil) -- 徹底解除無敵
				ShowLoseUI:FireClient(player)
				endStun()
				return true -- 仍然返回 true 關閉答題 UI，但觸發了 Lose 面板
			end
		end
		return false
	end

	-- 答對扣 Boss 血量
	bossHumanoid:TakeDamage(BOSS_DAMAGE)
	print(("[BossGameManager] 🎉 答對！Boss 受到 %d 點重大傷害！目前 Boss 剩餘血量: %.1f"):format(
		BOSS_DAMAGE, bossHumanoid.Health
	))

	-- 答對金幣獎勵
	local stats = player:FindFirstChild("leaderstats")
	local gold = stats and stats:FindFirstChild("Gold")
	if gold and gold:IsA("IntValue") then
		gold.Value += config.GoldReward
	end

	-- 檢查 Boss 是否死亡
	if bossHumanoid.Health <= 0 then
		print("[BossGameManager] 🏆 Boss 被擊敗！關卡勝利！")
		if _G.StopPVESuddenDeath then
			_G.StopPVESuddenDeath()
		end
		-- 記錄並更新玩家最高通關關卡
		if _G.SetHighestClearedLevel then
			_G.SetHighestClearedLevel(player, lvl)
		end
		spawnFireworks()
		ShowWinUI:FireClient(player, lvl, config.GoldReward)
		endStun()
		return true
	end

	endStun()
	return true
end

-- 關卡跳過與重試請求監聽
RequestNextLevel.OnServerEvent:Connect(function(player: Player)
	local currentLvl = getLevel()
	local nextLvl = currentLvl + 1
	if nextLvl > 3 then
		nextLvl = 1 -- 通關所有後，循環回第一大關
	end
	workspace:SetAttribute("CurrentLevel", nextLvl)
	print("[BossGameManager] ➡️ 玩家請求解鎖下一關。目前關卡變更為:", nextLvl)
	-- Boss 位置與血量由 MapRebuilt → initBossForLevel 統一處理

	-- 恢復玩家滿血
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.Health = hum.MaxHealth end
end)

RequestRetry.OnServerEvent:Connect(function(player: Player)
	print("[BossGameManager] 🔄 玩家請求重新挑戰當前關卡:", getLevel())

	-- 恢復玩家滿血
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.Health = hum.MaxHealth end
end)

-- leaderstats 初始化 (安全防重疊版)
local function setupLeaderstats(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end

	local gold = stats:FindFirstChild("Gold")
	if not gold then
		gold = Instance.new("IntValue")
		gold.Name = "Gold"
		gold.Value = 0
		gold.Parent = stats
	end
end

Players.PlayerAdded:Connect(setupLeaderstats)
for _, player in Players:GetPlayers() do
	if not player:FindFirstChild("leaderstats") then
		setupLeaderstats(player)
	end
end

-- 等地圖建完後再重置 Boss（由 BomberGameManager 觸發 MapRebuilt）
MapRebuilt.Event:Connect(function()
	initBossForLevel()
end)

print("[BossGameManager] 智慧關卡管理與接觸扣血 AI 已完美啟動（等待 MapRebuilt）")
