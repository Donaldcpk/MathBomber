--[[
	【遊戲打磨與自癒優化版】玩家狀態 HUD、關卡勝負面板與金幣商店 (PlayerHUD)
	功能：
	1. 狀態欄：同步顯示生命值紅心（最高支援 15 顆心）、金幣數量、炸彈範圍。
	2. 關卡勝負面板：
	   - 勝利面板 (ShowWinUI)：炫麗通關動畫、發放金幣、提供「下一關」按鈕。
	   - 失敗面板 (ShowLoseUI)：暗紅死亡動畫、提供「重新挑戰」按鈕。
	3. 屬性商店 (Power-up Shop)：點擊 HUD 的「商店」按鈕或於兩關之間，開啟商店購買屬性升級。
]]

--[[
	【遊戲打磨與自癒優化版】玩家狀態 HUD、關卡勝負面板與金幣商店 (PlayerHUD)
	功能：
	1. 狀態欄：同步顯示生命值紅心（最高支援 15 顆心）、金幣數量、炸彈範圍。
	2. 關卡勝負面板：
	   - 勝利面板 (ShowWinUI)：炫麗通關動畫、發放金幣、提供「下一關」按鈕。
	   - 失敗面板 (ShowLoseUI)：暗紅死亡動畫、提供「重新挑戰」按鈕。
	3. 屬性商店 (Power-up Shop)：點擊 HUD 的「商店」按鈕或於兩關之間，開啟商店購買屬性升級。
	4. 隱藏預設血條：在載入時確保隱藏 Roblox 預設右上角血條，讓「10顆紅心」成為唯一且最清晰的生命指標。
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

-- 關閉 Roblox 預設血條與名字標籤
task.spawn(function()
	local success = false
	while not success do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then success = true else task.wait(0.2) end
	end
end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function findMainMenuScreenGui(): ScreenGui?
	for _, child in ipairs(playerGui:GetChildren()) do
		if child.Name == "MainMenuGui" and child:IsA("ScreenGui") then
			return child :: ScreenGui
		end
	end
	return nil
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShowWinUI = Remotes:WaitForChild("ShowWinUI")
local ShowLoseUI = Remotes:WaitForChild("ShowLoseUI")
local RequestNextLevel = Remotes:WaitForChild("RequestNextLevel")
local RequestRetry = Remotes:WaitForChild("RequestRetry")
local BuyShopItem = Remotes:WaitForChild("BuyShopItem") :: RemoteFunction
local ReturnToLobby = Remotes:WaitForChild("ReturnToLobby")

-- 共用 UI 容器：絕不 Destroy 既有 ScreenGui（PlayerHUD 必須最先被保留）
local screenGui = playerGui:FindFirstChild("MathQuizScreenGui") :: ScreenGui?
if not screenGui then
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MathQuizScreenGui"
	screenGui.ResetOnSpawn = true
	screenGui.Parent = playerGui
	print("[UI Engine] 成功建立全新的 MathQuizScreenGui 容器")
else
	print("[UI Engine] 發現已存在的容器，直接沿用，不進行 Destroy 防止 HUD 消失")
end
screenGui.DisplayOrder = math.max(screenGui.DisplayOrder, 10)

-- ==================== 1. HUD 狀態欄與自癒 ====================

local hudFrame = screenGui:FindFirstChild("HUDFrame") :: Frame
if not hudFrame then
	hudFrame = Instance.new("Frame")
	hudFrame.Name = "HUDFrame"
	hudFrame.Size = UDim2.new(0, 320, 0, 110)
	hudFrame.Position = UDim2.new(0, 15, 0, 15)
	hudFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	hudFrame.BackgroundTransparency = 0.25
	hudFrame.BorderSizePixel = 0
	hudFrame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = hudFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 100, 130)
	stroke.Thickness = 2.5
	stroke.Parent = hudFrame

	-- 紅心容器 Grid
	local hContainer = Instance.new("Frame")
	hContainer.Name = "HeartsContainer"
	hContainer.Size = UDim2.new(1, -20, 0, 35)
	hContainer.Position = UDim2.new(0, 10, 0, 10)
	hContainer.BackgroundTransparency = 1
	hContainer.Parent = hudFrame

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 18, 0, 18)
	grid.CellPadding = UDim2.new(0, 2, 0, 2)
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = hContainer

	-- 金幣與範圍狀態文字
	local goldLabel = Instance.new("TextLabel")
	goldLabel.Name = "GoldLabel"
	goldLabel.Size = UDim2.new(0.5, -10, 0, 30)
	goldLabel.Position = UDim2.new(0, 10, 0, 50)
	goldLabel.BackgroundTransparency = 1
	goldLabel.Text = "🪙 金幣: 0"
	goldLabel.Font = Enum.Font.GothamBold
	goldLabel.TextSize = 18
	goldLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left
	goldLabel.Parent = hudFrame

	local rangeLabel = Instance.new("TextLabel")
	rangeLabel.Name = "RangeLabel"
	rangeLabel.Size = UDim2.new(0.5, -10, 0, 30)
	rangeLabel.Position = UDim2.new(0.5, 0, 0, 50)
	rangeLabel.BackgroundTransparency = 1
	rangeLabel.Text = "💣 爆炸範圍: 3 格"
	rangeLabel.Font = Enum.Font.GothamBold
	rangeLabel.TextSize = 18
	rangeLabel.TextColor3 = Color3.fromRGB(240, 120, 40)
	rangeLabel.TextXAlignment = Enum.TextXAlignment.Left
	rangeLabel.Parent = hudFrame

	-- 商店快捷按鈕
	local shopBtn = Instance.new("TextButton")
	shopBtn.Name = "ShopButton"
	shopBtn.Size = UDim2.new(0, 80, 0, 26)
	shopBtn.Position = UDim2.new(1, -90, 0, 10)
	shopBtn.BackgroundColor3 = Color3.fromRGB(240, 160, 40)
	shopBtn.Text = "🛒 商店"
	shopBtn.Font = Enum.Font.GothamBold
	shopBtn.TextSize = 14
	shopBtn.TextColor3 = Color3.new(1, 1, 1)
	shopBtn.Parent = hudFrame

	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(0, 6)
	sCorner.Parent = shopBtn

	-- 5分鐘計時器文字標籤
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(1, -20, 0, 30)
	timerLabel.Position = UDim2.new(0, 10, 0, 80)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "⏱️ 剩餘時間: --:--"
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextSize = 15
	timerLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center
	timerLabel.Parent = hudFrame
end

local heartsContainer = hudFrame:WaitForChild("HeartsContainer") :: Frame
local goldLabel = hudFrame:WaitForChild("GoldLabel") :: TextLabel
local rangeLabel = hudFrame:WaitForChild("RangeLabel") :: TextLabel
local shopBtn = hudFrame:WaitForChild("ShopButton") :: TextButton
local timerLabel = hudFrame:WaitForChild("TimerLabel") :: TextLabel

-- 連接 5 分鐘計時器同步 RemoteEvent
local SyncPVETimer = Remotes:WaitForChild("SyncPVETimer", 10) :: RemoteEvent?
if SyncPVETimer then
	SyncPVETimer.OnClientEvent:Connect(function(secondsLeft)
		local mins = math.floor(secondsLeft / 60)
		local secs = secondsLeft % 60
		local formattedTime = string.format("%02d:%02d", mins, secs)
		
		local currentLvl = workspace:GetAttribute("CurrentLevel") or 1
		if currentLvl == 4 then
			timerLabel.Text = "⏱️ PVP 激烈對決中！"
			timerLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
		else
			timerLabel.Text = "⏱️ 剩餘時間: " .. formattedTime
			if secondsLeft <= 30 then
				timerLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
			else
				timerLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
			end
		end
	end)
end

-- ==================== 1.2 進階道具客戶端同步與頂部 Toast 提示 ====================
local SyncAdvancedItems = Remotes:WaitForChild("SyncAdvancedItems", 10) :: RemoteEvent?

local function showCenterNotification(msg: string, color: Color3?)
	local screenGui = script.Parent :: ScreenGui
	if not screenGui then return end
	
	local notification = Instance.new("TextLabel")
	notification.Size = UDim2.new(0, 340, 0, 45)
	notification.Position = UDim2.new(0.5, -170, 0.15, 0)
	notification.BackgroundColor3 = color or Color3.fromRGB(30, 30, 30)
	notification.TextColor3 = Color3.new(1, 1, 1)
	notification.Font = Enum.Font.GothamBold
	notification.TextSize = 14
	notification.Text = msg
	notification.BorderSizePixel = 0
	notification.Parent = screenGui
	
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 8)
	uiCorner.Parent = notification
	
	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = Color3.new(1, 1, 1)
	uiStroke.Thickness = 1.5
	uiStroke.Parent = notification
	
	notification.Transparency = 1
	uiStroke.Transparency = 1
	notification.TextTransparency = 1
	
	TweenService:Create(notification, TweenInfo.new(0.3), { Transparency = 0.1, TextTransparency = 0, BackgroundTransparency = 0.1 }):Play()
	TweenService:Create(uiStroke, TweenInfo.new(0.3), { Transparency = 0.2 }):Play()
	
	task.delay(2.5, function()
		local t = TweenService:Create(notification, TweenInfo.new(0.4), { Transparency = 1, TextTransparency = 1, BackgroundTransparency = 1 })
		local s = TweenService:Create(uiStroke, TweenInfo.new(0.4), { Transparency = 1 })
		t:Play()
		s:Play()
		t.Completed:Connect(function()
			notification:Destroy()
		end)
	end)
end

if SyncAdvancedItems then
	SyncAdvancedItems.OnClientEvent:Connect(function(itemType: string, active: boolean)
		if itemType == "BlinkBoots" then
			if active then
				showCenterNotification("👟 獲得閃現靴！按 Q 鍵可向前閃現 3 格！", Color3.fromRGB(218, 165, 32))
			else
				showCenterNotification("⚡ 閃現靴能量已消耗！", Color3.fromRGB(120, 120, 120))
			end
		elseif itemType == "PhaseFluid" then
			if active then
				showCenterNotification("🧪 獲得量子穿彈水！6 秒內可穿越所有炸彈！", Color3.fromRGB(0, 191, 255))
			else
				showCenterNotification("🛡️ 量子穿彈效果已失效！", Color3.fromRGB(120, 120, 120))
			end
		end
	end)
end

-- ==================== 1.5 HUD 可見度與大廳自動同步 ====================
task.spawn(function()
	local mainMenu = playerGui:WaitForChild("MainMenuGui", 10)
	if mainMenu then
		local function syncHUD()
			hudFrame.Visible = not mainMenu.Enabled
		end
		mainMenu:GetPropertyChangedSignal("Enabled"):Connect(syncHUD)
		syncHUD()
	else
		hudFrame.Visible = true
	end
end)

-- ==================== 2. 屬性商城 UI 自癒 ====================

local shopFrame = screenGui:FindFirstChild("ShopFrame") :: Frame
if not shopFrame then
	shopFrame = Instance.new("Frame")
	shopFrame.Name = "ShopFrame"
	shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	shopFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	shopFrame.Size = UDim2.new(0, 380, 0, 320)
	shopFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
	shopFrame.BorderSizePixel = 0
	shopFrame.Visible = false
	shopFrame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = shopFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(240, 160, 40)
	stroke.Thickness = 3
	stroke.Parent = shopFrame

	-- 標題
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 45)
	title.Position = UDim2.new(0, 0, 0, 5)
	title.BackgroundTransparency = 1
	title.Text = "🛒 戰力金幣商店"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Parent = shopFrame

	-- 關閉按鈕
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 35, 0, 35)
	closeBtn.Position = UDim2.new(1, -45, 0, 5)
	closeBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.Parent = shopFrame

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, 8)
	cCorner.Parent = closeBtn

	-- 商店品項
	local function createShopItem(name: string, displayName: string, desc: string, costText: string, yPos: number)
		local item = Instance.new("Frame")
		item.Name = name
		item.Size = UDim2.new(1, -20, 0, 75)
		item.Position = UDim2.new(0, 10, 0, yPos)
		item.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
		item.BorderSizePixel = 0
		item.Parent = shopFrame

		local ic = Instance.new("UICorner")
		ic.CornerRadius = UDim.new(0, 8)
		ic.Parent = item

		local ilbl = Instance.new("TextLabel")
		ilbl.Size = UDim2.new(0.65, 0, 0.5, 0)
		ilbl.Position = UDim2.new(0, 12, 0, 5)
		ilbl.BackgroundTransparency = 1
		ilbl.Text = displayName
		ilbl.Font = Enum.Font.GothamBold
		ilbl.TextSize = 16
		ilbl.TextColor3 = Color3.new(1, 1, 1)
		ilbl.TextXAlignment = Enum.TextXAlignment.Left
		ilbl.Parent = item

		local idesc = Instance.new("TextLabel")
		idesc.Size = UDim2.new(0.65, 0, 0.5, 0)
		idesc.Position = UDim2.new(0, 12, 0.5, -5)
		idesc.BackgroundTransparency = 1
		idesc.Text = desc
		idesc.Font = Enum.Font.Gotham
		idesc.TextSize = 12
		idesc.TextColor3 = Color3.fromRGB(180, 180, 200)
		idesc.TextXAlignment = Enum.TextXAlignment.Left
		idesc.Parent = item

		local ibtn = Instance.new("TextButton")
		ibtn.Name = "BuyButton"
		ibtn.Size = UDim2.new(0.3, -10, 0.7, 0)
		ibtn.Position = UDim2.new(0.7, 5, 0.15, 0)
		ibtn.BackgroundColor3 = Color3.fromRGB(50, 150, 80)
		ibtn.Text = costText
		ibtn.Font = Enum.Font.GothamBold
		ibtn.TextSize = 14
		ibtn.TextColor3 = Color3.new(1, 1, 1)
		ibtn.Parent = item

		local ibc = Instance.new("UICorner")
		ibc.CornerRadius = UDim.new(0, 6)
		ibc.Parent = ibtn
	end

	createShopItem("MaxHP", "❤️ 生命上限上限 (+1 顆心)", "生命最大上限提升 10 HP，並補滿生命", "🪙 150 Gold", 60)
	createShopItem("BombRange", "💣 炸彈爆炸範圍 (+1 格)", "增大你放置的所有炸彈的爆燃區域", "🪙 100 Gold", 145)
	createShopItem("WalkSpeed", "🏃 移動速度 (+2 WalkSpeed)", "提升你在地圖上跑步穿梭的敏捷度", "🪙 80 Gold", 230)
end

local shopCloseBtn = shopFrame:WaitForChild("CloseButton") :: TextButton
local buyHpBtn = shopFrame:WaitForChild("MaxHP"):WaitForChild("BuyButton") :: TextButton
local buyRangeBtn = shopFrame:WaitForChild("BombRange"):WaitForChild("BuyButton") :: TextButton
local buySpeedBtn = shopFrame:WaitForChild("WalkSpeed"):WaitForChild("BuyButton") :: TextButton

-- ==================== 3. 勝利與失敗面板 UI 自癒 ====================

local winLoseOverlay = screenGui:FindFirstChild("WinLoseOverlay") :: Frame
if not winLoseOverlay then
	winLoseOverlay = Instance.new("Frame")
	winLoseOverlay.Name = "WinLoseOverlay"
	winLoseOverlay.Size = UDim2.new(1, 0, 1, 0)
	winLoseOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	winLoseOverlay.BackgroundTransparency = 0.45
	winLoseOverlay.BorderSizePixel = 0
	winLoseOverlay.Visible = false
	winLoseOverlay.Parent = screenGui

	-- 中間結算主面板
	local panel = Instance.new("Frame")
	panel.Name = "MainPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0, 420, 0, 260)
	panel.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
	panel.BorderSizePixel = 0
	panel.Parent = winLoseOverlay

	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 16)
	pc.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 200, 120)
	stroke.Thickness = 4
	stroke.Parent = panel

	-- 大主標題
	local head = Instance.new("TextLabel")
	head.Name = "Header"
	head.Size = UDim2.new(1, 0, 0, 60)
	head.Position = UDim2.new(0, 0, 0, 20)
	head.BackgroundTransparency = 1
	head.Text = "🏆 勝利通關！"
	head.Font = Enum.Font.GothamBold
	head.TextSize = 32
	head.TextColor3 = Color3.fromRGB(255, 215, 0)
	head.Parent = panel

	-- 詳細描述內容
	local details = Instance.new("TextLabel")
	details.Name = "Details"
	details.Size = UDim2.new(1, -40, 0, 70)
	details.Position = UDim2.new(0, 20, 0, 80)
	details.BackgroundTransparency = 1
	details.Text = "第 1 關挑戰成功！\n成功擊敗 Boss！獎勵：+100 Gold"
	details.Font = Enum.Font.GothamBold
	details.TextSize = 18
	details.TextColor3 = Color3.new(0.9, 0.9, 0.9)
	details.Parent = panel

	-- 確定動作按鈕
	local actionBtn = Instance.new("TextButton")
	actionBtn.Name = "ActionButton"
	actionBtn.Size = UDim2.new(0.6, 0, 0, 45)
	actionBtn.Position = UDim2.new(0.2, 0, 1, -65)
	actionBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 100)
	actionBtn.Text = "進入下一關"
	actionBtn.Font = Enum.Font.GothamBold
	actionBtn.TextSize = 18
	actionBtn.TextColor3 = Color3.new(1, 1, 1)
	actionBtn.Parent = panel

	local ac = Instance.new("UICorner")
	ac.CornerRadius = UDim.new(0, 10)
	ac.Parent = actionBtn
end

local panel = winLoseOverlay:WaitForChild("MainPanel") :: Frame
local panelStroke = panel:WaitForChild("UIStroke") :: UIStroke
local panelHeader = panel:WaitForChild("Header") :: TextLabel
local panelDetails = panel:WaitForChild("Details") :: TextLabel
local panelActionBtn = panel:WaitForChild("ActionButton") :: TextButton

-- ==================== 4. HUD 生命心心同步繪製邏輯 ====================

local function updateHearts(humanoid: Humanoid)
	for _, item in ipairs(heartsContainer:GetChildren()) do
		if not item:IsA("UIGridLayout") then
			item:Destroy()
		end
	end

	local health = humanoid.Health
	local maxHealth = humanoid.MaxHealth
	local totalHearts = math.max(1, math.floor(maxHealth / 10))
	local fullHearts = math.floor(health / 10)
	local hasHalf = (health % 10) >= 5
	local currentHearts = fullHearts + (hasHalf and 0.5 or 0)

	local grid = heartsContainer:FindFirstChildOfClass("UIGridLayout")

	if totalHearts <= 5 then
		if grid then grid.Enabled = true end
		for i = 1, totalHearts do
			local heart = Instance.new("TextLabel")
			heart.Name = "Heart_" .. i
			heart.BackgroundTransparency = 1
			heart.BorderSizePixel = 0
			heart.LayoutOrder = i
			heart.Font = Enum.Font.GothamBold
			heart.TextSize = 18
			heart.TextScaled = false

			if i <= fullHearts then
				heart.Text = "❤"
				heart.TextColor3 = Color3.fromRGB(240, 50, 50)
			elseif i == fullHearts + 1 and hasHalf then
				heart.Text = "💛"
				heart.TextColor3 = Color3.fromRGB(240, 180, 50)
			else
				heart.Text = "♡"
				heart.TextColor3 = Color3.fromRGB(90, 90, 100)
			end

			heart.Parent = heartsContainer
		end
	else
		if grid then grid.Enabled = false end
		
		local label = Instance.new("TextLabel")
		label.Name = "CompactHearts"
		label.Size = UDim2.fromScale(1, 1)
		label.Position = UDim2.fromScale(0, 0)
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.TextColor3 = Color3.fromRGB(240, 50, 50)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.Text = ("❤ x %.1f / %d"):format(currentHearts, totalHearts)
		label.Parent = heartsContainer
	end
end

-- 玩家監聽
local function monitorCharacter(char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	
	-- 當血量變更時，立即更新紅心
	hum.HealthChanged:Connect(function()
		updateHearts(hum)
	end)
	updateHearts(hum)

	-- 每 0.2 秒同步炸彈爆炸範圍與移動速度
	task.spawn(function()
		while char.Parent do
			task.wait(0.2)
			local range = char:GetAttribute("BombRange") or 3
			rangeLabel.Text = ("💣 爆炸範圍: %d 格"):format(range)
		end
	end)
end

player.CharacterAdded:Connect(monitorCharacter)
if player.Character then
	monitorCharacter(player.Character)
end

-- ==================== 5. 數據與金幣更新同步 ====================

RunService.RenderStepped:Connect(function()
	local stats = player:FindFirstChild("leaderstats")
	local gold = stats and stats:FindFirstChild("Gold")
	if gold then
		goldLabel.Text = "🪙 金幣: " .. tostring(gold.Value)
	end
end)

-- ==================== 6. 金幣商店操作與通訊 ====================

shopBtn.MouseButton1Click:Connect(function()
	shopFrame.Visible = not shopFrame.Visible
end)

shopCloseBtn.MouseButton1Click:Connect(function()
	shopFrame.Visible = false
end)

local function handleBuy(itemType: string)
	local ok, msg = BuyShopItem:InvokeServer(itemType)
	-- 播放商店小提示通知
	print("[Shop]", msg)
	
	-- 彈出一個精美臨時淡入淡出標籤
	local tip = Instance.new("TextLabel")
	tip.Size = UDim2.new(1, 0, 0, 30)
	tip.Position = UDim2.new(0, 0, 0, -35)
	tip.BackgroundColor3 = ok and Color3.fromRGB(50, 150, 80) or Color3.fromRGB(150, 50, 50)
	tip.TextColor3 = Color3.new(1, 1, 1)
	tip.Font = Enum.Font.GothamBold
	tip.TextSize = 14
	tip.Text = msg
	tip.Parent = shopFrame

	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 6)
	tc.Parent = tip

	TweenService:Create(tip, TweenInfo.new(0.3), { Position = UDim2.new(0, 0, 0, -45) }):Play()
	task.delay(1.5, function()
		local tw = TweenService:Create(tip, TweenInfo.new(0.3), { TextTransparency = 1, BackgroundTransparency = 1 })
		tw:Play()
		tw.Completed:Connect(function() tip:Destroy() end)
	end)
end

buyHpBtn.MouseButton1Click:Connect(function() handleBuy("MaxHP") end)
buyRangeBtn.MouseButton1Click:Connect(function() handleBuy("BombRange") end)
buySpeedBtn.MouseButton1Click:Connect(function() handleBuy("WalkSpeed") end)

-- ==================== 7. 勝負面板通訊 ====================

ShowWinUI.OnClientEvent:Connect(function(lvl: number, goldBonus: number)
	print("[HUD] 🏆 接收到勝利結算通知！")
	
	panelStroke.Color = Color3.fromRGB(80, 220, 100) -- 綠色外框
	
	if lvl == 3 then
		panelHeader.Text = "👑 恭喜通關大滿貫！ 👑"
		panelHeader.TextColor3 = Color3.fromRGB(255, 215, 0)
		panelDetails.Text = ("第 %d 關挑戰成功！\n成功擊敗 400HP 終極 Boss！\n恭喜總統您已完成全部 PVE 挑戰！"):format(lvl)
		panelActionBtn.Text = "返回歡迎大廳 (Return to Lobby)"
		panelActionBtn.BackgroundColor3 = Color3.fromRGB(130, 80, 220) -- 萬花筒紫色
	else
		panelHeader.Text = "🏆 勝利通關！"
		panelHeader.TextColor3 = Color3.fromRGB(255, 215, 0)
		panelDetails.Text = ("第 %d 關挑戰成功！\n成功擊敗 Boss！通關獎勵：+%d Gold"):format(lvl, goldBonus)
		panelActionBtn.Text = "進入下一關 (Next Level)"
		panelActionBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 100)
	end
	
	-- 顯示
	winLoseOverlay.Visible = true
end)

ShowLoseUI.OnClientEvent:Connect(function()
	print("[HUD] 💀 接收到失敗結算通知！")
	
	panelStroke.Color = Color3.fromRGB(220, 60, 60) -- 紅色外框
	panelHeader.Text = "💀 挑戰失敗！"
	panelHeader.TextColor3 = Color3.fromRGB(220, 60, 60)
	panelDetails.Text = "你被 Boss 或小怪擊敗了，紅心被扣光了。\n別氣餒，重新調整戰術再出發！"
	panelActionBtn.Text = "重新挑戰 (Retry)"
	panelActionBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
	
	-- 顯示
	winLoseOverlay.Visible = true
end)

-- 勝利/失敗面板按鈕點擊
panelActionBtn.MouseButton1Click:Connect(function()
	winLoseOverlay.Visible = false
	
	if panelActionBtn.Text == "重新挑戰 (Retry)" then
		print("[HUD] 傳送 RequestRetry 請求至 Server...")
		RequestRetry:FireServer()
	elseif panelActionBtn.Text == "返回歡迎大廳 (Return to Lobby)" then
		-- 顯示主大廳，並隱藏 HUD
		local mainMenu = findMainMenuScreenGui()
		if mainMenu then
			mainMenu.Enabled = true
		end
		if hudFrame then
			hudFrame.Visible = false
		end
		-- 補強安全：通知伺服器重設大廳鎖定，避免後台移動或受傷
		if ReturnToLobby then
			ReturnToLobby:FireServer()
		end
	else
		print("[HUD] 傳送 RequestNextLevel 請求至 Server...")
		RequestNextLevel:FireServer()
	end
end)

-- ==================== 8. PVE Boss 頂部血條與心跳更新 ====================
local bossHPFrame = screenGui:FindFirstChild("BossHPFrame") :: Frame?
if not bossHPFrame then
	bossHPFrame = Instance.new("Frame")
	bossHPFrame.Name = "BossHPFrame"
	bossHPFrame.Size = UDim2.new(0, 400, 0, 45)
	bossHPFrame.Position = UDim2.new(0.5, -200, 0, 15)
	bossHPFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	bossHPFrame.BackgroundTransparency = 0.2
	bossHPFrame.BorderSizePixel = 0
	bossHPFrame.Visible = false
	bossHPFrame.Parent = screenGui

	local bhCorner = Instance.new("UICorner")
	bhCorner.CornerRadius = UDim.new(0, 8)
	bhCorner.Parent = bossHPFrame

	local bhStroke = Instance.new("UIStroke")
	bhStroke.Color = Color3.fromRGB(220, 50, 50)
	bhStroke.Thickness = 2
	bhStroke.Parent = bossHPFrame

	-- 血條背景
	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(1, -20, 0, 15)
	barBg.Position = UDim2.new(0, 10, 1, -23)
	barBg.BackgroundColor3 = Color3.fromRGB(50, 20, 20)
	barBg.BorderSizePixel = 0
	barBg.Parent = bossHPFrame

	local bbgCorner = Instance.new("UICorner")
	bbgCorner.CornerRadius = UDim.new(0, 4)
	bbgCorner.Parent = barBg

	-- 血條填充
	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	local bfCorner = Instance.new("UICorner")
	bfCorner.CornerRadius = UDim.new(0, 4)
	bfCorner.Parent = barFill

	-- Boss 名字與 HP 數值
	local bossLabel = Instance.new("TextLabel")
	bossLabel.Name = "BossLabel"
	bossLabel.Size = UDim2.new(1, -20, 0, 20)
	bossLabel.Position = UDim2.new(0, 10, 0, 4)
	bossLabel.BackgroundTransparency = 1
	bossLabel.Text = "👾 數學霸王 TSA Boss"
	bossLabel.Font = Enum.Font.GothamBold
	bossLabel.TextSize = 13
	bossLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	bossLabel.TextXAlignment = Enum.TextXAlignment.Left
	bossLabel.Parent = bossHPFrame
end

local barBg = bossHPFrame:WaitForChild("BarBg") :: Frame
local barFill = barBg:WaitForChild("BarFill") :: Frame
local bossLabel = bossHPFrame:WaitForChild("BossLabel") :: TextLabel

RunService.Heartbeat:Connect(function()
	local mainMenu = findMainMenuScreenGui()
	if mainMenu and mainMenu.Enabled then
		bossHPFrame.Visible = false
		return
	end

	local lvl = workspace:GetAttribute("CurrentLevel") or 1
	if lvl == 4 then
		bossHPFrame.Visible = false
		return
	end

	local arena = workspace:FindFirstChild("PVE_Arena")
	local boss = arena and arena:FindFirstChild("TSABoss")
	local hum = boss and boss:FindFirstChild("Humanoid") :: Humanoid?

	if hum and hum.Health > 0 then
		bossHPFrame.Visible = true
		local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
		TweenService:Create(barFill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(ratio, 1)
		}):Play()
		bossLabel.Text = string.format("👾 數學霸王 TSA Boss (HP: %d / %d)", math.round(hum.Health), math.round(hum.MaxHealth))
	else
		bossHPFrame.Visible = false
	end
end)

print("[PlayerHUD] 狀態 HUD、金幣商店與勝負結算系統全部加載成功！")
